"""Mirror GPS-bearing intervals.icu activities into Dawarich as GPX imports.

intervals.icu is not one of Dawarich's supported import sources, but it can
render any activity as GPX and Dawarich accepts GPX uploads over its API, so
this bridges the two: list activities in a window, keep the ones that actually
happened outdoors, and POST their GPX to Dawarich.

Configuration is entirely environmental. Secrets come from the age-decrypted
EnvironmentFile; everything else is set by the systemd unit.
"""

import json
import os
import re
import sys
import time
from datetime import date, timedelta

import requests

INTERVALS_BASE = "https://intervals.icu/api/v1"

# Far enough back to cover any account. intervals.icu wants a local ISO date.
EPOCH = "1970-01-01"


def env(name, default=None, required=False):
    value = os.environ.get(name, default)
    if required and not value:
        sys.exit(f"{name} is not set")
    return value


def log(message):
    print(message, flush=True)


def load_state(path):
    try:
        with open(path) as handle:
            state = json.load(handle)
    except FileNotFoundError:
        state = {}
    state.setdefault("backfill_complete", False)
    state.setdefault("processed", {})
    return state


def save_state(path, state):
    """Write atomically: this is flushed after every single upload, so a crash
    mid-run must never leave a truncated file behind and re-upload the lot."""
    tmp = f"{path}.tmp"
    with open(tmp, "w") as handle:
        json.dump(state, handle, indent=2, sort_keys=True)
    os.replace(tmp, path)


def is_virtual(activity):
    """Zwift and other indoor rides.

    Three overlapping checks on purpose. Zwift GPX files carry genuine Watopia
    coordinates, so an unfiltered one plots as a trip to the middle of the
    Pacific -- a false negative here is far more annoying than a false positive.
    """
    if (activity.get("type") or "").startswith("Virtual"):
        return True
    if activity.get("trainer"):
        return True
    if (activity.get("source") or "").upper() == "ZWIFT":
        return True
    return False


def has_gps(activity):
    """Whether the activity recorded coordinates.

    Absent rather than empty stream_types means intervals.icu did not tell us
    either way, so assume yes and let the GPX download decide -- a 404 there is
    recorded as permanent, which costs one wasted request per activity once.
    """
    if "stream_types" not in activity:
        return True
    return "latlng" in (activity["stream_types"] or [])


def gpx_filename(activity):
    name = activity.get("name") or "activity"
    slug = re.sub(r"[^A-Za-z0-9]+", "-", name).strip("-").lower()[:60]
    return f"intervals-{activity['id']}{'-' + slug if slug else ''}.gpx"


def list_activities(session, athlete_id, oldest):
    response = session.get(
        f"{INTERVALS_BASE}/athlete/{athlete_id}/activities",
        # No "fields" filter: it would trim the response usefully, but an
        # unrecognised name there is dropped silently, and a missing
        # stream_types would then look like "no activity has GPS" -- a total
        # no-op that reports success.
        params={"oldest": oldest},
        timeout=(10, 120),
    )
    response.raise_for_status()
    return response.json()


def fetch_gpx(session, activity_id):
    response = session.get(
        f"{INTERVALS_BASE}/activity/{activity_id}/gpx-file", timeout=(10, 120)
    )
    # intervals.icu refuses GPX for Strava-sourced activities and for anything
    # it decides has no usable GPS, even when stream_types said otherwise.
    # Those will never succeed, so report them as permanent rather than retrying
    # every hour forever.
    if response.status_code in (404, 422):
        return None
    response.raise_for_status()
    return response.content


def upload(session, base_url, activity, gpx):
    response = session.post(
        f"{base_url}/api/v1/imports",
        files={"file": (gpx_filename(activity), gpx, "application/gpx+xml")},
        timeout=(10, 300),
    )
    response.raise_for_status()
    return response.json()


def main():
    athlete_id = env("INTERVALS_ATHLETE_ID", required=True)
    intervals_key = env("INTERVALS_API_KEY", required=True)
    dawarich_url = env("DAWARICH_URL", required=True).rstrip("/")
    dawarich_key = env("DAWARICH_API_KEY", required=True)
    state_path = env("STATE_PATH", required=True)
    lookback_days = int(env("LOOKBACK_DAYS", "14"))
    upload_delay = float(env("UPLOAD_DELAY_SECONDS", "2"))

    state = load_state(state_path)

    # Everything ever, until one complete pass has succeeded; a rolling window
    # from then on.
    backfilling = not state["backfill_complete"]
    oldest = EPOCH if backfilling else (date.today() - timedelta(days=lookback_days)).isoformat()
    log(f"Listing activities since {oldest}" + (" (backfill)" if backfilling else ""))

    intervals = requests.Session()
    intervals.auth = ("API_KEY", intervals_key)

    dawarich = requests.Session()
    dawarich.headers["Authorization"] = f"Bearer {dawarich_key}"

    activities = list_activities(intervals, athlete_id, oldest)
    # The API returns newest first; upload chronologically so a partial run
    # leaves the oldest gap rather than a hole in the middle.
    activities.reverse()

    uploaded = 0
    skipped = 0
    failed = 0

    for activity in activities:
        activity_id = activity.get("id")
        if not activity_id or activity_id in state["processed"]:
            continue
        if is_virtual(activity) or not has_gps(activity):
            skipped += 1
            continue

        try:
            gpx = fetch_gpx(intervals, activity_id)
            if gpx is None:
                log(f"{activity_id}: intervals.icu has no GPX, not retrying")
                state["processed"][activity_id] = "no_gpx"
                save_state(state_path, state)
                skipped += 1
                continue
            result = upload(dawarich, dawarich_url, activity, gpx)
        except requests.RequestException as error:
            # Keep going: one bad activity should not stall the rest, and the
            # non-zero exit below still surfaces the failure in systemd.
            log(f"{activity_id}: {error}")
            failed += 1
            continue

        state["processed"][activity_id] = "uploaded"
        save_state(state_path, state)
        uploaded += 1
        log(f"{activity_id}: imported as {result.get('name')} ({activity.get('name')})")

        if upload_delay:
            time.sleep(upload_delay)

    # Only close out the backfill on a clean pass, so a run that hit errors
    # keeps the wide window and picks the stragglers up next time.
    if backfilling and failed == 0:
        state["backfill_complete"] = True
        save_state(state_path, state)
        log("Backfill complete; future runs use the rolling window")

    log(f"Done: {uploaded} uploaded, {skipped} skipped, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
