#!/usr/bin/env python3
"""Signed completion webhook; the receiver independently verifies statuses."""
import hashlib
import hmac
import json
import os
import subprocess
import urllib.request
from common import REPOSITORY
sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
body = json.dumps({"repository": REPOSITORY, "sha": sha}).encode()
signature = hmac.new(os.environ["CI_WEBHOOK_SECRET"].encode(), body, hashlib.sha256).hexdigest()
request = urllib.request.Request(os.environ["FORGEJO_URL"].rstrip("/") + "/_automation/events", data=body,
    headers={"Content-Type": "application/json", "X-Forgejo-Signature": signature})
with urllib.request.urlopen(request, timeout=30) as response:
    response.read()
