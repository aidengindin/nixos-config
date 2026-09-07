#!/usr/bin/env python3
"""Provision accounts, repository automation, and encrypted runtime credentials.

Run accounts after Forgejo starts; run automation after importing the repository.
Temporary bootstrap credentials are mode 0600 and never printed.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import subprocess
import urllib.error
import urllib.request
from common import API, HOSTS, REPOSITORY, atomic_json


def basic(api, user, password, path, data):
    auth = base64.b64encode((user + ":" + password).encode()).decode()
    request = urllib.request.Request(api.url + "/api/v1/" + path, data=json.dumps(data).encode(),
        headers={"Authorization": "Basic " + auth, "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def encrypt_env(path, values, recipients, age):
    text = "".join(f'{key}={value}\n' for key, value in values.items())
    command = [age]
    for recipient in recipients:
        command += ["-r", recipient]
    # Write atomically, since agenix declarations detect these files at eval time.
    temporary = path.with_suffix(".age.new")
    with temporary.open("wb") as output:
        subprocess.run(command, input=text.encode(), stdout=output, check=True)
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["accounts", "automation"])
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--recovery-password-file", type=Path)
    parser.add_argument("--age", default="age")
    args = parser.parse_args()
    os.umask(0o077)
    args.state.mkdir(parents=True, exist_ok=True)
    state_file = args.state / "credentials.json"
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    url = os.environ.get("FORGEJO_URL", "https://git.gindin.xyz")
    api = API(url, state.get("admin_token", "bootstrap"))
    if args.phase == "accounts":
        if "admin_token" not in state:
            password = args.recovery_password_file.read_text().strip()
            token = basic(api, "forgejo-recovery", password, "users/forgejo-recovery/tokens",
                {"name": "migration-bootstrap", "scopes": ["all"]})
            state["admin_token"] = token["sha1"]
            atomic_json(state_file, state)
            api.token = state["admin_token"]
        for username, email in [("aidengindin", "aiden@aidengindin.com"), ("forgejo-update", "aiden+forgejo-update@aidengindin.com")]:
            try:
                user = api.request("users/" + username)
            except urllib.error.HTTPError as error:
                if error.code != 404:
                    raise
                password = secrets.token_urlsafe(36)
                # Persist before account creation so a retry never loses access.
                state[username + "_password"] = password
                atomic_json(state_file, state)
                user = api.request("admin/users", data={"username": username, "email": email,
                    "password": password, "must_change_password": False, "send_notify": False})
            state[username + "_id"] = user["id"]
            atomic_json(state_file, state)
        print("Owner and bot accounts ready. Link the owner to Pocket ID at first sign-in.")
        return
    api.repo("collaborators/forgejo-update", data={"permission": "write"}, method="PUT")
    api.request("repos/" + REPOSITORY, data={"has_actions": True}, method="PATCH")
    if "bot_token" not in state:
        token = basic(api, "forgejo-update", state["forgejo-update_password"], "users/forgejo-update/tokens",
            {"name": "nixos-config-automation", "scopes": ["write:repository", "write:issue"],
             "repositories": [{"owner": "aidengindin", "name": "nixos-config"}]})
        state["bot_token"] = token["sha1"]
    state.setdefault("webhook_secret", secrets.token_hex(32))
    state.setdefault("hermes_secret", secrets.token_hex(32))
    state.setdefault("ci_secret", secrets.token_hex(32))
    atomic_json(state_file, state)
    api.repo("actions/secrets/AUTOMATION_TOKEN", data={"data": state["bot_token"]}, method="PUT")
    # Public upstream releases still need a GitHub token for gh's noninteractive
    # API calls. It is used only for upstream reads, never for the mirror.
    if os.environ.get("UPSTREAM_GITHUB_TOKEN"):
        api.repo("actions/secrets/UPSTREAM_GITHUB_TOKEN", data={"data": os.environ["UPSTREAM_GITHUB_TOKEN"]}, method="PUT")
    api.repo("actions/secrets/CI_WEBHOOK_SECRET", data={"data": state["ci_secret"]}, method="PUT")
    hooks = api.repo("hooks")
    hook_url = "http://127.0.0.1:8431/forgejo"
    hook_data = {"type": "forgejo", "active": True, "events": ["issue_comment", "pull_request_comment"],
        "config": {"url": hook_url, "content_type": "json", "secret": state["webhook_secret"]}}
    existing = next((h for h in hooks if h.get("config", {}).get("url") == hook_url), None)
    if existing:
        api.repo(f"hooks/{existing['id']}", data=hook_data, method="PATCH")
    else:
        api.repo("hooks", data=hook_data)
    protections = api.repo("branch_protections")
    protection = {"rule_name": "main", "enable_push": False, "enable_status_check": True,
        "status_check_contexts": [f"colmena/{host}" for host in HOSTS], "required_approvals": 0,
        "apply_to_admins": True}
    if any(p.get("rule_name", p.get("branch_name")) == "main" for p in protections):
        api.repo("branch_protections/main", data=protection, method="PATCH")
    else:
        api.repo("branch_protections", data=protection)
    # Stable runner 13.1 retains the legacy registration flow; Forgejo 15 still
    # supports this endpoint. A future runner upgrade must migrate UUID/token.
    runner_token = api.repo("actions/runners/registration-token")["token"]
    root = Path(__file__).resolve().parents[2]
    import re
    variables = (root / "common/variables.nix").read_text()
    recipients = [re.search(name + r' = "([^"]+)"', variables)[1] for name in ["osgiliathHost", "khazad-dumUser"]]
    common = {"FORGEJO_URL": url, "FORGEJO_TOKEN": state["bot_token"], "FORGEJO_BOT_ID": state["forgejo-update_id"]}
    encrypt_env(root / "secrets/forgejo-controller-env.age", {**common,
        "FORGEJO_OWNER_ID": state["aidengindin_id"], "FORGEJO_WEBHOOK_SECRET": state["webhook_secret"],
        "HERMES_WEBHOOK_SECRET": state["hermes_secret"], "CI_WEBHOOK_SECRET": state["ci_secret"]}, recipients, args.age)
    encrypt_env(root / "secrets/forgejo-hermes-env.age", {**common, "WEBHOOK_SECRET": state["hermes_secret"]}, recipients, args.age)
    encrypt_env(root / "secrets/forgejo-runner-env.age", {"TOKEN": runner_token}, recipients, args.age)
    print("Repository automation configured and agenix files written. Build/deploy osgiliath to start consumers.")

if __name__ == "__main__":
    main()
