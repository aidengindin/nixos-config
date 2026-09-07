"""Small, dependency-free Forgejo API client shared by the automation."""
import json
import os
import re
import urllib.request

REPOSITORY = "aidengindin/nixos-config"
HOSTS = ("lorien", "osgiliath", "khazad-dum", "weathertop")
TAGS = {"server": HOSTS[:2], "onprem": HOSTS[:2], "laptop": ("khazad-dum",),
        "gaming": ("weathertop",), "mobile": HOSTS[2:]}
UPDATE_BRANCH = "automation/update"
SHA = re.compile(r"^[0-9a-f]{40}$")
STORE_PATH = re.compile(r"^/nix/store/[0-9a-z]{32}-nixos-system-[A-Za-z0-9.+_-]+$")

class API:
    def __init__(self, url=None, token=None):
        self.url = (url or os.environ["FORGEJO_URL"]).rstrip("/")
        self.token = token or os.environ["FORGEJO_TOKEN"]

    def request(self, path, data=None, method=None, timeout=60):
        request = urllib.request.Request(self.url + "/api/v1/" + path.lstrip("/"),
            data=None if data is None else json.dumps(data).encode(),
            method=method or ("GET" if data is None else "POST"),
            headers={"Authorization": "token " + self.token, "Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read()
            return json.loads(body) if body else None

    def repo(self, path, **kwargs):
        return self.request(f"repos/{REPOSITORY}/{path}", **kwargs)

    def comment(self, pr, body):
        return self.repo(f"issues/{int(pr)}/comments", data={"body": body})

    def statuses(self, sha):
        assert SHA.fullmatch(sha)
        # Combined status supplies the newest status for each context.
        statuses = self.repo(f"commits/{sha}/status").get("statuses", [])
        # Forgejo 15 serializes CommitStatus.State as `status` even though the
        # create endpoint accepts it as `state`.
        for status in statuses:
            status["state"] = status.get("state") or status.get("status")
        return statuses

    def status(self, sha, context, state, description, target_url):
        return self.repo(f"statuses/{sha}", data={"context": context, "state": state,
            "description": description[:140], "target_url": target_url})

    def pulls(self):
        result = []
        page = 1
        while True:
            items = self.repo(f"pulls?state=open&limit=50&page={page}")
            result.extend(items)
            if len(items) < 50:
                return result
            page += 1


def selectors(text):
    parts = text.strip().split()
    if len(parts) != 2 or parts[0] != "/deploy":
        raise ValueError("Use /deploy host1,host2 or /deploy @server")
    targets = set()
    for item in parts[1].split(","):
        if item in HOSTS:
            targets.add(item)
        elif item.startswith("@") and item[1:] in TAGS:
            targets.update(TAGS[item[1:]])
        else:
            raise ValueError("Unknown host or tag: " + item)
    return [host for host in HOSTS if host in targets]


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)
