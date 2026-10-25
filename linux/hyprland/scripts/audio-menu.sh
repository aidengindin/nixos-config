# Audio device menu: pick the default output (sink) or input (source).
# Reads PipeWire's machine-readable pw-dump instead of scraping `wpctl status`.

# "id<TAB>class<TAB>is_default<TAB>description", outputs first.
nodes() {
  pw-dump | jq -r '
    ([.[] | select(.type == "PipeWire:Interface:Metadata" and .props."metadata.name" == "default")
          | .metadata[] | {(.key): .value.name}] | add // {}) as $defaults
    | [.[] | select((.info.props."media.class"? // "") | test("^Audio/(Sink|Source)$"))
           | .info.props as $p
           | ($p."media.class" | if . == "Audio/Sink" then "sink" else "source" end) as $kind
           | {id, $kind, desc: ($p."node.description" // $p."node.name"),
              default: ($p."node.name" == $defaults["default.audio." + $kind])}]
    | sort_by(.kind != "sink", .desc)[]
    | [.id, .kind, (if .default then 1 else 0 end), .desc] | @tsv'
}

main() {
  local -a ids=() descs=() rows=()
  local id kind default desc
  while IFS=$'\t' read -r id kind default desc; do
    ids+=("$id")
    descs+=("$desc")
    local icon="󰓃" mark=""
    [[ "$kind" == "source" ]] && icon="󰍬"
    [[ "$default" == 1 ]] && mark="  (default)"
    rows+=("$icon  $desc$mark")
  done < <(nodes)

  ((${#ids[@]} > 0)) || {
    notify-send -a Audio -u normal "Audio" "No audio devices found"
    exit 0
  }

  local i
  i=$(printf '%s\n' "${rows[@]}" | rofi -dmenu -i -format i -p "Audio") || exit 0
  if wpctl set-default "${ids[$i]}"; then
    notify-send -a Audio -u low "Audio" "Default: ${descs[$i]}"
  else
    notify-send -a Audio -u critical "Audio" "Could not switch to ${descs[$i]}"
  fi
}

main "$@"
