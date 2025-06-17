#!/usr/bin/env bash

# Get current volume
get_volume() {
    pamixer --get-volume
}

# Get mute status
get_mute() {
    pamixer --get-mute
}

# Send notification
notify_volume() {
    volume=$(get_volume)
    
    if [[ $(get_mute) == "true" ]]; then
        notify-send -h string:x-canonical-private-synchronous:sys-notify -u low "Volume" "Muted" \
            -h int:value:0 -t 1500
    else
        notify-send -h string:x-canonical-private-synchronous:sys-notify -u low "Volume" "${volume}%" \
            -h int:value:$volume -t 1500
    fi
}

# Main
case "$1" in
    up)
        pamixer -u  # Unmute first
        pamixer -i 5
        notify_volume
        ;;
    down)
        pamixer -u  # Unmute first
        pamixer -d 5
        notify_volume
        ;;
    mute)
        pamixer -t  # Toggle mute
        notify_volume
        ;;
    *)
        echo "Usage: $0 {up|down|mute}"
        exit 1
        ;;
esac