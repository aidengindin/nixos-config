# Keep awake: hold a logind idle inhibitor in a transient user unit, so
# hypridle neither dims, locks, blanks nor suspends. Lid-close suspend is
# unaffected (only "idle" is inhibited). The bar and a keybind share the
# state, and it survives a waybar restart.
#   keep-awake [toggle]   flip it
#   keep-awake status     waybar JSON

unit=keep-awake

active() { systemctl --user is-active --quiet "$unit"; }

case "${1:-toggle}" in
  toggle)
    if active; then
      systemctl --user stop "$unit"
      notify-send -a "Keep awake" -u low "Keep awake" "Off"
    else
      systemd-run --user --quiet --collect --unit="$unit" --description="Keep awake" \
        systemd-inhibit --what=idle --who="Keep awake" --why="Toggled on from the bar" \
        sleep infinity
      notify-send -a "Keep awake" -u low "Keep awake" "On: the screen won't dim, lock or sleep"
    fi
    pkill -RTMIN+9 -x waybar || true
    ;;
  status)
    if active; then
      printf '{"text": "󰅶", "class": "on", "tooltip": "Keep awake: on"}\n'
    else
      printf '{"text": "󰾪", "class": "off", "tooltip": "Keep awake: off"}\n'
    fi
    ;;
  *)
    echo "usage: keep-awake [toggle|status]" >&2
    exit 2
    ;;
esac
