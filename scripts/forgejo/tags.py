#!/usr/bin/env python3
"""Bump flake inputs pinned to a GitHub release tag, with the same cooldown.

Discovery: every `<name>.url = "github:owner/repo/<tag>";` in flake.nix whose tag
starts with a version number. The newest non-draft, non-prerelease GitHub release
published at least COOLDOWN_DAYS ago wins. "Newest" is by publication time, not
by version, because projects change tag schemes (calver to semver); a release
is never chosen over the current tag unless it was published after it. The URL
is rewritten and the input relocked with `nix flake update <name>`.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys

from cooldown import COOLDOWN_DAYS, ROOT, GitHub, exempt

TAG_INPUT = re.compile(r'(?P<name>[A-Za-z0-9_-]+)\.url\s*=\s*"github:(?P<owner>[^/"]+)/(?P<repo>[^/"]+)/(?P<tag>v?\d[^"]*)"')


def parse_time(text):
    return datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))


def choose(releases, current, now):
    """Return (tag, note): the newest eligible release tag, or `current`."""
    cutoff = now - datetime.timedelta(days=COOLDOWN_DAYS)
    stable = sorted((r for r in releases if not r.get("draft") and not r.get("prerelease") and r.get("published_at")),
        key=lambda r: parse_time(r["published_at"]), reverse=True)
    held = []
    for release in stable:
        if release["tag_name"] == current:
            return current, (f"held back newer {', '.join(held)}" if held else "")
        if parse_time(release["published_at"]) <= cutoff:
            return release["tag_name"], (f"held back newer {', '.join(held)}" if held else "")
        held.append(f"{release['tag_name']} ({(now - parse_time(release['published_at'])).days}d old)")
    return current, (f"held back newer {', '.join(held)}" if held else "")


def update_text(text, github, now, log):
    """Return (new text, [(input name, new tag)], notes)."""
    changed, notes = [], []

    def replace(match):
        name, owner, repo, tag = match["name"], match["owner"], match["repo"], match["tag"]
        if exempt({"type": "github", "owner": owner, "repo": repo}):
            log(f"{name}: exempt")
            return match.group(0)
        try:
            new_tag, note = choose(github.get(f"repos/{owner}/{repo}/releases?per_page=30"), tag, now)
        except (OSError, KeyError, ValueError) as error:
            log(f"{name}: release lookup failed, left unchanged ({error})")
            notes.append(f"`{name}`: release lookup failed")
            return match.group(0)
        log(f"{name}: {tag} -> {new_tag}" + (f" [{note}]" if note else ""))
        if note:
            notes.append(f"`{name}` ({owner}/{repo}): {note}")
        if new_tag != tag:
            changed.append((name, new_tag))
        return match.group(0).replace(f"/{tag}\"", f"/{new_tag}\"")

    return TAG_INPUT.sub(replace, text), changed, notes


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--report")
    parser.add_argument("--flake", default=str(ROOT / "flake.nix"))
    args = parser.parse_args(argv)
    path = Path(args.flake)
    now = datetime.datetime.now(datetime.timezone.utc)
    text = path.read_text()
    new, changed, notes = update_text(text, GitHub(), now, print)
    if args.report:
        Path(args.report).write_text(json.dumps({"held": notes}))
    if args.dry_run or not changed:
        return 0
    path.write_text(new)
    for name, _ in changed:
        subprocess.run(["nix", "flake", "update", name], check=True, cwd=path.parent, timeout=1800)
    return 0


if __name__ == "__main__":
    sys.exit(main())
