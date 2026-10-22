#!/usr/bin/env python3
"""Daily CVE scan of host closures and pinned images; see
docs/plans/2026-10-22-cve-scanning-design.md. Pure helpers come first so the
tests need no scanners, network or Forgejo."""
import csv
import datetime
import io
import json
import re
import tomllib

# Repology says the local version is outside the CVE's range. Everything else,
# including err_invalid_version, stays visible: an unknown answer is not "safe".
NOT_VULNERABLE = {"err_not_vulnerable_based_on_repology"}
SCANNER_WARNING = re.compile(r"scan_(vulnix|grype|osv)\(\)")
CRITICAL = 9.0
HIGH = 7.0
FLAP_DAYS = 14
ISSUE_TITLE = "CVE report"
STATE_START, STATE_END = "<!-- cve-state", "cve-state -->"
PING_MARKER = "<!-- cve-ping -->"


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


def merge(rows, kev):
    merged = {}
    for row in rows:
        key = f"{row['cve']}|{row['package']}"
        item = merged.setdefault(key, {"targets": [], "cvss": row["cvss"], "kev": row["cve"] in kev,
            "version": row["version"], "fix": row["fix"]})
        if row["target"] not in item["targets"]:
            item["targets"].append(row["target"])
        if row["cvss"] is not None and (item["cvss"] is None or row["cvss"] > item["cvss"]):
            item["cvss"] = row["cvss"]
    for item in merged.values():
        item["targets"].sort()
    return merged


def diff(previous, current, scanned, today):
    """Return (state, new keys, resolved keys). A finding is resolved only when
    every target it was seen on was scanned this run and none reported it."""
    iso = today.isoformat()
    old = previous.get("findings", {})
    resolved_at = dict(previous.get("resolved", {}))
    findings, new, resolved = {}, [], []
    for key, item in current.items():
        was = old.get(key)
        if not was:
            gone = resolved_at.pop(key, None)
            if not gone or (today - datetime.date.fromisoformat(gone)).days > FLAP_DAYS:
                new.append(key)
        findings[key] = {**item, "first_seen": was["first_seen"] if was else iso, "last_seen": iso}
    for key, was in old.items():
        if key in findings:
            continue
        if set(was["targets"]) - scanned:
            findings[key] = was  # some target was not scanned: carry over unchanged
        else:
            resolved.append(key)
            resolved_at[key] = iso
    cutoff = today - datetime.timedelta(days=FLAP_DAYS)
    resolved_at = {k: d for k, d in resolved_at.items() if datetime.date.fromisoformat(d) >= cutoff}
    state = {**previous, "version": 1, "findings": findings, "resolved": resolved_at}
    return state, sorted(new), sorted(resolved)


def to_ping(state, new):
    return [k for k in new if state["findings"][k]["kev"] or (state["findings"][k]["cvss"] or 0) >= CRITICAL]


def state_from_body(body):
    start = body.find(STATE_START)
    end = body.find(STATE_END, start)
    if start < 0 or end < 0:
        return {"findings": {}}
    return json.loads(body[start + len(STATE_START):end])


def _bucket(cvss):
    if cvss is None:
        return "Unscored"
    return "Critical" if cvss >= CRITICAL else "High" if cvss >= HIGH else "Medium" if cvss >= 4 else "Low"


def _line(key, item):
    cve, package = key.split("|", 1)
    kev = " **KEV**" if item["kev"] else ""
    fix = item["fix"] or "–"
    return (f"| [{cve}](https://nvd.nist.gov/vuln/detail/{cve}){kev} | {item['cvss'] or '?'} | {package} "
            f"{item['version']} | {fix} | {', '.join(item['targets'])} | {item['first_seen']} |")


def render_issue(state):
    findings = state["findings"]
    shown = sorted((k for k, v in findings.items() if v["kev"] or (v["cvss"] or 0) >= HIGH),
        key=lambda k: (-(findings[k]["cvss"] or 0), k))
    counts = {}
    for key, item in findings.items():
        if key not in shown:
            counts[_bucket(item["cvss"])] = counts.get(_bucket(item["cvss"]), 0) + 1
    lines = [f"Last successful scan: **{state.get('last_success') or 'never'}**"
             f" · last failure: {state.get('last_failure') or 'none'}", ""]
    for name, url in sorted(state.get("unscanned", {}).items()):
        lines.append(f"- :warning: `{name}` not scanned this run ([log]({url}))")
    for note in state.get("notes", []):
        lines.append(f"- :warning: {note}")
    if state.get("databases"):
        lines.append("- Databases: " + ", ".join(f"{k} {v}" for k, v in sorted(state["databases"].items())))
    lines += ["", "| CVE | CVSS | Package | Fixed in | Targets | First seen |", "|---|---|---|---|---|---|"]
    lines += [_line(k, findings[k]) for k in shown] or ["| none | | | | | |"]
    lines += ["", "Not listed: " + (", ".join(f"{k}: {v}" for k, v in sorted(counts.items())) or "nothing"),
              "", "Suppress a finding with a reasoned entry in `security/cve-ignore.toml`.", "",
              STATE_START + json.dumps(state, sort_keys=True) + STATE_END]
    return "\n".join(lines)


def render_comment(state, new, resolved, ping=()):
    lines = [PING_MARKER] if ping else []
    if new:
        lines += ["### New", "| CVE | CVSS | Package | Fixed in | Targets | First seen |", "|---|---|---|---|---|---|"]
        lines += [_line(k, state["findings"][k]) for k in new]
    if resolved:
        lines += ["", "### Resolved", ", ".join(k.replace("|", " in ") for k in resolved)]
    return "\n".join(lines)
