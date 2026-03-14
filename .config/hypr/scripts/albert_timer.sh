#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${ALBERT_TIMER_STATE_DIR:-$SCRIPT_DIR/../.local/albert-timer}"
STATE_FILE="$STATE_DIR/state.json"
LOCK_FILE="$STATE_DIR/sound.lock"
LOG_FILE="$STATE_DIR/albert.log"
DEFAULT_MINUTES=7
QUOTE="Seven minutes is all I can spare to play with you."
ALERT_SOUND="${ALBERT_TIMER_SOUND:-/run/current-system/sw/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga}"

mkdir -p "$STATE_DIR"

log() {
  printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" >> "$LOG_FILE"
}

ensure_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    cat > "$STATE_FILE" <<'EOF'
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

write_state() {
  local tmp
  tmp="$(mktemp)"
  cat > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

json_set() {
  local filter="$1"
  local tmp
  tmp="$(mktemp)"
  jq "$filter" "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

format_seconds() {
  local total="$1"
  local h=$(( total / 3600 ))
  local m=$(( (total % 3600) / 60 ))
  local s=$(( total % 60 ))
  if (( h > 0 )); then
    printf '%02d:%02d:%02d' "$h" "$m" "$s"
  else
    printf '%02d:%02d' "$m" "$s"
  fi
}

prompt() {
  local message="$1"
  local value="${2:-}"
  if has_cmd rofi; then
    rofi -dmenu -i -p "$message" -theme-str 'entry { placeholder: "Type here"; }' <<<"$value"
  else
    printf '%s' "$value"
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

play_sound_loop() {
  [[ -f "$ALERT_SOUND" ]] || return
  (
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
    while [[ -f "$LOCK_FILE" ]]; do
      if has_cmd pw-play; then
        pw-play "$ALERT_SOUND" >/dev/null 2>&1 || true
      elif has_cmd paplay; then
        paplay "$ALERT_SOUND" >/dev/null 2>&1 || true
      elif has_cmd ffplay; then
        ffplay -nodisp -autoexit -loglevel quiet "$ALERT_SOUND" >/dev/null 2>&1 || true
      else
        sleep 2
      fi
    done
  ) >/dev/null 2>&1 &
}

stop_sound_loop() {
  [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE"
}

update_waste() {
  local now last_idle current waste_add
  now="$(now_epoch)"
  current="$(jq '.current' "$STATE_FILE")"
  last_idle="$(jq -r '.last_idle_started_at // empty' "$STATE_FILE")"
  if [[ "$current" == "null" && -n "$last_idle" ]]; then
    waste_add=$(( now - last_idle ))
    if (( waste_add > 0 )); then
      json_set ".waste_seconds += $waste_add | .last_idle_started_at = $now"
    fi
  fi
}

render() {
  ensure_state
  update_waste
  local now current text tooltip class progress remaining total task waste end_at
  now="$(now_epoch)"
  current="$(jq '.current' "$STATE_FILE")"
  waste="$(jq '.waste_seconds' "$STATE_FILE")"

  if [[ "$current" != "null" ]]; then
    end_at="$(jq '.current.ends_at_epoch' "$STATE_FILE")"
    total="$(jq '.current.duration_seconds' "$STATE_FILE")"
    task="$(jq -r '.current.task' "$STATE_FILE")"
    remaining=$(( end_at - now ))
    if (( remaining <= 0 )); then
      complete
      exec "$0" render
    fi
    progress=$(( ((total - remaining) * 100) / total ))
    text="󱎫 $(format_seconds "$remaining")"
    tooltip="$QUOTE\nTask: $task\nProgress: ${progress}%\nWaste: $(format_seconds "$waste")"
    class='["active"]'
  else
    text="󰔛 07:00"
    tooltip="$QUOTE\nNo active task.\nWaste: $(format_seconds "$waste")\nClick to begin the next round."
    class='["idle"]'
  fi

  jq -cn --arg text "$text" --arg tooltip "$tooltip" --argjson class "$class" '{text:$text,tooltip:$tooltip,class:$class}'
}

start_timer() {
  ensure_state
  stop_sound_loop

  local task_input minutes_input now end duration history_len id
  log "start requested"
  if ! task_input="$(prompt 'Task for this round' '')"; then
    log "task prompt failed or cancelled"
    notify critical "Albert Wesker" "Task prompt did not open. Check Waybar environment or rofi availability."
    exit 1
  fi
  [[ -z "${task_input// }" ]] && exit 0

  if ! minutes_input="$(prompt 'Minutes to spare' "$DEFAULT_MINUTES")"; then
    log "minutes prompt failed or cancelled"
    notify critical "Albert Wesker" "Time prompt did not open."
    exit 1
  fi
  [[ -z "${minutes_input// }" ]] && exit 0
  if ! [[ "$minutes_input" =~ ^[0-9]+$ ]] || (( minutes_input <= 0 )); then
    notify critical "Albert Wesker" "That is not a valid number of minutes."
    exit 1
  fi

  update_waste

  now="$(now_epoch)"
  duration=$(( minutes_input * 60 ))
  end=$(( now + duration ))
  history_len="$(jq '.history | length' "$STATE_FILE")"
  id=$(( history_len + 1 ))

  json_set ".current = {id:$id, task:$(jq -Rn --arg v "$task_input" '$v'), duration_minutes:$minutes_input, duration_seconds:$duration, started_at:$(jq -Rn --arg v "$(now_iso)" '$v'), started_at_epoch:$now, ends_at_epoch:$end, quote:$(jq -Rn --arg v "$QUOTE" '$v')} | .last_idle_started_at = null"
  log "timer started task=$task_input minutes=$minutes_input"
  notify normal "Albert Wesker" "$QUOTE\nTask: $task_input\nTime: ${minutes_input} minutes"
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
  play_sound_loop
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
