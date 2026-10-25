# Ambient sound: loop one sound with mpv in a transient user unit.
# `sounds_dir` is set by Nix (see diy.nix).
#   ambient-menu          pick a sound / volume / stop
#   ambient-menu status   waybar JSON

unit=ambient-sound
socket="${XDG_RUNTIME_DIR:-/tmp}/ambient-sound.sock"
current_file="${XDG_RUNTIME_DIR:-/tmp}/ambient-sound.current"

active() { systemctl --user is-active --quiet "$unit"; }
refresh() { pkill -RTMIN+10 -x waybar || true; }
pretty() { # rain.ogg -> Rain, coffee-shop.ogg -> Coffee shop
  local n=${1%.*}
  n=${n//-/ }
  echo "${n^}"
}

play() { # $1 = file
  systemctl --user stop "$unit" 2>/dev/null || true
  systemd-run --user --quiet --collect --unit="$unit" --description="Ambient sound" \
    mpv --no-video --no-terminal --loop-file=inf --volume=60 \
    --input-ipc-server="$socket" "$1"
  pretty "$(basename "$1")" >"$current_file"
  refresh
}

volume_menu() {
  local levels=(20 40 60 80 100) i
  i=$(printf '%s%%\n' "${levels[@]}" | rofi -dmenu -i -format i -p "Volume") || exit 0
  printf '{"command": ["set_property", "volume", %d]}\n' "${levels[$i]}" |
    socat - "UNIX-CONNECT:$socket" >/dev/null
}

if [[ "${1:-}" == status ]]; then
  if active; then
    printf '{"text": "󰋋", "class": "on", "tooltip": "Ambient: %s"}\n' "$(cat "$current_file" 2>/dev/null)"
  else
    printf '{"text": "󰋋", "class": "off", "tooltip": "Ambient sound: off"}\n'
  fi
  exit 0
fi

mapfile -t files < <(find "$sounds_dir" -maxdepth 1 -name '*.ogg' -printf '%f\n' | sort)
rows=()
for f in "${files[@]}"; do rows+=("$(pretty "$f")"); done
extra=()
if active; then extra=("󰝚  Volume" "󰓛  Stop"); fi

i=$(printf '%s\n' "${extra[@]}" "${rows[@]}" | rofi -dmenu -i -format i -p "Ambient") || exit 0
if ((i < ${#extra[@]})); then
  case "${extra[$i]}" in
    *Volume) volume_menu ;;
    *Stop)
      systemctl --user stop "$unit"
      refresh
      ;;
  esac
else
  play "$sounds_dir/${files[$((i - ${#extra[@]}))]}"
fi
