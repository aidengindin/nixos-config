#!/usr/bin/env python3
"""Daily CVE scan of host closures and pinned images; see
docs/plans/2026-10-22-cve-scanning-design.md. Pure helpers come first so the
tests need no scanners, network or Forgejo."""
import csv
import io
import re
import tomllib

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


def _max_cvss(entries):
    scores = [e.get("metrics", {}).get("baseScore") for e in entries or []]
    scores = [s for s in scores if isinstance(s, (int, float))]
    return max(scores) if scores else None


def parse_grype(report, target):
    rows = []
    for match in report.get("matches", []):
        vuln, artifact = match["vulnerability"], match["artifact"]
        cve, cvss = vuln["id"], _max_cvss(vuln.get("cvss"))
        if not cve.startswith("CVE-"):
            related = next((r for r in match.get("relatedVulnerabilities") or [] if r["id"].startswith("CVE-")), None)
            if related:
                cve, cvss = related["id"], cvss if cvss is not None else _max_cvss(related.get("cvss"))
        fixes = (vuln.get("fix") or {}).get("versions") or []
        rows.append({"cve": cve, "package": artifact["name"], "version": artifact["version"], "cvss": cvss,
            "target": target, "fix": fixes[0] if fixes else None, "classify": "grype"})
    return rows


def load_ignores(text, today):
    rules = []
    for rule in tomllib.loads(text).get("ignore", []):
        if not rule.get("cve") or not str(rule.get("reason", "")).strip():
            raise ValueError(f"cve-ignore entry needs cve and reason: {rule}")
        if rule.get("expires") and rule["expires"] < today:
            continue
        rules.append(rule)
    return rules


def ignored(row, rules):
    return any(r["cve"] == row["cve"] and r.get("package") in (None, row["package"]) for r in rules)
