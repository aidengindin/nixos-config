#!/usr/bin/env python3
"""Build exact PR heads, retain closures, and publish one status per host."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
from common import API, HOSTS, REPOSITORY, SHA, STORE_PATH, atomic_json


def main():
    api = API()
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    pr_number = os.environ.get("PR_NUMBER") or event.get("number")
    sha = os.environ.get("COMMIT_SHA") or event.get("pull_request", {}).get("head", {}).get("sha") or event.get("after")
    if not sha or not SHA.fullmatch(sha):
        raise ValueError("Missing exact commit SHA")
    pulls = api.pulls()
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
    failed = False
    with (state / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for host in HOSTS:
            api.status(sha, f"colmena/{host}", "pending", "Queued exact PR head", run_url)
        for host in HOSTS:
            result_file = state / "results" / sha / f"{host}.json"
            if result_file.exists():
                previous = json.loads(result_file.read_text())
                if Path(previous["closure"]).exists():
                    api.status(sha, f"colmena/{host}", "success", "Retained successful build", previous["run_url"])
                    continue
            api.status(sha, f"colmena/{host}", "pending", "Building exact PR head", run_url)
            log = state / "results" / sha / f"{host}.log"
            log.parent.mkdir(parents=True, exist_ok=True)
            with log.open("w") as output:
                process = subprocess.Popen(["nix", "run", ".#colmena", "--", "build", "--on", host,
                    "--parallel", "1"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                for line in process.stdout:
                    print(line, end="", flush=True)
                    output.write(line)
                rc = process.wait()
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
        # Keep all current PR results. Pending deployment closures are pulled
        # and rooted by the controller before activation; preserve old results
        # for seven days as a transfer grace period.
        import time
        current = {p["head"]["sha"] for p in api.pulls()}
        for directory in (state / "roots").iterdir():
            if directory.name not in current and time.time() - directory.stat().st_mtime > 7 * 86400:
                import shutil
                shutil.rmtree(directory)
    return int(failed)

if __name__ == "__main__":
    sys.exit(main())
