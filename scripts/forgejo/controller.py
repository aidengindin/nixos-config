#!/usr/bin/env python3
"""Authenticated ChatOps receiver and restart-safe, serial deployment worker."""
from datetime import date, datetime, timezone
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
from common import API, CI_HOSTS, REPOSITORY, SHA, STORE_PATH, selectors

LOG = logging.getLogger("forgejo-controller")
ACTIVATION_GRACE_SECONDS = 300
WAIT_REPORT_SECONDS = 30 * 60
CVE_STALE_DAYS = 3
CVE_STALE_CHECK_SECONDS = 3600
CVE_HEADER = re.compile(r"Last successful scan: \*\*(\d{4}-\d{2}-\d{2}|never)\*\*")


def built_sha(run):
    """Return the PR head an action run built, or None if it is untrusted."""
    if run.get("trigger_event") != "workflow_dispatch":
        return run.get("commit_sha")
    # A dispatched build runs main's workflow, so commit_sha is main's head;
    # build.yml checks out the exact PR head named by its `sha` input instead.
    try:
        payload = json.loads(run.get("event_payload") or "{}")
    except json.JSONDecodeError:
        return None
    if run.get("workflow_id") != "build.yml" or payload.get("ref") != "refs/heads/main":
        return None
    return (payload.get("inputs") or {}).get("sha")


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
            db.execute("CREATE TABLE IF NOT EXISTS notifications (id TEXT PRIMARY KEY, payload TEXT NOT NULL, sent INTEGER NOT NULL DEFAULT 0)")
            db.execute("CREATE TABLE IF NOT EXISTS comments (id TEXT PRIMARY KEY, pr INTEGER NOT NULL, body TEXT NOT NULL, sent INTEGER NOT NULL DEFAULT 0)")
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

    def queue_notification(self, key, message):
        payload = {"event_type": "forgejo_notification", "message": message}
        with self.db() as db:
            db.execute("INSERT OR IGNORE INTO notifications(id,payload) VALUES (?,?)",
                (key, json.dumps(payload)))

    def queue_comment(self, key, pr, body):
        with self.db() as db:
            db.execute("INSERT OR IGNORE INTO comments(id,pr,body) VALUES (?,?,?)", (key, pr, body))

    def send_comments(self):
        with self.db() as db:
            rows = db.execute("SELECT id,pr,body FROM comments WHERE sent=0").fetchall()
        for key, pr, body in rows:
            self.api.comment(pr, body)
            with self.db() as db:
                db.execute("UPDATE comments SET sent=1 WHERE id=?", (key,))

    def queue_build_notification(self, sha):
        if not SHA.fullmatch(sha):
            return
        statuses = self.trusted_statuses(sha)
        host_statuses = {host: statuses.get(f"colmena/{host}") for host in CI_HOSTS}
        if any(not status or status.get("state") not in ("success", "failure", "error")
                for status in host_statuses.values()):
            return
        pulls = [pull for pull in self.api.pulls() if pull["head"]["sha"] == sha]
        if not pulls:
            return
        failures = [host for host, status in host_statuses.items()
                    if status["state"] in ("failure", "error")]
        run_url = next((status.get("target_url") for status in host_statuses.values()
                        if status.get("target_url")), f"{self.api.url}/{REPOSITORY}/pulls/{pulls[0]['number']}")
        result = "failed for " + ", ".join(failures) if failures else "passed for all CI hosts"
        for pull in pulls:
            message = (f"Forgejo CI {result} on PR #{pull['number']} at `{sha[:12]}`.\n"
                f"Run and logs: {run_url}")
            self.queue_notification(f"build:{pull['number']}:{sha}", message)

    def queue_cve_notification(self, payload):
        """Ping Matrix for a CVE scan. Content comes from the API, not the webhook."""
        def number(name):
            try:
                return int(payload[name])
            except (KeyError, TypeError, ValueError):
                raise ValueError(f"Missing or invalid {name}") from None
        issue_number = number("issue")
        issue = self.api.repo(f"issues/{issue_number}")
        if issue.get("title") != "CVE report" or issue["user"]["id"] != self.bot_id:
            raise ValueError("Not the bot's CVE report issue")
        comment_id = number("comment")
        comment = self.api.repo(f"issues/comments/{comment_id}")
        if (not comment.get("issue_url", "").endswith(f"/issues/{issue_number}")
                or comment["user"]["id"] != self.bot_id):
            raise ValueError("Comment is not a CVE ping on the CVE report")
        ping = re.search(r"^<!-- cve-ping: ([^ ]+) -->$", comment["body"], re.MULTILINE)
        cves = ping[1].split(",") if ping else []
        if not cves or not all(re.fullmatch(r"CVE-\d{4}-\d+|GHSA-[\w-]+", cve) for cve in cves):
            raise ValueError("Comment has no valid CVE ping line")
        listed = ", ".join(cves[:5]) + (f" and {len(cves) - 5} more" if len(cves) > 5 else "")
        self.queue_notification(f"cve:{comment_id}",
            f"New critical or known-exploited CVEs ({len(cves)}): {listed}.\n{comment['html_url']}")

    def check_cve_staleness(self, now=None):
        """Dead-man switch: ping when the bot's CVE report shows no recent successful scan."""
        today = (now or datetime.now(timezone.utc)).date()
        issues, page = [], 1
        while True:
            items = self.api.repo(f"issues?state=all&type=issues&limit=50&page={page}")
            issues.extend(items)
            if len(items) < 50:
                break
            page += 1
        reports = [issue for issue in issues
                   if issue.get("title") == "CVE report" and issue["user"]["id"] == self.bot_id]
        # Closed reports still count, so closing the issue cannot silence the alarm.
        for issue in sorted(reports, key=lambda issue: issue["created_at"])[-1:]:
            match = CVE_HEADER.match((issue.get("body") or "").split("\n", 1)[0])
            if not match:
                self.queue_notification(f"cve-stale:unparseable:{issue['number']}",
                    f"The CVE report header is unreadable, so scan staleness cannot be checked.\n{issue['html_url']}")
                continue
            last = match[1]
            reference = date.fromisoformat(issue["created_at"][:10] if last == "never" else last)
            if (today - reference).days >= CVE_STALE_DAYS:
                self.queue_notification(f"cve-stale:{last}",
                    f"CVE scan has not succeeded since {last}.\n{issue['html_url']}")

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
            unsupported = [host for host in targets if host not in CI_HOSTS]
            if unsupported:
                raise ValueError("PR deployment is unavailable for hosts excluded from CI: " + ", ".join(unsupported))
            job = {"pr": pr, "sha": pull["head"]["sha"], "targets": targets, "created": time.time(), "hosts": {}}
            key = str(comment["id"])
            with self.db() as db:
                inserted = db.execute("INSERT OR IGNORE INTO jobs VALUES (?,?,?)", (key, json.dumps(job), "queued")).rowcount
            if inserted:
                self.api.comment(pr, f"Deployment queued for `{job['sha']}`: {', '.join(targets)}.")
        elif event == "status":
            sha = payload.get("sha", "")
            self.queue_build_notification(sha)

    def trusted_statuses(self, sha, rejected=None):
        """Return verified statuses by context; record why others were dropped.

        API errors propagate so callers retry; only a status that exists and
        fails verification lands in `rejected`.
        """
        trusted = {}
        rejected = {} if rejected is None else rejected
        prefix = f"{self.api.url}/{REPOSITORY}/actions/runs/"
        for status in self.api.statuses(sha):
            creator = (status.get("creator") or {}).get("id")
            if creator != self.bot_id:
                target = status.get("target_url", "")
                if creator is not None:
                    rejected[status["context"]] = f"posted by untrusted user {creator}"
                    continue
                if not target.startswith(prefix):
                    rejected[status["context"]] = f"links outside this repository's runs: {target or 'none'}"
                    continue
                run_id = target[len(prefix):].split("/", 1)[0]
                if not run_id.isdigit():
                    rejected[status["context"]] = f"links to an invalid run: {target}"
                    continue
                run = self.api.repo(f"actions/runs/{run_id}")
                built = built_sha(run)
                if built != sha:
                    rejected[status["context"]] = f"run {run_id} built {built or 'an unverifiable commit'}, not this PR head"
                    continue
            trusted[status["context"]] = status
        return trusted

    def reconcile_terminal_build(self, sha):
        """Close host statuses when Forgejo ended a run before cleanup ran."""
        statuses = self.trusted_statuses(sha)
        unresolved = [
            host for host in CI_HOSTS
            if statuses.get(f"colmena/{host}", {}).get("state")
            not in ("success", "failure", "error")
        ]
        if not unresolved:
            return False
        runs = self.api.repo("actions/runs?limit=50").get("workflow_runs", [])
        run = next((
            item for item in runs
            if item.get("workflow_id") == "build.yml" and built_sha(item) == sha
        ), None)
        if not run or run.get("status") not in ("success", "failure", "cancelled"):
            return False
        state = "failure" if run["status"] == "failure" else "error"
        description = f"Forgejo run {run['status']} before this host reported a result"
        run_url = run.get("html_url") or f"{self.api.url}/{REPOSITORY}/actions/runs/{int(run['id'])}"
        for host in unresolved:
            self.api.status(sha, f"colmena/{host}", state, description, run_url)
        return True

    def send_notifications(self):
        with self.db() as db:
            rows = db.execute("SELECT id,payload FROM notifications WHERE sent=0").fetchall()
        for key, payload in rows:
            body = payload.encode()
            signature = hmac.new(os.environ["HERMES_WEBHOOK_SECRET"].encode(), body, hashlib.sha256).hexdigest()
            request = urllib.request.Request(os.environ["HERMES_NOTIFY_URL"], data=body, headers={
                "Content-Type": "application/json", "X-Hub-Signature-256": "sha256=" + signature,
                "X-GitHub-Event": "forgejo_notification", "X-GitHub-Delivery": key})
            with urllib.request.urlopen(request, timeout=30) as response:
                response.read()
            with self.db() as db:
                db.execute("UPDATE notifications SET sent=1 WHERE id=?", (key,))

    def store_ssh(self):
        os.chmod(os.environ["STORE_KEY"], 0o600)
        return ["ssh", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=15",
            "-o", "UserKnownHostsFile=" + os.environ["STORE_KNOWN_HOSTS"],
            "-i", os.environ["STORE_KEY"], "-p", os.environ["STORE_PORT"]]

    @staticmethod
    def target_command(host, command):
        return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15",
            "-o", "StrictHostKeyChecking=yes", f"nixos-deploy@{host}", *command]

    def target(self, host, command):
        return subprocess.check_output(self.target_command(host, command), text=True, timeout=600).strip()

    def start_self_activation(self, closure):
        # Activation stops forgejo-controller.service. Do not leave stdout or a
        # controlling session tied to the controller process that systemd kills.
        subprocess.Popen(self.target_command("osgiliath", [
            "sudo", "-H", "--", closure + "/bin/switch-to-configuration", "switch",
        ]), stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True)

    def pull_closure(self, sha, host, status):
        raw = subprocess.check_output(self.store_ssh() + ["store-export@127.0.0.1", f"result {sha} {host}"], text=True, timeout=30)
        result = json.loads(raw)
        if (result.get("repository"), result.get("sha"), result.get("host")) != (REPOSITORY, sha, host):
            raise ValueError("Build result identity mismatch")
        if result.get("run_url") != status.get("target_url") or not STORE_PATH.fullmatch(result.get("closure", "")):
            raise ValueError("Build result does not match successful status")
        closure = result["closure"]
        exporter = subprocess.Popen(
            self.store_ssh() + ["store-export@127.0.0.1", f"export {sha} {host}"],
            stdout=subprocess.PIPE,
        )
        try:
            # nixos-deploy is the trusted local controller user. Disable
            # signature checks only for this manifest-bound import stream.
            imported = subprocess.run(
                ["nix-store", "--import", "--option", "require-sigs", "false"],
                stdin=exporter.stdout,
                stdout=subprocess.DEVNULL,
                timeout=3600,
            )
        finally:
            exporter.stdout.close()
        export_rc = exporter.wait(timeout=30)
        if imported.returncode or export_rc:
            raise subprocess.CalledProcessError(imported.returncode or export_rc, "restricted closure transfer")
        # Only closures bound to the verified CI manifest reach this point.
        # Sign the full closure so remote targets can retain normal signature
        # enforcement during the subsequent ssh-ng copy.
        subprocess.run([
            "nix", "store", "sign", "--recursive", "--key-file",
            os.environ["STORE_SIGNING_KEY"], closure,
        ], check=True, timeout=3600)
        root = self.state / "roots" / sha / host
        root.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["nix-store", "--realise", closure, "--add-root", str(root), "--indirect"], check=True)
        return closure

    def note_waiting(self, key, job, hosts):
        if job.get("waiting") != hosts:
            LOG.info("Deployment %s for PR #%s waiting on builds for %s", key, job["pr"], ", ".join(hosts))
            job["waiting"] = hosts
        if not job.get("wait_reported") and time.time() - job["created"] > WAIT_REPORT_SECONDS:
            self.queue_comment(f"deploy:{key}:waiting", job["pr"],
                f"Deployment for `{job['sha']}` is still waiting on builds for: {', '.join(hosts)}.")
            job["wait_reported"] = True

    def supersede(self, jobs):
        """Fail waiting jobs whose hosts a newer /deploy also targets."""
        claimed, kept = {}, []
        for key, job in reversed(jobs):
            newer = next((claimed[host] for host in job["targets"] if host in claimed), None)
            for host in job["targets"]:
                claimed.setdefault(host, job["pr"])
            if newer is not None and not job.get("started"):
                self.save(key, job, "failed")
                summary = self.summary(job, f"Deployment superseded by a newer /deploy on #{newer}")
                self.queue_comment(f"deploy:{key}:superseded", job["pr"], summary)
                continue
            kept.append((key, job))
        return kept[::-1]

    def deploy(self, key, job):
        sha, pr = job["sha"], job["pr"]
        if time.time() - job["created"] > 13 * 3600 and not job.get("started"):
            raise ValueError("Timed out waiting for builds")
        if not job.get("started"):
            pull = self.api.repo(f"pulls/{pr}")
            if pull["state"] != "open" or pull["head"]["sha"] != sha:
                raise ValueError("PR changed; submit a new /deploy command")
            rejected = {}
            statuses = self.trusted_statuses(sha, rejected)
            waiting = []
            for host in job["targets"]:
                context = f"colmena/{host}"
                status = statuses.get(context)
                # Waiting cannot make a rejected status trustworthy. Fail now
                # rather than sit silently until the build timeout.
                if context in rejected:
                    raise ValueError(f"Untrusted {context} status: {rejected[context]}")
                if status and status["state"] in ("failure", "error"):
                    raise ValueError(f"Build failed for {host}")
                if not status or status["state"] != "success":
                    waiting.append(host)
            if waiting:
                if not job.get("dispatched"):
                    self.api.repo("actions/workflows/build.yml/dispatches", data={"ref": "main", "inputs": {"pr": str(pr), "sha": sha}})
                    job["dispatched"] = True
                self.note_waiting(key, job, waiting)
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
                started = item.get("activation_started")
                if started is None:
                    item["activation_started"] = time.time()
                    self.save(key, job)
                    return
                if time.time() - started < ACTIVATION_GRACE_SECONDS:
                    return
                # An interrupted activation is ambiguous. Never repeat it.
                raise ValueError(f"Interrupted activation on {host}; inspect manually before retrying")
            try:
                item["previous"] = self.target(host, ["readlink", "-f", "/run/current-system"])
            except subprocess.CalledProcessError:
                if host == "osgiliath":
                    raise
                # Legacy target wrappers did not allow generation queries. The
                # closure switch below upgrades the wrapper for future deploys.
                LOG.warning("Cannot read active generation on legacy target %s", host)
                item["previous"] = "unknown"
            if host != "osgiliath":
                # Let the target fetch public paths from its own substituters
                # (compressed, parallel); only the rest streams from here.
                subprocess.run(["nix", "copy", "--substitute-on-destination", "--to",
                    f"ssh-ng://nixos-deploy@{host}", closure], check=True, timeout=3600)
            item["stage"] = "activating"
            item["activation_started"] = time.time()
            self.save(key, job)
            self.target(host, ["sudo", "-H", "--", "nix-env", "--profile", "/nix/var/nix/profiles/system", "--set", closure])
            if host == "osgiliath":
                self.start_self_activation(closure)
                # The controller will be stopped by activation. Its replacement
                # confirms the active generation before completing the job.
                return
            self.target(host, ["sudo", "-H", "--", closure + "/bin/switch-to-configuration", "switch"])
            item["stage"] = "done"
            self.save(key, job)
        summary = self.summary(job, "Deployment complete")
        self.queue_comment(f"deploy:{key}:success", pr, summary)
        self.queue_notification(f"deploy:{key}:success", f"Forgejo {summary}")
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

    def run_jobs(self):
        """Advance queued deployments without letting a waiting job block others.

        Activation stays serial: a started job runs alone until it finishes,
        and at most one waiting job starts per pass.
        """
        with self.db() as db:
            rows = db.execute("SELECT id,data FROM jobs WHERE state='queued' ORDER BY rowid").fetchall()
        jobs = self.supersede([(key, json.loads(data)) for key, data in rows])
        started = [(key, job) for key, job in jobs if job.get("started")]
        for key, job in started[:1] or jobs:
            try:
                self.deploy(key, job)
            except OSError as exc:
                if job.get("started"):
                    self.fail(key, job, exc)
                    return
                # Forgejo restarting while a job waits is not a deploy failure.
                LOG.warning("Deployment %s could not check builds; retrying", key, exc_info=True)
                continue
            except Exception as exc:
                self.fail(key, job, exc)
                continue
            if job.get("started"):
                return

    def fail(self, key, job, exc):
        LOG.exception("Deployment %s failed", key)
        self.save(key, job, "failed")
        summary = self.summary(job, "Deployment stopped: " + str(exc))
        self.queue_comment(f"deploy:{key}:failure", job["pr"], summary)
        self.queue_notification(f"deploy:{key}:failure", f"Forgejo {summary}")

    def work(self):
        last_stale_check = None
        while True:
            try:
                self.run_jobs()
                # Reconcile dropped status webhooks after Forgejo/controller restart.
                for pull in self.api.pulls():
                    self.reconcile_terminal_build(pull["head"]["sha"])
                    self.queue_build_notification(pull["head"]["sha"])
                self.send_comments()
            except Exception:
                LOG.exception("Controller reconciliation failed; retrying")
            if last_stale_check is None or time.monotonic() - last_stale_check >= CVE_STALE_CHECK_SECONDS:
                last_stale_check = time.monotonic()
                try:
                    self.check_cve_staleness()
                except Exception:
                    LOG.exception("CVE staleness check failed")
            try:
                self.send_notifications()
            except Exception:
                LOG.exception("Sending notifications failed; retrying")
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
                    if payload.get("kind") == "cve":
                        controller.queue_cve_notification(payload)
                    else:
                        controller.queue_build_notification(payload.get("sha", ""))
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
