#!/usr/bin/env python3
"""Build exact PR heads, retain closures, and publish one status per host."""
import errno
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from common import API, HOSTS, REPOSITORY, SHA, STORE_PATH, atomic_json
from retention import prune_retention


def supersede_pending(api, pull, sha, current_heads, run_url):
    """Close custom statuses stranded when Forgejo cancels an older run."""
    host_contexts = {f"colmena/{host}" for host in HOSTS}
    workflow_context = "Colmena PR builds / build (pull_request)"
    commits = api.repo(f"pulls/{pull['number']}/commits?limit=100")
    old_shas = {commit["sha"] for commit in commits}
    # A force-pushed commit disappears from the PR commit list. Forgejo keeps
    # its SHA and original PR number on the detailed canceled-run record.
    runs = api.repo("actions/runs?limit=50").get("workflow_runs", [])
    for summary in runs:
        if summary.get("status") != "cancelled":
            continue
        detail = api.repo(f"actions/runs/{int(summary['id'])}")
        try:
            payload = json.loads(detail.get("event_payload", "{}"))
            old_sha = detail["commit_sha"]
        except (KeyError, TypeError, ValueError, json.JSONDecodeError):
            continue
        if detail.get("event") == "pull_request" and payload.get("number") == pull["number"] and SHA.fullmatch(old_sha):
            old_shas.add(old_sha)
    for old_sha in old_shas:
        if old_sha == sha or old_sha in current_heads:
            continue
        for status in api.statuses(old_sha):
            if status["state"] != "pending":
                continue
            if status["context"] not in host_contexts and status["context"] != workflow_context:
                continue
            target = status.get("target_url") or run_url
            if target.startswith("/"):
                target = api.url + target
            api.status(old_sha, status["context"], "error", "Superseded by newer PR head", target)


GIB = 1024 ** 3


def gc_if_needed(state, threshold_percent=85, minimum_free=40 * GIB):
    usage = shutil.disk_usage(state)
    used_percent = usage.used * 100 / usage.total
    free_gib = usage.free / GIB
    if used_percent < threshold_percent and usage.free >= minimum_free:
        print(f"Nix store filesystem is {used_percent:.1f}% full with {free_gib:.1f} GiB free; skipping GC.")
        return False
    print(f"Nix store filesystem is {used_percent:.1f}% full with {free_gib:.1f} GiB free; running GC.")
    subprocess.run(["nix-store", "--gc"], check=True)
    return True


def require_build_headroom(state, minimum_free=30 * GIB):
    usage = shutil.disk_usage(state)
    if usage.free < minimum_free:
        raise RuntimeError(
            f"Only {usage.free / GIB:.1f} GiB is free after GC; "
            f"refusing to start another build below the {minimum_free / GIB:.0f} GiB reserve"
        )


def main():
    api = API()
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    pr_number = os.environ.get("PR_NUMBER") or event.get("number")
    sha = os.environ.get("COMMIT_SHA") or event.get("pull_request", {}).get("head", {}).get("sha") or event.get("after")
    if not sha or not SHA.fullmatch(sha):
        raise ValueError("Missing exact commit SHA")
    open_pulls = api.pulls()
    pulls = open_pulls
    if pr_number:
        pulls = [api.repo(f"pulls/{int(pr_number)}")]
    pulls = [p for p in pulls if p["head"]["sha"] == sha and p["state"] == "open"]
    if not pulls:
        print("No open PR at this SHA; nothing to build.")
        return 0
    if any(p["head"]["repo"]["full_name"] != REPOSITORY for p in pulls):
        raise ValueError("Only this single-user repository is supported")
    subprocess.run(["git", "fetch", "--no-tags", "origin", sha], check=True)
    subprocess.run(["git", "checkout", "--detach", sha], check=True)
    if subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() != sha:
        raise ValueError("Checkout SHA mismatch")
    state = Path("/var/lib/forgejo-ci")
    state.mkdir(exist_ok=True)
    run = os.environ["GITHUB_RUN_ID"]
    run_url = f"{api.url}/{REPOSITORY}/actions/runs/{run}"
    current_heads = {p["head"]["sha"] for p in open_pulls}
    for pull in pulls:
        supersede_pending(api, pull, sha, current_heads, run_url)
    failed = False
    with (state / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        prune_retention(state, current_heads)
        gc_if_needed(state)
        for host in HOSTS:
            api.status(sha, f"colmena/{host}", "pending", "Queued exact PR head", run_url)
        for host in HOSTS:
            result_file = state / "results" / sha / f"{host}.json"
            if result_file.exists():
                previous = json.loads(result_file.read_text())
                if Path(previous["closure"]).exists():
                    api.status(sha, f"colmena/{host}", "success", "Retained successful build", previous["run_url"])
                    continue
            # Preserve unrooted outputs from partial builds while space allows.
            # Successful current-PR closures remain protected by explicit roots.
            gc_if_needed(state)
            try:
                require_build_headroom(state)
            except RuntimeError as error:
                print(f"{host}: {error}", file=sys.stderr)
                failed = True
                api.status(sha, f"colmena/{host}", "failure", "Insufficient CI disk after garbage collection", run_url)
                continue
            api.status(sha, f"colmena/{host}", "pending", "Building exact PR head", run_url)
            log = state / "results" / sha / f"{host}.log"
            log.parent.mkdir(parents=True, exist_ok=True)
            process = None
            try:
                with log.open("w", buffering=1) as output:
                    process = subprocess.Popen(["nix", "run", ".#colmena", "--", "build", "--on", host,
                        "--parallel", "1"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                    for line in process.stdout:
                        print(line, end="", flush=True)
                        output.write(line)
                    rc = process.wait()
            except OSError as error:
                if error.errno != errno.ENOSPC:
                    raise
                if process is not None and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=30)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()
                print(f"{host}: CI VM ran out of disk space while writing its log", file=sys.stderr)
                failed = True
                api.status(sha, f"colmena/{host}", "failure", "CI VM ran out of disk space", run_url)
                continue
            if rc:
                failed = True
                api.status(sha, f"colmena/{host}", "failure", "Colmena build failed; see job log", run_url)
                continue
            # Query Colmena's hive, not a separately evaluated nixosConfiguration.
            expression = f'{{ nodes, ... }}: nodes.{host}.config.system.build.toplevel.outPath'
            closure = subprocess.check_output(["nix", "run", ".#colmena", "--", "eval", "-E", expression], text=True).strip()
            closure = json.loads(closure)
            if not STORE_PATH.fullmatch(closure) or not Path(closure).exists():
                raise ValueError("Colmena did not produce the expected system closure")
            root = state / "roots" / sha / host
            root.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["nix-store", "--realise", closure, "--add-root", str(root), "--indirect"], check=True)
            atomic_json(result_file, {"repository": REPOSITORY, "sha": sha, "host": host,
                "closure": closure, "run": run, "run_url": run_url, "prs": [p["number"] for p in pulls]})
            api.status(sha, f"colmena/{host}", "success", "Colmena build passed", run_url)
        # Refresh leases after a long run and remove roots plus diagnostic files
        # that have been superseded beyond the transfer grace period.
        current = {p["head"]["sha"] for p in api.pulls()}
        prune_retention(state, current)
    return int(failed)

if __name__ == "__main__":
    sys.exit(main())
