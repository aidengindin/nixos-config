#!/usr/bin/env python3
"""Staged migration. Each subcommand is explicit; cutover requires verification."""
import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import time
from common import API, REPOSITORY, atomic_json


def gh(path, paginate=True):
    args = ["gh", "api", path]
    if paginate:
        args += ["--paginate", "--slurp"]
    value = json.loads(subprocess.check_output(args, text=True))
    return [item for page in value for item in page] if paginate else value


def refs(url):
    output = subprocess.check_output(["git", "ls-remote", "--heads", "--tags", url], text=True)
    return {ref: sha for sha, ref in (line.split() for line in output.splitlines())}


def snapshot(directory):
    directory.mkdir(parents=True, exist_ok=False)
    os.chmod(directory, 0o700)
    remote = f"git@github.com:{REPOSITORY}.git"
    subprocess.run(["git", "clone", "--mirror", remote, str(directory / "repository.git")], check=True)
    subprocess.run(["git", "-C", str(directory / "repository.git"), "bundle", "create", str(directory / "repository.bundle"), "--all"], check=True)
    data = {"repository": gh(f"repos/{REPOSITORY}", False), "refs": refs(remote)}
    for endpoint in ["pulls?state=all", "issues?state=all", "issues/comments", "labels", "milestones?state=all", "releases"]:
        data[endpoint] = gh(f"repos/{REPOSITORY}/{endpoint}" + ("&" if "?" in endpoint else "?") + "per_page=100")
    data["pull_details"] = {}
    for pr in data["pulls?state=all"]:
        number = pr["number"]
        data["pull_details"][number] = {
            "pull": gh(f"repos/{REPOSITORY}/pulls/{number}", False),
            "reviews": gh(f"repos/{REPOSITORY}/pulls/{number}/reviews?per_page=100"),
            "review_comments": gh(f"repos/{REPOSITORY}/pulls/{number}/comments?per_page=100"),
        }
    atomic_json(directory / "github.json", data)
    print(f"Snapshot saved; {len(data['pulls?state=all'])} PRs.")


def pages(api, endpoint):
    result, page = [], 1
    while True:
        items = api.repo(endpoint + ("&" if "?" in endpoint else "?") + f"limit=50&page={page}")
        result.extend(items)
        if len(items) < 50:
            return result
        page += 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["snapshot", "import", "verify", "mirror", "cutover"])
    parser.add_argument("--snapshot", type=Path, required=True)
    args = parser.parse_args()
    directory = args.snapshot.resolve()
    if args.phase == "snapshot":
        snapshot(directory); return
    api = API()
    source = json.loads((directory / "github.json").read_text())
    if args.phase == "import":
        api.request("repos/migrate", timeout=600, data={
            "clone_addr": f"https://github.com/{REPOSITORY}.git",
            "auth_token": os.environ["GITHUB_MIGRATION_TOKEN"],
            "repo_owner": "aidengindin", "repo_name": "nixos-config", "service": "github",
            "mirror": False, "private": False, "issues": True, "labels": True,
            "milestones": True, "pull_requests": True, "releases": True, "wiki": True,
        })
        print("Import requested. Wait for Forgejo to finish, then run verify.")
    elif args.phase == "verify":
        forge_refs = refs(api.url + "/" + REPOSITORY + ".git")
        github_refs = refs(f"git@github.com:{REPOSITORY}.git")
        pull_requests = pages(api, "pulls?state=all")
        issues = pages(api, "issues?state=all&type=issues")
        report = {
            "verified_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "github_unchanged_since_snapshot": github_refs == source["refs"],
            "refs_equal": forge_refs == github_refs,
            "github_prs": len(source["pulls?state=all"]), "forgejo_prs": len(pull_requests),
            "github_issues": sum("pull_request" not in i for i in source["issues?state=all"]),
            "forgejo_issues": len(issues),
            "pr_titles_equal": sorted(p["title"] for p in source["pulls?state=all"]) == sorted(p["title"] for p in pull_requests),
            "labels_equal": sorted(i["name"] for i in source["labels"]) == sorted(i["name"] for i in pages(api, "labels")),
            "release_tags_equal": sorted(i["tag_name"] for i in source["releases"]) == sorted(i["tag_name"] for i in pages(api, "releases")),
            "limitations": ["GitHub review identities, review states, Actions logs, and cross-references need manual spot checks; source export retains reviews/comments.",
                "Wiki contents and release attachments require manual verification before cutover."],
        }
        report["passed"] = (report["github_unchanged_since_snapshot"] and report["refs_equal"] and report["pr_titles_equal"]
            and report["labels_equal"] and report["release_tags_equal"] and report["github_issues"] == report["forgejo_issues"])
        atomic_json(directory / "verification.json", report)
        print(json.dumps(report, indent=2))
        if not report["passed"]:
            raise SystemExit(1)
    elif args.phase == "mirror":
        report = json.loads((directory / "verification.json").read_text())
        if not report["passed"]:
            raise SystemExit("Verify the import before configuring its force-push mirror")
        github_refs = refs(f"git@github.com:{REPOSITORY}.git")
        forge_refs = refs(api.url + "/" + REPOSITORY + ".git")
        if github_refs != source["refs"] or any(forge_refs.get(ref) != sha for ref, sha in github_refs.items()):
            raise SystemExit("An original ref diverged after verification")
        # Additional Forgejo branches (e.g. the implementation PR) are safe to
        # mirror; every original GitHub ref must still match the snapshot.
        api.repo("push_mirrors", data={"remote_address": f"https://github.com/{REPOSITORY}.git",
            "remote_username": "aidengindin", "remote_password": os.environ["GITHUB_MIRROR_TOKEN"],
            "interval": "1h0m0s", "sync_on_commit": True})
        api.repo("push_mirrors-sync", data={})
        print("Mirror configured. Verify last_error and last_update before cutover.")
    elif args.phase == "cutover":
        report = json.loads((directory / "verification.json").read_text())
        if not report["passed"] or not (directory / "manual-verification-complete").exists():
            raise SystemExit("Complete import, CI, restore, and manual metadata checks first; see docs/forgejo.md")
        mirrors = api.repo("push_mirrors")
        if not mirrors or any(m.get("last_error") or not m.get("last_update") for m in mirrors):
            raise SystemExit("Mirror has not synchronized successfully")
        if refs(f"git@github.com:{REPOSITORY}.git") != refs(api.url + "/" + REPOSITORY + ".git"):
            raise SystemExit("Mirror refs are not synchronized")
        subprocess.run(["gh", "api", "--method", "PUT", f"repos/{REPOSITORY}/actions/permissions", "-F", "enabled=false"], check=True)
        subprocess.run(["gh", "api", "--method", "PATCH", f"repos/{REPOSITORY}", "-f", "description=Read-only mirror. Development: " + api.url + "/" + REPOSITORY,
            "-f", "homepage=" + api.url + "/" + REPOSITORY], check=True)
        remotes = subprocess.check_output(["git", "remote"], text=True).splitlines()
        if "github" not in remotes:
            subprocess.run(["git", "remote", "add", "github", f"git@github.com:{REPOSITORY}.git"], check=True)
        subprocess.run(["git", "remote", "set-url", "origin", f"ssh://git@{api.url.split('://',1)[1]}:2222/{REPOSITORY}.git"], check=True)
        print("Cutover complete. Enable the Forgejo update schedule after confirming GitHub Actions is disabled.")

if __name__ == "__main__":
    main()
