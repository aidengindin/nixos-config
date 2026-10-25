# Wi-Fi menu: pick a network to connect, or manage the active/saved ones.
# Selections are made by index (rofi -format i), never by parsing the
# displayed text back, so SSIDs with colons, brackets or spaces are safe.

menu() { # prompt, then lines on stdin; prints the chosen index
  rofi -dmenu -i -format i -p "$1" "${@:2}"
}

notify() { notify-send -a "Wi-Fi" -u "${2:-low}" "Wi-Fi" "$1"; }

# try <success message> <command…>: run quietly, notify either way.
try() {
  local msg=$1
  shift
  if "$@" >/dev/null 2>&1; then notify "$msg"; else notify "Failed: $msg" critical; fi
}

# Saved Wi-Fi profiles, as "name<TAB>ssid" (the profile name may differ from
# the SSID, e.g. "GindinNet 1").
saved_profiles() {
  nmcli -g NAME,TYPE connection show | while IFS= read -r line; do
    [[ "$line" == *:802-11-wireless ]] || continue
    name=${line%:802-11-wireless}
    name=${name//\\:/:}
    ssid=$(nmcli -g 802-11-wireless.ssid connection show id "$name")
    printf '%s\t%s\n' "$name" "$ssid"
  done
}

profile_for_ssid() {
  saved_profiles | awk -F '\t' -v s="$1" '$2 == s { print $1; exit }'
}

network_menu() { # $1 = SSID of an active connection
  local ssid=$1 profile
  profile=$(profile_for_ssid "$ssid")
  local actions=("Disconnect" "Copy password" "Forget network")
  local i
  i=$(printf '%s\n' "${actions[@]}" | menu "$ssid") || exit 0
  case "${actions[$i]}" in
    "Disconnect")
      try "Disconnected from $ssid" nmcli connection down id "$profile"
      ;;
    "Copy password")
      local psk
      psk=$(nmcli -s -g 802-11-wireless-security.psk connection show id "$profile" || true)
      if [[ -n "$psk" ]]; then
        printf '%s' "$psk" | wl-copy
        notify "Password for $ssid copied"
      else
        notify "No saved password for $ssid" normal
      fi
      ;;
    "Forget network")
      try "Forgot $ssid" nmcli connection delete id "$profile"
      ;;
  esac
}

connect() { # $1 = SSID, $2 = security
  local ssid=$1 security=$2 profile
  profile=$(profile_for_ssid "$ssid")
  if [[ -n "$profile" ]]; then
    notify "Connecting to $ssid…"
    try "Connected to $ssid" nmcli connection up id "$profile"
  elif [[ -z "$security" || "$security" == "--" ]]; then
    notify "Connecting to $ssid…"
    try "Connected to $ssid" nmcli device wifi connect "$ssid"
  else
    local password
    password=$(rofi -dmenu -password -p "Password for $ssid" -l 0) || exit 0
    [[ -n "$password" ]] || exit 0
    notify "Connecting to $ssid…"
    try "Connected to $ssid" nmcli device wifi connect "$ssid" password "$password"
  fi
}

main() {
  if [[ "$(nmcli radio wifi)" != "enabled" ]]; then
    i=$(printf '%s\n' "󰖩  Turn Wi-Fi on" | menu "Wi-Fi") || exit 0
    try "Wi-Fi on" nmcli radio wifi on
    exit 0
  fi

  # One row per SSID (strongest BSSID), strongest first, active first.
  # SSID goes last so `read` keeps any colons in it.
  local -a ssids=() securities=() rows=()
  while IFS=: read -r inuse signal security ssid; do
    ssid=${ssid//\\:/:}
    [[ -n "$ssid" ]] || continue
    local seen=0 s
    for s in "${ssids[@]}"; do [[ "$s" == "$ssid" ]] && seen=1 && break; done
    ((seen)) && continue
    ssids+=("$ssid")
    securities+=("$security")
    local icon="󰤨"
    ((signal < 75)) && icon="󰤥"
    ((signal < 50)) && icon="󰤢"
    ((signal < 25)) && icon="󰤟"
    local lock=""
    [[ -n "$security" && "$security" != "--" ]] && lock=" 󰌾"
    local mark=""
    [[ "$inuse" == "*" ]] && mark="  (connected)"
    rows+=("$icon  $ssid$lock$mark")
  done < <(nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan auto |
    sort -t: -k1,1r -k2,2nr)

  local extra=("󰑐  Rescan" "󰖪  Turn Wi-Fi off")
  i=$(printf '%s\n' "${rows[@]}" "${extra[@]}" | menu "Wi-Fi" -selected-row 0) || exit 0

  if ((i < ${#ssids[@]})); then
    if [[ "${rows[$i]}" == *"(connected)" ]]; then
      network_menu "${ssids[$i]}"
    else
      connect "${ssids[$i]}" "${securities[$i]}"
    fi
  else
    case "${extra[$((i - ${#ssids[@]}))]}" in
      *Rescan)
        notify "Scanning…"
        nmcli device wifi rescan 2>/dev/null || true
        sleep 3
        exec "$0"
        ;;
      *off) try "Wi-Fi off" nmcli radio wifi off ;;
    esac
  fi
}

main "$@"
