"""Import a PSEG hourly usage export into Home Assistant long-term statistics.

Watches for a raw PSEG "Usage.csv" export, reshapes its hourly kWh/cost columns
into the cumulative-sum form Home Assistant's statistics tables expect, and
pushes the result over the websocket API. Home Assistant is the only source of
truth for how far the series already runs, so this keeps no local state: each
run reads the last imported hour back before deciding what to send.
"""

import csv
import glob
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from websockets.sync.client import connect

EXPECTED_HEADER = ["Start", "kWh", "$"]
# PSEG writes naive local timestamps on a 12-hour clock: "03/09/2026 1:00:00 PM".
ROW_FORMAT = "%m/%d/%Y %I:%M:%S %p"
# Predates any plausible meter reading, so this is "the beginning of time".
FAR_PAST = datetime(2000, 1, 1, tzinfo=timezone.utc)
CHUNK_SIZE = 1000
KWH_INDEX = 1
COST_INDEX = 2


def env(name, default=None, required=False):
    value = os.environ.get(name, default)
    if required and not value:
        sys.exit(f"{name} is not set")
    return value


def log(message):
    # stderr, so DRY_RUN can emit a clean CSV on stdout. systemd journals both.
    print(message, file=sys.stderr, flush=True)


def notify(summary, body, urgent=False):
    """Best-effort desktop notification; never fatal."""
    if os.environ.get("NOTIFY", "1") != "1":
        return
    try:
        subprocess.run(
            [
                "notify-send",
                "--app-name=PSEG import",
                f"--urgency={'critical' if urgent else 'normal'}",
                summary,
                body,
            ],
            check=False,
        )
    except FileNotFoundError:
        log("notify-send is not available; skipping desktop notification")


def read_header(path):
    try:
        with open(path, newline="") as handle:
            return next(csv.reader(handle), None)
    except (OSError, UnicodeDecodeError):
        return None


def find_candidate(watch_dir, pattern):
    """Oldest file matching the glob whose header marks it as a PSEG export."""
    matches = sorted(glob.glob(os.path.join(watch_dir, pattern)), key=os.path.getmtime)
    for path in matches:
        if read_header(path) == EXPECTED_HEADER:
            return path
        log(f"ignoring {path}: header is not a PSEG usage export")
    return None


def read_rows(path):
    """Parse the export into (naive local datetime, kWh, dollars) tuples."""
    rows = []
    with open(path, newline="") as handle:
        reader = csv.reader(handle)
        next(reader)
        for lineno, raw in enumerate(reader, start=2):
            if not raw or not raw[0].strip():
                continue
            if len(raw) < 3:
                sys.exit(f"{path}:{lineno}: expected 3 columns, got {len(raw)}")
            try:
                local = datetime.strptime(raw[0].strip(), ROW_FORMAT)
                kwh = float(raw[1].strip())
                cost = float(raw[2].strip().replace("$", "").replace(",", ""))
            except ValueError as error:
                sys.exit(f"{path}:{lineno}: {error}")
            rows.append((local, kwh, cost))
    if not rows:
        sys.exit(f"{path}: no data rows")
    # Stable sort, so the two halves of a repeated DST hour keep file order.
    rows.sort(key=lambda row: row[0])
    return rows


def localize(rows, tz):
    """Attach the local zone, resolving the repeated DST fall-back hour.

    A naive local timestamp is ambiguous exactly once a year. Rather than encode
    DST rules, assume the export is in chronological order: take fold=0, and if
    that does not advance past the previous row, it must be the second pass
    through the repeated hour, so take fold=1.
    """
    out = []
    previous = None
    for local, kwh, cost in rows:
        aware = local.replace(tzinfo=tz)
        if previous is not None and aware.astimezone(timezone.utc) <= previous:
            aware = local.replace(tzinfo=tz, fold=1)
        instant = aware.astimezone(timezone.utc)
        if previous is not None and instant <= previous:
            sys.exit(f"timestamps do not advance at {local}; is the export corrupt?")
        previous = instant
        out.append((aware, kwh, cost))
    return out


class HomeAssistant:
    def __init__(self, url, token):
        ws_url = url.rstrip("/").replace("https://", "wss://").replace("http://", "ws://")
        self.socket = connect(f"{ws_url}/api/websocket", max_size=None, open_timeout=20)
        self.next_id = 0
        greeting = json.loads(self.socket.recv(timeout=30))
        if greeting.get("type") != "auth_required":
            sys.exit(f"unexpected websocket greeting: {greeting.get('type')}")
        self.socket.send(json.dumps({"type": "auth", "access_token": token}))
        reply = json.loads(self.socket.recv(timeout=30))
        if reply.get("type") != "auth_ok":
            sys.exit(f"Home Assistant rejected the access token: {reply.get('message')}")

    def command(self, payload):
        self.next_id += 1
        message_id = self.next_id
        self.socket.send(json.dumps({**payload, "id": message_id}))
        while True:
            message = json.loads(self.socket.recv(timeout=120))
            if message.get("id") != message_id or message.get("type") != "result":
                continue
            if not message.get("success"):
                error = message.get("error") or {}
                raise RuntimeError(
                    f"{payload['type']} failed: {error.get('code')}: {error.get('message')}"
                )
            return message.get("result")

    def close(self):
        try:
            self.socket.close()
        except Exception:
            pass


def to_datetime(epoch_ms):
    return datetime.fromtimestamp(float(epoch_ms) / 1000, tz=timezone.utc)


def read_metadata(client, statistic_ids):
    result = client.command(
        {"type": "recorder/get_statistics_metadata", "statistic_ids": statistic_ids}
    )
    return {item["statistic_id"]: item for item in (result or [])}


def read_watermark(client, statistic_id):
    """Last imported hour and its cumulative sum, or (None, 0.0) if unknown.

    Asks for monthly buckets first to locate the tail of the series, then pulls
    hourly rows for that one month only. Avoids dragging thousands of hourly
    points across the wire just to read the final value.
    """
    monthly = client.command(
        {
            "type": "recorder/statistics_during_period",
            "start_time": FAR_PAST.isoformat(),
            "statistic_ids": [statistic_id],
            "period": "month",
            "types": ["sum"],
        }
    )
    months = (monthly or {}).get(statistic_id) or []
    if not months:
        return None, 0.0
    hourly = client.command(
        {
            "type": "recorder/statistics_during_period",
            "start_time": to_datetime(months[-1]["start"]).isoformat(),
            "statistic_ids": [statistic_id],
            "period": "hour",
            "types": ["sum"],
        }
    )
    hours = (hourly or {}).get(statistic_id) or []
    if not hours:
        return None, 0.0
    return to_datetime(hours[-1]["start"]), round(float(hours[-1]["sum"]), 3)


def build_series(rows, value_index, watermark_hour, watermark_sum):
    """Cumulative statistics rows for everything newer than the watermark."""
    stats = []
    running = watermark_sum
    # Compare as UTC instants, never as local datetimes: Python compares two
    # aware datetimes sharing a tzinfo by wall clock and ignores fold, so both
    # halves of the repeated DST hour would look equal and one would be dropped.
    cutoff = watermark_hour.astimezone(timezone.utc) if watermark_hour is not None else None
    if watermark_hour is None:
        # Prime the series with a zero an hour before the first reading, so the
        # first real hour reads as a delta rather than a step up from nothing.
        first = rows[0][0]
        prime = (first.astimezone(timezone.utc) - timedelta(hours=1)).astimezone(first.tzinfo)
        stats.append({"start": prime.isoformat(), "sum": 0.0, "state": 0.0})
    for row in rows:
        start = row[0]
        if cutoff is not None and start.astimezone(timezone.utc) <= cutoff:
            continue
        running = round(running + row[value_index], 3)
        stats.append({"start": start.isoformat(), "sum": running, "state": running})
    return stats


def import_statistics(client, metadata, stats):
    for index in range(0, len(stats), CHUNK_SIZE):
        chunk = stats[index:index + CHUNK_SIZE]
        client.command(
            {"type": "recorder/import_statistics", "metadata": metadata, "stats": chunk}
        )
        log(f"  {metadata['statistic_id']}: {index + len(chunk)}/{len(stats)} rows")


def print_dry_run(statistic_id, unit, stats, tz):
    for row in stats:
        start = datetime.fromisoformat(row["start"]).astimezone(tz)
        print(
            f"{statistic_id},{start.strftime('%Y-%m-%d %H:%M')},{unit},"
            f"{row['sum']:.3f},{row['state']:.3f}"
        )


def fail(path, summary, detail):
    """Rename the export out of the trigger's glob so a retry re-arms it."""
    log(detail)
    if path and os.path.exists(path):
        stamp = datetime.now().strftime("%Y%m%d%H%M%S")
        failed = os.path.join(os.path.dirname(path), f"pseg-failed-{stamp}.csv")
        os.replace(path, failed)
        detail = f"{detail}\nKept as {os.path.basename(failed)}"
    notify(summary, detail, urgent=True)
    sys.exit(1)


def plan_series(client, rows):
    """Metadata + statistics rows to send, one entry per statistic."""
    series = [
        {
            "statistic_id": env("ENERGY_STATISTIC_ID", "sensor:pseg_nj_imported_energy"),
            "default_name": env("ENERGY_NAME", "PSEG NJ Imported Energy"),
            "unit": "kWh",
            "index": KWH_INDEX,
        },
        {
            "statistic_id": env("COST_STATISTIC_ID", "sensor:pseg_nj_imported_cost"),
            "default_name": env("COST_NAME", "PSEG NJ Imported Cost"),
            "unit": "USD",
            "index": COST_INDEX,
        },
    ]
    existing = {} if client is None else read_metadata(client, [s["statistic_id"] for s in series])
    planned = []
    for spec in series:
        statistic_id = spec["statistic_id"]
        known = existing.get(statistic_id)
        hour, total = read_watermark(client, statistic_id) if known else (None, 0.0)
        log(f"{statistic_id}: last imported {hour} sum={total}")
        metadata = {
            "has_mean": False,
            "has_sum": True,
            # Keep whatever name the statistic already carries -- including a
            # null one, which is what the existing series has -- so re-importing
            # never relabels it. The default only names a brand-new statistic.
            "name": known["name"] if known else spec["default_name"],
            # Must equal the part before the colon or Home Assistant refuses it.
            "source": statistic_id.split(":", 1)[0],
            "statistic_id": statistic_id,
            "unit_of_measurement": spec["unit"],
        }
        planned.append((metadata, build_series(rows, spec["index"], hour, total), spec))
    return planned


def main():
    watch_dir = env("WATCH_DIR", required=True)
    pattern = env("FILE_GLOB", "Usage*.csv")
    tz = ZoneInfo(env("TIMEZONE", "America/New_York"))
    dry_run = os.environ.get("DRY_RUN", "0") == "1"

    path = find_candidate(watch_dir, pattern)
    if path is None:
        log(f"no PSEG export in {watch_dir} matching {pattern}")
        return 0
    log(f"processing {path}")

    rows = localize(read_rows(path), tz)
    log(f"read {len(rows)} hourly readings, {rows[0][0]} .. {rows[-1][0]}")

    # Offline mode: rebuild the whole series from zero without contacting Home
    # Assistant, so the transform can be diffed against a known-good export.
    if dry_run and os.environ.get("FORCE_FROM_ZERO", "0") == "1":
        print("statistic_id,start,unit,sum,state")
        for _, stats, spec in plan_series(None, rows):
            print_dry_run(spec["statistic_id"], spec["unit"], stats, tz)
        return 0

    client = None
    planned = None
    try:
        client = HomeAssistant(
            env("HA_URL", required=True),
            open(env("HA_TOKEN_FILE", required=True)).read().strip(),
        )
        planned = plan_series(client, rows)

        if not any(stats for _, stats, _ in planned):
            log("Home Assistant is already up to date")
            os.remove(path)
            notify("PSEG import", "Already up to date; nothing new to import")
            return 0

        if dry_run:
            print("statistic_id,start,unit,sum,state")
            for _, stats, spec in planned:
                print_dry_run(spec["statistic_id"], spec["unit"], stats, tz)
            return 0

        for metadata, stats, _ in planned:
            if stats:
                import_statistics(client, metadata, stats)
    except SystemExit:
        raise
    except Exception as error:
        fail(path, "PSEG import failed", str(error))
    finally:
        if client is not None:
            client.close()

    energy_stats = planned[0][1]
    cost_stats = planned[1][1]
    through = datetime.fromisoformat(energy_stats[-1]["start"]).astimezone(tz)
    summary = (
        f"Imported {len(energy_stats)} hours through {through.strftime('%Y-%m-%d %H:%M')}\n"
        f"+{energy_stats[-1]['sum'] - energy_stats[0]['sum']:.1f} kWh / "
        f"${cost_stats[-1]['sum'] - cost_stats[0]['sum']:.2f}"
    )
    log(summary.replace("\n", ", "))
    os.remove(path)
    notify("PSEG import", summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
