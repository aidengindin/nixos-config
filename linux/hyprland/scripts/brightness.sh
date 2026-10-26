# Brightness for whichever monitor is focused: the laptop panel through
# swayosd (backlight), external monitors over DDC/CI with ddcutil.
#   brightness up|down [OUTPUT]   step 5%; OUTPUT defaults to the focused one,
#                                 "external" means the first DDC monitor
#   brightness status             waybar JSON for the external monitor
#
# `ddcutil detect` takes ~1s, so the connector -> I2C bus map is cached in
# $XDG_RUNTIME_DIR and only re-detected when a call against it fails (e.g.
# after re-docking renumbers the buses). With --bus a call takes ~0.15s.

step=5
run="${XDG_RUNTIME_DIR:-/tmp}"
bus_cache="$run/ddc-buses" # lines of "CONNECTOR BUS", e.g. "DP-7 19"

detect() {
  ddcutil detect --terse 2>/dev/null | awk '
    /^Display/      { valid = 1; next }
    /^Invalid/      { valid = 0; next }
    /I2C bus:/      { sub(".*/dev/i2c-", ""); bus = $0 }
    /DRM connector/ { if (valid) { sub(".*card[0-9]+-", ""); print $0, bus } }
  ' >"$bus_cache"
}

bus_for() { # $1 = connector; prints the bus or nothing
  [[ -s "$bus_cache" ]] || detect
  awk -v c="$1" '$1 == c { print $2 }' "$bus_cache"
}

get() { # $1 = bus; prints 0-100
  ddcutil --bus "$1" getvcp 10 --brief 2>/dev/null | awk '$3 == "C" { printf "%d", $4 * 100 / $5 }'
}

osd() { # $1 = output, $2 = percent
  swayosd-client --monitor "$1" --custom-icon display-brightness-symbolic \
    --custom-progress "$(awk -v p="$2" 'BEGIN { print p / 100 }')" \
    --custom-progress-text "$2%" >/dev/null 2>&1 || true
}

adjust() { # $1 = up|down, $2 = output
  local dir=$1 output=$2
  if [[ "$output" == eDP-* ]]; then
    if [[ "$dir" == up ]]; then swayosd-client --brightness raise; else swayosd-client --brightness lower; fi
    return
  fi

  # Drop key-repeat events that arrive while a DDC write is in flight.
  exec 9>"$run/ddc-brightness.lock"
  flock -n 9 || exit 0

  local bus value attempt
  for attempt in 1 2; do
    bus=$(bus_for "$output")
    if [[ -n "$bus" ]] && value=$(get "$bus") && [[ -n "$value" ]]; then
      break
    fi
    ((attempt == 1)) && detect # stale map: re-detect once
    bus=""
  done
  if [[ -z "$bus" ]]; then
    notify-send -a Brightness -u low "Brightness" "$output doesn't support DDC/CI"
    exit 0
  fi

  if [[ "$dir" == up ]]; then value=$((value + step)); else value=$((value - step)); fi
  ((value > 100)) && value=100
  ((value < 0)) && value=0
  ddcutil --bus "$bus" --noverify setvcp 10 "$value" >/dev/null 2>&1 || true
  osd "$output" "$value"
  pkill -RTMIN+11 -x waybar || true
}

status() {
  [[ -s "$bus_cache" ]] || detect
  local output bus value
  while read -r output bus; do
    if value=$(get "$bus") && [[ -n "$value" ]]; then
      printf '{"text": "󰍹 %s%%", "tooltip": "%s brightness %s%% (DDC)\\nScroll to adjust"}\n' "$value" "$output" "$value"
      return
    fi
  done <"$bus_cache"
  # Nothing answered: maybe undocked or re-docked. Re-detect for next time.
  detect
  printf '{"text": ""}\n'
}

focused() { hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'; }

case "${1:-}" in
  up | down)
    output=${2:-$(focused)}
    if [[ "$output" == external ]]; then # the bar module: first DDC monitor
      [[ -s "$bus_cache" ]] || detect
      output=$(awk 'NR == 1 { print $1 }' "$bus_cache")
      [[ -n "$output" ]] || exit 0
    fi
    adjust "$1" "$output"
    ;;
  status) status ;;
  *)
    echo "usage: brightness up|down [OUTPUT] | status" >&2
    exit 2
    ;;
esac
