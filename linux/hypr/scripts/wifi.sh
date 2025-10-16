#!/usr/bin/env bash

get_available_networks() {
  nmcli -t -f IN-USE,SSID,SECURITY device wifi list | grep -v '^:$' | grep -v '^:--$'
}

get_saved_connections() {
  nmcli -t -f NAME,TYPE connection show | grep ':wifi$' | cut -d: -f1
}

get_all_connections() {
  nmcli -t -f NAME,TYPE,DEVICE connection show
}

get_active_connection() {
  nmcli -t -f IN-USE,SSID device wifi list | grep '^\*:' | cut -d: -f2
}

list_networks() {
  local active=$(get_active_connection)
  
  echo "󰌑 Back"
  while IFS=: read -r in_use ssid security; do
    if [ "$ssid" = "$active" ]; then
      echo "󰖩 $ssid [Connected]"
    elif nmcli -t -f NAME connection show | grep -q "^${ssid}$"; then
      echo "󰖩 $ssid [Saved]"
    else
      echo "󰖩 $ssid"
    fi
  done < <(get_available_networks | sort -t: -k2 -u)
}

list_all_connections() {
  echo "󰌑 Back"
  while IFS=: read -r name type device; do
    if [ -n "$device" ] && [ "$device" != "--" ]; then
      case "$type" in
        802-11-wireless) echo "󰖩 $name [$type] [Connected]" ;;
        802-3-ethernet) echo "󰈀 $name [$type] [Connected]" ;;
        tun) echo "󰌾 $name [$type] [Connected]" ;;
        bridge) echo "󰛳 $name [$type] [Connected]" ;;
        loopback) echo "󰿘 $name [$type] [Connected]" ;;
        *) echo "󰛳 $name [$type] [Connected]" ;;
      esac
    else
      case "$type" in
        802-11-wireless) echo "󰖩 $name [$type]" ;;
        802-3-ethernet) echo "󰈀 $name [$type]" ;;
        tun) echo "󰌾 $name [$type]" ;;
        bridge) echo "󰛳 $name [$type]" ;;
        loopback) echo "󰿘 $name [$type]" ;;
        *) echo "󰛳 $name [$type]" ;;
      esac
    fi
  done < <(get_all_connections)
}

get_connection_type() {
  local name="$1"
  nmcli -t -f TYPE connection show "$name" | head -n1
}

show_connection_details() {
  local name="$1"
  details=$(nmcli connection show "$name")
  
  choice=$(echo -e "󰌑 Back\n$details" | rofi -dmenu -i -p "Details: $name" -theme-str 'window {width: 800px; height: 600px;}')
  
  if [ "$choice" = "󰌑 Back" ]; then
    exec "$0"
  fi
}

get_wifi_password() {
  local name="$1"
  nmcli -s -g 802-11-wireless-security.psk connection show "$name" 2>/dev/null
}

connection_menu() {
  local name="$1"
  local type="$2"
  
  echo "󰌑 Back"
  echo "󰋼 Show Details"
  if [ "$type" = "802-11-wireless" ]; then
    echo "󰌆 Show Password & Copy"
    echo "󰆴 Forget Connection"
  fi
}

handle_connection_action() {
  local selection="$1"
  
  if [ "$selection" = "󰌑 Back" ]; then
    exec "$0"
    return
  fi
  
  local name=$(echo "$selection" | sed 's/^[^ ]* //' | sed 's/ \[.*$//')
  local type=$(echo "$selection" | grep -o '\[[^]]*\]' | head -n1 | tr -d '[]')
  
  action=$(connection_menu "$name" "$type" | rofi -dmenu -i -p "Action for $name" -theme-str 'window {width: 400px;}')
  
  case "$action" in
    "󰌑 Back")
      exec "$0"
      ;;
    "󰋼 Show Details")
      show_connection_details "$name"
      ;;
    "󰌆 Show Password & Copy")
      password=$(get_wifi_password "$name")
      if [ -n "$password" ]; then
        echo -n "$password" | wl-copy
        echo "$password" | rofi -dmenu -p "Password for $name (copied to clipboard)" -theme-str 'window {width: 500px;}'
        notify-send -u low "WiFi" "Password copied to clipboard"
      else
        notify-send -u critical "WiFi" "No password found for $name"
      fi
      ;;
    "󰆴 Forget Connection")
      if nmcli connection delete "$name"; then
        notify-send -u low "Network" "Forgot connection $name"
      else
        notify-send -u critical "Network" "Failed to forget connection $name"
      fi
      ;;
  esac
}

connect_network() {
  local selection="$1"
  
  if [ "$selection" = "󰌑 Back" ]; then
    exec "$0"
    return
  fi
  
  local ssid=$(echo "$selection" | sed 's/^[^ ]* //' | sed 's/ \[Connected\]$//' | sed 's/ \[Saved\]$//')
  
  if nmcli -t -f NAME connection show | grep -q "^${ssid}$"; then
    if nmcli connection up "$ssid"; then
      notify-send -u low "WiFi" "Connected to $ssid"
    else
      notify-send -u critical "WiFi" "Failed to connect to $ssid"
    fi
  else
    password=$(rofi -dmenu -password -p "Password for $ssid" -theme-str 'window {width: 400px;}')
    if [ -n "$password" ]; then
      if nmcli device wifi connect "$ssid" password "$password"; then
        notify-send -u low "WiFi" "Connected to $ssid"
      else
        notify-send -u critical "WiFi" "Failed to connect to $ssid"
      fi
    fi
  fi
}

disconnect_network() {
  local selection="$1"
  local ssid=$(echo "$selection" | sed 's/^[^ ]* //' | sed 's/ \[Connected\]$//' | sed 's/ \[Saved\]$//')
  
  if nmcli connection down "$ssid"; then
    notify-send -u low "WiFi" "Disconnected from $ssid"
  else
    notify-send -u critical "WiFi" "Failed to disconnect from $ssid"
  fi
}

main_menu() {
  echo "󰖩 Connect to Network"
  echo "󰖪 Disconnect"
  echo "󰛳 Manage Connections"
  echo "󰌘 Refresh"
}

case "$1" in
  "")
    choice=$(main_menu | rofi -dmenu -i -p "WiFi" -theme-str 'window {width: 400px;}')
    
    case "$choice" in
      "󰖩 Connect to Network")
        nmcli device wifi rescan 2>/dev/null
        network=$(list_networks | rofi -dmenu -i -p "Select Network" -theme-str 'window {width: 500px;}')
        [ -n "$network" ] && connect_network "$network"
        ;;
      "󰖪 Disconnect")
        active=$(get_active_connection)
        if [ -n "$active" ]; then
          disconnect_network "󰖩 $active"
        else
          notify-send -u low "WiFi" "No active WiFi connection"
        fi
        ;;
      "󰛳 Manage Connections")
        connection=$(list_all_connections | rofi -dmenu -i -p "Select Connection" -theme-str 'window {width: 600px;}')
        [ -n "$connection" ] && handle_connection_action "$connection"
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
