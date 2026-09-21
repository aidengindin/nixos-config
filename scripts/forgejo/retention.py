#!/usr/bin/env python3
"""Expire superseded CI results while preserving every current PR head."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import time

from common import API, SHA

# Grace period for the final head of a PR that is no longer open, so its
# closure survives long enough to be transferred after the PR lands. Heads that
# a still-open PR has moved past are dropped immediately instead of waiting
# this out -- see superseded_heads.
RETENTION_SECONDS = 2 * 86400


def _manifest_prs(directory):
    """PR numbers recorded by build.py for a retained SHA, or None if unknown."""
    numbers = set()
    found = False
    for manifest in sorted(directory.glob("*.json")):
        try:
            payload = json.loads(manifest.read_text())
        except (OSError, ValueError):
            continue
        prs = payload.get("prs")
        if isinstance(prs, list):
            numbers.update(pr for pr in prs if isinstance(pr, int))
            found = True
    return numbers if found else None


def superseded_heads(state, pr_heads):
    """SHAs whose every known open PR has since moved to a different head.

    These are dead the moment a newer head is built: nothing will ever deploy
    them, and each one pins a full system closure per host. A PR that is no
    longer open drops out of pr_heads, so its final head is left to the age
    rule and keeps the transfer grace period.
    """
    superseded = set()
    results = state / "results"
    if not results.is_dir():
        return superseded
    for directory in results.iterdir():
        if not directory.is_dir() or not SHA.fullmatch(directory.name):
            continue
        prs = _manifest_prs(directory)
        if not prs:
            # No manifest, or one without PR numbers: fall back to the age rule
            # rather than guess.
            continue
        open_prs = [pr for pr in prs if pr in pr_heads]
        if open_prs and all(pr_heads[pr] != directory.name for pr in open_prs):
            superseded.add(directory.name)
    return superseded


def prune_retention(state, pr_heads, now=None):
    """Refresh current-head leases and remove superseded or expired state.

    pr_heads maps an open PR number to its current head SHA.
    """
    now = time.time() if now is None else now
    current_heads = set(pr_heads.values())
    # Computed before anything is deleted: it reads the results manifests.
    superseded = superseded_heads(state, pr_heads)
    removed = []
    for name in ("roots", "results"):
        parent = state / name
        parent.mkdir(parents=True, exist_ok=True)
        for directory in parent.iterdir():
            if not directory.is_dir() or not SHA.fullmatch(directory.name):
                continue
            if directory.name in current_heads:
                os.utime(directory, (now, now))
                continue
            expired = now - directory.stat().st_mtime > RETENTION_SECONDS
            if directory.name in superseded or expired:
                shutil.rmtree(directory)
                removed.append(str(directory))
    return removed


def open_pr_heads(api):
    return {pull["number"]: pull["head"]["sha"] for pull in api.pulls()}


def main():
    state = Path(os.environ.get("CI_STATE", "/var/lib/forgejo-ci"))
    pr_heads = open_pr_heads(API())
    with (state / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for path in prune_retention(state, pr_heads):
            print("Removed expired CI state:", path)


if __name__ == "__main__":
    main()
