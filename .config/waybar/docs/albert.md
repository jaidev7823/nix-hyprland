Albert Wesker timer for Waybar

Goal
- Add a header timer inspired by Albert Wesker's line: "Seven minutes is all I can spare to play with you."
- Clicking the module should ask for a task, then ask how much time to spend.
- The timer should run in Waybar, play a repeating alert sound when time ends, and immediately push for the next task.
- Any time spent without an active task should be counted as waste.
- Persist everything in structured JSON.

Implemented
- Added custom Waybar module `custom/albert`.
- Added script `.config/hypr/scripts/albert_timer.sh`.
- Stores state in `.config/hypr/.local/albert-timer/state.json` by default.
- Tracks `current`, `history`, `waste_seconds`, `last_idle_started_at`, and `last_completed_at`.
- Uses `rofi` for prompts and `notify-send` for aggressive follow-up.

JSON structure
```json
{
  "version": 1,
  "current": null,
  "history": [],
  "waste_seconds": 0,
  "last_idle_started_at": null,
  "last_completed_at": null
}
```

Usage notes
- Left click the timer to start a round.
- The module updates every second.
- Default input time is `7` minutes.
- Override the alert sound with `ALBERT_TIMER_SOUND` if wanted.
- Reset saved state with `.config/hypr/scripts/albert_timer.sh reset`.
