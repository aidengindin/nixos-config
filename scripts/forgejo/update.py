#!/usr/bin/env python3
"""Preserve partial updater edits, then open/update the single automation PR."""
import datetime
import fcntl
import os
from pathlib import Path
import subprocess
import sys
from common import API, REPOSITORY, UPDATE_BRANCH

COMMANDS = [
    ["nix", "flake", "update"],
    ["nix", "run", "nixpkgs#nix-update", "--", "--flake", "catppuccin-userstyles", "--version=unstable"],
    ["nix", "run", "nixpkgs#nix-update", "--", "--flake", "intervals-mcp-server", "--version=branch"],
    *[["bash", "scripts/" + name] for name in ["update-caddy-hash.sh", "update-ublock-hash.sh",
        "update-claude-desktop.sh", "update-chatgpt-desktop.sh"]],
]
# calibre-plugins bundles multiple sources; withings-sync inherits its version
# from nixpkgs. Neither is safe to hand to nix-update automatically.


def git(*args, capture=False):
    return subprocess.check_output(["git", *args], text=True).strip() if capture else subprocess.run(["git", *args], check=True)


def main():
    api = API()
    with open("/var/lib/forgejo-ci/update.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        git("config", "user.name", "forgejo-update")
        git("config", "user.email", "forgejo-update@git.gindin.xyz")
        pulls = [p for p in api.pulls() if p["head"]["ref"] == UPDATE_BRANCH]
        git("fetch", "origin", "main")
        remote_branch = subprocess.run(["git", "ls-remote", "--exit-code", "--heads", "origin", UPDATE_BRANCH], stdout=subprocess.DEVNULL).returncode == 0
        if remote_branch:
            git("fetch", "origin", UPDATE_BRANCH)
            git("checkout", "-B", UPDATE_BRANCH, "FETCH_HEAD")
            # Refuse to overwrite repairs or human changes; merging main is a
            # normal fast-forward/non-rewriting merge and conflicts fail visibly.
            git("merge", "--no-edit", "origin/main")
        else:
            git("checkout", "-B", UPDATE_BRANCH, "origin/main")
        failures = []
        for command in COMMANDS:
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
        body += "\n\nCI builds all four hosts. Merge manually; use `/deploy @server` or individual hosts to deploy this PR."
        if pulls:
            pr = pulls[0]
            api.repo(f"pulls/{pr['number']}", data={"body": body}, method="PATCH")
        else:
            pr = api.repo("pulls", data={"head": UPDATE_BRANCH, "base": "main", "title": "chore: automated flake and package updates", "body": body})
        run_url = f"{api.url}/{REPOSITORY}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
        api.status(sha, "updates", "failure" if failures else "success", "Updater failure; partial changes preserved" if failures else "All updater steps passed", run_url)
        return int(bool(failures))

if __name__ == "__main__":
    sys.exit(main())
