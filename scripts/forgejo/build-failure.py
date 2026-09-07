#!/usr/bin/env python3
"""Turn an interrupted/exceptional build into actionable failed statuses."""
import os
import subprocess
from common import API, HOSTS, REPOSITORY
api = API()
sha = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
url = f"{api.url}/{REPOSITORY}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
for status in api.statuses(sha):
    if status["context"] in [f"colmena/{host}" for host in HOSTS] and status["state"] == "pending":
        api.status(sha, status["context"], "failure", "Build job interrupted or failed unexpectedly", url)
