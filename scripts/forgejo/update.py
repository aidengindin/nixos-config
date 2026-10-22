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
# nix-update is taken from the flake's own locked nixpkgs (`--inputs-from .`),
# never from the mutable global registry.
NIX_UPDATE = ["nix", "run", "--inputs-from", ".", "nixpkgs#nix-update", "--"]
COMMANDS = [
    ["nix", "flake", "update"],
    [sys.executable, str(SCRIPTS / "cooldown.py"), "--report", "{reports}/cooldown.json"],
    [sys.executable, str(SCRIPTS / "tags.py"), "--report", "{reports}/tags.json"],
    # A tag bump can pull in new transitive inputs at their newest commits.
    [sys.executable, str(SCRIPTS / "cooldown.py"), "--report", "{reports}/cooldown-tags.json"],
    [*NIX_UPDATE, "--flake", "catppuccin-userstyles", "--version=unstable"],
    [*NIX_UPDATE, "--flake", "intervals-mcp-server", "--version=branch"],
    *[["bash", "scripts/" + name] for name in ["update-caddy-hash.sh", "update-ublock-hash.sh",
        "update-claude-desktop.sh", "update-chatgpt-desktop.sh"]],
    [sys.executable, str(SCRIPTS / "images.py"), "--report", "{reports}/images.json"],
]


def git(*args, capture=False):
    return subprocess.check_output(["git", *args], text=True).strip() if capture else subprocess.run(["git", *args], check=True)


def read_reports(directory):
    reports = {}
    for name in ("cooldown", "cooldown-tags", "tags", "images"):
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
    notes = reports["tags"].get("held", []) + reports["images"].get("held", [])
    if notes:
        lines += ["Tags and container images held back by the cooldown:", ""] + ["- " + n for n in notes] + [""]
    if reports["images"].get("problems"):
        lines += ["Image pinning problems:", ""] + ["- " + p for p in reports["images"]["problems"]] + [""]
    return "\n".join(lines)


def main():
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
        for command in COMMANDS:
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
            git("commit", "--allow-empty", "-m", f"chore: automated update {cycle}")
        # A normal push refuses a concurrently updated remote branch.
        git("push", "origin", f"HEAD:refs/heads/{UPDATE_BRANCH}")
        sha = git("rev-parse", "HEAD", capture=True)
        body = f"Automated flake and custom package updates.\n\nUpdate-Cycle: {cycle}\n\n"
        body += "Updater failures:\n" + "\n".join("- `" + f + "`" for f in failures) if failures else "All updater steps completed."
        body += "\n\n" + cooldown_section(read_reports(reports_dir))
        body += "\n\nCI builds lorien, osgiliath, and khazad-dum. Merge manually; use `/deploy @server` or individual hosts to deploy this PR."
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
