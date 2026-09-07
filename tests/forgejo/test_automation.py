import hashlib
import hmac
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/forgejo"))
from common import HOSTS, REPOSITORY, selectors
from controller import Controller, signed

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

    def test_store_export_denies_writes_and_traversal(self):
        script = Path(__file__).resolve().parents[2] / "scripts/forgejo/store-export.py"
        for command in ["nix-store --serve --write", "result ../../etc/passwd lorien", "bash", "result " + SHA + " lorien;id"]:
            proc = subprocess.run([sys.executable, str(script)], env={**os.environ, "SSH_ORIGINAL_COMMAND": command}, capture_output=True)
            self.assertEqual(proc.returncode, 1)

class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = patch.dict(os.environ, {"CONTROLLER_STATE": self.tmp.name, "FORGEJO_OWNER_ID": "1", "FORGEJO_BOT_ID": "2"})
        self.env.start(); self.addCleanup(self.env.stop)
        self.api_patch = patch("controller.API")
        self.api = self.api_patch.start().return_value
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
        self.assertEqual(self.c.target.call_count, 3)

    def test_restart_checks_completed_activation_without_repeating(self):
        job = self.job(); job["started"] = True
        job["hosts"]["lorien"] = {"closure": CLOSURE, "stage": "activating", "previous": "old"}
        self.c.trusted_statuses = Mock(return_value={})
        self.c.target = Mock(return_value=CLOSURE)
        self.c.deploy("1", job)
        self.c.target.assert_called_once_with("lorien", ["readlink", "-f", "/run/current-system"])
        self.assertEqual(job["hosts"]["lorien"]["stage"], "done")

    def test_ambiguous_activation_never_repeats(self):
        job = self.job(); job["started"] = True
        job["hosts"]["lorien"] = {"closure": CLOSURE, "stage": "activating"}
        self.c.trusted_statuses = Mock(return_value={})
        self.c.target = Mock(return_value="old")
        with self.assertRaisesRegex(ValueError, "Interrupted activation"):
            self.c.deploy("1", job)
        self.assertEqual(self.c.target.call_count, 1)

    def test_untrusted_status_is_ignored(self):
        self.api.statuses.return_value = [{"context": "colmena/lorien", "creator": {"id": 99}, "state": "success"}]
        self.assertEqual(self.c.trusted_statuses(SHA), {})

    def test_status_without_creator_is_ignored(self):
        self.api.statuses.return_value = [{"context": "colmena/lorien", "creator": None, "state": "failure"}]
        self.assertEqual(self.c.trusted_statuses(SHA), {})

    def test_unknown_comment_author_is_ignored(self):
        self.c.accept("issue_comment", {"repository": {"full_name": REPOSITORY}, "action": "created", "comment": {"body": "/deploy @server", "user": {"id": 99}}})
        self.api.repo.assert_not_called()

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
