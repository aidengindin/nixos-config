import hashlib
import hmac
import importlib.util
import io
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/forgejo"))
from build import BUILD_ORDER, GIB, close_incomplete_statuses, gc_if_needed, require_build_headroom, supersede_pending
from common import CI_HOSTS, HOSTS, REPOSITORY, event_sha, selectors
from controller import Controller, signed
from retention import RETENTION_SECONDS, prune_retention, superseded_heads

SHA = "a" * 40
CLOSURE = "/nix/store/" + "b" * 32 + "-nixos-system-lorien-26.05"

class ValidationTests(unittest.TestCase):
    def test_selectors(self):
        self.assertEqual(selectors("/deploy osgiliath,lorien"), ["lorien", "osgiliath"])
        self.assertEqual(selectors("/deploy @mobile"), ["khazad-dum", "weathertop"])
        self.assertEqual(selectors("/deploy @server,osgiliath"), ["lorien", "osgiliath"])

    def test_reject_shell_and_unknown_targets(self):
        for command in ["/deploy", "/deploy lorien;reboot", "/deploy $(id)", "/deploy @all", "/deploy lorien --reboot", "/deploy lorien,", "/deploy ../host"]:
            with self.subTest(command=command), self.assertRaises(ValueError):
                selectors(command)

    def test_signatures(self):
        body = b'{"test":true}'
        digest = hmac.new(b"secret", body, hashlib.sha256).hexdigest()
        self.assertTrue(signed(body, digest, "secret"))
        self.assertTrue(signed(body, "sha256=" + digest, "secret"))
        self.assertFalse(signed(body + b" ", digest, "secret"))
        self.assertFalse(signed(body, "", "secret"))

    def test_store_export_denies_generic_protocol_and_traversal(self):
        script = Path(__file__).resolve().parents[2] / "scripts/forgejo/store-export.py"
        commands = [
            "nix-store --serve",
            "nix-store --serve --write",
            "result ../../etc/passwd lorien",
            "bash",
            "result " + SHA + " lorien;id",
            "export " + SHA + " lorien;id",
        ]
        for command in commands:
            proc = subprocess.run(
                [sys.executable, str(script)],
                env={**os.environ, "SSH_ORIGINAL_COMMAND": command},
                capture_output=True,
            )
            self.assertEqual(proc.returncode, 1)

    def test_store_export_is_bound_to_validated_manifest(self):
        script = Path(__file__).resolve().parents[2] / "scripts/forgejo/store-export.py"
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary) / "state"
            result = state / "results" / SHA / "lorien.json"
            result.parent.mkdir(parents=True)
            manifest = {
                "repository": REPOSITORY,
                "sha": SHA,
                "host": "lorien",
                "closure": CLOSURE,
            }
            result.write_text(json.dumps(manifest))
            bindir = Path(temporary) / "bin"
            bindir.mkdir()
            fake = bindir / "nix-store"
            fake.write_text(
                '#!/bin/sh\ncase "$1" in\n'
                '  --query) printf "%s\\n" "$3";;\n'
                '  --export) printf archive;;\n'
                '  *) exit 2;;\n'
                'esac\n'
            )
            fake.chmod(0o755)
            env = {
                **os.environ,
                "FORGEJO_CI_STATE": str(state),
                "PATH": str(bindir) + ":" + os.environ["PATH"],
            }
            metadata = subprocess.run(
                [sys.executable, str(script)],
                env={**env, "SSH_ORIGINAL_COMMAND": f"result {SHA} lorien"},
                capture_output=True,
                check=True,
                text=True,
            )
            self.assertEqual(json.loads(metadata.stdout), manifest)
            archive = subprocess.run(
                [sys.executable, str(script)],
                env={**env, "SSH_ORIGINAL_COMMAND": f"export {SHA} lorien"},
                capture_output=True,
                check=True,
            )
            self.assertEqual(archive.stdout, b"archive")
            manifest["repository"] = "attacker/repository"
            result.write_text(json.dumps(manifest))
            denied = subprocess.run(
                [sys.executable, str(script)],
                env={**env, "SSH_ORIGINAL_COMMAND": f"export {SHA} lorien"},
                capture_output=True,
            )
            self.assertEqual(denied.returncode, 1)

class WorkflowTests(unittest.TestCase):
    def test_update_branch_does_not_duplicate_pr_builds(self):
        workflow = (Path(__file__).resolve().parents[2] / ".forgejo/workflows/build.yml").read_text()
        self.assertIn("\n  pull_request:", workflow)
        self.assertNotIn("\n  push:", workflow)
        # Removing `push` left the update PR with no trigger at all, so
        # update.py dispatches this workflow itself. Keep the inputs it sends.
        self.assertIn("workflow_dispatch:", workflow)


class StatusCleanupTests(unittest.TestCase):
    def test_force_pushed_cancelled_run_is_closed(self):
        old_sha = "c" * 40
        api = Mock()
        api.url = "https://example.test"
        api.repo.side_effect = lambda path: {
            "pulls/78/commits?limit=100": [],
            "actions/runs?limit=50": {"workflow_runs": [{"id": 16, "status": "cancelled"}]},
            "actions/runs/16": {
                "event": "pull_request",
                "commit_sha": old_sha,
                "event_payload": json.dumps({"number": 78}),
            },
        }[path]
        api.statuses.return_value = [{
            "context": "colmena/khazad-dum",
            "state": "pending",
            "target_url": "/actions/runs/16",
        }]
        supersede_pending(api, {"number": 78}, SHA, {SHA}, "https://example.test/actions/runs/17")
        api.status.assert_called_once_with(
            old_sha,
            "colmena/khazad-dum",
            "error",
            "Superseded by newer PR head",
            "https://example.test/actions/runs/16",
        )

    def test_dispatched_run_status_is_superseded(self):
        # update.py asks for its build through workflow_dispatch, so Forgejo
        # names the generated check for that event, not for pull_request.
        old_sha = "d" * 40
        context = "Colmena PR builds / build (workflow_dispatch)"
        api = Mock()
        api.url = "https://example.test"
        api.repo.side_effect = lambda path: {
            "pulls/93/commits?limit=100": [{"sha": old_sha}],
            "actions/runs?limit=50": {"workflow_runs": []},
        }[path]
        api.statuses.return_value = [
            {"context": context, "state": "pending", "target_url": "/actions/runs/72"},
            {"context": "unrelated / check (workflow_dispatch)", "state": "pending", "target_url": ""},
        ]
        supersede_pending(api, {"number": 93}, SHA, {SHA}, "https://example.test/actions/runs/73")
        api.status.assert_called_once_with(
            old_sha,
            context,
            "error",
            "Superseded by newer PR head",
            "https://example.test/actions/runs/72",
        )

    def test_unexpected_failure_closes_missing_and_pending_hosts(self):
        api = Mock()
        api.statuses.return_value = [
            {"context": "colmena/lorien", "state": "success"},
            {"context": "colmena/osgiliath", "state": "pending"},
            {"context": "unrelated", "state": "pending"},
        ]
        close_incomplete_statuses(api, SHA, "https://example.test/run/1")
        self.assertEqual(
            [call.args[1] for call in api.status.call_args_list],
            ["colmena/osgiliath", "colmena/khazad-dum"],
        )

    def test_event_sha_uses_pr_head_before_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            event = Path(temporary) / "event.json"
            event.write_text(json.dumps({"pull_request": {"head": {"sha": SHA}}}))
            with patch.dict(os.environ, {"GITHUB_EVENT_PATH": str(event), "COMMIT_SHA": ""}):
                self.assertEqual(event_sha(), SHA)


class RetentionTests(unittest.TestCase):
    def test_weathertop_is_excluded_from_ci(self):
        self.assertEqual(BUILD_ORDER, CI_HOSTS)
        self.assertNotIn("weathertop", CI_HOSTS)
        self.assertIn("weathertop", HOSTS)

    @staticmethod
    def _seed(state, sha, now, age=0, prs=None):
        for name in ("roots", "results"):
            (state / name / sha).mkdir(parents=True)
        if prs is not None:
            manifest = state / "results" / sha / "osgiliath.json"
            manifest.write_text(json.dumps({"sha": sha, "prs": prs}))
        # Set mtimes last: writing the manifest touches the results directory,
        # which would otherwise stamp it with the real clock and defeat `now`.
        for name in ("roots", "results"):
            os.utime(state / name / sha, (now - age,) * 2)

    def test_prune_preserves_current_head_and_removes_expired_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary)
            current = "b" * 40
            expired = "c" * 40
            now = 2_000_000_000
            for sha in (current, expired):
                self._seed(state, sha, now, age=RETENTION_SECONDS + 1)
            removed = prune_retention(state, {7: current}, now=now)
            self.assertEqual(len(removed), 2)
            self.assertTrue((state / "roots" / current).exists())
            self.assertTrue((state / "results" / current).exists())
            self.assertFalse((state / "roots" / expired).exists())
            self.assertFalse((state / "results" / expired).exists())
            self.assertEqual((state / "roots" / current).stat().st_mtime, now)

    def test_superseded_head_is_dropped_immediately(self):
        """A head its own PR has moved past pins a closure nothing can deploy."""
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary)
            current = "b" * 40
            old = "c" * 40
            now = 2_000_000_000
            self._seed(state, current, now, prs=[7])
            self._seed(state, old, now, prs=[7])
            removed = prune_retention(state, {7: current}, now=now)
            self.assertEqual(len(removed), 2)
            self.assertFalse((state / "roots" / old).exists())
            self.assertTrue((state / "roots" / current).exists())

    def test_closed_pr_head_keeps_the_transfer_grace_period(self):
        """PR 7 is gone from pr_heads; its final head must survive to transfer."""
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary)
            landed = "c" * 40
            now = 2_000_000_000
            self._seed(state, landed, now, prs=[7])
            self.assertEqual(prune_retention(state, {}, now=now), [])
            self.assertTrue((state / "roots" / landed).exists())
            # ...but not forever.
            os.utime(state / "roots" / landed, (now - RETENTION_SECONDS - 1,) * 2)
            os.utime(state / "results" / landed, (now - RETENTION_SECONDS - 1,) * 2)
            self.assertEqual(len(prune_retention(state, {}, now=now)), 2)

    def test_head_shared_by_a_still_current_pr_is_kept(self):
        """Two PRs can point at one SHA; one moving on must not evict it."""
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary)
            shared = "c" * 40
            now = 2_000_000_000
            self._seed(state, shared, now, prs=[7, 8])
            self.assertEqual(prune_retention(state, {7: "b" * 40, 8: shared}, now=now), [])
            self.assertTrue((state / "roots" / shared).exists())

    def test_state_without_a_manifest_falls_back_to_the_age_rule(self):
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary)
            orphan = "c" * 40
            now = 2_000_000_000
            self._seed(state, orphan, now)
            self.assertEqual(superseded_heads(state, {7: "b" * 40}), set())
            self.assertEqual(prune_retention(state, {7: "b" * 40}, now=now), [])
            self.assertTrue((state / "roots" / orphan).exists())

    def test_grace_period_is_short_enough_to_bound_the_store(self):
        self.assertLessEqual(RETENTION_SECONDS, 2 * 86400)

    @patch("build.subprocess.run")
    @patch("build.shutil.disk_usage")
    def test_gc_runs_only_at_disk_threshold(self, disk_usage, run):
        disk_usage.return_value = shutil._ntuple_diskusage(500 * GIB, 400 * GIB, 100 * GIB)
        self.assertFalse(gc_if_needed(Path("/state")))
        run.assert_not_called()
        disk_usage.return_value = shutil._ntuple_diskusage(500 * GIB, 425 * GIB, 75 * GIB)
        self.assertTrue(gc_if_needed(Path("/state")))
        run.assert_called_once_with(["nix-store", "--gc"], check=True)

    @patch("build.subprocess.run")
    @patch("build.shutil.disk_usage")
    def test_gc_also_preserves_build_headroom(self, disk_usage, run):
        disk_usage.return_value = shutil._ntuple_diskusage(160 * GIB, 135 * GIB, 25 * GIB)
        self.assertTrue(gc_if_needed(Path("/state")))
        run.assert_called_once_with(["nix-store", "--gc"], check=True)

    @patch("build.shutil.disk_usage")
    def test_build_refuses_to_consume_final_reserve(self, disk_usage):
        disk_usage.return_value = shutil._ntuple_diskusage(160 * GIB, 131 * GIB, 29 * GIB)
        with self.assertRaisesRegex(RuntimeError, "refusing to start"):
            require_build_headroom(Path("/state"))

class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = patch.dict(os.environ, {"CONTROLLER_STATE": self.tmp.name, "FORGEJO_OWNER_ID": "1", "FORGEJO_BOT_ID": "2"})
        self.env.start(); self.addCleanup(self.env.stop)
        self.api_patch = patch("controller.API")
        self.api = self.api_patch.start().return_value
        self.api.url = "https://example.test"
        self.addCleanup(self.api_patch.stop)
        self.c = Controller()
        self.pr = {"number": 5, "state": "open", "head": {"sha": SHA, "repo": {"full_name": REPOSITORY}, "ref": "test"}}
        self.api.repo.return_value = self.pr
        self.api.pulls.return_value = []

    def job(self):
        import time
        return {"sha": SHA, "pr": 5, "targets": ["lorien"], "created": time.time(), "hosts": {}}

    def test_stale_sha_is_not_deployed(self):
        self.api.repo.return_value = {**self.pr, "head": {**self.pr["head"], "sha": "c" * 40}}
        with self.assertRaisesRegex(ValueError, "PR changed"):
            self.c.deploy("1", self.job())

    def test_failed_selected_host_blocks_deploy(self):
        self.c.trusted_statuses = Mock(return_value={"colmena/lorien": {"state": "failure"}})
        with self.assertRaisesRegex(ValueError, "Build failed"):
            self.c.deploy("1", self.job())

    def test_pending_build_dispatches_once(self):
        self.c.trusted_statuses = Mock(return_value={})
        job = self.job()
        self.c.deploy("1", job); self.c.deploy("1", job)
        dispatches = [call for call in self.api.repo.call_args_list if "dispatches" in call.args[0]]
        self.assertEqual(len(dispatches), 1)

    def test_unrelated_host_failure_does_not_block(self):
        self.c.trusted_statuses = Mock(return_value={"colmena/lorien": {"state": "success"}, "colmena/weathertop": {"state": "failure"}})
        self.c.pull_closure = Mock(return_value=CLOSURE)
        self.c.target = Mock(return_value="/nix/store/previous")
        with patch("controller.subprocess.run") as run:
            self.c.deploy("1", self.job())
        self.assertTrue(any(call.args[0][:2] == ["nix", "copy"] for call in run.call_args_list))
        self.assertFalse(any("build" in call.args[0] for call in run.call_args_list))
        run.assert_called_once_with(["nix", "copy", "--to", "ssh-ng://nixos-deploy@lorien", CLOSURE], check=True, timeout=3600)
        self.assertEqual(self.c.target.call_count, 3)
        self.c.target.assert_any_call("lorien", ["readlink", "-f", "/run/current-system"])

    def test_legacy_target_without_readlink_still_activates(self):
        self.c.trusted_statuses = Mock(return_value={"colmena/lorien": {"state": "success"}})
        self.c.pull_closure = Mock(return_value=CLOSURE)
        self.c.target = Mock(side_effect=[
            subprocess.CalledProcessError(1, "readlink"), "", "",
        ])
        job = self.job()
        with patch("controller.subprocess.run"):
            self.c.deploy("1", job)
        self.assertEqual(job["hosts"]["lorien"]["previous"], "unknown")
        self.assertEqual(job["hosts"]["lorien"]["stage"], "done")

    def test_restart_checks_completed_activation_without_repeating(self):
        job = self.job(); job["started"] = True
        job["hosts"]["lorien"] = {"closure": CLOSURE, "stage": "activating", "previous": "old"}
        self.c.trusted_statuses = Mock(side_effect=OSError("Forgejo restarting"))
        self.api.repo.side_effect = OSError("Forgejo restarting")
        self.c.target = Mock(return_value=CLOSURE)
        self.c.deploy("1", job)
        self.c.target.assert_called_once_with("lorien", ["readlink", "-f", "/run/current-system"])
        self.api.repo.assert_not_called()
        self.c.trusted_statuses.assert_not_called()
        self.assertEqual(job["hosts"]["lorien"]["stage"], "done")

    def test_restarted_controller_gives_activation_time_to_finish(self):
        job = self.job(); job["started"] = True
        job["hosts"]["lorien"] = {"closure": CLOSURE, "stage": "activating"}
        self.c.trusted_statuses = Mock(return_value={})
        self.c.target = Mock(return_value="old")
        with patch("controller.time.time", return_value=1000):
            self.c.deploy("1", job)
        self.assertEqual(job["hosts"]["lorien"]["activation_started"], 1000)
        self.assertEqual(job["hosts"]["lorien"]["stage"], "activating")

    def test_ambiguous_activation_never_repeats(self):
        job = self.job(); job["started"] = True
        job["hosts"]["lorien"] = {"closure": CLOSURE, "stage": "activating", "activation_started": time.time() - 301}
        self.c.trusted_statuses = Mock(return_value={})
        self.c.target = Mock(return_value="old")
        with self.assertRaisesRegex(ValueError, "Interrupted activation"):
            self.c.deploy("1", job)
        self.assertEqual(self.c.target.call_count, 1)

    @patch("controller.os.chmod")
    def test_store_ssh_protects_private_key(self, chmod):
        with patch.dict(os.environ, {"STORE_KEY": "/state/reader", "STORE_KNOWN_HOSTS": "/state/known", "STORE_PORT": "2223"}):
            command = self.c.store_ssh()
        chmod.assert_called_once_with("/state/reader", 0o600)
        self.assertIn("/state/reader", command)

    @patch("controller.subprocess.run")
    @patch("controller.subprocess.Popen")
    @patch("controller.subprocess.check_output")
    def test_manifest_verified_closure_is_signed_before_retention(self, check_output, popen, run):
        check_output.return_value = json.dumps({
            "repository": REPOSITORY, "sha": SHA, "host": "lorien",
            "run_url": "https://example.test/run/1", "closure": CLOSURE,
        })
        exporter = popen.return_value
        exporter.stdout = io.BytesIO()
        exporter.wait.return_value = 0
        run.side_effect = [Mock(returncode=0), Mock(returncode=0), Mock(returncode=0)]
        self.c.store_ssh = Mock(return_value=["ssh"])
        with patch.dict(os.environ, {"STORE_SIGNING_KEY": "/run/agenix/signing-key"}):
            self.assertEqual(self.c.pull_closure(SHA, "lorien", {
                "target_url": "https://example.test/run/1",
            }), CLOSURE)
        self.assertEqual(run.call_args_list[1].args[0], [
            "nix", "store", "sign", "--recursive", "--key-file",
            "/run/agenix/signing-key", CLOSURE,
        ])

    @patch("controller.subprocess.check_output", return_value="")
    def test_self_activation_uses_restricted_ssh_session(self, check_output):
        self.c.target("osgiliath", ["sudo", "-H", "--", "nix-env", "--version"])
        check_output.assert_called_once_with(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=yes", "nixos-deploy@osgiliath", "sudo", "-H", "--", "nix-env", "--version"],
            text=True,
            timeout=600,
        )

    @patch("controller.subprocess.Popen")
    def test_self_activation_is_detached_from_controller(self, popen):
        self.c.start_self_activation(CLOSURE)
        popen.assert_called_once_with(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15",
             "-o", "StrictHostKeyChecking=yes", "nixos-deploy@osgiliath",
             "sudo", "-H", "--", CLOSURE + "/bin/switch-to-configuration", "switch"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True,
        )

    def test_pr_comment_retries_after_forgejo_restart(self):
        self.c.queue_comment("deploy:1:success", 5, "complete")
        self.api.comment.side_effect = OSError("Forgejo restarting")
        with self.assertRaises(OSError):
            self.c.send_comments()
        with self.c.db() as db:
            self.assertEqual(db.execute("SELECT sent FROM comments").fetchone()[0], 0)
        self.api.comment.side_effect = None
        self.c.send_comments()
        with self.c.db() as db:
            self.assertEqual(db.execute("SELECT sent FROM comments").fetchone()[0], 1)

    def test_terminal_build_notification_is_deduplicated(self):
        self.api.pulls.return_value = [self.pr]
        self.api.statuses.return_value = [
            {"context": f"colmena/{host}", "creator": {"id": 2}, "state": "success",
             "target_url": "https://example.test/run/7"} for host in CI_HOSTS
        ]
        self.c.queue_build_notification(SHA)
        self.c.queue_build_notification(SHA)
        with self.c.db() as db:
            rows = db.execute("SELECT id,payload FROM notifications").fetchall()
        self.assertEqual(len(rows), 1)
        self.assertIn("passed for all CI hosts", rows[0][1])

    def test_pending_build_has_no_notification(self):
        self.api.pulls.return_value = [self.pr]
        self.api.statuses.return_value = [
            {"context": f"colmena/{host}", "creator": {"id": 2},
             "state": "pending" if host == "khazad-dum" else "success"}
            for host in CI_HOSTS
        ]
        self.c.queue_build_notification(SHA)
        with self.c.db() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM notifications").fetchone()[0], 0)

    def test_terminal_action_run_closes_unresolved_host_status(self):
        self.api.statuses.return_value = [
            {"context": f"colmena/{host}", "creator": {"id": 2},
             "state": "pending" if host == "khazad-dum" else "failure"}
            for host in CI_HOSTS
        ]
        self.api.repo.return_value = {"workflow_runs": [{
            "id": 24,
            "workflow_id": "build.yml",
            "commit_sha": SHA,
            "status": "failure",
            "html_url": "https://example.test/run/24",
        }]}
        self.assertTrue(self.c.reconcile_terminal_build(SHA))
        self.api.status.assert_called_once_with(
            SHA,
            "colmena/khazad-dum",
            "failure",
            "Forgejo run failure before this host reported a result",
            "https://example.test/run/24",
        )

    def test_running_action_does_not_close_pending_status(self):
        self.api.statuses.return_value = [
            {"context": f"colmena/{host}", "creator": {"id": 2}, "state": "pending"}
            for host in CI_HOSTS
        ]
        self.api.repo.return_value = {"workflow_runs": [{
            "id": 24,
            "workflow_id": "build.yml",
            "commit_sha": SHA,
            "status": "running",
        }]}
        self.assertFalse(self.c.reconcile_terminal_build(SHA))
        self.api.status.assert_not_called()

    def test_untrusted_status_is_ignored(self):
        self.api.statuses.return_value = [{"context": "colmena/lorien", "creator": {"id": 99}, "state": "success"}]
        self.assertEqual(self.c.trusted_statuses(SHA), {})

    def test_status_without_creator_uses_matching_action_run(self):
        self.api.statuses.return_value = [{"context": "colmena/lorien", "creator": None, "state": "failure",
            "target_url": "https://example.test/aidengindin/nixos-config/actions/runs/7"}]
        self.api.repo.return_value = {"commit_sha": SHA}
        self.assertEqual(self.c.trusted_statuses(SHA)["colmena/lorien"]["state"], "failure")

    def test_status_without_creator_rejects_mismatched_run(self):
        self.api.statuses.return_value = [{"context": "colmena/lorien", "creator": None, "state": "success",
            "target_url": "https://example.test/aidengindin/nixos-config/actions/runs/7"}]
        self.api.repo.return_value = {"commit_sha": "b" * 40}
        self.assertEqual(self.c.trusted_statuses(SHA), {})

    def test_unknown_comment_author_is_ignored(self):
        self.c.accept("issue_comment", {"repository": {"full_name": REPOSITORY}, "action": "created", "comment": {"body": "/deploy @server", "user": {"id": 99}}})
        self.api.repo.assert_not_called()

    def test_ci_excluded_host_cannot_be_deployed_from_pr(self):
        comment = {"id": 9, "user": {"id": 1}, "body": "/deploy weathertop"}
        self.api.repo.side_effect = [comment, self.pr]
        payload = {"repository": {"full_name": REPOSITORY}, "action": "created", "comment": comment, "issue": {"number": 5}}
        with self.assertRaisesRegex(ValueError, "excluded from CI"):
            self.c.accept("issue_comment", payload)
        with self.c.db() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM jobs").fetchone()[0], 0)

    def test_duplicate_comment_is_queued_once(self):
        comment = {"id": 10, "user": {"id": 1}, "body": "/deploy lorien"}
        self.api.repo.side_effect = [comment, self.pr, comment, self.pr]
        payload = {"repository": {"full_name": REPOSITORY}, "action": "created", "comment": comment, "issue": {"number": 5}}
        self.c.accept("issue_comment", payload); self.c.accept("issue_comment", payload)
        with self.c.db() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM jobs").fetchone()[0], 1)
        self.api.comment.assert_called_once()

if __name__ == "__main__":
    unittest.main()
