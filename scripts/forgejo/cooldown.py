#!/usr/bin/env python3
"""Supply-chain cooldown for flake.lock, run right after `nix flake update`.

Every lock node (including transitive ones) whose newly locked commit is younger
than COOLDOWN_DAYS is re-pinned to the newest commit on the same ref that is old
enough. Only `locked.{rev,narHash,lastModified}` change; `original` is untouched.
If the pre-update lock already pinned a rev that is old enough and equals the
newest eligible commit, that locked entry is restored verbatim (no prefetch).
A baseline entry is never replaced by an older commit.

Exempt: NixOS-owned nixpkgs channel branches, home-manager, the owner's own
repositories and anything on git.gindin.xyz. Non-GitHub nodes that are young and
not exempt cannot be handled and are reported.
"""
import argparse
import copy
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.parse
import urllib.request

COOLDOWN_DAYS = 7
ROOT = Path(__file__).resolve().parents[2]
OWN_OWNERS = {"aidengindin"}
CHANNEL = re.compile(r"^(nixos|nixpkgs|release)-")
VERSION_TAG = re.compile(r"^v?\d+(\.\d+)*$")


def exempt(original):
    """True when the input is trusted enough to skip the cooldown."""
    kind = original.get("type")
    owner, repo = (original.get("owner") or "").lower(), (original.get("repo") or "").lower()
    if kind == "github":
        return (owner in OWN_OWNERS
            or (owner == "nixos" and repo == "nixpkgs" and bool(CHANNEL.match(original.get("ref") or "")))
            or (owner == "nix-community" and repo == "home-manager"))
    host = urllib.parse.urlparse(original.get("url") or "").hostname or ""
    return host == "git.gindin.xyz" or (kind == "tarball" and host == "channels.nixos.org")


def immutable(original):
    """Pinned to a rev or a version tag: nothing floats, nothing to delay."""
    return bool(original.get("rev")) or bool(VERSION_TAG.match(original.get("ref") or ""))


def age_days(timestamp, now):
    return round((now.timestamp() - timestamp) / 86400, 1)


class GitHub:
    def __init__(self, token=None):
        self.token = token if token is not None else os.environ.get("GH_TOKEN", "")

    def get(self, path):
        request = urllib.request.Request("https://api.github.com/" + path,
            headers={"Accept": "application/vnd.github+json", **({"Authorization": "Bearer " + self.token} if self.token else {})})
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read())

    def commit_before(self, owner, repo, ref, until):
        """Newest (rev, unix time) on `ref` (default branch when None) at or before `until`."""
        query = {"until": until.strftime("%Y-%m-%dT%H:%M:%SZ"), "per_page": "1"}
        if ref:
            query["sha"] = ref
        commits = self.get(f"repos/{owner}/{repo}/commits?" + urllib.parse.urlencode(query))
        if not commits:
            return None
        when = datetime.datetime.fromisoformat(commits[0]["commit"]["committer"]["date"].replace("Z", "+00:00"))
        return commits[0]["sha"], int(when.timestamp())

    def head_time(self, owner, repo, ref):
        query = {"per_page": "1", **({"sha": ref} if ref else {})}
        commits = self.get(f"repos/{owner}/{repo}/commits?" + urllib.parse.urlencode(query))
        when = datetime.datetime.fromisoformat(commits[0]["commit"]["committer"]["date"].replace("Z", "+00:00"))
        return int(when.timestamp())

    def prefetch(self, owner, repo, rev):
        out = subprocess.check_output(["nix", "flake", "prefetch", f"github:{owner}/{repo}/{rev}", "--json"], text=True, timeout=600)
        data = json.loads(out)
        locked = data.get("locked", {})
        return {"rev": rev, "narHash": data.get("hash") or locked["narHash"], "lastModified": locked["lastModified"]}


def apply_cooldown(lock, baseline, now, github, prefetch=True):
    """Return (new lock, decisions, held, unhandled). Decisions are printable strings."""
    lock = copy.deepcopy(lock)
    cutoff = now - datetime.timedelta(days=COOLDOWN_DAYS)
    decisions, held, unhandled = [], [], []
    for name, node in sorted(lock["nodes"].items()):
        locked, original = node.get("locked"), node.get("original")
        if not locked or not original:
            continue
        if exempt(original):
            decisions.append(f"{name}: exempt")
            continue
        if immutable(original):
            decisions.append(f"{name}: pinned to a rev or tag, skipped")
            continue
        if locked["lastModified"] <= cutoff.timestamp():
            decisions.append(f"{name}: ok ({age_days(locked['lastModified'], now)}d old)")
            continue
        if original.get("type") != "github" or original.get("host"):
            decisions.append(f"{name}: {age_days(locked['lastModified'], now)}d old, type {original.get('type')} unsupported")
            unhandled.append(f"`{name}` ({original.get('type')}, locked {age_days(locked['lastModified'], now)}d ago)")
            continue
        owner, repo, ref = locked["owner"], locked["repo"], original.get("ref")
        head_age = age_days(locked["lastModified"], now)
        found = github.commit_before(owner, repo, ref, cutoff)
        base = (baseline or {}).get("nodes", {}).get(name, {})
        base_locked = base.get("locked") if base.get("original") == original else None
        if found is None and not base_locked:
            decisions.append(f"{name}: no commit older than {COOLDOWN_DAYS}d; left at {head_age}d old")
            held.append({"name": name, "repo": f"{owner}/{repo}", "upstream_head_age_days": head_age,
                "pinned_age_days": head_age, "pinned_rev": locked["rev"], "note": "no eligible commit, left as updated"})
            continue
        if base_locked and (found is None or base_locked["lastModified"] >= found[1]):
            # Never downgrade the committed lock, and a baseline already equal
            # to the newest eligible commit is kept byte for byte.
            new = {k: base_locked[k] for k in ("rev", "narHash", "lastModified")}
            how = "kept baseline"
        else:
            new = ({"rev": found[0], "narHash": "", "lastModified": found[1]} if not prefetch
                else github.prefetch(owner, repo, found[0]))
            how = "re-pinned"
        pinned_age = age_days(new["lastModified"], now)
        if new["rev"] == locked["rev"]:
            decisions.append(f"{name}: {head_age}d old but already in the committed lock; not downgrading")
            continue
        decisions.append(f"{name}: head {locked['rev'][:10]} is {head_age}d old; {how} to {new['rev'][:10]} ({pinned_age}d old)")
        held.append({"name": name, "repo": f"{owner}/{repo}", "upstream_head_age_days": head_age,
            "pinned_age_days": pinned_age, "pinned_rev": new["rev"]})
        node["locked"] = {**locked, **new}
    return lock, decisions, held, unhandled


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="print decisions without writing or prefetching")
    parser.add_argument("--report", help="write held-back inputs to this JSON file")
    parser.add_argument("--lock", default=str(ROOT / "flake.lock"))
    parser.add_argument("--baseline", help="pre-update lock (default: flake.lock at HEAD)")
    args = parser.parse_args(argv)
    path = Path(args.lock)
    lock = json.loads(path.read_text())
    if args.baseline:
        baseline = json.loads(Path(args.baseline).read_text())
    else:
        shown = subprocess.run(["git", "show", "HEAD:flake.lock"], capture_output=True, text=True, cwd=path.parent)
        baseline = json.loads(shown.stdout) if shown.returncode == 0 else None
    now = datetime.datetime.now(datetime.timezone.utc)
    github = GitHub()
    new, decisions, held, unhandled = apply_cooldown(lock, baseline, now, github, prefetch=not args.dry_run)
    for line in decisions:
        print(line)
    if args.report:
        Path(args.report).write_text(json.dumps({"held": held, "unhandled": unhandled}))
    if args.dry_run:
        return 0
    if new != lock:
        original_text = path.read_text()
        path.write_text(json.dumps(new, indent=2, ensure_ascii=False) + "\n")
        # The edited lock must satisfy Nix without being re-locked. If an older
        # commit changed a flake's own inputs the lock is inconsistent: restore
        # the un-cooled lock rather than commit something that cannot evaluate.
        try:
            subprocess.run(["nix", "flake", "metadata", "--no-update-lock-file", "--json"], check=True,
                cwd=path.parent, stdout=subprocess.DEVNULL, timeout=1800)
        except (subprocess.SubprocessError, OSError):
            path.write_text(original_text)
            print("ERROR: cooled lock needs re-locking; restored the uncooled lock", file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
