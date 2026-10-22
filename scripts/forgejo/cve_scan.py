#!/usr/bin/env python3
"""Daily CVE scan of host closures and pinned images; see
docs/plans/2026-10-22-cve-scanning-design.md. Pure helpers come first so the
tests need no scanners, network or Forgejo."""
import csv
import io
import re

# Repology says the local version is outside the CVE's range. Everything else,
# including err_invalid_version, stays visible: an unknown answer is not "safe".
NOT_VULNERABLE = {"err_not_vulnerable_based_on_repology"}
SCANNER_WARNING = re.compile(r"scan_(vulnix|grype|osv)\(\)")


def _score(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def parse_triage(text, target):
    rows = []
    for item in csv.DictReader(io.StringIO(text)):
        if item["classify"] in NOT_VULNERABLE:
            continue
        rows.append({"cve": item["vuln_id"], "package": item["package"], "version": item["version_local"],
            "cvss": _score(item["severity"]), "target": target, "fix": item["version_nixpkgs"] or None,
            "classify": item["classify"]})
    return rows


def degraded_scanners(log):
    """vulnxscan exits 0 when a sub-scanner fails; its log is the only signal."""
    return sorted(set(SCANNER_WARNING.findall(log)))
