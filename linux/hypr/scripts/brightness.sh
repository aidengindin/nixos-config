#!/usr/bin/env bash

# Get current brightness percentage
get_brightness() {
    brightnessctl -m | cut -d',' -f4 | tr -d '%'
}

# Send notification
notify_brightness() {
    brightness=$(get_brightness)
    notify-send -h string:x-canonical-private-synchronous:sys-notify -u low "Brightness" "${brightness}%" \
        -h int:value:$brightness -t 1500
}

# Main
case "$1" in
    up)
        brightnessctl set +5%
        notify_brightness
        ;;
    down)
        brightnessctl set 5%-
        notify_brightness
        ;;
    *)
        echo "Usage: $0 {up|down}"
        exit 1
        ;;
esac