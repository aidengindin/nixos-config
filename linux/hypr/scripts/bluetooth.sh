#!/usr/bin/env bash

get_paired_devices() {
  bluetoothctl devices Paired | cut -d' ' -f2-
}

get_connected_devices() {
  bluetoothctl devices Connected | cut -d' ' -f2-
}

get_device_mac() {
  echo "$1" | awk '{print $1}'
}

get_device_name() {
  echo "$1" | cut -d' ' -f2-
}

is_connected() {
  local mac="$1"
  bluetoothctl info "$mac" | grep -q "Connected: yes"
}

main_menu() {
  echo "󰂱 Connect Device"
  echo "󰂲 Disconnect Device"
  echo "󰐲 Pair New Device"
  echo "󰌘 Refresh"
}

list_paired_devices() {
  while IFS= read -r device; do
    mac=$(get_device_mac "$device")
    name=$(get_device_name "$device")
    if is_connected "$mac"; then
      echo "󰂱 $name [Connected]"
    else
      echo "󰂯 $name"
    fi
  done < <(get_paired_devices)
}

list_available_devices() {
  bluetoothctl --timeout 10 scan on >/dev/null 2>&1 &
  scan_pid=$!
  
  sleep 5
  
  bluetoothctl devices | while IFS= read -r device; do
    mac=$(echo "$device" | awk '{print $2}')
    name=$(echo "$device" | cut -d' ' -f3-)
    
    if ! bluetoothctl devices Paired | grep -q "$mac"; then
      echo "󰂯 $name"
    fi
  done
  
  kill $scan_pid 2>/dev/null
}

connect_device() {
  local selection="$1"
  local name=$(echo "$selection" | sed 's/^[^ ]* //' | sed 's/ \[Connected\]$//')
  
  local devices=$(get_paired_devices)
  local matched=$(echo "$devices" | grep -F "$name")
  local mac=$(echo "$matched" | head -n1 | awk '{print $1}')
  
  if [ -n "$mac" ]; then
    if bluetoothctl connect "$mac"; then
      notify-send -u low "Bluetooth" "Connected to $name"
    else
      notify-send -u critical "Bluetooth" "Failed to connect to $name"
    fi
  else
    notify-send -u critical "Bluetooth" "Device not found: $name"
  fi
}

disconnect_device() {
  local selection="$1"
  local name=$(echo "$selection" | sed 's/^[^ ]* //' | sed 's/ \[Connected\]$//')
  
  local devices=$(get_paired_devices)
  local matched=$(echo "$devices" | grep -F "$name")
  local mac=$(echo "$matched" | head -n1 | awk '{print $1}')
  
  if [ -n "$mac" ]; then
    if bluetoothctl disconnect "$mac"; then
      notify-send -u low "Bluetooth" "Disconnected from $name"
    else
      notify-send -u critical "Bluetooth" "Failed to disconnect from $name"
    fi
  else
    notify-send -u critical "Bluetooth" "Device not found: $name"
  fi
}

pair_device() {
  local selection="$1"
  local name=$(echo "$selection" | sed 's/^[^ ]* //')
  
  local devices=$(bluetoothctl devices)
  local matched=$(echo "$devices" | grep -F "$name")
  local mac=$(echo "$matched" | head -n1 | awk '{print $2}')
  
  if [ -n "$mac" ]; then
    notify-send -u low "Bluetooth" "Pairing with $name..."
    if bluetoothctl pair "$mac" && bluetoothctl trust "$mac"; then
      notify-send -u low "Bluetooth" "Paired with $name"
      if bluetoothctl connect "$mac"; then
        notify-send -u low "Bluetooth" "Connected to $name"
      fi
    else
      notify-send -u critical "Bluetooth" "Failed to pair with $name"
    fi
  else
    notify-send -u critical "Bluetooth" "Device not found: $name"
  fi
}

case "$1" in
  "")
    choice=$(main_menu | rofi -dmenu -i -p "Bluetooth" -theme-str 'window {width: 400px;}')
    
    case "$choice" in
      "󰂱 Connect Device")
        device=$(list_paired_devices | grep -v "\[Connected\]" | rofi -dmenu -i -p "Connect to" -theme-str 'window {width: 400px;}')
        [ -n "$device" ] && connect_device "$device"
        ;;
      "󰂲 Disconnect Device")
        device=$(list_paired_devices | grep "\[Connected\]" | rofi -dmenu -i -p "Disconnect from" -theme-str 'window {width: 400px;}')
        [ -n "$device" ] && disconnect_device "$device"
        ;;
      "󰐲 Pair New Device")
        notify-send -u low "Bluetooth" "Scanning for devices..."
        device=$(list_available_devices | rofi -dmenu -i -p "Pair with" -theme-str 'window {width: 400px;}')
        [ -n "$device" ] && pair_device "$device"
        ;;
      "󰌘 Refresh")
        exec "$0"
        ;;
    esac
    ;;
  *)
    echo "Usage: $0"
    exit 1
    ;;
esac
