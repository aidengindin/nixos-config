# Run a nixpkgs package without installing it, or open a shell with it.
# `package_list` (one attribute name per line, from the system's nixpkgs) is
# set by Nix (see diy.nix). Typing a name that isn't listed works too.

pkg=$(rofi -dmenu -i -p "nix run" <"$package_list") || exit 0
[[ -n "$pkg" ]] || exit 0

i=$(printf '%s\n' "󰐊  Run $pkg" "  Shell with $pkg" | rofi -dmenu -i -format i -p "$pkg") || exit 0

case "$i" in
  0)
    notify-send -a "nix run" -u low "nix run" "Starting $pkg…"
    (
      if ! err=$(nix run "nixpkgs#$pkg" 2>&1 >/dev/null); then
        notify-send -a "nix run" -u critical "nix run $pkg failed" "$(tail -n 3 <<<"$err")"
      fi
    ) &
    disown
    ;;
  1) kitty --detach nix shell "nixpkgs#$pkg" ;;
esac
