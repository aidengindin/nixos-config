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


if __name__ == "__main__":
    unittest.main()
