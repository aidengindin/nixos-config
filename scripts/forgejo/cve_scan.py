#!/usr/bin/env python3
"""Daily CVE scan of host closures and pinned images; see
docs/plans/2026-10-22-cve-scanning-design.md. Pure helpers come first so the
tests need no scanners, network or Forgejo."""
import argparse
import csv
import datetime
import hashlib
import hmac
import io
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time
import tomllib
import urllib.parse
import urllib.request
from common import API, HOSTS, REPOSITORY
import images

# Repology says the local version is outside the CVE's range. Everything else,
# including err_invalid_version, stays visible: an unknown answer is not "safe".
NOT_VULNERABLE = {"err_not_vulnerable_based_on_repology"}
SCANNER_WARNING = re.compile(r"scan_(vulnix|grype|osv)\(\)")
CRITICAL = 9.0
HIGH = 7.0
FLAP_DAYS = 14
IGNORE_KEYS = {"cve", "package", "reason", "expires"}
ISSUE_TITLE = "CVE report"
STATE_START, STATE_END = "<!-- cve-state", "cve-state -->"
PING_PREFIX = "<!-- cve-ping:"
MAX_RESOLVED = 50
ROOT = Path(__file__).resolve().parents[2]
KEV_URL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
SECRET_ENV = ("FORGEJO_TOKEN", "CI_WEBHOOK_SECRET")
RUN_TIMEOUT = 540 * 60
BUILD_TIMEOUT = 120 * 60
VULNXSCAN_TIMEOUT = 60 * 60
GRYPE_TIMEOUT = 15 * 60
MIN_KEV = 1000


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
        if set(rule) - IGNORE_KEYS:
            raise ValueError(f"cve-ignore entry has unknown keys {sorted(set(rule) - IGNORE_KEYS)}: {rule}")
        # A datetime is a date subclass and would not compare with today.
        if "expires" in rule and type(rule["expires"]) is not datetime.date:
            raise ValueError(f"cve-ignore entry {rule['cve']}: expires must be a TOML date: {rule}")
        if rule.get("expires") and rule["expires"] < today:
            continue
        rules.append(rule)
    return rules


def ignored(row, rules):
    return any(r["cve"] == row["cve"] and r.get("package") in (None, row["package"]) for r in rules)


def merge(rows, kev):
    """kev is the set of known-exploited CVE ids, or None when the feed was
    unavailable (the flag is then unknown, resolved in diff)."""
    merged = {}
    for row in rows:
        key = f"{row['cve']}|{row['package']}"
        item = merged.setdefault(key, {"targets": [], "cvss": row["cvss"],
            "kev": None if kev is None else row["cve"] in kev,
            "version": row["version"], "fix": row["fix"]})
        if row["target"] not in item["targets"]:
            item["targets"].append(row["target"])
        if row["cvss"] is not None and (item["cvss"] is None or row["cvss"] > item["cvss"]):
            item["cvss"] = row["cvss"]
    for item in merged.values():
        item["targets"].sort()
    return merged


def diff(previous, current, failed, today):
    """Return (state, new keys, resolved keys, KEV-escalated keys). `failed` is
    the set of known targets not cleanly scanned this run. A finding is carried
    over while any of its targets failed, and a failed target is never dropped
    from it; a target that no longer exists is not failed, so its findings
    resolve."""
    iso = today.isoformat()
    old = previous.get("findings", {})
    resolved_at = dict(previous.get("resolved", {}))
    findings, new, resolved, escalated = {}, [], [], []
    for key, item in current.items():
        was = old.get(key)
        targets = item["targets"]
        if item["kev"] is None:  # feed unavailable: keep what we knew, never escalate
            item = {**item, "kev": bool(was and was["kev"])}
        if not was:
            gone = resolved_at.pop(key, None)
            if not gone or (today - datetime.date.fromisoformat(gone)).days > FLAP_DAYS:
                new.append(key)
        else:
            targets = sorted(set(targets) | (set(was["targets"]) & failed))
            if item["kev"] and not was["kev"]:
                escalated.append(key)
        findings[key] = {**item, "targets": targets,
            "first_seen": was["first_seen"] if was else iso, "last_seen": iso}
    for key, was in old.items():
        if key in findings:
            continue
        if set(was["targets"]) & failed:
            findings[key] = was  # a target was not cleanly scanned: carry over unchanged
        else:
            resolved.append(key)
            resolved_at[key] = iso
    cutoff = today - datetime.timedelta(days=FLAP_DAYS)
    resolved_at = {k: d for k, d in resolved_at.items() if datetime.date.fromisoformat(d) >= cutoff}
    state = {**previous, "version": 1, "findings": findings, "resolved": resolved_at}
    return state, sorted(new), sorted(resolved), sorted(escalated)


def to_ping(state, new, escalated=()):
    critical = [k for k in new if state["findings"][k]["kev"] or (state["findings"][k]["cvss"] or 0) >= CRITICAL]
    return sorted(set(critical) | set(escalated))


def state_from_body(body):
    start = body.rfind(STATE_START)  # the block is last; earlier text may quote the marker
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
    cell = lambda text: str(text).replace("|", "\\|").replace("<", "&lt;").replace(">", "&gt;")
    return (f"| [{cve}](https://nvd.nist.gov/vuln/detail/{cve}){kev} | {item['cvss'] or '?'} | {cell(package)} "
            f"{cell(item['version'])} | {cell(fix)} | {', '.join(item['targets'])} | {item['first_seen']} |")


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
              # Escape < and > so no value can contain a comment terminator.
              STATE_START + json.dumps(state, sort_keys=True).replace("<", "\\u003c").replace(">", "\\u003e")
              + STATE_END]
    return "\n".join(lines)


def render_comment(state, new, resolved, ping=(), escalated=()):
    findings = state["findings"]
    rank = lambda k: (-(findings[k]["cvss"] or 0), not findings[k]["kev"], k)
    lines = []
    if ping:
        ids = list(dict.fromkeys(k.split("|", 1)[0] for k in sorted(ping, key=rank)))
        lines.append(f"{PING_PREFIX} {','.join(ids)} -->")
    header = ["| CVE | CVSS | Package | Fixed in | Targets | First seen |", "|---|---|---|---|---|---|"]
    if new:
        shown = sorted((k for k in new if findings[k]["kev"] or (findings[k]["cvss"] or 0) >= HIGH), key=rank)
        lines.append("### New")
        if shown:
            lines += [*header, *(_line(k, findings[k]) for k in shown)]
        if len(new) > len(shown):
            lines += ["", f"Plus {len(new) - len(shown)} lower-severity new findings; see the issue's counts."]
    if escalated:
        lines += ["", "### Now known-exploited", *header]
        lines += [_line(k, state["findings"][k]) for k in escalated]
    if resolved:
        text = ", ".join(k.replace("|", " in ") for k in resolved[:MAX_RESOLVED])
        if len(resolved) > MAX_RESOLVED:
            text += f" and {len(resolved) - MAX_RESOLVED} more"
        lines += ["", "### Resolved", text]
    return "\n".join(lines)


def _run(cmd, timeout, **kwargs):
    """Run cmd in its own process group with the automation secrets removed from
    its environment. On timeout the whole group is killed. Returns
    (returncode, stdout, stderr)."""
    if timeout <= 0:
        raise subprocess.TimeoutExpired(cmd, timeout)
    env = {k: v for k, v in os.environ.items() if k not in SECRET_ENV}
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
        start_new_session=True, **kwargs)
    try:
        out, err = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise
    return proc.returncode, out, err


def build_host(host, timeout=BUILD_TIMEOUT):
    attr = f"{ROOT}#nixosConfigurations.{host}.config.system.build.toplevel"
    code, out, err = _run(["nix", "build", "--no-link", "--print-out-paths", attr], timeout)
    if code != 0:
        raise RuntimeError(f"nix build failed: {err[-2000:]}")
    return out.strip()


def scan_closure(path, target, work, timeout=VULNXSCAN_TIMEOUT):
    out = Path(work, target)
    out.mkdir(parents=True, exist_ok=True)
    code, stdout, stderr = _run(["vulnxscan", "--triage", "--verbose", "1", "--out", str(out / "vulns.csv"), path],
        timeout, cwd=out)
    if code != 0:
        raise RuntimeError(f"vulnxscan failed: {stderr[-2000:]}")
    degraded = degraded_scanners(stderr + stdout)
    if degraded:
        print(stderr, file=sys.stderr)
    return parse_triage((out / "vulns.triage.csv").read_text(), target), degraded


def pinned_images():
    found = set()
    for path in sorted((ROOT / "services").glob("*.nix")):
        for repo, tag, digest in images.PINNED.findall(path.read_text()):
            found.add((f"{repo}:{tag}", f"{repo}@sha256:{digest}"))
    return sorted(found)


def scan_image(name, ref, timeout=GRYPE_TIMEOUT):
    code, out, err = _run(["grype", f"registry:{ref}", "-o", "json", "--quiet"], timeout)
    if code != 0:
        raise RuntimeError(f"grype failed: {err[-2000:]}")
    return parse_grype(json.loads(out), name)


def fetch_kev():
    with urllib.request.urlopen(KEV_URL, timeout=60) as response:
        found = {v["cveID"] for v in json.load(response)["vulnerabilities"]}
    if len(found) < MIN_KEV:  # a truncated or empty feed must not read as "nothing is exploited"
        raise ValueError(f"KEV feed has only {len(found)} entries")
    return found


def find_issue(api):
    me = api.request("user")["login"]
    mine, page = [], 1
    while True:
        items = api.repo(f"issues?state=all&type=issues&created_by={urllib.parse.quote(me)}&limit=50&page={page}")
        mine += [i for i in items if i["title"] == ISSUE_TITLE]
        if len(items) < 50:
            break
        page += 1
    if len(mine) > 1:
        raise RuntimeError(f"{len(mine)} issues titled {ISSUE_TITLE!r} by {me}; close the duplicates")
    if mine:
        found = mine[0]
        if found["state"] == "closed":
            return api.repo(f"issues/{found['number']}", data={"state": "open"}, method="PATCH")
        return found
    return api.repo("issues", data={"title": ISSUE_TITLE, "body": render_issue({"findings": {}})})


def send_webhook(payload):
    body = json.dumps({"repository": REPOSITORY, **payload}).encode()
    signature = hmac.new(os.environ["CI_WEBHOOK_SECRET"].encode(), body, hashlib.sha256).hexdigest()
    request = urllib.request.Request(os.environ["FORGEJO_URL"].rstrip("/") + "/_automation/events", data=body,
        headers={"Content-Type": "application/json", "X-Forgejo-Signature": signature})
    with urllib.request.urlopen(request, timeout=30) as response:
        response.read()


def run_url():
    server, repo, run = (os.environ.get(k, "") for k in ("GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "GITHUB_RUN_ID"))
    return f"{server}/{repo}/actions/runs/{run}" if run else "(local run)"


def scan(today, report_dir):
    rows, unscanned, notes, failed = [], {}, [], set()
    ignores = load_ignores((ROOT / "security/cve-ignore.toml").read_text(), today)
    deadline = time.monotonic() + RUN_TIMEOUT
    left = lambda: deadline - time.monotonic()
    with tempfile.TemporaryDirectory() as work:
        for host in HOSTS:
            if left() <= 0:
                unscanned[host] = run_url()
                continue
            try:
                path = build_host(host, timeout=min(BUILD_TIMEOUT, left()))
                found, degraded = scan_closure(path, host, work, timeout=min(VULNXSCAN_TIMEOUT, left()))
                rows += found
                if degraded:
                    # Keep its rows, but a partial scan must not resolve anything.
                    notes.append(f"`{host}`: {', '.join(degraded)} failed; results are partial")
                    failed.add(host)
            except Exception as exc:  # one bad host must not hide the others
                print(f"{host}: {exc}", file=sys.stderr)
                unscanned[host] = run_url()
        for name, ref in pinned_images():
            if left() <= 0:
                unscanned[name] = run_url()
                continue
            try:
                rows += scan_image(name, ref, timeout=min(GRYPE_TIMEOUT, left()))
            except Exception as exc:
                print(f"{name}: {exc}", file=sys.stderr)
                unscanned[name] = run_url()
    try:
        kev = fetch_kev()
    except Exception as exc:
        print(f"KEV: {exc}", file=sys.stderr)
        kev = None  # unknown: diff keeps each finding's previous flag
        notes.append("CISA KEV feed unavailable; pings used CVSS only")
    rows = [r for r in rows if not ignored(r, ignores)]
    Path(report_dir).mkdir(parents=True, exist_ok=True)
    Path(report_dir, "findings.json").write_text(json.dumps(rows, indent=1))
    return merge(rows, kev), failed | set(unscanned), unscanned, notes


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--record-failure", action="store_true", help="called by the workflow's failure() step")
    parser.add_argument("--report-dir", default="cve-report")
    args = parser.parse_args(argv)
    today = datetime.datetime.now(datetime.timezone.utc).date()
    api = None if args.dry_run else API()
    issue = find_issue(api) if api else {"number": 0, "body": ""}
    previous = state_from_body(issue["body"] or "")

    if args.record_failure:
        state = {**previous, "last_failure": f"{today} ([log]({run_url()}))"}
        api.repo(f"issues/{issue['number']}", data={"body": render_issue(state)}, method="PATCH")
        return 0

    current, failed, unscanned, notes = scan(today, args.report_dir)
    state, new, resolved, escalated = diff(previous, current, failed, today)
    # Success needs at least one host: images alone say nothing about the closures.
    scanned_host = any(host not in failed for host in HOSTS)
    if scanned_host:
        state["last_success"] = today.isoformat()
    state.update(unscanned=unscanned, notes=notes)
    ping = to_ping(state, new, escalated)
    body, comment = render_issue(state), render_comment(state, new, resolved, ping=ping, escalated=escalated)
    code = 0 if scanned_host else 1
    if args.dry_run:
        print(body, "\n\n--- comment ---\n", comment or "(none)", "\n\n--- ping ---\n", ping or "(none)")
        return code
    # At-least-once: announce before saving state. If either step raises, the
    # state is not saved and the next run sees the findings as new again.
    if comment:
        posted = api.comment(issue["number"], comment)
        if ping:
            send_webhook({"kind": "cve", "issue": issue["number"], "comment": posted["id"]})
    api.repo(f"issues/{issue['number']}", data={"body": body}, method="PATCH")
    return code


if __name__ == "__main__":
    sys.exit(main())
