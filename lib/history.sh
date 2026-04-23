#!/usr/bin/env bash
# history.sh — append-only JSONL log of claude-clean actions.
# One JSON object per line. Used by `cmd_digest` for weekly summaries and
# by humans via `jq -c '.' ~/.claude/.clean/history.jsonl`.
#
# Event types:
#   spawned   — PostToolUse captured a new tracked process
#   killed    — cmd_kill terminated a tree
#   stashed   — Phase 4: cc_stash_kill_target snapshotted + killed
#   resumed   — Phase 4: cc_respawn re-launched a stashed command
#   orphaned  — Phase 6: detected at digest time

cc_history_file() { echo "${HOME}/.claude/.clean/history.jsonl"; }

# cc_history_append <event_type> <session_id> [pid] [command] [reason] [ram_kb]
# Locked append. Silent no-op if jq missing or write fails — history must
# never block real work.
cc_history_append() {
  command -v jq >/dev/null 2>&1 || return 0
  local event="$1" session="${2:-}" pid="${3:-}" cmd="${4:-}" reason="${5:-}" ram="${6:-}"
  [ -z "$event" ] && return 0
  local f; f=$(cc_history_file)
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0

  local record
  record=$(jq -cn \
    --arg ts "$(cc_iso_now)" \
    --arg event "$event" \
    --arg session "$session" \
    --arg pid "$pid" \
    --arg cmd "$cmd" \
    --arg reason "$reason" \
    --arg ram "$ram" \
    '{ts: $ts, event: $event, session_id: $session}
     + (if $pid == ""    then {} else {pid: ($pid | tonumber? // $pid)} end)
     + (if $cmd == ""    then {} else {command: $cmd} end)
     + (if $reason == "" then {} else {reason: $reason} end)
     + (if $ram == ""    then {} else {ram_kb: ($ram | tonumber? // 0)} end)
    ' 2>/dev/null) || return 0

  cc_with_lock "$f" bash -c 'printf "%s\n" "$1" >> "$2"' _ "$record" "$f" || return 0
  cc_history_rotate
}

# cc_history_rotate — if history exceeds config.history.max_bytes, move to .old.
cc_history_rotate() {
  local f; f=$(cc_history_file)
  [ -f "$f" ] || return 0
  local max_bytes
  max_bytes=$(cc_config_get '.history.max_bytes' 1048576)
  local size
  # macOS stat -f%z; Linux stat -c%s.
  size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
  if [ "$size" -gt "$max_bytes" ]; then
    mv "$f" "${f}.old" 2>/dev/null || true
  fi
}
