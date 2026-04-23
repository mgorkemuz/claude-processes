#!/usr/bin/env bash
# track.sh — per-session tracking state in ~/.claude/.clean/<id>.json
#
# Schema:
# {
#   "session_id": "...",
#   "claude_pid": 12345,
#   "started_at": "2026-04-22T13:00:00Z",
#   "cwd": "/path",
#   "spawned": [
#     { "wrapper_pid": 56157, "command": "npm run dev",
#       "started_at": "...", "shell_snapshot": "snapshot-zsh-...-pqx4rs.sh",
#       "child_pids": [56165, 56207, 56208] }
#   ]
# }
#
# Concurrency: each hook appends to the spawned array. We rely on a short
# flock per write to avoid races between PreToolUse invocations.

CC_STATE_DIR="${CC_STATE_DIR:-$HOME/.claude/.clean}"

cc_state_dir() { echo "$CC_STATE_DIR"; }

cc_state_init() {
  mkdir -p "$CC_STATE_DIR"
}

cc_session_file() {
  echo "$CC_STATE_DIR/$1.json"
}

cc_have_jq() { command -v jq >/dev/null 2>&1; }

cc_iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# cc_with_lock <file> <command...>
# Run command while holding an exclusive lock on <file>.lock. Uses flock if
# present, otherwise a mkdir-based fallback (portable to stock macOS).
cc_with_lock() {
  local target="$1"; shift
  local lock="${target}.lock"
  if command -v flock >/dev/null 2>&1; then
    ( flock -x 9; "$@" ) 9>"$lock"
    return $?
  fi
  # mkdir-lock fallback
  local waited=0
  while ! mkdir "$lock" 2>/dev/null; do
    sleep 0.05
    waited=$((waited + 50))
    [ $waited -ge 2000 ] && break   # give up after 2s, proceed anyway
  done
  "$@"
  local rc=$?
  rmdir "$lock" 2>/dev/null || true
  return $rc
}

# cc_session_init <session_id> <claude_pid> <cwd>
# Create the tracking file. No-op if it exists.
cc_session_init() {
  cc_state_init
  local id="$1" pid="$2" cwd="$3"
  local f; f=$(cc_session_file "$id")
  [ -f "$f" ] && return 0
  cc_have_jq || return 1
  cc_with_lock "$f" bash -c '
    jq -n --arg id "$1" --argjson pid "$2" --arg cwd "$3" --arg ts "$4" \
      "{session_id:\$id, claude_pid:\$pid, started_at:\$ts, cwd:\$cwd, spawned:[]}" \
      > "$5"
  ' _ "$id" "$pid" "$cwd" "$(cc_iso_now)" "$f"
}

# cc_session_add_spawn <session_id> <wrapper_pid> <command> <snapshot> [child_pid...]
cc_session_add_spawn() {
  local id="$1"; shift
  local wrapper_pid="$1"; shift
  local command="$1"; shift
  local snapshot="$1"; shift
  local f; f=$(cc_session_file "$id")
  [ -f "$f" ] || return 1
  cc_have_jq || return 1

  # Build a JSON array of child pids from remaining args.
  local children_json="[]"
  if [ "$#" -gt 0 ]; then
    children_json=$(printf '%s\n' "$@" | jq -R 'tonumber? // empty' | jq -s .)
  fi

  cc_with_lock "$f" bash -c '
    tmp=$(mktemp)
    jq --argjson wp "$1" --arg cmd "$2" --arg snap "$3" --arg ts "$4" --argjson kids "$5" \
       ".spawned += [{wrapper_pid:\$wp, command:\$cmd, shell_snapshot:\$snap, started_at:\$ts, child_pids:\$kids}]" \
       "$6" > "$tmp" && mv "$tmp" "$6"
  ' _ "$wrapper_pid" "$command" "$snapshot" "$(cc_iso_now)" "$children_json" "$f"
}

# cc_session_list
# Echo all session IDs (one per line) that have tracking files.
cc_session_list() {
  cc_state_init
  local f
  for f in "$CC_STATE_DIR"/*.json; do
    [ -f "$f" ] || continue
    local base="${f##*/}"
    echo "${base%.json}"
  done
}

# cc_session_get <session_id>
# Print the raw JSON for the given session, or nothing if absent.
cc_session_get() {
  local f; f=$(cc_session_file "$1")
  [ -f "$f" ] && cat "$f"
}

# cc_session_all_pids <session_id>
# Echo every tracked PID for a session — both wrapper PIDs and child PIDs —
# one per line. Used by `kill --session`.
cc_session_all_pids() {
  local id="$1"
  local f; f=$(cc_session_file "$id")
  [ -f "$f" ] || return 0
  cc_have_jq || return 1
  jq -r '.spawned[]? | (.wrapper_pid, (.child_pids[]? // empty))' "$f" | awk 'NF'
}

# cc_session_claude_pid <session_id>
cc_session_claude_pid() {
  local f; f=$(cc_session_file "$1")
  [ -f "$f" ] || return 0
  cc_have_jq || return 1
  jq -r '.claude_pid' "$f"
}

# cc_session_cwd <session_id>
cc_session_cwd() {
  local f; f=$(cc_session_file "$1")
  [ -f "$f" ] || return 0
  cc_have_jq || return 1
  jq -r '.cwd' "$f"
}

# cc_session_delete <session_id>
cc_session_delete() {
  local f; f=$(cc_session_file "$1")
  rm -f "$f" "${f}.lock"
}
