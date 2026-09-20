import os
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, mock_open, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/forgejo"))
import update

class UpdateTests(unittest.TestCase):
    def test_partial_edits_are_committed_before_failure_is_reported(self):
        api = Mock(); api.url = "https://forgejo.test"; api.pulls.return_value = []
        api.repo.return_value = {"number": 78}
        operations = []
        def git(*args, capture=False):
            operations.append(args)
            if args[0] == "status": return " M flake.lock"
            if args[0] == "rev-parse": return "a" * 40
        def run(command, **kwargs):
            return Mock(returncode=1 if command[0] in ("git", "first-updater") else 0)
        with patch.object(update, "API", return_value=api), patch.object(update, "git", side_effect=git), patch.object(update, "COMMANDS", [["first-updater"], ["second-updater"]]), patch.object(update.subprocess, "run", side_effect=run), patch("builtins.open", mock_open()), patch.object(update.fcntl, "flock"), patch.dict(os.environ, {"GITHUB_RUN_ID": "1"}):
            self.assertEqual(update.main(), 1)
        self.assertLess(next(i for i,o in enumerate(operations) if o[0] == "commit"), next(i for i,o in enumerate(operations) if o[0] == "push"))
        api.status.assert_called_once()
        self.assertEqual(api.status.call_args.args[2], "failure")
        # The PR call is no longer the last one; the build dispatch follows it.
        body = next(c.kwargs["data"]["body"] for c in api.repo.call_args_list if c.args[0] == "pulls")
        self.assertIn("first-updater", body)

    def test_no_change_success_does_not_open_pr(self):
        api = Mock(); api.pulls.return_value = []
        with patch.object(update, "API", return_value=api), patch.object(update, "git", return_value=""), patch.object(update, "COMMANDS", []), patch.object(update.subprocess, "run", return_value=Mock(returncode=2)), patch("builtins.open", mock_open()), patch.object(update.fcntl, "flock"):
            self.assertEqual(update.main(), 0)
        api.repo.assert_not_called()
        api.status.assert_not_called()


class DispatchTests(unittest.TestCase):
    """The update PR is opened by the Forgejo Actions user, and Forgejo raises no
    workflow events for that actor, so build.yml's `pull_request` trigger never
    fires for it. The `push` trigger that used to cover this branch was removed
    to deduplicate builds, so update.py asks for the build itself."""

    BEFORE = "b" * 40
    AFTER = "c" * 40

    def dispatches(self, *, moved=True, changed=True, remote=True, existing=True):
        captures = {("status", "--porcelain"): "M flake.lock" if changed else "",
            ("rev-parse", "FETCH_HEAD"): self.BEFORE,
            ("rev-parse", "HEAD"): self.AFTER if moved else self.BEFORE}
        def git(*args, capture=False):
            return captures[args] if capture else None
        api = Mock(); api.url = "https://forgejo.test"
        api.pulls.return_value = [{"number": 93, "head": {"ref": "automation/update"}}] if existing else []
        api.repo.return_value = {"number": 93}
        with patch.object(update, "API", return_value=api), patch.object(update, "git", git), patch.object(update, "COMMANDS", []), patch.object(update.subprocess, "run", return_value=Mock(returncode=0 if remote else 1)), patch("builtins.open", mock_open()), patch.object(update.fcntl, "flock"), patch.dict(os.environ, {"GITHUB_RUN_ID": "72"}):
            update.main()
        return [c for c in api.repo.call_args_list if c.args[0] == "actions/workflows/build.yml/dispatches"]

    def test_new_head_is_dispatched_with_the_pushed_sha(self):
        dispatched = self.dispatches()
        self.assertEqual(len(dispatched), 1)
        self.assertEqual(dispatched[0].kwargs["data"],
            {"ref": "main", "inputs": {"pr": "93", "sha": self.AFTER}})

    def test_first_cycle_dispatches_for_the_newly_opened_pr(self):
        self.assertEqual(len(self.dispatches(remote=False, existing=False)), 1)

    def test_unmoved_head_is_not_rebuilt(self):
        self.assertEqual(self.dispatches(moved=False, changed=False), [])
