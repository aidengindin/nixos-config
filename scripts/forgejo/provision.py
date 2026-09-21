#!/usr/bin/env python3
"""Provision accounts, repository automation, and encrypted runtime credentials.

Run accounts after Forgejo starts; run automation after importing the repository.
Run adopt when the bootstrap state is gone, to rebuild what automation needs
from the deployed encrypted runtime file before running automation again.
Temporary bootstrap credentials are mode 0600 and never printed.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import urllib.error
import urllib.request
from common import API, CI_HOSTS, INPUT_REPOSITORIES, REPOSITORY, atomic_json


def basic(api, user, password, path, data=None, method=None):
    auth = base64.b64encode((user + ":" + password).encode()).decode()
    request = urllib.request.Request(api.url + "/api/v1/" + path,
        data=None if data is None else json.dumps(data).encode(),
        method=method or ("GET" if data is None else "POST"),
        headers={"Authorization": "Basic " + auth, "Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read()
        # Token deletion answers 204; every caller that reads a result posts.
        return json.loads(body) if body else {}


def decrypt(path, identity, age):
    """Decrypt an agenix file with an SSH identity its recipients include."""
    return subprocess.run([age, "-d", "-i", str(identity), str(path)],
        check=True, stdout=subprocess.PIPE).stdout.decode()


def env_values(text):
    values = {}
    for line in text.splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    return values


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
    parser.add_argument("phase", choices=["accounts", "automation", "adopt"])
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--recovery-password-file", type=Path)
    parser.add_argument("--age", default="age")
    # adopt reads deployed secrets instead of the discarded bootstrap state.
    parser.add_argument("--identity", type=Path, default=Path.home() / ".ssh/id_ed25519")
    parser.add_argument("--controller-env", type=Path)
    parser.add_argument("--recovery-password-age", type=Path)
    args = parser.parse_args()
    # Every phase encrypts or decrypts, and `age` is not in the user profile
    # (only `agenix` is). Say so before doing any work.
    if not shutil.which(args.age):
        parser.error(f"{args.age} not found; rerun inside `nix develop` or pass --age")
    root = Path(__file__).resolve().parents[2]
    args.controller_env = args.controller_env or root / "secrets/forgejo-controller-env.age"
    args.recovery_password_age = args.recovery_password_age or root / "secrets/forgejo-recovery-password.age"
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
            if not user.get("active"):
                user = api.request("admin/users/" + username, data={"active": True}, method="PATCH")
            state[username + "_id"] = user["id"]
            atomic_json(state_file, state)
        print("Owner and bot accounts ready. Link the owner to Pocket ID at first sign-in.")
        return
    if args.phase == "adopt":
        # Bootstrap credentials are destroyed after migration, so rebuild what
        # automation needs from the deployed runtime file. Its webhook and CI
        # secrets must keep their current values or the hooks stop verifying.
        runtime = env_values(decrypt(args.controller_env, args.identity, args.age))
        api.url = runtime.get("FORGEJO_URL", url).rstrip("/")
        for key, name in [("FORGEJO_WEBHOOK_SECRET", "webhook_secret"),
                ("HERMES_WEBHOOK_SECRET", "hermes_secret"), ("CI_WEBHOOK_SECRET", "ci_secret"),
                ("FORGEJO_OWNER_ID", "aidengindin_id"), ("FORGEJO_BOT_ID", "forgejo-update_id"),
                ("FORGEJO_TOKEN", "bot_token")]:
            state[name] = runtime[key]
        # The live token's repository scope is recorded nowhere, so leave it
        # unknown: automation then reissues a token scoped to the current inputs.
        state.pop("bot_token_repositories", None)
        if args.recovery_password_file:
            recovery = args.recovery_password_file.read_text()
        else:
            recovery = decrypt(args.recovery_password_age, args.identity, args.age)
        recovery = recovery.strip()
        name = "provision-adopt"
        tokens = basic(api, "forgejo-recovery", recovery, "users/forgejo-recovery/tokens") or []
        if any(token.get("name") == name for token in tokens):
            basic(api, "forgejo-recovery", recovery, f"users/forgejo-recovery/tokens/{name}", method="DELETE")
        state["admin_token"] = basic(api, "forgejo-recovery", recovery,
            "users/forgejo-recovery/tokens", {"name": name, "scopes": ["all"]})["sha1"]
        atomic_json(state_file, state)
        api.token = state["admin_token"]
        # The bot password cannot be recovered and token endpoints accept only
        # basic auth. Reset it, persisting first so a failed retry keeps access.
        state["forgejo-update_password"] = secrets.token_urlsafe(36)
        atomic_json(state_file, state)
        api.request("admin/users/forgejo-update", method="PATCH",
            data={"password": state["forgejo-update_password"], "must_change_password": False})
        print("Rebuilt bootstrap state. Run the automation phase next, then revoke the"
            " provision-adopt token and commit the re-encrypted files.")
        return
    api.repo("collaborators/forgejo-update", data={"permission": "write"}, method="PUT")
    api.request("repos/" + REPOSITORY, data={"has_actions": True}, method="PATCH")
    # Private flake inputs are cloned by CI with this token, so the bot reads
    # them too. Token repository scope is fixed at creation: recreate the token
    # whenever the set of inputs changes.
    for repository in INPUT_REPOSITORIES:
        api.request(f"repos/{repository}/collaborators/forgejo-update", data={"permission": "read"}, method="PUT")
    scope = [REPOSITORY, *INPUT_REPOSITORIES]
    if state.get("bot_token_repositories") != scope:
        state.pop("bot_token", None)
    if "bot_token" not in state:
        password = state["forgejo-update_password"]
        name = "nixos-config-automation"
        existing = basic(api, "forgejo-update", password, "users/forgejo-update/tokens") or []
        if any(t.get("name") == name for t in existing):
            basic(api, "forgejo-update", password, f"users/forgejo-update/tokens/{name}", method="DELETE")
        token = basic(api, "forgejo-update", password, "users/forgejo-update/tokens",
            {"name": name, "scopes": ["write:repository", "write:issue"],
             "repositories": [{"owner": r.split("/")[0], "name": r.split("/")[1]} for r in scope]})
        state["bot_token"] = token["sha1"]
        state["bot_token_repositories"] = scope
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
        "status_check_contexts": [f"colmena/{host}" for host in CI_HOSTS], "required_approvals": 0,
        "apply_to_admins": True}
    if any(p.get("rule_name", p.get("branch_name")) == "main" for p in protections):
        api.repo("branch_protections/main", data=protection, method="PATCH")
    else:
        api.repo("branch_protections", data=protection)
    # Stable runner 13.1 retains the legacy registration flow; Forgejo 15 still
    # supports this endpoint. A future runner upgrade must migrate UUID/token.
    runner_token = api.repo("actions/runners/registration-token")["token"]
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
