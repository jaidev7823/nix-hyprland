#!/usr/bin/env bash

export PATH="/run/current-system/sw/bin:/usr/bin:/bin:$PATH"
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${ALBERT_TIMER_STATE_DIR:-$SCRIPT_DIR/../.local/albert-timer}"
STATE_FILE="$STATE_DIR/state.json"
LOCK_FILE="$STATE_DIR/sound.lock"
LOG_FILE="$STATE_DIR/albert.log"
DEFAULT_MINUTES=7

mkdir -p "$STATE_DIR"

log() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >>"$LOG_FILE"
}

ensure_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    cat >"$STATE_FILE" <<'EOF'
{
  "version": 1,
  "current": null,
  "history": [],
  "waste_seconds": 0,
  "last_idle_started_at": null,
  "last_completed_at": null
}
EOF
  fi
}

now_epoch() { date +%s; }
now_iso() { date --iso-8601=seconds; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

spell_minutes() {
  local minutes="$1"
  case "$minutes" in
  0) printf 'Zero' ;;
  1) printf 'One' ;;
  2) printf 'Two' ;;
  3) printf 'Three' ;;
  4) printf 'Four' ;;
  5) printf 'Five' ;;
  6) printf 'Six' ;;
  7) printf 'Seven' ;;
  8) printf 'Eight' ;;
  9) printf 'Nine' ;;
  10) printf 'Ten' ;;
  11) printf 'Eleven' ;;
  12) printf 'Twelve' ;;
  13) printf 'Thirteen' ;;
  14) printf 'Fourteen' ;;
  15) printf 'Fifteen' ;;
  16) printf 'Sixteen' ;;
  17) printf 'Seventeen' ;;
  18) printf 'Eighteen' ;;
  19) printf 'Nineteen' ;;
  20) printf 'Twenty' ;;
  *) printf '%s' "$minutes" ;;
  esac
}

build_quote() {
  local minutes="$1"
  local task="$2"
  local minute_word unit
  minute_word="$(spell_minutes "$minutes")"
  if [[ "$minutes" == "1" ]]; then
    unit='minute'
  else
    unit='minutes'
  fi
  printf '%s %s is all I can spare to play with %s.' "$minute_word" "$unit" "$task"
}

write_state() {
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  mv "$tmp" "$STATE_FILE"
}

json_set() {
  local filter="$1"
  local tmp
  tmp="$(mktemp)"
  jq "$filter" "$STATE_FILE" >"$tmp"
  mv "$tmp" "$STATE_FILE"
}

format_seconds() {
  local total="$1"
  local h=$((total / 3600))
  local m=$(((total % 3600) / 60))
  local s=$((total % 60))
  if ((h > 0)); then
    printf '%02d:%02d:%02d' "$h" "$m" "$s"
  else
    printf '%02d:%02d' "$m" "$s"
  fi
}

terminal_form() {
  local terminal="$1"
  local prompt_file="$STATE_DIR/prompt.out"
  local default_minutes_q prompt_q cmd

  rm -f "$prompt_file"
  printf -v default_minutes_q '%q' "$DEFAULT_MINUTES"
  printf -v prompt_q '%q' "$prompt_file"
  cmd="printf 'Task for this round: '; read -r task; printf 'Minutes to spare [%s]: ' $default_minutes_q; read -r minutes; if [[ -z \"\$minutes\" ]]; then minutes=$default_minutes_q; fi; printf '%s\n%s' \"\$task\" \"\$minutes\" > $prompt_q"

  case "$terminal" in
  kitty)
    kitty --class albert-timer sh -lc "$cmd" >/dev/null 2>&1
    ;;
  footclient)
    footclient sh -lc "$cmd" >/dev/null 2>&1
    ;;
  wezterm)
    wezterm start --always-new-process sh -lc "$cmd" >/dev/null 2>&1
    ;;
  alacritty)
    alacritty -e sh -lc "$cmd" >/dev/null 2>&1
    ;;
  *)
    return 1
    ;;
  esac

  [[ -f "$prompt_file" ]] || return 1
  cat "$prompt_file"
  rm -f "$prompt_file"
}

prompt_round() {
  if has_cmd kitty; then
    terminal_form kitty
  elif has_cmd footclient; then
    terminal_form footclient
  elif has_cmd wezterm; then
    terminal_form wezterm
  elif has_cmd alacritty; then
    terminal_form alacritty
  elif has_cmd zenity; then
    local task_input minutes_input
    task_input="$(zenity --entry --title='Albert Wesker' --text='Task for this round')" || return 1
    minutes_input="$(zenity --entry --title='Albert Wesker' --text='Minutes to spare' --entry-text="$DEFAULT_MINUTES")" || return 1
    printf '%s\n%s' "$task_input" "$minutes_input"
  elif has_cmd walker; then
    local task_input minutes_input
    task_input="$(walker -d -I -p 'Task for this round' <<<"")" || return 1
    minutes_input="$(walker -d -I -p 'Minutes to spare' <<<"$DEFAULT_MINUTES")" || return 1
    printf '%s\n%s' "$task_input" "$minutes_input"
  elif has_cmd rofi; then
    local task_input minutes_input
    task_input="$(rofi -dmenu -i -p 'Task for this round' -theme-str 'entry { placeholder: "Type here"; }' <<<"")" || return 1
    minutes_input="$(rofi -dmenu -i -p 'Minutes to spare' -theme-str 'entry { placeholder: "Type here"; }' <<<"$DEFAULT_MINUTES")" || return 1
    printf '%s\n%s' "$task_input" "$minutes_input"
  else
    return 1
  fi
}

notify() {
  local urgency="$1"
  local title="$2"
  local body="$3"
  if has_cmd notify-send; then
    notify-send -u "$urgency" "$title" "$body"
  fi
}

stop_sound_loop() {
  rm -f "$LOCK_FILE"
}

update_waste() {
  local now last_idle current waste_add
  now="$(now_epoch)"
  current="$(jq '.current' "$STATE_FILE")"
  last_idle="$(jq -r '.last_idle_started_at // empty' "$STATE_FILE")"
  if [[ "$current" == "null" && -n "$last_idle" ]]; then
    waste_add=$((now - last_idle))
    if ((waste_add > 0)); then
      json_set ".waste_seconds += $waste_add | .last_idle_started_at = $now"
    fi
  fi
}

render() {
  ensure_state
  update_waste
  local now current text tooltip class progress remaining total task waste end_at quote
  now="$(now_epoch)"
  current="$(jq '.current' "$STATE_FILE")"
  waste="$(jq '.waste_seconds' "$STATE_FILE")"

  if [[ "$current" != "null" ]]; then
    end_at="$(jq '.current.ends_at_epoch' "$STATE_FILE")"
    total="$(jq '.current.duration_seconds' "$STATE_FILE")"
    task="$(jq -r '.current.task' "$STATE_FILE")"
    quote="$(jq -r '.current.quote' "$STATE_FILE")"
    remaining=$((end_at - now))
    if ((remaining <= 0)); then
      complete
      exec "$0" render
    fi
    progress=$((((total - remaining) * 100) / total))
    text="󱎫 $(format_seconds "$remaining")"
    tooltip="$quote\nTask: $task\nProgress: ${progress}%\nWaste: $(format_seconds "$waste")"
    class='["active"]'
  else
    text="󰔛 07:00"
    tooltip="Click to begin the next round.\nWaste: $(format_seconds "$waste")"
    class='["idle"]'
  fi

  jq -cn --arg text "$text" --arg tooltip "$tooltip" --argjson class "$class" '{text:$text,tooltip:$tooltip,class:$class}'
}

start_timer() {
  ensure_state
  stop_sound_loop

  local task_input minutes_input now end duration history_len id prompt_output quote
  log "start requested"
  if ! prompt_output="$(prompt_round)"; then
    log "round prompt failed or cancelled"
    notify critical "Albert Wesker" "Task prompt did not open. Check Waybar environment or rofi availability."
    exit 1
  fi
  task_input="$(printf '%s\n' "$prompt_output" | sed -n '1p')"
  minutes_input="$(printf '%s\n' "$prompt_output" | sed -n '2p')"
  [[ -z "${task_input// /}" ]] && exit 0
  [[ -z "${minutes_input// /}" ]] && exit 0
  if ! [[ "$minutes_input" =~ ^[0-9]+$ ]] || ((minutes_input <= 0)); then
    notify critical "Albert Wesker" "That is not a valid number of minutes."
    exit 1
  fi

  update_waste

  now="$(now_epoch)"
  duration=$((minutes_input * 60))
  end=$((now + duration))
  history_len="$(jq '.history | length' "$STATE_FILE")"
  id=$((history_len + 1))
  quote="$(build_quote "$minutes_input" "$task_input")"

  json_set ".current = {id:$id, task:$(jq -Rn --arg v "$task_input" '$v'), duration_minutes:$minutes_input, duration_seconds:$duration, started_at:$(jq -Rn --arg v "$(now_iso)" '$v'), started_at_epoch:$now, ends_at_epoch:$end, quote:$(jq -Rn --arg v "$quote" '$v')} | .last_idle_started_at = null"
  log "timer started task=$task_input minutes=$minutes_input"
  notify normal "Albert Wesker" "$quote\nTask: $task_input\nTime: ${minutes_input} minutes"
}

complete() {
  ensure_state
  stop_sound_loop

  local current now payload
  current="$(jq '.current' "$STATE_FILE")"
  [[ "$current" == "null" ]] && exit 0

  now="$(now_epoch)"
  payload="$(jq --arg finished_at "$(now_iso)" --argjson finished_epoch "$now" '.current + {finished_at:$finished_at, finished_at_epoch:$finished_epoch, status:"completed"}' "$STATE_FILE")"
  jq --argjson completed "$payload" --argjson now "$now" '.history += [$completed] | .current = null | .last_completed_at = $now | .last_idle_started_at = $now' "$STATE_FILE" | write_state
  log "timer completed"
  notify critical "Albert Wesker" "Time is up. Choose your next target now."
  start_timer || true
}

reset_state() {
  stop_sound_loop
  rm -f "$STATE_FILE"
  ensure_state
}

case "${1:-render}" in
render) render ;;
start) start_timer ;;
complete) complete ;;
reset) reset_state ;;
*)
  echo "Usage: $0 {render|start|complete|reset}" >&2
  exit 1
  ;;
esac
