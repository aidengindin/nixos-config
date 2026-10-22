#!/usr/bin/env python3
"""Bump flake inputs pinned to a GitHub release tag, with the same cooldown.

Discovery: every `<name>.url = "github:owner/repo/<tag>";` in flake.nix whose tag
starts with a version number. Candidates must share the current tag's version
scheme (calver = first component >= 1000, otherwise semver-ish); the highest
non-draft, non-prerelease release published at least COOLDOWN_DAYS ago wins and
never a version below the current pin. A scheme change upstream is reported, not
applied. The URL is rewritten and the input relocked with `nix flake update <name>`.
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


def version(tag):
    """Numeric version tuple of a release tag, or None."""
    match = re.match(r"^v?(\d+(?:\.\d+)*)$", tag)
    return tuple(int(p) for p in match[1].split(".")) if match else None


def scheme(parsed):
    return "calver" if parsed[0] >= 1000 else "semver"


def choose(releases, current, now):
    """Return (tag, held note, scheme note).

    Only releases in the same version scheme as `current` (calver when the first
    component is >= 1000) are candidates: the highest version that is stable and
    at least COOLDOWN_DAYS old, never lower than `current`. Eligible releases in
    the other scheme published after the current tag are never applied, only
    reported through the scheme note.
    """
    cutoff = now - datetime.timedelta(days=COOLDOWN_DAYS)
    here = version(current)
    stable = [(version(r["tag_name"]), r) for r in releases
        if not r.get("draft") and not r.get("prerelease") and r.get("published_at") and version(r["tag_name"])]
    same = sorted(((v, r) for v, r in stable if scheme(v) == scheme(here)), key=lambda item: item[0], reverse=True)
    best = current
    for v, r in same:
        if v >= here and parse_time(r["published_at"]) <= cutoff:
            best = r["tag_name"]
            break
    held = [f"{r['tag_name']} ({(now - parse_time(r['published_at'])).days}d old)"
        for v, r in same if v > version(best) and parse_time(r["published_at"]) > cutoff]
    current_published = next((parse_time(r["published_at"]) for v, r in same if v == here), None)
    other = [(v, r) for v, r in stable if scheme(v) != scheme(here) and parse_time(r["published_at"]) <= cutoff
        and (current_published is None or parse_time(r["published_at"]) > current_published)]
    note = ""
    if other:
        newest = max(other, key=lambda item: parse_time(item[1]["published_at"]))[0]
        latest = "v" + ".".join([str(p) for p in newest[:-1]] + ["x"]) if len(newest) > 1 else f"v{newest[0]}"
        note = f"upstream changed version scheme (latest {latest}); migrate manually"
    return best, (f"held back newer {', '.join(held)}" if held else ""), note


def update_text(text, github, now, log):
    """Return (new text, [(input name, new tag)], notes)."""
    changed, notes = [], []

    def replace(match):
        name, owner, repo, tag = match["name"], match["owner"], match["repo"], match["tag"]
        if exempt({"type": "github", "owner": owner, "repo": repo}):
            log(f"{name}: exempt")
            return match.group(0)
        try:
            new_tag, note, scheme_note = choose(github.get(f"repos/{owner}/{repo}/releases?per_page=30"), tag, now)
        except (OSError, KeyError, ValueError) as error:
            log(f"{name}: release lookup failed, left unchanged ({error})")
            notes.append(f"`{name}`: release lookup failed")
            return match.group(0)
        log(f"{name}: {tag} -> {new_tag}" + (f" [{note}]" if note else ""))
        if note:
            notes.append(f"`{name}` ({owner}/{repo}): {note}")
        if scheme_note:
            log(f"{name}: {scheme_note}")
            notes.append(f"{name}: {scheme_note}")
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
