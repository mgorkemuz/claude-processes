#!/usr/bin/env bash
# kill.sh — graceful tree termination: SIGTERM, wait, then SIGKILL stragglers.

# cc_kill_tree <pid> [grace_seconds]
# Send SIGTERM to <pid> and all its descendants (deepest first so parents
# don't respawn children). Wait up to grace_seconds (default 3), then SIGKILL
# any survivors. Returns 0 if the whole tree is dead, 1 otherwise.
cc_kill_tree() {
  local root="$1"
  local grace="${2:-3}"
  [ -z "$root" ] && return 1

  # Collect tree (including root) before we start killing — list changes
  # as processes exit.
  local pids
  pids=$(cc_tree "$root")
  [ -z "$pids" ] && return 0

  # Reverse order: deepest first. cc_tree emits root first, then BFS, so
  # simply reversing line order gives us leaves-first.
  local reversed
  reversed=$(printf '%s\n' "$pids" | awk '{ a[NR]=$0 } END { for (i=NR;i>=1;i--) print a[i] }')

  local pid
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    kill -TERM "$pid" 2>/dev/null || true
  done <<< "$reversed"

  # Wait for the tree to die, checking every 100ms up to grace seconds.
  local waited=0
  local deadline_ms=$((grace * 1000))
  while [ "$waited" -lt "$deadline_ms" ]; do
    local alive=0
    while IFS= read -r pid; do
      [ -z "$pid" ] && continue
      if cc_is_alive "$pid"; then alive=1; break; fi
    done <<< "$reversed"
    [ "$alive" -eq 0 ] && return 0
    sleep 0.1
    waited=$((waited + 100))
  done

  # SIGKILL survivors.
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    cc_is_alive "$pid" && kill -KILL "$pid" 2>/dev/null || true
  done <<< "$reversed"

  # Final check.
  sleep 0.2
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    if cc_is_alive "$pid"; then return 1; fi
  done <<< "$reversed"
  return 0
}
