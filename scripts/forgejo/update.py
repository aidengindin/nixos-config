#!/usr/bin/env python3
"""Preserve partial updater edits, then open/update the single automation PR."""
import datetime
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from common import API, REPOSITORY, UPDATE_BRANCH

SCRIPTS = Path(__file__).resolve().parent
# `{reports}` is replaced with a scratch directory outside the checkout, where
# the pinning steps leave JSON notes for the PR body.
# Order matters: lock update, then the 7-day cooldown re-pin, then tag-pinned
# inputs, then package updaters, then container images.
# Third-party sources for packages/ are `flake = false` inputs, so the lock
# update and cooldown move them; nothing here bumps a source outside it.
COMMANDS = [
    ["nix", "flake", "update"],
    [sys.executable, str(SCRIPTS / "cooldown.py"), "--report", "{reports}/cooldown.json"],
    [sys.executable, str(SCRIPTS / "tags.py"), "--report", "{reports}/tags.json"],
    # A tag bump can pull in new transitive inputs at their newest commits.
    [sys.executable, str(SCRIPTS / "cooldown.py"), "--report", "{reports}/cooldown-tags.json"],
    *[["bash", "scripts/" + name] for name in ["update-caddy-hash.sh", "update-claude-desktop.sh", "update-chatgpt-desktop.sh"]],
    [sys.executable, str(SCRIPTS / "assets.py"), "--report", "{reports}/assets.json"],
    [sys.executable, str(SCRIPTS / "images.py"), "--report", "{reports}/images.json"],
]
# Daily runs move only the NixOS channel branches and the Home Manager releases
# that follow them. These carry security fixes, advance only after upstream's
# Hydra gates pass, and are exempt from the cooldown, so they need no pinning
# pass. Everything else waits for the weekly full run.
CHANNEL_INPUTS = ["nixpkgs", "unstable", "home-manager", "hm-unstable"]
DAILY_COMMANDS = [["nix", "flake", "update", *CHANNEL_INPUTS]]
# The full run's notes live between these markers, so a daily run can carry
# them over instead of erasing what the last weekly run held back.
FULL_START, FULL_END = "<!-- full-update -->", "<!-- /full-update -->"


# Inputs left out of the review list: the Hydra-gated channel repositories,
# whose compare views are enormous, and the owner's own repositories.
UNREVIEWED_REPOS = {("nixos", "nixpkgs"), ("nix-community", "home-manager")}
OWN = "aidengindin"


def moved_inputs(old_lock, new_lock):
    """Lock nodes whose source moved between main and this branch.

    Nodes are matched by key, falling back to an identical `original` because
    keys such as `nixpkgs_2` can renumber when inputs are added or removed."""
    old_nodes = old_lock.get("nodes", {})
    by_original = {json.dumps(n.get("original"), sort_keys=True): n
                   for k, n in old_nodes.items() if k != "root"}
    moved = []
    for key, node in sorted(new_lock.get("nodes", {}).items()):
        locked, original = node.get("locked") or {}, node.get("original") or {}
        if key == "root" or not locked.get("rev"):
            continue
        owner, repo = (locked.get("owner") or "").lower(), locked.get("repo") or ""
        url = locked.get("url") or ""
        if (owner, repo.lower()) in UNREVIEWED_REPOS or owner == OWN.lower() or "git.gindin.xyz" in url:
            continue
        old = old_nodes.get(key)
        if not old or old.get("original") != original:
            old = by_original.get(json.dumps(original, sort_keys=True))
        old_rev = ((old or {}).get("locked") or {}).get("rev")
        if old_rev == locked["rev"]:
            continue
        if locked.get("type") == "github":
            base = f"https://github.com/{locked['owner']}/{locked['repo']}"
            link = f"{base}/compare/{old_rev}...{locked['rev']}" if old_rev else f"{base}/tree/{locked['rev']}"
        else:
            link = None
        moved.append({"name": key, "old": old_rev, "new": locked["rev"], "link": link})
    return moved


def review_section(moved):
    """Markdown listing every third-party input this PR moves, with diffs."""
    if not moved:
        return "No third-party flake inputs move in this PR."
    lines = ["Third-party flake inputs this PR moves. Skim each upstream diff before deploying:", "",
        "| input | from | to | upstream diff |", "|---|---|---|---|"]
    for m in moved:
        old = f"`{m['old'][:12]}`" if m["old"] else "new input"
        label = "compare" if m["old"] else "tree"
        diff = f"[{label}]({m['link']})" if m["link"] else "not on GitHub"
        lines.append(f"| `{m['name']}` | {old} | `{m['new'][:12]}` | {diff} |")
    return "\n".join(lines)


def review_against_main():
    """Review section for this branch's lock relative to origin/main."""
    try:
        old = json.loads(git("show", "origin/main:flake.lock", capture=True))
        new = json.loads(Path("flake.lock").read_text())
    except (OSError, TypeError, ValueError, subprocess.CalledProcessError) as exc:
        return f"Could not compute moved inputs: {exc}"
    return review_section(moved_inputs(old, new))


def resolve_mode(environ=os.environ, today=None):
    """`full` or `channels`. An explicit UPDATE_MODE wins; otherwise the daily
    schedule runs channels-only except on Sundays, and anything else is full."""
    mode = environ.get("UPDATE_MODE", "").strip()
    if mode in ("full", "channels"):
        return mode
    if mode:
        raise ValueError(f"Unknown UPDATE_MODE {mode!r}")
    today = today or datetime.datetime.now(datetime.timezone.utc).date()
    if environ.get("GITHUB_EVENT_NAME") == "schedule" and today.isoweekday() != 7:
        return "channels"
    return "full"


def carried_full_section(body):
    """The previous full run's section from an existing PR body, if any."""
    body = body or ""
    start, end = body.find(FULL_START), body.find(FULL_END)
    if start == -1 or end < start:
        return None
    return body[start:end + len(FULL_END)]


def git(*args, capture=False):
    return subprocess.check_output(["git", *args], text=True).strip() if capture else subprocess.run(["git", *args], check=True)


def read_reports(directory):
    reports = {}
    for name in ("cooldown", "cooldown-tags", "tags", "assets", "images"):
        try:
            reports[name] = json.loads(Path(directory, name + ".json").read_text())
        except (OSError, ValueError):
            reports[name] = {}
    # The second cooldown pass only adds inputs the first did not see.
    second = reports.pop("cooldown-tags")
    seen = {h["name"] for h in reports["cooldown"].get("held", [])}
    for key in ("held", "unhandled"):
        reports["cooldown"][key] = reports["cooldown"].get(key, []) + [
            h for h in second.get(key, []) if not isinstance(h, dict) or h["name"] not in seen]
    return reports


def cooldown_section(reports):
    """Markdown describing everything the 7-day cooldown held back."""
    lines = []
    held = reports["cooldown"].get("held", [])
    if held:
        lines += ["Flake inputs held back by the 7-day cooldown (pinned to the newest older commit):", "",
            "| input | repository | upstream head age | pinned rev age | pinned rev |", "|---|---|---|---|---|"]
        lines += [f"| `{h['name']}` | {h['repo']} | {h['upstream_head_age_days']}d | {h['pinned_age_days']}d | `{h['pinned_rev'][:12]}` |" for h in held]
        lines.append("")
    if reports["cooldown"].get("unhandled"):
        lines += ["Young inputs the cooldown cannot handle (non-GitHub), left as updated:", ""]
        lines += ["- " + u for u in reports["cooldown"]["unhandled"]] + [""]
    notes = reports["tags"].get("held", []) + reports.get("assets", {}).get("held", []) + reports["images"].get("held", [])
    if notes:
        lines += ["Tags, release assets and container images held back by the cooldown:", ""] + ["- " + n for n in notes] + [""]
    if reports["images"].get("problems"):
        lines += ["Image pinning problems:", ""] + ["- " + p for p in reports["images"]["problems"]] + [""]
    if reports.get("assets", {}).get("problems"):
        lines += ["Release asset pinning problems:", ""] + ["- " + p for p in reports["assets"]["problems"]] + [""]
    return "\n".join(lines)


def main():
    mode = resolve_mode()
    print("Update mode:", mode, flush=True)
    api = API()
    with open("/var/lib/forgejo-ci/update.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        git("config", "user.name", "forgejo-update")
        git("config", "user.email", "forgejo-update@git.gindin.xyz")
        pulls = [p for p in api.pulls() if p["head"]["ref"] == UPDATE_BRANCH]
        git("fetch", "origin", "main")
        remote_branch = subprocess.run(["git", "ls-remote", "--exit-code", "--heads", "origin", UPDATE_BRANCH], stdout=subprocess.DEVNULL).returncode == 0
        before = None
        if remote_branch:
            git("fetch", "origin", UPDATE_BRANCH)
            before = git("rev-parse", "FETCH_HEAD", capture=True)
            git("checkout", "-B", UPDATE_BRANCH, "FETCH_HEAD")
            # Refuse to overwrite repairs or human changes; merging main is a
            # normal fast-forward/non-rewriting merge and conflicts fail visibly.
            git("merge", "--no-edit", "origin/main")
        else:
            git("checkout", "-B", UPDATE_BRANCH, "origin/main")
        failures = []
        reports_dir = tempfile.mkdtemp(prefix="update-reports-")
        for command in COMMANDS if mode == "full" else DAILY_COMMANDS:
            command = [part.replace("{reports}", reports_dir) for part in command]
            print("Running:", " ".join(command), flush=True)
            try:
                rc = subprocess.run(command, timeout=7200).returncode
            except subprocess.TimeoutExpired:
                rc = 124
            if rc:
                failures.append(" ".join(command))
                # Keep later updaters independent and publish every partial edit.
        changed = bool(git("status", "--porcelain", capture=True))
        if not changed and not failures and not pulls:
            print("No changes")
            return 0
        cycle = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
        if changed or failures:
            git("add", "-A")
            kind = "update" if mode == "full" else "channel update"
            git("commit", "--allow-empty", "-m", f"chore: automated {kind} {cycle}")
        # A normal push refuses a concurrently updated remote branch.
        git("push", "origin", f"HEAD:refs/heads/{UPDATE_BRANCH}")
        sha = git("rev-parse", "HEAD", capture=True)
        result = ("Updater failures:\n" + "\n".join("- `" + f + "`" for f in failures)
            if failures else "All updater steps completed.")
        if mode == "full":
            full = f"{FULL_START}\n### Last full update: {cycle}\n\n{result}\n\n{cooldown_section(read_reports(reports_dir))}\n{FULL_END}"
            latest = f"Latest run: full update, {cycle}."
        else:
            full = carried_full_section(pulls[0].get("body") if pulls else None) or (
                f"{FULL_START}\n### Last full update: none yet on this PR; the next runs Sunday.\n{FULL_END}")
            latest = f"Latest run: channel update ({', '.join(CHANNEL_INPUTS)}), {cycle}.\n\n{result}"
        body = (f"Automated flake and custom package updates. NixOS channels update daily; "
            f"every other input, tag and image updates weekly on Sunday.\n\nUpdate-Cycle: {cycle}\n\n"
            f"{latest}\n\n{review_against_main()}\n\n{full}\n\n"
            "CI builds lorien, osgiliath, and khazad-dum. Merge manually; use `/deploy @server` or individual hosts to deploy this PR.")
        if pulls:
            pr = pulls[0]
            api.repo(f"pulls/{pr['number']}", data={"body": body}, method="PATCH")
        else:
            pr = api.repo("pulls", data={"head": UPDATE_BRANCH, "base": "main", "title": "chore: automated flake and package updates", "body": body})
        run_url = f"{api.url}/{REPOSITORY}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
        api.status(sha, "updates", "failure" if failures else "success", "Updater failure; partial changes preserved" if failures else "All updater steps passed", run_url)
        # This PR is opened by the Forgejo Actions user, and Forgejo raises no
        # workflow events for that actor, so its `pull_request` trigger never
        # fires. The `push` trigger that used to build this branch was removed
        # to stop duplicate builds, so ask for the build explicitly. Only a
        # moved head needs one, which is what `push` would have signalled.
        if sha != before:
            api.repo("actions/workflows/build.yml/dispatches",
                data={"ref": "main", "inputs": {"pr": str(pr["number"]), "sha": sha}})
        return int(bool(failures))

if __name__ == "__main__":
    sys.exit(main())
