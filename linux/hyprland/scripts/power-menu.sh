# Power menu. Log out, reboot and shut down ask for confirmation.

choices=("󰌾  Lock" "󰤄  Suspend" "󰍃  Log out" "󰜉  Reboot" "󰐥  Shut down")
i=$(printf '%s\n' "${choices[@]}" | rofi -dmenu -i -format i -p "Power") || exit 0

confirm() {
  local answer
  answer=$(printf '%s\n' "No" "Yes, $1" | rofi -dmenu -i -format i -p "$1?") || exit 0
  [[ "$answer" == 1 ]] || exit 0
}

case "$i" in
  0) loginctl lock-session ;;
  1) systemctl suspend ;;
  2) confirm "log out" && uwsm stop ;;
  3) confirm "reboot" && systemctl reboot ;;
  4) confirm "shut down" && systemctl poweroff ;;
esac
