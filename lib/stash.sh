#!/usr/bin/env bash
# stash.sh — snapshot a background process's command + cwd + filtered env,
# kill the tree (freeing RAM/ports), and later re-spawn it in the same cwd.
#
# Files:
#   ~/.claude/.processes/stashed/<8-hex>.json
#   /tmp/claude-processes-<8-hex>.log       (respawn stdout/stderr capture)

cc_stash_dir() { echo "${HOME}/.claude/.processes/stashed"; }

# Generate a random 8-hex stash id. /dev/urandom + od is portable.
cc_stash_new_id() {
  head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n'
}

# cc_capture_env <pid>
# Print a JSON object of env vars captured from <pid>, filtered by
# config.stash.env_allowlist (exact match) and env_allowlist_prefix.
# Never leaks secrets — allowlist-only. Returns "{}" on any error.
#
# Best-effort: macOS (Catalina+) restricts `ps -wwE` env display for
# security — this function returns {} there, and cc_respawn falls back
# to inheriting the current shell env. Linux /proc/<pid>/environ works
# fine for processes the user owns.
cc_capture_env() {
  local pid="$1"
  [ -z "$pid" ] && { echo "{}"; return; }
  command -v jq >/dev/null 2>&1 || { echo "{}"; return; }

  local raw=""
  if [ -r "/proc/$pid/environ" ]; then
    raw=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null)
  else
    # macOS: ps -wwE prints env tokens after the command. Extract KEY=VAL.
    raw=$(ps -wwE -o command= -p "$pid" 2>/dev/null | tr ' ' '\n' | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' || true)
  fi
  [ -z "$raw" ] && { echo "{}"; return; }

  local allow_items prefix_items
  allow_items=$(cc_config_get '.stash.env_allowlist' '[]' | jq -r '.[]' 2>/dev/null || echo "")
  prefix_items=$(cc_config_get '.stash.env_allowlist_prefix' '[]' | jq -r '.[]' 2>/dev/null || echo "")

  local filtered=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local key="${line%%=*}"
    local matched=0
    while IFS= read -r allowed; do
      [ -z "$allowed" ] && continue
      [ "$key" = "$allowed" ] && { matched=1; break; }
    done <<< "$allow_items"
    if [ "$matched" -eq 0 ]; then
      while IFS= read -r prefix; do
        [ -z "$prefix" ] && continue
        case "$key" in "$prefix"*) matched=1; break ;; esac
      done <<< "$prefix_items"
    fi
    [ "$matched" -eq 1 ] && filtered+="$line"$'\n'
  done <<< "$raw"

  if [ -z "$filtered" ]; then
    echo "{}"
  else
    printf '%s' "$filtered" | jq -R -s '
      split("\n") | map(select(length > 0))
      | map(capture("^(?<k>[^=]+)=(?<v>.*)$"))
      | map({key: .k, value: .v}) | from_entries
    ' 2>/dev/null || echo "{}"
  fi
}

# cc_tree_rss <pid>
# Sum RSS (KB) of <pid> and all its descendants. Stashing this reports
# what RAM the user will reclaim.
cc_tree_rss() {
  local root="$1"
  [ -z "$root" ] && { echo 0; return; }
  local total=0
  local p
  for p in "$root" $(cc_descendants "$root" | tr '\n' ' '); do
    [ -z "$p" ] && continue
    local r; r=$(ps -o rss= -p "$p" 2>/dev/null | tr -d ' ')
    case "$r" in ''|*[!0-9]*) continue ;; esac
    total=$((total + r))
  done
  echo "$total"
}

# cc_stash_create <pid>
# Snapshot <pid> to disk WITHOUT killing. Echoes the stash_id.
# Resolves cwd + command from tracked session first, falls back to live
# lsof/ps inspection. Captures tree RSS so digest can aggregate RAM freed.
cc_stash_create() {
  local pid="$1"
  [ -z "$pid" ] && return 1
  cc_is_alive "$pid" || { echo "pid $pid not alive" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || return 1

  mkdir -p "$(cc_stash_dir)"
  local stash_id; stash_id=$(cc_stash_new_id)
  local snap_file="$(cc_stash_dir)/${stash_id}.json"

  local session_id="" cwd="" command=""
  local s
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    local pids; pids=$(cc_session_all_pids "$s")
    if printf '%s\n' "$pids" | grep -qFx "$pid"; then
      session_id="$s"
      cwd=$(cc_session_cwd "$s")
      command=$(cc_session_get "$s" | jq -r --argjson p "$pid" \
        '.spawned[] | select(.wrapper_pid == $p or ((.child_pids // []) | index($p)) != null) | .command' 2>/dev/null | head -1)
      break
    fi
  done < <(cc_session_list)

  [ -z "$cwd" ]     && cwd=$(lsof -p "$pid" 2>/dev/null | awk '$4=="cwd" {print $NF}' | head -1)
  [ -z "$command" ] && command=$(ps -wwo command= -p "$pid" 2>/dev/null | sed 's/^ *//')

  local env_json; env_json=$(cc_capture_env "$pid")
  local tree_rss; tree_rss=$(cc_tree_rss "$pid")

  jq -n \
    --arg id "$stash_id" \
    --arg session "$session_id" \
    --arg pid "$pid" \
    --arg cwd "$cwd" \
    --arg command "$command" \
    --arg ts "$(cc_iso_now)" \
    --argjson env "$env_json" \
    --argjson rss "$tree_rss" \
    '{stash_id: $id, session_id: $session, origin_pid: ($pid | tonumber),
      cwd: $cwd, command: $command, env: $env,
      origin_ram_kb: $rss, stashed_at: $ts}' \
    > "$snap_file"

  echo "$stash_id"
}

# cc_stash_kill_target <pid>
# Snapshot + kill tree + history record. Echoes stash_id.
cc_stash_kill_target() {
  local pid="$1"
  local stash_id; stash_id=$(cc_stash_create "$pid") || return 1
  local snap_file="$(cc_stash_dir)/${stash_id}.json"
  local cwd cmd session ram_kb
  cwd=$(jq -r '.cwd // ""'            "$snap_file")
  cmd=$(jq -r '.command // ""'        "$snap_file")
  session=$(jq -r '.session_id // ""' "$snap_file")
  ram_kb=$(jq -r '.origin_ram_kb // 0' "$snap_file")

  local grace; grace=$(cc_config_get '.kill.grace_seconds' 3)
  cc_kill_tree "$pid" "$grace" || true
  cc_history_append stashed "$session" "$pid" "$cmd" "stash_id=$stash_id" "$ram_kb" 2>/dev/null || true
  echo "$stash_id"
}

# cc_stash_rm <stash_id>
# Remove a stash snapshot without respawning. Safe: no process is affected.
cc_stash_rm() {
  local id="$1"
  [ -z "$id" ] && return 1
  local f="$(cc_stash_dir)/${id}.json"
  [ -f "$f" ] || { echo "stash not found: $id" >&2; return 1; }
  rm -f "$f"
}

# cc_stash_rm_all
# Wipe every stash snapshot. Returns count removed.
cc_stash_rm_all() {
  local dir; dir=$(cc_stash_dir)
  [ -d "$dir" ] || { echo 0; return; }
  local count=0
  local f
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    rm -f "$f"
    count=$((count + 1))
  done
  echo "$count"
}

# cc_stash_latest — echo the stash_id of the most recently stashed snapshot.
# Empty when no stashes exist. Sorts by stashed_at ISO timestamp (lexicographic
# comparison is correct for the UTC Z format we emit).
cc_stash_latest() {
  local dir; dir=$(cc_stash_dir)
  [ -d "$dir" ] || return 0
  local best_ts="" best_id=""
  local f
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    local id ts
    id=$(jq -r '.stash_id // ""' "$f" 2>/dev/null)
    ts=$(jq -r '.stashed_at // ""' "$f" 2>/dev/null)
    [ -z "$id" ] && continue
    if [ -z "$best_ts" ] || [ "$ts" \> "$best_ts" ]; then
      best_ts="$ts"
      best_id="$id"
    fi
  done
  [ -n "$best_id" ] && echo "$best_id"
}

# cc_stash_list — tabular listing of stashed snapshots.
cc_stash_list() {
  local dir; dir=$(cc_stash_dir)
  [ -d "$dir" ] || { echo "No stashed snapshots."; return 0; }
  local files
  files=$(ls -1 "$dir"/*.json 2>/dev/null)
  [ -z "$files" ] && { echo "No stashed snapshots."; return 0; }
  printf '%-10s  %-36s  %-40s  %s\n' "STASH" "CWD" "COMMAND" "WHEN"
  local f
  while IFS= read -r f; do
    local id cwd cmd ts
    id=$(jq -r '.stash_id' "$f")
    cwd=$(jq -r '.cwd // ""' "$f")
    cmd=$(jq -r '.command // ""' "$f")
    ts=$(jq -r '.stashed_at // ""' "$f")
    [ "${#cwd}" -gt 36 ] && cwd="…${cwd: -35}"
    [ "${#cmd}" -gt 40 ] && cmd="${cmd:0:37}..."
    printf '%-10s  %-36s  %-40s  %s\n' "$id" "$cwd" "$cmd" "$ts"
  done <<< "$files"
}

# cc_respawn <stash_id> [--attach]
# Re-launch a stashed command in its original cwd with the filtered env.
# Echoes the new pid. With --attach, registers the new pid into the
# current Claude session's tracking.
cc_respawn() {
  local id="$1" mode="${2:-}"
  local f="$(cc_stash_dir)/${id}.json"
  [ -f "$f" ] || { echo "stash not found: $id" >&2; return 1; }
  local cwd cmd env_json session_from_snap
  cwd=$(jq -r '.cwd' "$f")
  cmd=$(jq -r '.command' "$f")
  env_json=$(jq -c '.env // {}' "$f")
  session_from_snap=$(jq -r '.session_id // ""' "$f")
  if [ -z "$cwd" ] || [ -z "$cmd" ]; then
    echo "stash missing cwd or command" >&2; return 1
  fi

  local env_args=()
  while IFS='=' read -r k v; do
    [ -z "$k" ] && continue
    env_args+=("$k=$v")
  done < <(printf '%s' "$env_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"' 2>/dev/null)

  local log_file="/tmp/claude-processes-${id}.log"
  local new_pid
  # exec inside a backgrounded subshell: the subshell's PID replaces itself
  # with env/nohup/bash, giving us a stable pid to return. Command-substitution
  # `$(... & echo $!)` is unreliable because $! points to an intermediate
  # process that exits mid exec chain.
  if [ "${#env_args[@]}" -gt 0 ]; then
    (cd "$cwd" && exec env -i "${env_args[@]}" nohup bash -c "$cmd" >"$log_file" 2>&1) < /dev/null &
  else
    (cd "$cwd" && exec nohup bash -c "$cmd" >"$log_file" 2>&1) < /dev/null &
  fi
  new_pid=$!
  disown 2>/dev/null || true

  [ -z "$new_pid" ] && { echo "respawn failed" >&2; return 1; }

  # Liveness check: wait briefly and confirm the respawned pid is still
  # alive. If it died immediately, surface the log tail and keep the stash
  # file so the user can retry or inspect.
  sleep 0.4
  if ! cc_is_alive "$new_pid"; then
    {
      echo "⚠ respawn of $id died within 400ms (pid was $new_pid)"
      echo "--- log tail ($log_file) ---"
      tail -n 20 "$log_file" 2>/dev/null | sed 's/^/  /'
      echo "--- /log tail ---"
      echo "stash kept at $(cc_stash_dir)/${id}.json — fix and retry unstash, or cc-rm it"
    } >&2
    return 1
  fi

  # Exported so cmd_unstash can report attach truthfully. Empty if attach
  # was requested but no session could be resolved.
  CC_RESPAWN_ATTACHED_TO=""
  if [ "$mode" = "--attach" ]; then
    local cur; cur=$(cc_discover_current_session)
    if [ -n "$cur" ]; then
      # Give the spawned command a brief moment to fork descendants
      # (npm → node → next-server) before we snapshot the tree.
      sleep 0.2
      local desc=()
      local d
      while IFS= read -r d; do
        [ -n "$d" ] && desc+=("$d")
      done < <(cc_descendants "$new_pid")
      if cc_session_add_spawn "$cur" "$new_pid" "$cmd" "" ${desc[@]+"${desc[@]}"} 2>/dev/null; then
        CC_RESPAWN_ATTACHED_TO="$cur"
      fi
    fi
  fi

  rm -f "$f"
  cc_history_append resumed "$session_from_snap" "$new_pid" "$cmd" "stash_id=$id" "" 2>/dev/null || true
  echo "$new_pid"
}

# cc_discover_current_session
# Returns the active Claude session id. Priority:
#   1. The authoritative marker file written by hook handlers on every
#      fire (cc_touch_current). Reliable because Claude Code hands us
#      session_id directly in the hook event payload.
#   2. PPID chain walk — for cases where cc_respawn is invoked from a
#      context where hooks haven't fired recently (unlikely).
#   3. Most-recently-modified live session file (last-resort fallback).
cc_discover_current_session() {
  # 1) hook-written marker
  local from_file; from_file=$(cc_read_current)
  if [ -n "$from_file" ] && [ -f "$(cc_session_file "$from_file")" ]; then
    echo "$from_file"; return 0
  fi

  # 2) PPID chain walk
  local p=$$ depth=0
  while [ "$p" -gt 1 ] && [ "$depth" -lt 10 ]; do
    local s
    while IFS= read -r s; do
      [ -z "$s" ] && continue
      local claude_pid; claude_pid=$(cc_session_claude_pid "$s")
      if [ "$claude_pid" = "$p" ]; then echo "$s"; return 0; fi
    done < <(cc_session_list)
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [ -z "$p" ] && return 0
    depth=$((depth + 1))
  done

  # 3) Most-recently-modified live session file
  local f best_m="" best_s=""
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    local cp; cp=$(cc_session_claude_pid "$s")
    cc_is_claude_alive "$cp" || continue
    f=$(cc_session_file "$s")
    local m; m=$(stat -f%m "$f" 2>/dev/null || stat -c%Y "$f" 2>/dev/null || echo 0)
    if [ -z "$best_m" ] || [ "$m" -gt "$best_m" ]; then
      best_m="$m"; best_s="$s"
    fi
  done < <(cc_session_list)
  [ -n "$best_s" ] && echo "$best_s"
}
