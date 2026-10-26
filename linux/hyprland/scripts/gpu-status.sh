# AMD GPU status for waybar, straight from amdgpu sysfs (no amdgpu_top).

dev=""
for d in /sys/class/drm/card*/device; do
  [[ -r "$d/gpu_busy_percent" ]] && dev=$d && break
done
if [[ -z "$dev" ]]; then
  printf '{"text": "", "tooltip": "No amdgpu device"}\n'
  exit 0
fi

busy=$(<"$dev/gpu_busy_percent")
vram_used=$(<"$dev/mem_info_vram_used")
vram_total=$(<"$dev/mem_info_vram_total")
gib() { awk -v b="$1" 'BEGIN { printf "%.1f", b / 1073741824 }'; }

temp="?"
power="?"
for h in "$dev"/hwmon/hwmon*; do
  [[ -r "$h/temp1_input" ]] && temp=$(($(<"$h/temp1_input") / 1000))
  for p in power1_average power1_input; do
    if [[ -r "$h/$p" ]]; then
      power=$(awk -v u="$(<"$h/$p")" 'BEGIN { printf "%.1f", u / 1000000 }')
      break
    fi
  done
done

class=normal
((busy >= 85)) && class=high

printf '{"text": "󰢮 %s%%", "class": "%s", "tooltip": "GPU %s%%\\nVRAM %s / %s GiB\\nTemp %s°C · Power %s W"}\n' \
  "$busy" "$class" "$busy" "$(gib "$vram_used")" "$(gib "$vram_total")" "$temp" "$power"
