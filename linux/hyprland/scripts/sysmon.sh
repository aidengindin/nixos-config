# CPU / memory bar modules whose tooltips list the heaviest programs.
# Processes are grouped by program, so e.g. all of Firefox's add up to one line.
#   sysmon cpu      current usage; top programs by CPU over the last 0.5s
#   sysmon memory   used RAM; top programs by resident memory

export LC_ALL=C
top_n=6

# awk: turn a process name into a program name. Nix wrappers show up as
# ".foo-wrapped" (truncated to 15 chars: "-wrap", "-wrappe", …), and Firefox
# names its child processes by role.
normalize='
  function program(c) {
    sub(/^\./, "", c)
    sub(/-wrap[a-z]*$/, "", c)
    if (c ~ /^(Isolated Web Co|Isolated Servic|Web Content|WebExtensions|Privileged Cont|RDD Process|Socket Process|Utility Process|GPU Process|Forked Child)$/)
      c = "firefox"
    return c
  }'

json() { jq -cn --arg text "$1" --arg tooltip "$2" --arg class "$3" \
  '{text: $text, tooltip: $tooltip, class: $class}'; }

cpu() {
  # `ps` %CPU is a lifetime average; top's second sample is the current load.
  local sample usage table
  sample=$(top -b -n 2 -d 0.5 -w 512 | awk '/^top -/ { n++ } n == 2')
  usage=$(awk '/^%Cpu/ { for (i = 1; i <= NF; i++) if ($(i + 1) ~ /^id,?$/) { printf "%d", 100 - $i; exit } }' <<<"$sample")
  table=$(awk "$normalize"'
    header {
      c = $12
      for (i = 13; i <= NF; i++) c = c " " $i
      cpu[program(c)] += $9
    }
    $1 == "PID" { header = 1 }
    END { for (c in cpu) if (cpu[c] >= 0.1) printf "%6.1f%%  %s\n", cpu[c], c }
  ' <<<"$sample" | sort -rn | head -n "$top_n")
  local class=normal
  ((usage >= 85)) && class=high
  json "󰍛 ${usage}%" "CPU ${usage}%  (100% = one core)
${table:-  idle}" "$class"
}

memory() {
  local total avail used pct table
  total=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
  avail=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
  used=$((total - avail))
  pct=$((used * 100 / total))
  table=$(ps -eo rss=,comm= | awk "$normalize"'
    { kb = $1; $1 = ""; sub(/^ /, ""); rss[program($0)] += kb }
    END { for (c in rss) printf "%d %s\n", rss[c], c }
  ' | sort -rn | head -n "$top_n" | awk '{
    kb = $1; $1 = ""; sub(/^ /, "")
    if (kb >= 1048576) printf "%6.1f GiB  %s\n", kb / 1048576, $0
    else printf "%6.0f MiB  %s\n", kb / 1024, $0
  }')
  local class=normal
  ((pct >= 85)) && class=high
  json "󰘚 ${pct}%" "$(awk -v u="$used" -v t="$total" 'BEGIN { printf "RAM %.1f / %.1f GiB", u / 1048576, t / 1048576 }')
${table}" "$class"
}

case "${1:-}" in
  cpu) cpu ;;
  memory) memory ;;
  *)
    echo "usage: sysmon cpu|memory" >&2
    exit 2
    ;;
esac
