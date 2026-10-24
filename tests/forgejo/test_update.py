import datetime
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
            # Reads the test does not care about (such as main's flake.lock
            # for the review list) return nothing, which update.py tolerates.
            return captures.get(args) if capture else None
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


def node(owner, repo, rev, **original):
    return {"locked": {"type": "github", "owner": owner, "repo": repo, "rev": rev},
            "original": {"type": "github", "owner": owner, "repo": repo, **original}}


class ReviewTests(unittest.TestCase):
    """Every third-party input the PR moves is listed with an upstream diff."""

    def lock(self, **nodes):
        return {"nodes": {"root": {"inputs": {}}, **nodes}}

    def test_moved_third_party_input_gets_a_compare_link(self):
        moved = update.moved_inputs(self.lock(agenix=node("ryantm", "agenix", "a" * 40)),
                                    self.lock(agenix=node("ryantm", "agenix", "b" * 40)))
        self.assertEqual(moved, [{"name": "agenix", "old": "a" * 40, "new": "b" * 40,
            "link": f"https://github.com/ryantm/agenix/compare/{'a' * 40}...{'b' * 40}"}])

    def test_unmoved_channel_and_own_inputs_are_left_out(self):
        old = self.lock(
            agenix=node("ryantm", "agenix", "a" * 40),
            nixpkgs=node("NixOS", "nixpkgs", "a" * 40, ref="nixos-26.05"),
            anduin=node("aidengindin", "anduin", "a" * 40),
            job=dict(locked={"type": "git", "url": "https://git.gindin.xyz/aidengindin/job-scraper.git", "rev": "a" * 40}, original={}))
        new = self.lock(
            agenix=node("ryantm", "agenix", "a" * 40),
            nixpkgs=node("NixOS", "nixpkgs", "b" * 40, ref="nixos-26.05"),
            anduin=node("aidengindin", "anduin", "b" * 40),
            job=dict(locked={"type": "git", "url": "https://git.gindin.xyz/aidengindin/job-scraper.git", "rev": "b" * 40}, original={}))
        self.assertEqual(update.moved_inputs(old, new), [])

    def test_renumbered_node_is_matched_by_its_original(self):
        old = self.lock(nixvim_2=node("nix-community", "nixvim", "a" * 40))
        new = self.lock(nixvim=node("nix-community", "nixvim", "b" * 40))
        self.assertEqual(update.moved_inputs(old, new)[0]["old"], "a" * 40)

    def test_new_input_links_to_its_tree(self):
        moved = update.moved_inputs(self.lock(), self.lock(x=node("o", "r", "c" * 40)))
        self.assertIsNone(moved[0]["old"])
        self.assertIn("/tree/" + "c" * 40, moved[0]["link"])
        self.assertIn("new input", update.review_section(moved))

    def test_nothing_moved_says_so(self):
        self.assertIn("No third-party", update.review_section([]))


class ModeTests(unittest.TestCase):
    """Daily runs move only the NixOS channels; Sundays run everything."""

    MONDAY = datetime.date(2026, 10, 26)
    SUNDAY = datetime.date(2026, 10, 25)

    def test_schedule_runs_channels_on_weekdays_and_full_on_sunday(self):
        env = {"GITHUB_EVENT_NAME": "schedule"}
        self.assertEqual(update.resolve_mode(env, self.MONDAY), "channels")
        self.assertEqual(update.resolve_mode(env, self.SUNDAY), "full")

    def test_explicit_mode_wins_and_unknown_mode_is_refused(self):
        env = {"GITHUB_EVENT_NAME": "schedule", "UPDATE_MODE": "full"}
        self.assertEqual(update.resolve_mode(env, self.MONDAY), "full")
        self.assertEqual(update.resolve_mode({"UPDATE_MODE": "channels"}, self.SUNDAY), "channels")
        with self.assertRaises(ValueError):
            update.resolve_mode({"UPDATE_MODE": "everything"}, self.MONDAY)

    def test_dispatch_and_manual_runs_default_to_full(self):
        self.assertEqual(update.resolve_mode({"GITHUB_EVENT_NAME": "workflow_dispatch"}, self.MONDAY), "full")
        self.assertEqual(update.resolve_mode({}, self.MONDAY), "full")

    def test_daily_commands_touch_only_channel_inputs(self):
        # The caddy plugin source hash depends on nixpkgs' caddy, which channels move.
        self.assertEqual(update.DAILY_COMMANDS,
            [["nix", "flake", "update", "nixpkgs", "unstable", "home-manager", "hm-unstable"],
             ["bash", "scripts/update-caddy-hash.sh"]])

    def run_channels(self, existing_body):
        api = Mock(); api.url = "https://forgejo.test"
        api.pulls.return_value = [{"number": 93, "head": {"ref": "automation/update"}, "body": existing_body}]
        ran = []
        def git(*args, capture=False):
            if args[0] == "status": return " M flake.lock"
            if args[0] == "rev-parse": return "a" * 40
        def run(command, **kwargs):
            ran.append(command)
            return Mock(returncode=0)
        with patch.object(update, "API", return_value=api), patch.object(update, "git", side_effect=git), patch.object(update.subprocess, "run", side_effect=run), patch("builtins.open", mock_open()), patch.object(update.fcntl, "flock"), patch.dict(os.environ, {"GITHUB_RUN_ID": "1", "UPDATE_MODE": "channels"}):
            self.assertEqual(update.main(), 0)
        body = next(c.kwargs["data"]["body"] for c in api.repo.call_args_list if c.args[0] == "pulls/93")
        return ran, body

    def test_channel_run_keeps_the_last_full_runs_notes(self):
        full = f"{update.FULL_START}\n### Last full update: 2026-10-25\n\n- held: `agenix`\n{update.FULL_END}"
        ran, body = self.run_channels("intro\n\n" + full + "\n\nfooter")
        self.assertIn(update.DAILY_COMMANDS[0], ran)
        self.assertNotIn(["nix", "flake", "update"], ran)
        self.assertIn(full, body)
        self.assertIn("channel update", body)

    def test_channel_run_without_a_previous_full_run_says_so(self):
        _, body = self.run_channels("an old body without markers")
        self.assertIn("none yet on this PR", body)
