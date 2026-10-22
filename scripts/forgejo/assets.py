#!/usr/bin/env python3
"""Bump GitHub release assets pinned in .nix files, with the same cooldown.

Discovery: every `fetchzip { ... }` / `fetchurl { ... }` block whose `url` is
`https://github.com/<owner>/<repo>/releases/download/<tag>/<asset>`. The target
tag comes from tags.choose (same version scheme, stable, at least COOLDOWN_DAYS
old, never a downgrade). The new asset name substitutes the version in the old
file name (a name without the version, such as `Chromium.Web.Store.crx`, stays
fixed) and must appear in the chosen release's asset list, otherwise the pin is
left and a problem is reported. The hash is of the unpacked tree for fetchzip and
of the file for fetchurl; only that block's url and hash are rewritten.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import subprocess
import sys

from cooldown import ROOT, GitHub, exempt
import tags

BLOCK = re.compile(r"\b(?P<fetcher>fetchzip|fetchurl)\s*\{[^{}]*\}")
URL = re.compile(r'url\s*=\s*"https://github\.com/(?P<owner>[^/"]+)/(?P<repo>[^/"]+)/releases/download/(?P<tag>[^/"]+)/(?P<asset>[^/"]+)"')
HASH = re.compile(r'(?P<key>sha256|hash)\s*=\s*"[^"]*"')


def asset_name(old_asset, old_tag, new_tag):
    old, new = old_tag.lstrip("v"), new_tag.lstrip("v")
    return old_asset.replace(old, new) if old in old_asset else old_asset


def prefetch(url, unpack):
    """SRI sha256 of the downloaded file, or of its unpacked tree."""
    command = ["nix-prefetch-url", *(["--unpack"] if unpack else []), url]
    flat = subprocess.run(command, check=True, capture_output=True, text=True, timeout=1800).stdout.strip().splitlines()[-1]
    return subprocess.run(["nix", "hash", "convert", "--hash-algo", "sha256", "--from", "nix32", flat],
        check=True, capture_output=True, text=True, timeout=120).stdout.strip()


def update_text(text, github, now, log, hasher=prefetch):
    """Return (new text, [(url, new tag)], held notes, problems)."""
    changed, notes, problems, releases = [], [], [], {}

    def replace(match):
        block = match.group(0)
        found = URL.search(block)
        if not found or not HASH.search(block):
            return block
        owner, repo, tag, asset = found["owner"], found["repo"], found["tag"], found["asset"]
        label = f"{owner}/{repo}"
        if tags.version(tag) is None or exempt({"type": "github", "owner": owner, "repo": repo}):
            log(f"{label}: skipped")
            return block
        try:
            if (owner, repo) not in releases:
                releases[owner, repo] = github.get(f"repos/{owner}/{repo}/releases?per_page=30")
            listing = releases[owner, repo]
            new_tag, note, scheme_note = tags.choose(listing, tag, now)
        except (OSError, KeyError, ValueError) as error:
            log(f"{label}: release lookup failed, left unchanged ({error})")
            problems.append(f"`{label}`: release lookup failed")
            return block
        if note:
            notes.append(f"`{label}` {asset}: {note}")
        if scheme_note:
            notes.append(f"`{label}`: {scheme_note}")
        log(f"{label}: {tag} -> {new_tag}" + (f" [{note}]" if note else ""))
        if new_tag == tag:
            return block
        new_asset = asset_name(asset, tag, new_tag)
        release = next((r for r in listing if r["tag_name"] == new_tag), {})
        if new_asset not in [a["name"] for a in release.get("assets", [])]:
            log(f"{label}: {new_asset} missing from {new_tag}, left unchanged")
            problems.append(f"`{label}`: release {new_tag} has no asset `{new_asset}`; pin left at {tag}")
            return block
        new_url = f"https://github.com/{owner}/{repo}/releases/download/{new_tag}/{new_asset}"
        try:
            new_hash = hasher(new_url, match["fetcher"] == "fetchzip")
        except (OSError, subprocess.SubprocessError, IndexError) as error:
            log(f"{label}: hashing {new_url} failed ({error})")
            problems.append(f"`{label}`: could not hash `{new_asset}` from {new_tag}")
            return block
        changed.append((new_url, new_tag))
        block = block.replace(found.group(0), found.group(0).replace(f"/{tag}/{asset}", f"/{new_tag}/{new_asset}"))
        return HASH.sub(lambda m: f'{m["key"]} = "{new_hash}"', block)

    return BLOCK.sub(replace, text), changed, notes, problems


def nix_files(root):
    return sorted(p for p in Path(root).rglob("*.nix")
        if not any(part.startswith(".") or part == "result" for part in p.relative_to(root).parts))


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--report")
    parser.add_argument("--root", default=str(ROOT))
    args = parser.parse_args(argv)
    now = datetime.datetime.now(datetime.timezone.utc)
    github, held, problems = GitHub(), [], []
    for path in nix_files(args.root):
        text = path.read_text()
        if "releases/download/" not in text:
            continue
        new, changed, notes, errors = update_text(text, github, now, print,
            hasher=(lambda url, unpack: "(dry run, not hashed)") if args.dry_run else prefetch)
        held += notes
        problems += errors
        if changed and not args.dry_run:
            path.write_text(new)
    if args.report:
        Path(args.report).write_text(json.dumps({"held": held, "problems": problems}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
