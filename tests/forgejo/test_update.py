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
        self.assertIn("first-updater", api.repo.call_args.kwargs["data"]["body"])

    def test_no_change_success_does_not_open_pr(self):
        api = Mock(); api.pulls.return_value = []
        with patch.object(update, "API", return_value=api), patch.object(update, "git", return_value=""), patch.object(update, "COMMANDS", []), patch.object(update.subprocess, "run", return_value=Mock(returncode=2)), patch("builtins.open", mock_open()), patch.object(update.fcntl, "flock"):
            self.assertEqual(update.main(), 0)
        api.repo.assert_not_called()
        api.status.assert_not_called()
