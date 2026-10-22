import datetime
from pathlib import Path
import sys
import unittest
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


class DiffTests(unittest.TestCase):
    def row(self, cve="CVE-1", package="p", target="lorien", cvss=9.5):
        return {"cve": cve, "package": package, "version": "1", "cvss": cvss, "target": target, "fix": None, "classify": "x"}

    def test_merge_groups_targets(self):
        merged = cve_scan.merge([self.row(target="lorien"), self.row(target="osgiliath")], kev=set())
        self.assertEqual(merged["CVE-1|p"]["targets"], ["lorien", "osgiliath"])

    def test_new_finding_pings_if_critical(self):
        current = cve_scan.merge([self.row()], kev=set())
        state, new, resolved = cve_scan.diff({"findings": {}}, current, scanned={"lorien"}, today=TODAY)
        self.assertEqual(new, ["CVE-1|p"])
        self.assertEqual(cve_scan.to_ping(state, new), ["CVE-1|p"])

    def test_low_score_kev_pings_and_low_score_alone_does_not(self):
        current = cve_scan.merge([self.row(cvss=5.0), self.row(cve="CVE-2", cvss=5.0)], kev={"CVE-2"})
        state, new, _ = cve_scan.diff({"findings": {}}, current, scanned={"lorien"}, today=TODAY)
        self.assertEqual(cve_scan.to_ping(state, new), ["CVE-2|p"])

    def test_unscanned_target_keeps_findings(self):
        previous = {"findings": {"CVE-1|p": {"first_seen": "2026-10-01", "last_seen": "2026-10-21",
            "targets": ["khazad-dum"], "cvss": 9.5, "kev": False, "version": "1", "fix": None}}}
        state, new, resolved = cve_scan.diff(previous, {}, scanned={"lorien"}, today=TODAY)
        self.assertEqual(resolved, [])
        self.assertIn("CVE-1|p", state["findings"])

    def test_scanned_target_resolves_and_is_remembered(self):
        previous = {"findings": {"CVE-1|p": {"first_seen": "2026-10-01", "last_seen": "2026-10-21",
            "targets": ["lorien"], "cvss": 9.5, "kev": False, "version": "1", "fix": None}}}
        state, _, resolved = cve_scan.diff(previous, {}, scanned={"lorien"}, today=TODAY)
        self.assertEqual(resolved, ["CVE-1|p"])
        self.assertEqual(state["resolved"]["CVE-1|p"], "2026-10-22")

    def test_flap_within_14_days_is_not_new(self):
        previous = {"findings": {}, "resolved": {"CVE-1|p": "2026-10-15"}}
        current = cve_scan.merge([self.row()], kev=set())
        _, new, _ = cve_scan.diff(previous, current, scanned={"lorien"}, today=TODAY)
        self.assertEqual(new, [])

    def test_reappearing_after_14_days_is_new(self):
        previous = {"findings": {}, "resolved": {"CVE-1|p": "2026-10-01"}}
        current = cve_scan.merge([self.row()], kev=set())
        _, new, _ = cve_scan.diff(previous, current, scanned={"lorien"}, today=TODAY)
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

    def test_missing_state_is_empty(self):
        self.assertEqual(cve_scan.state_from_body("hand-written issue"), {"findings": {}})

    def test_comment_and_ping_message(self):
        comment = cve_scan.render_comment(self.STATE, ["CVE-1|openssl"], ["CVE-9|old"])
        self.assertIn("New", comment)
        self.assertIn("CVE-1", comment)
        self.assertIn("Resolved", comment)
        self.assertIn(cve_scan.PING_MARKER, cve_scan.render_comment(self.STATE, ["CVE-1|openssl"], [], ping=["CVE-1|openssl"]))


if __name__ == "__main__":
    unittest.main()
