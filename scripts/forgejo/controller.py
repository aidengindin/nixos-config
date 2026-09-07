#!/usr/bin/env python3
"""Authenticated ChatOps receiver and restart-safe, serial deployment worker."""
import hashlib
from contextlib import contextmanager
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import logging
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import threading
import time
import urllib.request
from common import API, HOSTS, REPOSITORY, SHA, STORE_PATH, UPDATE_BRANCH, selectors

LOG = logging.getLogger("forgejo-controller")


def signed(body, signature, secret):
    signature = signature.removeprefix("sha256=")
    return hmac.compare_digest(hmac.new(secret.encode(), body, hashlib.sha256).hexdigest(), signature)


class Controller:
    def __init__(self):
        self.api = API()
        self.state = Path(os.environ["CONTROLLER_STATE"])
        self.state.mkdir(parents=True, exist_ok=True)
        self.db_path = self.state / "queue.sqlite"
        with self.db() as db:
            db.execute("CREATE TABLE IF NOT EXISTS jobs (id TEXT PRIMARY KEY, data TEXT NOT NULL, state TEXT NOT NULL)")
            db.execute("CREATE TABLE IF NOT EXISTS repairs (id TEXT PRIMARY KEY, payload TEXT NOT NULL, sent INTEGER NOT NULL DEFAULT 0)")
        self.owner_id = int(os.environ["FORGEJO_OWNER_ID"])
        self.bot_id = int(os.environ["FORGEJO_BOT_ID"])

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.db_path, timeout=30)
        db.execute("PRAGMA journal_mode=WAL")
        try:
            with db:
                yield db
        finally:
            db.close()

    def save(self, key, job, state="queued"):
        with self.db() as db:
            db.execute("UPDATE jobs SET data=?,state=? WHERE id=?", (json.dumps(job), state, key))

    def accept(self, event, payload):
        if payload.get("repository", {}).get("full_name") != REPOSITORY:
            return
        if event in ("issue_comment", "pull_request_comment") and payload.get("action") == "created":
            comment = payload.get("comment", {})
            if comment.get("user", {}).get("id") != self.owner_id:
                return
            if not comment.get("body", "").startswith("/deploy"):
                return
            pr = int(payload["issue"]["number"])
            # Verify persisted comment and PR using the API, not only the webhook.
            real = self.api.repo(f"issues/comments/{int(comment['id'])}")
            if real["user"]["id"] != self.owner_id or real["body"] != comment["body"]:
                raise ValueError("Comment verification failed")
            pull = self.api.repo(f"pulls/{pr}")
            if pull["state"] != "open" or pull["head"]["repo"]["full_name"] != REPOSITORY:
                raise ValueError("Deployment requires an open local PR")
            targets = selectors(real["body"])
            job = {"pr": pr, "sha": pull["head"]["sha"], "targets": targets, "created": time.time(), "hosts": {}}
            key = str(comment["id"])
            with self.db() as db:
                inserted = db.execute("INSERT OR IGNORE INTO jobs VALUES (?,?,?)", (key, json.dumps(job), "queued")).rowcount
            if inserted:
                self.api.comment(pr, f"Deployment queued for `{job['sha']}`: {', '.join(targets)}.")
        elif event == "status":
            self.queue_repair(payload.get("sha", ""))

    def trusted_statuses(self, sha):
        return {
            s["context"]: s
            for s in self.api.statuses(sha)
            if (s.get("creator") or {}).get("id") == self.bot_id
        }

    def queue_repair(self, sha):
        if not SHA.fullmatch(sha):
            return
        statuses = self.trusted_statuses(sha)
        if any(statuses.get(f"colmena/{host}", {}).get("state") not in ("success", "failure", "error") for host in HOSTS):
            return
        failures = [s for s in statuses.values()
                    if s["state"] in ("failure", "error") and (s["context"].startswith("colmena/") or s["context"] == "updates")]
        for pull in self.api.pulls():
            if pull["head"]["sha"] != sha or pull["head"]["ref"] != UPDATE_BRANCH or not failures:
                continue
            payload = {"event_type": "forgejo_repair", "repository": REPOSITORY,
                "pr": pull["number"], "sha": sha, "failures": failures}
            with self.db() as db:
                db.execute("INSERT OR IGNORE INTO repairs(id,payload) VALUES (?,?)", (sha, json.dumps(payload)))

    def send_repairs(self):
        with self.db() as db:
            rows = db.execute("SELECT id,payload FROM repairs WHERE sent=0").fetchall()
        for key, payload in rows:
            body = payload.encode()
            signature = hmac.new(os.environ["HERMES_WEBHOOK_SECRET"].encode(), body, hashlib.sha256).hexdigest()
            request = urllib.request.Request(os.environ["HERMES_URL"], data=body, headers={
                "Content-Type": "application/json", "X-Hub-Signature-256": "sha256=" + signature,
                "X-GitHub-Event": "forgejo_repair", "X-GitHub-Delivery": key})
            with urllib.request.urlopen(request, timeout=30) as response:
                response.read()
            with self.db() as db:
                db.execute("UPDATE repairs SET sent=1 WHERE id=?", (key,))

    def store_ssh(self):
        return ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=15",
            "-o", "UserKnownHostsFile=" + os.environ["STORE_KNOWN_HOSTS"],
            "-i", os.environ["STORE_KEY"], "-p", os.environ["STORE_PORT"]]

    def target(self, host, command):
        if host == "osgiliath":
            return subprocess.check_output(command, text=True, timeout=600).strip()
        return subprocess.check_output(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15",
            "-o", "StrictHostKeyChecking=yes", f"nixos-deploy@{host}", *command], text=True, timeout=600).strip()

    def pull_closure(self, sha, host, status):
        raw = subprocess.check_output(self.store_ssh() + ["store-export@127.0.0.1", f"result {sha} {host}"], text=True, timeout=30)
        result = json.loads(raw)
        if (result.get("repository"), result.get("sha"), result.get("host")) != (REPOSITORY, sha, host):
            raise ValueError("Build result identity mismatch")
        if result.get("run_url") != status.get("target_url") or not STORE_PATH.fullmatch(result.get("closure", "")):
            raise ValueError("Build result does not match successful status")
        closure = result["closure"]
        import shlex
        env = dict(os.environ, NIX_SSHOPTS=shlex.join(self.store_ssh()[1:]))
        # Only this explicit, authenticated import bypasses signatures. The VM
        # is not a globally trusted substitute source for arbitrary host builds.
        subprocess.run(["nix", "copy", "--no-check-sigs", "--from", "ssh://store-export@127.0.0.1", closure], env=env, check=True, timeout=3600)
        root = self.state / "roots" / sha / host
        root.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["nix-store", "--realise", closure, "--add-root", str(root), "--indirect"], check=True)
        return closure

    def deploy(self, key, job):
        sha, pr = job["sha"], job["pr"]
        if time.time() - job["created"] > 6 * 3600 and not job.get("started"):
            raise ValueError("Timed out waiting for builds")
        pull = self.api.repo(f"pulls/{pr}")
        if not job.get("started") and (pull["state"] != "open" or pull["head"]["sha"] != sha):
            raise ValueError("PR changed; submit a new /deploy command")
        statuses = self.trusted_statuses(sha)
        if not job.get("started"):
            for host in job["targets"]:
                status = statuses.get(f"colmena/{host}")
                if status and status["state"] in ("failure", "error"):
                    raise ValueError(f"Build failed for {host}")
                if not status or status["state"] != "success":
                    if not job.get("dispatched"):
                        self.api.repo("actions/workflows/build.yml/dispatches", data={"ref": "main", "inputs": {"pr": str(pr), "sha": sha}})
                        job["dispatched"] = True
                        self.save(key, job)
                    return
            # Transfer all requested closures before any activation.
            for host in job["targets"]:
                if host not in job["hosts"]:
                    closure = self.pull_closure(sha, host, statuses[f"colmena/{host}"])
                    job["hosts"][host] = {"closure": closure, "stage": "ready"}
                    self.save(key, job)
            if self.api.repo(f"pulls/{pr}")["head"]["sha"] != sha:
                raise ValueError("PR changed during transfer; submit a new /deploy command")
            job["started"] = True
            self.save(key, job)
        # Deploy osgiliath last so the forge/controller remains available.
        for host in sorted(job["targets"], key=lambda h: h == "osgiliath"):
            item = job["hosts"][host]
            if item["stage"] == "done":
                continue
            closure = item["closure"]
            if item["stage"] == "activating":
                active = self.target(host, ["readlink", "-f", "/run/current-system"])
                if active == closure:
                    item["stage"] = "done"
                    self.save(key, job)
                    continue
                # An interrupted activation is ambiguous. Never repeat it.
                raise ValueError(f"Interrupted activation on {host}; inspect manually before retrying")
            item["previous"] = self.target(host, ["readlink", "-f", "/nix/var/nix/profiles/system"])
            if host != "osgiliath":
                subprocess.run(["nix", "copy", "--to", f"ssh://nixos-deploy@{host}", closure], check=True, timeout=3600)
            item["stage"] = "activating"
            self.save(key, job)
            self.target(host, ["sudo", "-H", "--", "nix-env", "--profile", "/nix/var/nix/profiles/system", "--set", closure])
            self.target(host, ["sudo", "-H", "--", closure + "/bin/switch-to-configuration", "switch"])
            item["stage"] = "done"
            self.save(key, job)
        self.api.comment(pr, self.summary(job, "Deployment complete"))
        self.save(key, job, "done")
        # Current target generations now retain the closures. Keep this audit
        # journal, release the controller's temporary transfer roots.
        import shutil
        shutil.rmtree(self.state / "roots" / sha, ignore_errors=True)

    @staticmethod
    def summary(job, title):
        lines = [f"{title} for `{job['sha']}`."]
        for host in job["targets"]:
            item = job["hosts"].get(host, {})
            lines.append(f"- {host}: {item.get('stage', 'not started')}; previous: `{item.get('previous', 'unknown')}`")
        return "\n".join(lines)

    def work(self):
        while True:
            try:
                with self.db() as db:
                    row = db.execute("SELECT id,data FROM jobs WHERE state='queued' ORDER BY rowid LIMIT 1").fetchone()
                if row:
                    key, data = row
                    job = json.loads(data)
                    try:
                        self.deploy(key, job)
                    except Exception as exc:
                        LOG.exception("Deployment %s failed", key)
                        self.save(key, job, "failed")
                        self.api.comment(job["pr"], self.summary(job, "Deployment stopped: " + str(exc)))
                # Reconcile dropped status webhooks after Forgejo/controller restart.
                for pull in self.api.pulls():
                    if pull["head"]["ref"] == UPDATE_BRANCH:
                        self.queue_repair(pull["head"]["sha"])
                self.send_repairs()
            except Exception:
                LOG.exception("Controller reconciliation failed; retrying")
            time.sleep(15)


def main():
    logging.basicConfig(level=logging.INFO)
    controller = Controller()
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            if self.path not in ("/forgejo", "/ci") or not 0 < length <= 2_000_000:
                self.send_error(400); return
            body = self.rfile.read(length)
            secret = os.environ["CI_WEBHOOK_SECRET"] if self.path == "/ci" else os.environ["FORGEJO_WEBHOOK_SECRET"]
            if not signed(body, self.headers.get("X-Forgejo-Signature", self.headers.get("X-Gitea-Signature", "")), secret):
                self.send_error(403); return
            try:
                payload = json.loads(body)
                if self.path == "/ci":
                    if payload.get("repository") != REPOSITORY:
                        raise ValueError("Wrong repository")
                    controller.queue_repair(payload.get("sha", ""))
                else:
                    controller.accept(self.headers.get("X-Forgejo-Event", self.headers.get("X-Gitea-Event", "")), payload)
            except ValueError as exc:
                LOG.warning("Rejected webhook: %s", exc)
                self.send_error(400); return
            except Exception:
                LOG.exception("Webhook failed")
                self.send_error(503); return
            self.send_response(202); self.end_headers()
    threading.Thread(target=controller.work, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", int(os.environ["CONTROLLER_PORT"])), Handler).serve_forever()

if __name__ == "__main__":
    main()
