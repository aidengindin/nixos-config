# Clipboard history (cliphist). Enter copies; Ctrl+Delete deletes the entry;
# Ctrl+Shift+Delete wipes the whole history.

set +e
entry=$(cliphist list | rofi -dmenu -i -p "Clipboard" -display-columns 2 \
  -kb-custom-1 "Control+Delete" -kb-custom-2 "Control+Shift+Delete" \
  -mesg "Enter: copy · Ctrl+Del: delete · Ctrl+Shift+Del: clear all")
status=$?
set -e

case "$status" in
  0) cliphist decode <<<"$entry" | wl-copy ;;
  10)
    cliphist delete <<<"$entry"
    exec "$0"
    ;;
  11)
    cliphist wipe
    notify-send -a Clipboard -u low "Clipboard" "History cleared"
    ;;
esac
