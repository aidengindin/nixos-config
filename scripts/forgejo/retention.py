#!/usr/bin/env python3
"""Expire superseded CI results while preserving every current PR head."""
import fcntl
import os
from pathlib import Path
import shutil
import time

from common import API, SHA

RETENTION_SECONDS = 7 * 86400


def prune_retention(state, current_heads, now=None):
    """Refresh current-head leases and remove expired roots, logs, and manifests."""
    now = time.time() if now is None else now
    removed = []
    for name in ("roots", "results"):
        parent = state / name
        parent.mkdir(parents=True, exist_ok=True)
        for directory in parent.iterdir():
            if not directory.is_dir() or not SHA.fullmatch(directory.name):
                continue
            if directory.name in current_heads:
                os.utime(directory, (now, now))
            elif now - directory.stat().st_mtime > RETENTION_SECONDS:
                shutil.rmtree(directory)
                removed.append(str(directory))
    return removed


def main():
    state = Path(os.environ.get("CI_STATE", "/var/lib/forgejo-ci"))
    current_heads = {pull["head"]["sha"] for pull in API().pulls()}
    with (state / "build.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        for path in prune_retention(state, current_heads):
            print("Removed expired CI state:", path)


if __name__ == "__main__":
    main()
