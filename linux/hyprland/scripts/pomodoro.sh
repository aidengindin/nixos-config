# Pomodoro timer for waybar: 25 min focus, 5 min break, 15 min long break
# after every 4th focus. Phases advance on their own and notify.
#   pomodoro status   waybar JSON (polled every second; also advances phases)
#   pomodoro toggle   start / pause / resume
#   pomodoro skip     end the current phase now
#   pomodoro reset    stop and clear

state_file="${XDG_RUNTIME_DIR:-/tmp}/pomodoro"
declare -A minutes=([focus]=25 [break]=5 [long]=15)
declare -A labels=([focus]="Focus" [break]="Break" [long]="Long break")

# state: phase running(0/1) end_epoch remaining_s completed_focus_count
phase=idle running=0 end=0 remaining=0 count=0
[[ -f "$state_file" ]] && read -r phase running end remaining count <"$state_file"
now=$(date +%s)

save() { echo "$phase $running $end $remaining $count" >"$state_file"; }
refresh() { pkill -RTMIN+8 -x waybar || true; }

start_phase() { # $1 = phase
  phase=$1
  running=1
  remaining=$((minutes[$phase] * 60))
  end=$((now + remaining))
  save
}

advance() {
  if [[ "$phase" == focus ]]; then
    count=$((count + 1))
    if ((count % 4 == 0)); then start_phase long; else start_phase break; fi
    notify-send -a Pomodoro -u normal "Pomodoro" "${labels[$phase]}: ${minutes[$phase]} minutes"
  else
    start_phase focus
    notify-send -a Pomodoro -u normal "Pomodoro" "Back to focus: ${minutes[focus]} minutes"
  fi
}

case "${1:-status}" in
  status)
    if [[ "$phase" == idle ]]; then
      printf '{"text": "󰔛", "class": "idle", "tooltip": "Pomodoro: click to start"}\n'
      exit 0
    fi
    if ((running)); then
      remaining=$((end - now))
      if ((remaining <= 0)); then
        advance
        refresh
      fi
    fi
    text=$(printf '%02d:%02d' $((remaining / 60)) $((remaining % 60)))
    icon="󰔟"
    [[ "$phase" != focus ]] && icon="󰅶"
    ((running)) || icon="󰏤"
    class=$phase
    ((running)) || class=paused
    printf '{"text": "%s %s", "class": "%s", "tooltip": "%s · %d done\\nClick: pause/resume · Right: reset · Middle: skip"}\n' \
      "$icon" "$text" "$class" "${labels[$phase]}" "$count"
    ;;
  toggle)
    if [[ "$phase" == idle ]]; then
      start_phase focus
    elif ((running)); then
      remaining=$((end - now))
      running=0
      save
    else
      running=1
      end=$((now + remaining))
      save
    fi
    refresh
    ;;
  skip)
    [[ "$phase" == idle ]] || advance
    refresh
    ;;
  reset)
    rm -f "$state_file"
    refresh
    ;;
  *)
    echo "usage: pomodoro [status|toggle|skip|reset]" >&2
    exit 2
    ;;
esac
