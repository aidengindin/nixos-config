"""Forced SSH command: read-only Nix protocol and validated build manifests."""
import json
import os
from pathlib import Path
import re
import sys

command = os.environ.get("SSH_ORIGINAL_COMMAND", "")
# nix copy --from ssh:// uses the legacy read-only serve protocol.
if command in ("nix-store --serve", "nix-store --serve --verbose"):
    os.execvp("nix-store", ["nix-store", "--serve"])
match = re.fullmatch(r"result ([0-9a-f]{40}) (lorien|osgiliath|khazad-dum|weathertop)", command)
if match:
    path = Path("/var/lib/forgejo-ci/results") / match[1] / (match[2] + ".json")
    if path.is_file():
        sys.stdout.write(path.read_text())
        sys.exit(0)
sys.stderr.write("Denied or missing build result\n")
sys.exit(1)
