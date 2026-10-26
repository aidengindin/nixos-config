# Bluetooth menu: connect/disconnect/forget paired devices, scan and pair new
# ones. Devices are tracked by MAC and chosen by index, never by name.

menu() { # prompt, then lines on stdin; prints the chosen index
  rofi -dmenu -i -format i -p "$1" "${@:2}"
}

notify() { notify-send -a "Bluetooth" -u "${2:-low}" "Bluetooth" "$1"; }

# try <success message> <command…>: run quietly, notify either way.
try() {
  local msg=$1
  shift
  if "$@" >/dev/null 2>&1; then notify "$msg"; else notify "Failed: $msg" critical; fi
}

# "MAC<TAB>name" per line for `bluetoothctl devices [filter]`.
devices() {
  bluetoothctl devices "$@" | awk '$1 == "Device" { mac = $2; $1 = $2 = ""; sub(/^ +/, ""); print mac "\t" $0 }'
}

is_connected() { bluetoothctl info "$1" | grep -q "Connected: yes"; }

battery() { # "  90%" or nothing
  bluetoothctl info "$1" | sed -n 's/.*Battery Percentage: .*(\([0-9]*\)).*/  \1%/p'
}

device_menu() { # $1 = MAC, $2 = name
  local mac=$1 name=$2 i
  local -a actions
  if is_connected "$mac"; then actions=("Disconnect"); else actions=("Connect"); fi
  actions+=("Forget device")
  i=$(printf '%s\n' "${actions[@]}" | menu "$name") || exit 0
  case "${actions[$i]}" in
    Connect)
      notify "Connecting to $name…"
      try "Connected to $name" bluetoothctl connect "$mac"
      ;;
    Disconnect) try "Disconnected from $name" bluetoothctl disconnect "$mac" ;;
    "Forget device") try "Forgot $name" bluetoothctl remove "$mac" ;;
  esac
}

scan_and_pair() {
  notify "Scanning for 8 seconds…"
  bluetoothctl --timeout 8 scan on >/dev/null 2>&1 || true

  local -a macs=() names=()
  local paired mac name
  paired=$(devices Paired | cut -f1)
  while IFS=$'\t' read -r mac name; do
    grep -qxF "$mac" <<<"$paired" && continue
    # Unnamed devices report their MAC (with dashes) as the name.
    [[ "$name" == "${mac//:/-}" ]] && continue
    macs+=("$mac")
    names+=("$name")
  done < <(devices)

  if ((${#macs[@]} == 0)); then
    notify "No new devices found"
    return
  fi

  local i
  i=$(printf '󰂯  %s\n' "${names[@]}" | menu "Pair") || exit 0
  mac=${macs[$i]}
  name=${names[$i]}
  notify "Pairing with $name…"
  if bluetoothctl pair "$mac" >/dev/null 2>&1 && bluetoothctl trust "$mac" >/dev/null 2>&1; then
    try "Paired and connected to $name" bluetoothctl connect "$mac"
  else
    notify "Could not pair with $name" critical
  fi
}

main() {
  if ! bluetoothctl show | grep -q "Powered: yes"; then
    printf '%s\n' "󰂯  Turn Bluetooth on" | menu "Bluetooth" >/dev/null || exit 0
    try "Bluetooth on" bluetoothctl power on
    exit 0
  fi

  local -a macs=() names=() rows=()
  local mac name
  while IFS=$'\t' read -r mac name; do
    macs+=("$mac")
    names+=("$name")
    if is_connected "$mac"; then
      rows+=("󰂱  $name$(battery "$mac")  (connected)")
    else
      rows+=("󰂯  $name")
    fi
  done < <(devices Paired)

  local -a extra=("󰐲  Pair new device" "󰂲  Turn Bluetooth off")
  local i
  i=$(printf '%s\n' "${rows[@]}" "${extra[@]}" | menu "Bluetooth") || exit 0

  if ((i < ${#macs[@]})); then
    device_menu "${macs[$i]}" "${names[$i]}"
  else
    case "${extra[$((i - ${#macs[@]}))]}" in
      *Pair*) scan_and_pair ;;
      *off) try "Bluetooth off" bluetoothctl power off ;;
    esac
  fi
}

main "$@"
