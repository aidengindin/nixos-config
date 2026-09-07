import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("hermes_filter", Path(__file__).resolve().parents[2] / "scripts/forgejo/hermes-filter.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class HermesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.environment = patch.dict(os.environ, {"HERMES_REPAIR_STATE": self.tmp.name,
            "FORGEJO_BOT_ID": "2", "FORGEJO_URL": "https://example.test", "FORGEJO_TOKEN": "test"})
        self.environment.start(); self.addCleanup(self.environment.stop)

    def invoke(self, sha, *, changed=False, pending=False, creator=2):
        (Path(self.tmp.name) / sha).mkdir(exist_ok=True)
        payload = {"repository": module.REPO, "sha": sha, "pr": 5}
        pull = {"number": 5, "state": "open", "head": {"ref": module.BRANCH, "sha": "e" * 40 if changed else sha,
            "repo": {"full_name": module.REPO}}, "body": "Update-Cycle: 2026-09-07"}
        statuses = {"statuses": [{"state": "failure", "context": "colmena/lorien", "creator": {"id": creator}, "target_url": "https://example.test/log"}]}
        if pending:
            statuses["statuses"].append({"state": "pending", "context": "colmena/osgiliath"})
        output = io.StringIO()
        with patch.object(module, "api", side_effect=[pull, statuses]), patch.object(module.sys, "stdin", io.StringIO(json.dumps(payload))), patch.object(module.sys, "stdout", output), patch.object(module.subprocess, "run"), patch.object(module.subprocess, "check_output", return_value=sha):
            module.main()
        return output.getvalue()

    def test_valid_failure_prepares_repair_and_deduplicates(self):
        first = self.invoke("a" * 40)
        self.assertIn("Attempt 1 of 3", first)
        self.assertIn("push normally", first)
        self.assertEqual(self.invoke("a" * 40), "")

    def test_three_attempt_budget_survives_new_heads(self):
        for i, letter in enumerate("abc", 1):
            self.assertIn(f"Attempt {i} of 3", self.invoke(letter * 40))
        self.assertEqual(self.invoke("d" * 40), "")

    def test_stale_head_has_no_side_effects(self):
        self.assertEqual(self.invoke("a" * 40, changed=True), "")
        self.assertFalse((Path(self.tmp.name) / "attempts.json").exists())

    def test_pending_build_does_not_consume_attempt(self):
        self.assertIn("__hermes_ignore__", self.invoke("a" * 40, pending=True))
        self.assertFalse((Path(self.tmp.name) / "attempts.json").exists())

    def test_untrusted_failure_does_not_consume_attempt(self):
        self.invoke("a" * 40, creator=99)
        self.assertFalse((Path(self.tmp.name) / "attempts.json").exists())
