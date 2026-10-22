#!/usr/bin/env python3
"""Keep OCI images in services/*.nix pinned to `tag@sha256:digest` and bump them
within their release track, but only to images at least COOLDOWN_DAYS old.

The image list is discovered, not declared: every quoted string in services/*.nix
of the form `registry/repo:tag@sha256:<64 hex>` is a managed image. Adding an
image therefore means writing it pinned (use `images.py resolve repo:tag`).
Unpinned image strings are reported as failures rather than silently ignored.

Track rules: the tag is split into prefix, a dotted numeric version and suffix
(`0.8.7-pg18` -> "", 0.8.7, "-pg18"). A candidate must share prefix, suffix and
component count, must be >= the current version, and must share the major (or
major.minor while the major is 0, where minors are breaking). Tags containing
rc/beta/alpha/dev/nightly/... are ignored. Age comes from the image config's
`created` field, so a re-tag of an old image cannot dodge the cooldown.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

COOLDOWN_DAYS = 7
MAX_INSPECTS = 12
ROOT = Path(__file__).resolve().parents[2]
PINNED = re.compile(r'"((?:[a-z0-9.-]+(?::\d+)?/)?[a-z0-9._/-]+):([A-Za-z0-9._-]+)@sha256:([0-9a-f]{64})"')
IMAGE_STRING = re.compile(r'[iI]mage\s*=\s*(?:mkOption\s*\{[^}]*?default\s*=\s*)?"([^"$]+)"')
VERSIONED = re.compile(r"^(?P<prefix>[A-Za-z_-]*?)(?P<version>\d+(?:\.\d+)+)(?P<suffix>(?:[-_.][A-Za-z0-9._-]+)?)$")
PRERELEASE = re.compile(r"(?i)(?:^|[-_.])(rc|alpha|beta|dev|nightly|snapshot|preview|pre|canary|edge|test|unstable)\d*(?:$|[-_.])")


def parse_tag(tag):
    """Return (prefix, version tuple, suffix) or None for non-version tags."""
    match = VERSIONED.match(tag)
    if not match:
        return None
    return match["prefix"], tuple(int(p) for p in match["version"].split(".")), match["suffix"]


def track(version):
    return version[:1] if version[0] else version[:2]


def candidates(current, tags):
    """Tags in the same track as `current`, newest first, current included."""
    parsed = parse_tag(current)
    if not parsed:
        return []
    prefix, version, suffix = parsed
    found = []
    for tag in tags:
        other = parse_tag(tag)
        if (not other or PRERELEASE.search(tag) or other[0] != prefix or other[2] != suffix
                or len(other[1]) != len(version) or other[1] < version
                or track(other[1]) != track(version)):
            continue
        found.append((other[1], tag))
    return [tag for _, tag in sorted(found, reverse=True)]


class Registry:
    """skopeo wrapper. An empty registries.conf avoids host v1-format files."""

    def __init__(self):
        self.directory = tempfile.TemporaryDirectory()
        self.conf = Path(self.directory.name, "registries.conf")
        self.conf.write_text("")

    def skopeo(self, *args):
        return subprocess.run(["skopeo", "--registries-conf", str(self.conf), *args],
            check=True, capture_output=True, timeout=300).stdout

    def tags(self, repository):
        return json.loads(self.skopeo("list-tags", f"docker://{repository}"))["Tags"]

    def digest(self, repository, tag):
        return "sha256:" + hashlib.sha256(self.skopeo("inspect", "--raw", f"docker://{repository}:{tag}")).hexdigest()

    def created(self, repository, tag):
        config = json.loads(self.skopeo("inspect", "--config", "--override-os", "linux",
            "--override-arch", "amd64", f"docker://{repository}:{tag}"))
        return datetime.datetime.fromisoformat(config["created"].replace("Z", "+00:00"))


def decide(repository, tag, registry, now):
    """Return (new tag, note). The new tag equals `tag` when nothing is eligible."""
    options = candidates(tag, registry.tags(repository))
    newer = [t for t in options if t != tag]
    cutoff = now - datetime.timedelta(days=COOLDOWN_DAYS)
    held = []
    for option in newer[:MAX_INSPECTS]:
        created = registry.created(repository, option)
        if created <= cutoff:
            note = f"held back newer {', '.join(held)}" if held else ""
            return option, note
        held.append(f"{option} ({(now - created).days}d old)")
    return tag, (f"held back newer {', '.join(held)}" if held else "")


def update_text(text, registry, now, log):
    """Rewrite pinned images in `text`; returns (new text, held-back notes)."""
    notes = []

    def replace(match):
        repository, tag, digest = match.groups()
        try:
            new_tag, note = decide(repository, tag, registry, now)
            new_digest = f"sha256:{digest}" if new_tag == tag else registry.digest(repository, new_tag)
        except (subprocess.SubprocessError, OSError, KeyError, ValueError) as error:
            log(f"{repository}:{tag}: lookup failed, left unchanged ({error})")
            notes.append(f"`{repository}:{tag}`: lookup failed")
            return match.group(0)
        log(f"{repository}:{tag} -> {new_tag}" + (f" [{note}]" if note else ""))
        if note:
            notes.append(f"`{repository}:{tag}`: {note}")
        return f'"{repository}:{new_tag}@{new_digest}"'

    return PINNED.sub(replace, text), notes


def unpinned(text):
    return [ref for ref in IMAGE_STRING.findall(text) if "/" in ref and not PINNED.search(f'"{ref}"')]


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="print decisions without writing")
    parser.add_argument("--report", help="write held-back notes to this JSON file")
    parser.add_argument("--root", default=str(ROOT))
    parser.add_argument("resolve", nargs="*", help="`resolve repo:tag` prints the pinned form")
    args = parser.parse_args(argv)
    registry = Registry()
    if args.resolve[:1] == ["resolve"]:
        for ref in args.resolve[1:]:
            repository, tag = ref.rsplit(":", 1)
            print(f"{repository}:{tag}@{registry.digest(repository, tag)}  created {registry.created(repository, tag).isoformat()}")
        return 0
    now = datetime.datetime.now(datetime.timezone.utc)
    notes, problems = [], []
    for path in sorted(Path(args.root, "services").glob("*.nix")):
        text = path.read_text()
        for ref in unpinned(text):
            problems.append(f"{path.name}: unpinned image {ref}")
        new, file_notes = update_text(text, registry, now, lambda line, n=path.name: print(f"{n}: {line}", flush=True))
        notes += file_notes
        if new != text and not args.dry_run:
            path.write_text(new)
    for problem in problems:
        print("WARNING:", problem, file=sys.stderr)
    if args.report:
        Path(args.report).write_text(json.dumps({"held": notes, "problems": problems}))
    return int(bool(problems))


if __name__ == "__main__":
    sys.exit(main())
