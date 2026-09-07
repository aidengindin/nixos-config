#!/usr/bin/env python3
"""Hermes route filter: revalidate, deduplicate, budget, prepare a checkout."""
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.request

REPO = "aidengindin/nixos-config"
BRANCH = "automation/update"


def api(path):
    request = urllib.request.Request(os.environ["FORGEJO_URL"].rstrip("/") + "/api/v1/repos/" + REPO + "/" + path,
        headers={"Authorization": "token " + os.environ["FORGEJO_TOKEN"]})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main():
    payload = json.load(sys.stdin)
    if payload.get("repository") != REPO or not re.fullmatch("[0-9a-f]{40}", payload.get("sha", "")):
        return
    pull = api(f"pulls/{int(payload['pr'])}")
    if (pull["state"] != "open" or pull["head"]["ref"] != BRANCH or pull["head"]["sha"] != payload["sha"]
            or pull["head"]["repo"]["full_name"] != REPO):
        return
    statuses = api(f"commits/{payload['sha']}/status").get("statuses", [])
    failures = [s for s in statuses if s["state"] in ("failure", "error")
        and (s["context"].startswith("colmena/") or s["context"] == "updates")
        and s.get("creator", {}).get("id") == int(os.environ["FORGEJO_BOT_ID"])]
    # Wait for the whole build to settle, so simultaneous host failures cause
    # one repair attempt. The controller retries notifications until accepted.
    if not failures or any(s["state"] == "pending" for s in statuses if s["context"].startswith("colmena/")):
        print(json.dumps({"__hermes_ignore__": True}))
        return
    cycle = re.search(r"Update-Cycle: ([0-9-]+)", pull.get("body") or "")
    if not cycle:
        return
    base = Path(os.environ.get("HERMES_REPAIR_STATE", "/var/lib/hermes/workspace/forgejo"))
    base.mkdir(parents=True, exist_ok=True)
    with (base / "repair.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state_path = base / "attempts.json"
        state = json.loads(state_path.read_text()) if state_path.exists() else {}
        key = f"{pull['number']}:{cycle[1]}"
        attempted = state.setdefault(key, [])
        if payload["sha"] in attempted or len(attempted) >= 3:
            return
        checkout = base / payload["sha"]
        # Never put the token in the remote URL or command line. Askpass reads
        # only the bot credential already supplied to this Hermes instance.
        askpass = base / "askpass"
        askpass.write_text('#!/bin/sh\ncase "$1" in *Username*) echo forgejo-update;; *) printf "%s\\n" "$FORGEJO_TOKEN";; esac\n')
        askpass.chmod(0o700)
        env = dict(os.environ, GIT_ASKPASS=str(askpass), GIT_TERMINAL_PROMPT="0")
        if not checkout.exists():
            subprocess.run(["git", "clone", "--branch", BRANCH, "--single-branch",
                os.environ["FORGEJO_URL"].rstrip("/") + "/" + REPO + ".git", str(checkout)], env=env, check=True, stdout=subprocess.DEVNULL)
        actual = subprocess.check_output(["git", "-C", str(checkout), "rev-parse", "HEAD"], text=True).strip()
        if actual != payload["sha"]:
            return
        for name, value in [("user.name", "Hermes"), ("user.email", "hermes@git.gindin.xyz"), ("core.askPass", str(askpass))]:
            subprocess.run(["git", "-C", str(checkout), "config", name, value], check=True)
        attempted.append(payload["sha"])
        temporary = state_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(state)); temporary.replace(state_path)
    logs = "\n".join(f"- {s['context']}: {s['target_url']}" for s in failures)
    print(f"""Repair automated update PR #{pull['number']} in {checkout}.
Expected head: {payload['sha']}. Attempt {len(attempted)} of 3 this update cycle.
Inspect the Forgejo build/update logs through its API using FORGEJO_TOKEN:
{logs}
Fix the underlying update or build failure. Do not change secrets, workflows,
deployment controls, or repair policy. Do not merge, deploy, force-push, or run
Colmena here. The CI VM performs all builds. Spend at most 30 minutes on this attempt.
Before pushing, verify the remote branch still equals the expected SHA; otherwise
stop and report the concurrent edit. Commit your patch and push normally to
{BRANCH}; this triggers another CI build. Use the configured Git askpass helper.
If the updater failed, rerun the failed updater steps as appropriate and publish
an `updates` status for your new SHA; do not claim success without checking them.
Post a concise result on the Forgejo PR through its API, including unresolved
failures if you cannot repair them. Do not use gh for Forgejo API calls.
""")

if __name__ == "__main__":
    main()
