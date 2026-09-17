#!/usr/bin/env python3
"""Turn an interrupted/exceptional build into actionable failed statuses."""
import os
from build import close_incomplete_statuses
from common import API, REPOSITORY, event_sha

api = API()
sha = event_sha()
url = f"{api.url}/{REPOSITORY}/actions/runs/{os.environ['GITHUB_RUN_ID']}"
close_incomplete_statuses(api, sha, url)
