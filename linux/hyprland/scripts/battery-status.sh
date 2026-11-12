# Battery segment for the bar, read from UPower so it can show the charge
# limit (waybar's built-in battery module has no field for it).
#   battery-status [status]   waybar JSON
#   battery-status toggle     lift the charge limit until the next unplug, or
#                             put it back early
# The limit itself comes back on at boot and on unplug; see
# linux/batteryChargeLimit.nix.

upower_call() { busctl "$1" org.freedesktop.UPower "${@:2}"; }

dev=$(upower -e | grep -m1 '/battery_' || true)
if [ -z "$dev" ]; then
  # No battery: an empty text hides the segment.
  printf '{"text": ""}\n'
  exit 0
fi

prop() {
  upower_call get-property "$dev" org.freedesktop.UPower.Device "$1" | cut -d' ' -f2-
}

case "${1:-status}" in
  toggle)
    if [ "$(prop ChargeThresholdSupported)" != true ]; then
      notify-send -a "Battery" -u low "Battery" "This battery has no charge limit"
      exit 0
    fi
    limit=$(prop ChargeEndThreshold)
    if [ "$(prop ChargeThresholdEnabled)" = true ]; then
      upower_call call "$dev" org.freedesktop.UPower.Device EnableChargeThreshold b false
      notify-send -a "Battery" -u low "Charging to 100%" \
        "The ${limit}% limit comes back on when you unplug"
    else
      upower_call call "$dev" org.freedesktop.UPower.Device EnableChargeThreshold b true
      notify-send -a "Battery" -u low "Charge limit on" "Charging stops at ${limit}%"
    fi
    pkill -RTMIN+12 -x waybar || true
    ;;
  status)
    pct=$(printf '%.0f' "$(prop Percentage)")
    state=$(prop State) # 1 charging, 2 discharging, 4 full, 5 pending charge
    rate=$(prop EnergyRate)
    health=$(printf '%.0f' "$(prop Capacity)")
    on_battery=$(upower_call get-property /org/freedesktop/UPower org.freedesktop.UPower OnBattery | cut -d' ' -f2)

    icons=(󰂎 󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂁 󰂂 󰁹)
    classes=()
    if [ "$state" = 1 ]; then
      icon=󰂄
      classes+=(charging)
    elif [ "$on_battery" = false ]; then
      icon=󰚥
      classes+=(plugged)
    else
      icon=${icons[$((pct / 10))]}
    fi
    if [ "$pct" -le 15 ]; then
      classes+=(critical)
    elif [ "$pct" -le 30 ]; then
      classes+=(warning)
    fi

    hm() { printf '%dh %02dm' $(($1 / 3600)) $(($1 % 3600 / 60)); }
    case "$state" in
      1) secs=$(prop TimeToFull) && [ "$secs" -gt 0 ] && when="$(hm "$secs") until full" ;;
      2) secs=$(prop TimeToEmpty) && [ "$secs" -gt 0 ] && when="$(hm "$secs") until empty" ;;
      4) when="Full" ;;
      5) when="Not charging" ;;
    esac
    when=${when:-$([ "$on_battery" = true ] && echo "Discharging" || echo "Charging")}

    if [ "$(prop ChargeThresholdSupported)" = true ]; then
      limit=$(prop ChargeEndThreshold)
      if [ "$(prop ChargeThresholdEnabled)" = true ]; then
        limit_line="Charge limit ${limit}% · click to charge to 100%"
      else
        limit_line="Charging to 100% until unplugged · click to restore ${limit}%"
        classes+=(unlimited)
      fi
    fi

    jq -nc \
      --arg text "$icon $pct%" \
      --arg tooltip "$(printf '%s\n%.1f W · health %s%%%s' "$when" "$rate" "$health" "${limit_line:+$'\n'$limit_line}")" \
      --argjson pct "$pct" \
      '{text: $text, tooltip: $tooltip, percentage: $pct, class: $ARGS.positional}' \
      --args "${classes[@]}"
    ;;
  *)
    echo "usage: battery-status [status|toggle]" >&2
    exit 2
    ;;
esac
