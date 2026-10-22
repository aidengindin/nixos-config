import contextlib
import datetime
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts/forgejo"))
import cve_scan

TRIAGE = '''"vuln_id","url","package","severity","version_local","version_nixpkgs","version_upstream","package_repology","sortcol","classify"
"CVE-2026-96675","https://nvd.nist.gov/vuln/detail/CVE-2026-96675","alsa-lib","4.8","1.2.15.3","1.2.16.1","1.2.16.1","alsa-lib","2026A0000096675","err_not_vulnerable_based_on_repology"
"CVE-2026-11824","https://nvd.nist.gov/vuln/detail/CVE-2026-11824","sqlite","8.5","3.51.2","3.53.3","3.54.1","sqlite","2026A0000011824","fix_update_to_version_nixpkgs"
"CVE-2025-59529","https://nvd.nist.gov/vuln/detail/CVE-2025-59529","avahi","","0.8","0.8","","avahi","2025A0000059529","err_invalid_version"
'''


class ParseTests(unittest.TestCase):
    def test_triage_drops_repology_not_vulnerable(self):
        rows = cve_scan.parse_triage(TRIAGE, "lorien")
        self.assertEqual([r["cve"] for r in rows], ["CVE-2026-11824", "CVE-2025-59529"])

    def test_triage_row_shape(self):
        row = cve_scan.parse_triage(TRIAGE, "lorien")[0]
        self.assertEqual(row, {"cve": "CVE-2026-11824", "package": "sqlite", "version": "3.51.2",
            "cvss": 8.5, "target": "lorien", "fix": "3.53.3", "classify": "fix_update_to_version_nixpkgs"})

    def test_empty_severity_is_none(self):
        self.assertIsNone(cve_scan.parse_triage(TRIAGE, "lorien")[1]["cvss"])

    def test_degraded_scanners_detected_from_log(self):
        log = ("INFO ok\nWARNING vulnscan.py:scan_vulnix():86 Command '['vulnix', '/nix/store/x']' "
               "returned non-zero exit status 1.\n")
        self.assertEqual(cve_scan.degraded_scanners(log), ["vulnix"])
        self.assertEqual(cve_scan.degraded_scanners("INFO fine\n"), [])

    GRYPE = {"matches": [
        {"vulnerability": {"id": "CVE-2026-1", "cvss": [{"metrics": {"baseScore": 9.8}}, {"metrics": {"baseScore": 7.0}}],
                           "fix": {"versions": ["1.2.4"]}},
         "artifact": {"name": "openssl", "version": "1.2.3"}, "relatedVulnerabilities": []},
        {"vulnerability": {"id": "GHSA-xxxx", "cvss": [], "fix": {"versions": []}},
         "artifact": {"name": "lodash", "version": "4.0.0"},
         "relatedVulnerabilities": [{"id": "CVE-2026-2", "cvss": [{"metrics": {"baseScore": 5.0}}]}]},
        {"vulnerability": {"id": "GHSA-only", "cvss": [], "fix": {"versions": []}},
         "artifact": {"name": "x", "version": "1"}, "relatedVulnerabilities": []},
    ]}

    def test_grype_takes_max_cvss_and_maps_ghsa_to_cve(self):
        rows = cve_scan.parse_grype(self.GRYPE, "ghcr.io/a/b:1")
        self.assertEqual([(r["cve"], r["cvss"], r["fix"]) for r in rows],
            [("CVE-2026-1", 9.8, "1.2.4"), ("CVE-2026-2", 5.0, None), ("GHSA-only", None, None)])
        self.assertEqual(rows[0]["target"], "ghcr.io/a/b:1")


TODAY = datetime.date(2026, 10, 22)


class IgnoreTests(unittest.TestCase):
    def rules(self, text):
        return cve_scan.load_ignores(text, TODAY)

    def test_package_scoped_and_global(self):
        rules = self.rules('[[ignore]]\ncve="CVE-1"\npackage="a"\nreason="r"\n'
                           '[[ignore]]\ncve="CVE-2"\nreason="r"\n')
        self.assertTrue(cve_scan.ignored({"cve": "CVE-1", "package": "a"}, rules))
        self.assertFalse(cve_scan.ignored({"cve": "CVE-1", "package": "b"}, rules))
        self.assertTrue(cve_scan.ignored({"cve": "CVE-2", "package": "z"}, rules))

    def test_expired_rule_is_dropped(self):
        rules = self.rules('[[ignore]]\ncve="CVE-1"\nreason="r"\nexpires=2026-10-21\n')
        self.assertFalse(cve_scan.ignored({"cve": "CVE-1", "package": "a"}, rules))

    def test_reason_is_required(self):
        with self.assertRaisesRegex(ValueError, "reason"):
            self.rules('[[ignore]]\ncve="CVE-1"\n')

    def test_empty_file(self):
        self.assertEqual(self.rules(""), [])

    def test_unknown_key_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "pakage"):
            self.rules('[[ignore]]\ncve="CVE-1"\npakage="a"\nreason="r"\n')

    def test_expires_must_be_a_date(self):
        with self.assertRaisesRegex(ValueError, "CVE-1"):
            self.rules('[[ignore]]\ncve="CVE-1"\nreason="r"\nexpires="2026-10-21"\n')
        with self.assertRaisesRegex(ValueError, "CVE-1"):
            self.rules('[[ignore]]\ncve="CVE-1"\nreason="r"\nexpires=2026-10-21T00:00:00Z\n')


class DiffTests(unittest.TestCase):
    def row(self, cve="CVE-1", package="p", target="lorien", cvss=9.5):
        return {"cve": cve, "package": package, "version": "1", "cvss": cvss, "target": target, "fix": None, "classify": "x"}

    def test_merge_groups_targets(self):
        merged = cve_scan.merge([self.row(target="lorien"), self.row(target="osgiliath")], kev=set())
        self.assertEqual(merged["CVE-1|p"]["targets"], ["lorien", "osgiliath"])

    def test_new_finding_pings_if_critical(self):
        current = cve_scan.merge([self.row()], kev=set())
        state, new, resolved, _ = cve_scan.diff({"findings": {}}, current, failed=set(), today=TODAY)
        self.assertEqual(new, ["CVE-1|p"])
        self.assertEqual(cve_scan.to_ping(state, new), ["CVE-1|p"])

    def test_low_score_kev_pings_and_low_score_alone_does_not(self):
        current = cve_scan.merge([self.row(cvss=5.0), self.row(cve="CVE-2", cvss=5.0)], kev={"CVE-2"})
        state, new, _, _ = cve_scan.diff({"findings": {}}, current, failed=set(), today=TODAY)
        self.assertEqual(cve_scan.to_ping(state, new), ["CVE-2|p"])

    def test_unscanned_target_keeps_findings(self):
        previous = {"findings": {"CVE-1|p": {"first_seen": "2026-10-01", "last_seen": "2026-10-21",
            "targets": ["khazad-dum"], "cvss": 9.5, "kev": False, "version": "1", "fix": None}}}
        state, new, resolved, _ = cve_scan.diff(previous, {}, failed={"khazad-dum"}, today=TODAY)
        self.assertEqual(resolved, [])
        self.assertIn("CVE-1|p", state["findings"])

    def test_failed_target_is_not_dropped_across_days(self):
        previous = {"findings": {"CVE-1|p": {"first_seen": "2026-10-01", "last_seen": "2026-10-20",
            "targets": ["khazad-dum", "lorien"], "cvss": 9.5, "kev": False, "version": "1", "fix": None}}}
        day1 = cve_scan.merge([self.row(target="lorien")], kev=set())
        state, _, resolved, _ = cve_scan.diff(previous, day1, failed={"khazad-dum"}, today=TODAY)
        self.assertEqual(state["findings"]["CVE-1|p"]["targets"], ["khazad-dum", "lorien"])
        self.assertEqual(resolved, [])
        state, _, resolved, _ = cve_scan.diff(state, {}, failed={"khazad-dum"},
            today=TODAY + datetime.timedelta(days=1))
        self.assertEqual(resolved, [])
        self.assertIn("CVE-1|p", state["findings"])

    def test_removed_target_resolves(self):
        previous = {"findings": {"CVE-1|p": {"first_seen": "2026-10-01", "last_seen": "2026-10-21",
            "targets": ["ghcr.io/x:1"], "cvss": 9.5, "kev": False, "version": "1", "fix": None}}}
        _, _, resolved, _ = cve_scan.diff(previous, {}, failed=set(), today=TODAY)
        self.assertEqual(resolved, ["CVE-1|p"])

    def test_kev_escalation_is_reported_and_pinged(self):
        previous = {"findings": {"CVE-1|p": {"first_seen": "2026-10-01", "last_seen": "2026-10-21",
            "targets": ["lorien"], "cvss": 5.0, "kev": False, "version": "1", "fix": None}}}
        current = cve_scan.merge([self.row(cvss=5.0)], kev={"CVE-1"})
        state, new, _, escalated = cve_scan.diff(previous, current, failed=set(), today=TODAY)
        self.assertEqual((new, escalated), ([], ["CVE-1|p"]))
        self.assertEqual(cve_scan.to_ping(state, new, escalated), ["CVE-1|p"])
        _, _, _, again = cve_scan.diff(state, current, failed=set(), today=TODAY)
        self.assertEqual(again, [])

    def test_unknown_kev_keeps_previous_flag_and_never_escalates(self):
        kev = cve_scan.merge([self.row()], kev={"CVE-1"})
        state, _, _, _ = cve_scan.diff({"findings": {}}, kev, failed=set(), today=TODAY)
        self.assertTrue(state["findings"]["CVE-1|p"]["kev"])
        unknown = cve_scan.merge([self.row()], kev=None)
        self.assertIsNone(unknown["CVE-1|p"]["kev"])
        state, _, _, escalated = cve_scan.diff(state, unknown, failed=set(), today=TODAY)
        self.assertEqual(escalated, [])
        self.assertIs(state["findings"]["CVE-1|p"]["kev"], True)
        state, _, _, escalated = cve_scan.diff(state, kev, failed=set(), today=TODAY)
        self.assertEqual(escalated, [])

    def test_new_finding_with_unknown_kev_is_stored_false(self):
        unknown = cve_scan.merge([self.row()], kev=None)
        state, _, _, _ = cve_scan.diff({"findings": {}}, unknown, failed=set(), today=TODAY)
        self.assertIs(state["findings"]["CVE-1|p"]["kev"], False)
        kev = cve_scan.merge([self.row()], kev={"CVE-1"})
        _, _, _, escalated = cve_scan.diff(state, kev, failed=set(), today=TODAY)
        self.assertEqual(escalated, ["CVE-1|p"])

    def test_scanned_target_resolves_and_is_remembered(self):
        previous = {"findings": {"CVE-1|p": {"first_seen": "2026-10-01", "last_seen": "2026-10-21",
            "targets": ["lorien"], "cvss": 9.5, "kev": False, "version": "1", "fix": None}}}
        state, _, resolved, _ = cve_scan.diff(previous, {}, failed=set(), today=TODAY)
        self.assertEqual(resolved, ["CVE-1|p"])
        self.assertEqual(state["resolved"]["CVE-1|p"], "2026-10-22")

    def test_flap_within_14_days_is_not_new(self):
        previous = {"findings": {}, "resolved": {"CVE-1|p": "2026-10-15"}}
        current = cve_scan.merge([self.row()], kev=set())
        _, new, _, _ = cve_scan.diff(previous, current, failed=set(), today=TODAY)
        self.assertEqual(new, [])

    def test_reappearing_after_14_days_is_new(self):
        previous = {"findings": {}, "resolved": {"CVE-1|p": "2026-10-01"}}
        current = cve_scan.merge([self.row()], kev=set())
        _, new, _, _ = cve_scan.diff(previous, current, failed=set(), today=TODAY)
        self.assertEqual(new, ["CVE-1|p"])


class RenderTests(unittest.TestCase):
    STATE = {"version": 1, "last_success": "2026-10-22", "last_failure": None, "resolved": {},
        "databases": {"grype": "2026-10-22"}, "notes": ["KEV feed unavailable"],
        "unscanned": {"khazad-dum": "https://ci/run/1"},
        "findings": {
            "CVE-1|openssl": {"targets": ["lorien"], "cvss": 9.8, "kev": True, "version": "1", "fix": "2",
                              "first_seen": "2026-10-22", "last_seen": "2026-10-22"},
            "CVE-2|zlib": {"targets": ["lorien"], "cvss": 5.0, "kev": False, "version": "1", "fix": None,
                           "first_seen": "2026-10-22", "last_seen": "2026-10-22"}}}

    def test_state_round_trips_through_body(self):
        body = cve_scan.render_issue(self.STATE)
        self.assertEqual(cve_scan.state_from_body(body), self.STATE)

    def test_body_lists_high_and_counts_rest(self):
        body = cve_scan.render_issue(self.STATE)
        self.assertIn("CVE-1", body)
        self.assertIn("**KEV**", body)
        self.assertNotIn("| CVE-2", body)
        self.assertIn("Medium: 1", body)
        self.assertIn("khazad-dum", body)
        self.assertIn("KEV feed unavailable", body)

    def test_state_with_comment_terminators_round_trips(self):
        state = {**self.STATE, "notes": ["cve-state -->"], "findings": {"CVE-1|p": {
            **self.STATE["findings"]["CVE-1|openssl"], "version": "1-->2"}}}
        body = cve_scan.render_issue(state)
        self.assertEqual(body[body.index(cve_scan.STATE_START):].count("-->"), 1)
        self.assertEqual(cve_scan.state_from_body(body), state)

    def test_pipes_are_escaped_in_rows(self):
        state = {"findings": {"CVE-1|a|b": {**self.STATE["findings"]["CVE-1|openssl"],
            "version": "1|2", "fix": "3|4"}}}
        row = cve_scan.render_issue(state).split("\n| [CVE-1")[1].split("\n")[0]
        self.assertIn(r"a\|b 1\|2 | 3\|4", row)

    def test_escalated_listed_in_comment(self):
        comment = cve_scan.render_comment(self.STATE, [], [], escalated=["CVE-1|openssl"])
        self.assertIn("### Now known-exploited", comment)
        self.assertIn("CVE-1", comment)

    def test_missing_state_is_empty(self):
        self.assertEqual(cve_scan.state_from_body("hand-written issue"), {"findings": {}})

    def test_comment_and_ping_message(self):
        comment = cve_scan.render_comment(self.STATE, ["CVE-1|openssl"], ["CVE-9|old"])
        self.assertIn("New", comment)
        self.assertIn("CVE-1", comment)
        self.assertIn("Resolved", comment)
        self.assertIn(cve_scan.PING_PREFIX + " CVE-1 -->", cve_scan.render_comment(self.STATE, ["CVE-1|openssl"], [], ping=["CVE-1|openssl"]))


ROW = {"cve": "CVE-1", "package": "openssl", "version": "3", "cvss": 5.0, "target": "lorien", "fix": None, "classify": "x"}


class CommentTests(unittest.TestCase):
    @staticmethod
    def item(cvss, kev=False):
        return {"targets": ["lorien"], "cvss": cvss, "kev": kev, "version": "1", "fix": None,
            "first_seen": "2026-10-22", "last_seen": "2026-10-22"}

    def state(self):
        return {"findings": {"CVE-1|a": self.item(7.5), "CVE-2|b": self.item(9.8), "CVE-2|c": self.item(9.8),
            "CVE-3|d": self.item(9.8, kev=True), "CVE-4|e": self.item(3.0), "CVE-5|f": self.item(5.0)}}

    def test_ping_line_lists_cve_ids_by_severity(self):
        state = self.state()
        comment = cve_scan.render_comment(state, sorted(state["findings"]), [],
            ping=["CVE-2|b", "CVE-2|c", "CVE-3|d", "CVE-1|a"])
        self.assertEqual(comment.splitlines()[0], "<!-- cve-ping: CVE-3,CVE-2,CVE-1 -->")

    def test_no_ping_line_without_ping(self):
        state = self.state()
        self.assertNotIn(cve_scan.PING_PREFIX, cve_scan.render_comment(state, ["CVE-2|b"], []))

    def test_low_severity_new_findings_are_counted_not_listed(self):
        state = self.state()
        comment = cve_scan.render_comment(state, sorted(state["findings"]), [])
        self.assertIn("CVE-1", comment)
        self.assertNotIn("CVE-4", comment)
        self.assertNotIn("CVE-5", comment)
        self.assertIn("Plus 2 lower-severity new findings; see the issue's counts.", comment)
        self.assertLess(comment.index("CVE-3"), comment.index("CVE-1"))

    def test_resolved_list_is_capped(self):
        resolved = [f"CVE-{i}|p" for i in range(60)]
        comment = cve_scan.render_comment({"findings": {}}, [], resolved)
        self.assertIn("CVE-49 in p", comment)
        self.assertNotIn("CVE-50 in p", comment)
        self.assertIn("and 10 more", comment)


class ScanTests(unittest.TestCase):
    """scan() orchestration with every side effect patched out."""

    def run_scan(self, closure, kev=frozenset(), build=lambda host, timeout: "/nix/store/x", clock=None):
        patches = [mock.patch.object(cve_scan, "build_host", side_effect=build),
            mock.patch.object(cve_scan, "scan_closure", side_effect=closure),
            mock.patch.object(cve_scan, "pinned_images", return_value=[]),
            mock.patch.object(cve_scan, "scan_image"),
            mock.patch.object(cve_scan, "fetch_kev", side_effect=kev if isinstance(kev, Exception) else None,
                return_value=kev),
            mock.patch.object(cve_scan, "merge", wraps=cve_scan.merge)]
        if clock:
            patches.append(mock.patch.object(cve_scan.time, "monotonic", side_effect=clock))
        with tempfile.TemporaryDirectory() as report, contextlib.ExitStack() as stack, \
                contextlib.redirect_stderr(io.StringIO()):
            mocks = [stack.enter_context(p) for p in patches]
            result = cve_scan.scan(datetime.date(2026, 10, 22), report)
        return result, mocks

    def test_degraded_host_is_failed_but_keeps_rows(self):
        def closure(path, target, work, timeout):
            return [{**ROW, "target": target}], (["vulnix"] if target == "lorien" else [])
        (current, failed, unscanned, notes), _ = self.run_scan(closure)
        self.assertIn("lorien", failed)
        self.assertNotIn("osgiliath", failed)
        self.assertEqual(unscanned, {})
        self.assertIn("lorien", current["CVE-1|openssl"]["targets"])
        self.assertTrue(any("vulnix" in n for n in notes))

    def test_build_failure_is_failed_and_unscanned(self):
        def build(host, timeout):
            if host == "lorien":
                raise RuntimeError("build broke")
            return "/nix/store/x"
        (current, failed, unscanned, _), _ = self.run_scan(
            lambda path, target, work, timeout: ([{**ROW, "target": target}], []), build=build)
        self.assertIn("lorien", failed)
        self.assertIn("lorien", unscanned)
        self.assertNotIn("lorien", current["CVE-1|openssl"]["targets"])

    def test_kev_failure_merges_with_none_and_notes_it(self):
        (_, _, _, notes), mocks = self.run_scan(lambda path, target, work, timeout: ([ROW], []), kev=OSError("down"))
        merge = mocks[5]
        self.assertIsNone(merge.call_args.args[1] if len(merge.call_args.args) > 1 else merge.call_args.kwargs["kev"])
        self.assertTrue(any("KEV" in n for n in notes))

    def test_target_after_deadline_is_not_started(self):
        ticks = iter([0, 0, 0, 0])  # deadline and the first host in time, then the clock jumps past it
        clock = lambda: next(ticks, 10 ** 9)
        (_, failed, unscanned, _), mocks = self.run_scan(
            lambda path, target, work, timeout: ([{**ROW, "target": target}], []), clock=clock)
        self.assertEqual(mocks[0].call_count, 1)
        self.assertEqual(set(unscanned), {"osgiliath", "khazad-dum"})
        self.assertTrue(set(unscanned) <= failed)

    def test_timeouts_are_capped_by_remaining_time(self):
        seen = []
        def build(host, timeout):
            seen.append(timeout)
            return "/nix/store/x"
        self.run_scan(lambda path, target, work, timeout: ([], []), build=build, clock=lambda: 0)
        self.assertEqual(seen[0], 120 * 60)


class RunTests(unittest.TestCase):
    def test_timeout_kills_and_raises(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            cve_scan._run(["sleep", "30"], timeout=0.2)

    def test_secrets_are_not_passed_to_children(self):
        with mock.patch.dict(os.environ, {"FORGEJO_TOKEN": "t", "CI_WEBHOOK_SECRET": "s", "KEEP": "1"}):
            code, out, _ = cve_scan._run(["sh", "-c", "echo ${FORGEJO_TOKEN-u}${CI_WEBHOOK_SECRET-u}${KEEP-u}"], timeout=10)
        self.assertEqual((code, out.strip()), (0, "uu1"))


class KevTests(unittest.TestCase):
    def feed(self, count):
        data = json.dumps({"vulnerabilities": [{"cveID": f"CVE-{i}"} for i in range(count)]}).encode()
        return mock.MagicMock(**{"__enter__.return_value": io.BytesIO(data)})

    def test_short_feed_is_unavailable(self):
        with mock.patch.object(cve_scan.urllib.request, "urlopen", return_value=self.feed(5)):
            with self.assertRaises(ValueError):
                cve_scan.fetch_kev()

    def test_full_feed_is_returned(self):
        with mock.patch.object(cve_scan.urllib.request, "urlopen", return_value=self.feed(1000)):
            self.assertEqual(len(cve_scan.fetch_kev()), 1000)


def issue(number, state="open", title=cve_scan.ISSUE_TITLE):
    return {"number": number, "title": title, "state": state, "body": ""}


class FindIssueTests(unittest.TestCase):
    def api(self, pages):
        api = mock.MagicMock()
        api.request.return_value = {"login": "bot"}
        listed = []
        def repo(path, **kwargs):
            if path.startswith("issues?"):
                listed.append(path)
                return pages[len(listed) - 1]
            return {**kwargs.get("data", {}), "number": 99, "title": cve_scan.ISSUE_TITLE}
        api.repo.side_effect = repo
        api.listed = listed
        return api

    def test_query_is_by_author_and_paginated(self):
        api = self.api([[issue(i, title="other") for i in range(50)], [issue(7)]])
        self.assertEqual(cve_scan.find_issue(api)["number"], 7)
        api.request.assert_called_once_with("user")
        self.assertEqual(len(api.listed), 2)
        self.assertIn("state=all", api.listed[0])
        self.assertIn("created_by=bot", api.listed[0])
        self.assertIn("page=2", api.listed[1])
        self.assertNotIn("q=", api.listed[0])

    def test_two_matches_raise(self):
        with self.assertRaises(RuntimeError):
            cve_scan.find_issue(self.api([[issue(1), issue(2, "closed")]]))

    def test_closed_issue_is_reopened(self):
        api = self.api([[issue(3, "closed")]])
        cve_scan.find_issue(api)
        api.repo.assert_any_call("issues/3", data={"state": "open"}, method="PATCH")

    def test_none_creates(self):
        api = self.api([[issue(4, title="other")]])
        self.assertEqual(cve_scan.find_issue(api)["number"], 99)
        self.assertEqual(api.repo.call_args.args[0], "issues")


class UntrustedTests(unittest.TestCase):
    def test_package_name_cannot_forge_state(self):
        evil = '<!-- cve-state {"x":1} cve-state -->'
        state = {"version": 1, "last_success": "2026-10-22", "findings": {f"CVE-1|{evil}": {
            "targets": ["lorien"], "cvss": 9.8, "kev": False, "version": "1", "fix": None,
            "first_seen": "2026-10-22", "last_seen": "2026-10-22"}}}
        body = cve_scan.render_issue(state)
        self.assertEqual(cve_scan.state_from_body(body), state)


class MainTests(unittest.TestCase):
    STATE_BODY = cve_scan.render_issue({"version": 1, "last_success": "2026-10-01", "findings": {}})
    CRITICAL = cve_scan.merge([{**ROW, "cvss": 9.8}], kev=set())

    def run_main(self, current, failed, unscanned=None, webhook_error=None):
        calls = []
        api = mock.MagicMock()
        api.comment.side_effect = lambda n, body: calls.append("comment") or {"id": 5}
        api.repo.side_effect = lambda path, **kw: calls.append(("repo", path, kw.get("method"), kw.get("data")))
        def hook(payload):
            calls.append("webhook")
            if webhook_error:
                raise webhook_error
        with mock.patch.object(cve_scan, "API", return_value=api), \
                mock.patch.object(cve_scan, "find_issue", return_value={"number": 1, "body": self.STATE_BODY}), \
                mock.patch.object(cve_scan, "scan", return_value=(current, failed, unscanned or {}, [])), \
                mock.patch.object(cve_scan, "send_webhook", side_effect=hook):
            try:
                code = cve_scan.main([])
            except Exception as exc:
                code = exc
        return code, calls

    def test_comment_then_webhook_then_patch(self):
        code, calls = self.run_main(self.CRITICAL, set())
        self.assertEqual(code, 0)
        self.assertEqual(calls[:2], ["comment", "webhook"])
        self.assertEqual(calls[2][:3], ("repo", "issues/1", "PATCH"))

    def test_webhook_failure_does_not_save_state(self):
        code, calls = self.run_main(self.CRITICAL, set(), webhook_error=OSError("relay down"))
        self.assertIsInstance(code, OSError)
        self.assertNotIn("PATCH", [c[2] for c in calls if isinstance(c, tuple)])

    def test_nothing_scanned_keeps_last_success_and_fails(self):
        everything = set(cve_scan.HOSTS)
        code, calls = self.run_main({}, everything, {h: "u" for h in everything})
        self.assertEqual(code, 1)
        patch = [c for c in calls if isinstance(c, tuple)][-1]
        self.assertEqual(patch[2], "PATCH")
        self.assertEqual(cve_scan.state_from_body(patch[3]["body"])["last_success"], "2026-10-01")

    def test_one_clean_host_counts_as_success(self):
        code, calls = self.run_main({}, {"lorien", "osgiliath"})
        self.assertEqual(code, 0)
        state = cve_scan.state_from_body([c for c in calls if isinstance(c, tuple)][-1][3]["body"])
        self.assertEqual(state["last_success"], datetime.datetime.now(datetime.timezone.utc).date().isoformat())

    def test_record_failure_only_writes_last_failure(self):
        api = mock.MagicMock()
        with mock.patch.object(cve_scan, "API", return_value=api), \
                mock.patch.object(cve_scan, "find_issue", return_value={"number": 1, "body": self.STATE_BODY}), \
                mock.patch.object(cve_scan, "send_webhook") as hook:
            self.assertEqual(cve_scan.main(["--record-failure"]), 0)
        hook.assert_not_called()
        state = cve_scan.state_from_body(api.repo.call_args.kwargs["data"]["body"])
        self.assertIn(datetime.datetime.now(datetime.timezone.utc).date().isoformat(), state["last_failure"])



if __name__ == "__main__":
    unittest.main()
