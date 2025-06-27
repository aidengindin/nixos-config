#!/usr/bin/env bash

# Get current volume
get_volume() {
    # wpctl output format: "Volume: 0.45" or "Volume: 0.45 [MUTED]"
    # Extract percentage (0.45 = 45%)
    wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'
}

# Get mute status
get_mute() {
    # Check if output contains [MUTED]
    if wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q '\[MUTED\]'; then
        echo "true"
    else
        echo "false"
    fi
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

increase_volume() {
  if [[ "$(get_volume)" -lt "100" ]]; then
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
  fi
}

# Main
case "$1" in
    up)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0  # Unmute first
        increase_volume
        notify_volume
        ;;
    down)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0  # Unmute first
        wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
        notify_volume
        ;;
    mute)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle  # Toggle mute
        notify_volume
        ;;
    *)
        echo "Usage: $0 {up|down|mute}"
        exit 1
        ;;
esac
