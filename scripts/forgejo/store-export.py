#!/usr/bin/env python3
"""Forced SSH command: export only a retained, validated build closure."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

REPOSITORY = "aidengindin/nixos-config"
HOSTS = "lorien|osgiliath|khazad-dum|weathertop"
STORE_PATH = re.compile(r"/nix/store/[0-9a-df-np-sv-z]{32}-[^/]+")
command = os.environ.get("SSH_ORIGINAL_COMMAND", "")
match = re.fullmatch(rf"(result|export) ([0-9a-f]{{40}}) ({HOSTS})", command)
if not match:
    sys.stderr.write("Denied or missing build result\n")
    sys.exit(1)

operation, sha, host = match.groups()
state = Path(os.environ.get("FORGEJO_CI_STATE", "/var/lib/forgejo-ci"))
path = state / "results" / sha / (host + ".json")
try:
    raw = path.read_text()
    result = json.loads(raw)
    closure = result["closure"]
except (OSError, KeyError, ValueError, json.JSONDecodeError):
    sys.stderr.write("Denied or missing build result\n")
    sys.exit(1)
if ((result.get("repository"), result.get("sha"), result.get("host"))
        != (REPOSITORY, sha, host) or not STORE_PATH.fullmatch(closure)):
    sys.stderr.write("Denied or invalid build result\n")
    sys.exit(1)

if operation == "result":
    sys.stdout.write(raw)
    sys.exit(0)

try:
    paths = subprocess.check_output(
        ["nix-store", "--query", "--requisites", closure], text=True
    ).splitlines()
except subprocess.CalledProcessError:
    sys.stderr.write("Retained closure is unavailable\n")
    sys.exit(1)
if closure not in paths or any(not STORE_PATH.fullmatch(item) for item in paths):
    sys.stderr.write("Invalid retained closure\n")
    sys.exit(1)
os.execvp("nix-store", ["nix-store", "--export", *paths])
