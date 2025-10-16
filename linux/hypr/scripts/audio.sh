#!/usr/bin/env bash

get_sinks() {
  wpctl status | awk '/Audio/,/^[[:space:]]*$/ {if (/Sinks:/) flag=1; else if (/Sources:|Filters:|Streams:/) flag=0; if (flag && ($2 ~ /^[0-9]+\./ || $2 == "*")) print}' | sed 's/^[^0-9*]*//'
}

get_audio_sources() {
  wpctl status | awk '/Audio/,/^[[:space:]]*$/ {if (/Sources:/) flag=1; else if (/Filters:|Streams:/) flag=0; if (flag && ($2 ~ /^[0-9]+\./ || $2 == "*")) print}' | sed 's/^[^0-9*]*//'
}

get_video_sources() {
  wpctl status | awk '/Video/,0 {if (/Sources:/) flag=1; else if (/Filters:|Streams:/) flag=0; if (flag && ($2 ~ /^[0-9]+\./ || $2 == "*")) print}' | sed 's/^[^0-9*]*//'
}

get_device_id() {
  echo "$1" | sed 's/^[[:space:]]*\*[[:space:]]*//' | awk '{print $1}' | tr -d '.'
}

get_device_name() {
  echo "$1" | sed 's/^[[:space:]]*\*[[:space:]]*//' | sed 's/^[0-9]*\.[[:space:]]*//' | sed 's/[[:space:]]*\[vol:.*\]$//'
}

is_default() {
  echo "$1" | grep -q '^\*'
}

list_sinks() {
  while IFS= read -r device; do
    name=$(get_device_name "$device")
    if is_default "$device"; then
      echo "󰓃 $name [Default]"
    else
      echo "󰓃 $name"
    fi
  done < <(get_sinks)
}

list_audio_sources() {
  while IFS= read -r device; do
    name=$(get_device_name "$device")
    if is_default "$device"; then
      echo "󰍬 $name [Default]"
    else
      echo "󰍬 $name"
    fi
  done < <(get_audio_sources)
}

list_video_sources() {
  while IFS= read -r device; do
    name=$(get_device_name "$device")
    if is_default "$device"; then
      echo "󰄀 $name [Default]"
    else
      echo "󰄀 $name"
    fi
  done < <(get_video_sources)
}

set_default_sink() {
  local selection="$1"
  local name=$(echo "$selection" | sed 's/^[^ ]* //' | sed 's/ \[Default\]$//')
  
  local devices=$(get_sinks)
  local matched=$(echo "$devices" | grep -F "$name")
  local id=$(echo "$matched" | head -n1 | sed 's/^[[:space:]]*\*[[:space:]]*//' | awk '{print $1}' | tr -d '.')
  
  if [ -n "$id" ]; then
    if wpctl set-default "$id"; then
      notify-send -u low "Audio" "Default sink: $name"
    else
      notify-send -u critical "Audio" "Failed to set default sink"
    fi
  else
    notify-send -u critical "Audio" "Sink not found: $name"
  fi
}

set_default_audio_source() {
  local selection="$1"
  local name=$(echo "$selection" | sed 's/^[^ ]* //' | sed 's/ \[Default\]$//')
  
  local devices=$(get_audio_sources)
  local matched=$(echo "$devices" | grep -F "$name")
  local id=$(echo "$matched" | head -n1 | sed 's/^[[:space:]]*\*[[:space:]]*//' | awk '{print $1}' | tr -d '.')
  
  if [ -n "$id" ]; then
    if wpctl set-default "$id"; then
      notify-send -u low "Audio" "Default source: $name"
    else
      notify-send -u critical "Audio" "Failed to set default source"
    fi
  else
    notify-send -u critical "Audio" "Source not found: $name"
  fi
}

set_default_video_source() {
  local selection="$1"
  local name=$(echo "$selection" | sed 's/^[^ ]* //' | sed 's/ \[Default\]$//')
  
  local devices=$(get_video_sources)
  local matched=$(echo "$devices" | grep -F "$name")
  local id=$(echo "$matched" | head -n1 | sed 's/^[[:space:]]*\*[[:space:]]*//' | awk '{print $1}' | tr -d '.')
  
  if [ -n "$id" ]; then
    if wpctl set-default "$id"; then
      notify-send -u low "Video" "Default source: $name"
    else
      notify-send -u critical "Video" "Failed to set default source"
    fi
  else
    notify-send -u critical "Video" "Source not found: $name"
  fi
}

main_menu() {
  echo "󰓃 Set Default Audio Output"
  echo "󰍬 Set Default Audio Input"
  echo "󰄀 Set Default Video Input"
}

case "$1" in
  "")
    choice=$(main_menu | rofi -dmenu -i -p "Audio/Video" -theme-str 'window {width: 400px;}')
    
    case "$choice" in
      "󰓃 Set Default Audio Output")
        device=$(list_sinks | rofi -dmenu -i -p "Select Sink" -theme-str 'window {width: 500px;}')
        [ -n "$device" ] && set_default_sink "$device"
        ;;
      "󰍬 Set Default Audio Input")
        device=$(list_audio_sources | rofi -dmenu -i -p "Select Audio Source" -theme-str 'window {width: 500px;}')
        [ -n "$device" ] && set_default_audio_source "$device"
        ;;
      "󰄀 Set Default Video Input")
        device=$(list_video_sources | rofi -dmenu -i -p "Select Video Source" -theme-str 'window {width: 500px;}')
        [ -n "$device" ] && set_default_video_source "$device"
        ;;
    esac
    ;;
  *)
    echo "Usage: $0"
    exit 1
    ;;
esac
