#!/usr/bin/env bash
# awareness.sh — emit contextual warnings Claude (and the user) should see.
#
# Two channels:
#   cc_ram_threshold_check — PostToolUse nudge when a tracked process
#     crosses config.awareness.ram_threshold_kb (default 2 GB).
#     Rate-limited: one warning per below→above transition, via
#     ~/.claude/.processes/<session>.alerts.json.
#   cc_port_conflict_check — PreToolUse advisory when the incoming Bash
#     command looks like it will bind a port already held by another
#     tracked process.
# Both return plain text lines on stdout. cc_emit_context wraps them into
# the hook-response JSON Claude Code reads back into the conversation.

cc_alerts_file() { echo "${HOME}/.claude/.processes/${1}.alerts.json"; }

# cc_ram_threshold_check <session_id>
# Compare live tracked pids' RSS to config threshold. Emit a warning line
# only when a pid transitions from below to above the threshold.
cc_ram_threshold_check() {
  local session_id="$1"
  [ -z "$session_id" ] && return 0
  command -v jq >/dev/null 2>&1 || return 0

  local threshold
  threshold=$(cc_config_get '.awareness.ram_threshold_kb' 2097152)
  case "$threshold" in ''|*[!0-9]*) return 0 ;; esac
  [ "$threshold" -le 0 ] && return 0

  local alerts_file; alerts_file=$(cc_alerts_file "$session_id")
  local prev_json="{}"
  [ -f "$alerts_file" ] && prev_json=$(cat "$alerts_file" 2>/dev/null || echo "{}")
  local new_json="{}"

  local live_pids; live_pids=$(cc_session_live_pids "$session_id")
  [ -z "$live_pids" ] && return 0

  local p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    cc_is_alive "$p" || continue
    local rss
    rss=$(ps -o rss= -p "$p" 2>/dev/null | tr -d ' ')
    case "$rss" in ''|*[!0-9]*) continue ;; esac

    local was_over is_over="false"
    was_over=$(echo "$prev_json" | jq -r --arg k "$p" '.[$k] // false')
    [ "$rss" -gt "$threshold" ] && is_over="true"

    new_json=$(echo "$new_json" | jq --arg k "$p" --argjson v "$is_over" '. + {($k): $v}')

    if [ "$is_over" = "true" ] && [ "$was_over" != "true" ]; then
      local cmd; cmd=$(ps -o command= -p "$p" 2>/dev/null | head -c 60 | sed 's/^ *//')
      local rss_mb=$((rss / 1024))
      echo "⚠ claude-processes: pid $p ($cmd) crossed ${rss_mb} MB — consider 'claude-processes stash $p'"
    fi
  done <<< "$live_pids"

  # Persist alert state for next invocation
  mkdir -p "$(dirname "$alerts_file")" 2>/dev/null
  echo "$new_json" > "$alerts_file" 2>/dev/null || true
}

# cc_port_conflict_check <cmd>
# Parse <cmd> for port-binding patterns and warn if any of those ports are
# already held (LISTEN) by a tracked pid in any session.
cc_port_conflict_check() {
  local cmd="$1"
  [ -z "$cmd" ] && return 0
  command -v jq >/dev/null 2>&1 || return 0

  local enabled
  enabled=$(cc_config_get '.awareness.port_conflict_warn' true)
  [ "$enabled" != "true" ] && return 0

  local wanted_ports
  wanted_ports=$(cc_parse_ports_from_cmd "$cmd" | awk 'NF' | sort -u)
  [ -z "$wanted_ports" ] && return 0

  local s
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    local pids; pids=$(cc_session_live_pids "$s" 2>/dev/null)
    [ -z "$pids" ] && continue
    local p
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      local ports; ports=$(cc_listening_ports "$p")
      [ -z "$ports" ] && continue
      local wanted
      while IFS= read -r wanted; do
        [ -z "$wanted" ] && continue
        if echo ",$ports," | grep -q ",${wanted},"; then
          echo "⚠ claude-processes: port $wanted is already held by session ${s:0:6} (pid $p) — your command may fail to bind"
        fi
      done <<< "$wanted_ports"
    done <<< "$pids"
  done < <(cc_session_list)
}

# cc_emit_context <event_name>
# Read lines from stdin, wrap them into a Claude Code hook JSON response
# keyed at hookSpecificOutput.additionalContext. The event_name must match
# the firing hook (PreToolUse, PostToolUse, UserPromptSubmit, Stop, ...).
# Falls back to plain passthrough if jq is missing.
cc_emit_context() {
  local event_name="${1:-PostToolUse}"
  local content; content=$(cat)
  [ -z "$content" ] && return 0
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg c "$content" --arg e "$event_name" \
      '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}' 2>/dev/null \
      || echo "$content"
  else
    echo "$content"
  fi
}
