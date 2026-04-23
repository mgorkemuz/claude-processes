#!/usr/bin/env bash
# detect.sh — identify Claude-spawned shell wrappers from `ps`.
#
# Claude Code wraps every Bash tool call in:
#   /bin/zsh -c source <SHELL_SNAPSHOT> 2>/dev/null || true && setopt NO_EXTENDED_GLOB ... && eval '<user-cmd>' ... pwd -P >| /tmp/claude-<id>-cwd
# The path fragment "shell-snapshots/snapshot-zsh-" is the stable signature.
# The wrapper is usually short-lived — detection by signature only finds
# in-flight Bash tool calls. Backgrounded children must be tracked separately
# (see lib/track.sh).

CC_WRAPPER_SIGNATURE='shell-snapshots/snapshot-zsh-'

# cc_find_wrappers
# Print currently-running wrapper PIDs, one per line, along with their
# parent PID (the Claude process) and the snapshot id.
# Output format: <wrapper_pid>\t<claude_pid>\t<snapshot_id>\t<eval_cmd>
cc_find_wrappers() {
  # -ww disables column truncation on macOS/Linux ps
  # lstart would be nice but has spaces — skip it here, tree.sh has etime
  ps -ww -eo pid=,ppid=,command= 2>/dev/null | \
    awk -v sig="$CC_WRAPPER_SIGNATURE" '
      index($0, sig) > 0 {
        pid = $1; ppid = $2
        # Extract snapshot id: match snapshot-zsh-<digits>-<alnum>.sh
        snap = ""
        if (match($0, /snapshot-zsh-[0-9]+-[a-zA-Z0-9]+\.sh/)) {
          snap = substr($0, RSTART, RLENGTH)
        }
        # Extract the eval payload (single-quoted, first occurrence)
        cmd = ""
        m = index($0, "eval '\''")
        if (m > 0) {
          rest = substr($0, m + 6)
          end = index(rest, "'\''")
          if (end > 0) cmd = substr(rest, 1, end - 1)
        }
        printf "%s\t%s\t%s\t%s\n", pid, ppid, snap, cmd
      }'
}

# cc_find_wrappers_for_claude <claude_pid>
# Print only wrappers whose PPID matches the given Claude process PID.
cc_find_wrappers_for_claude() {
  local claude_pid="$1"
  cc_find_wrappers | awk -F'\t' -v cp="$claude_pid" '$2 == cp'
}

# cc_claude_pids
# Print PIDs of currently-running Claude Code processes (the TUI itself).
# Used for determining which sessions are active vs. orphaned.
cc_claude_pids() {
  # The Claude Code CLI binary is typically launched as "claude" or node ...
  # We identify it indirectly: any process that is the PPID of a detected
  # wrapper is (was) a Claude process. This avoids matching unrelated "claude"
  # binaries in PATH.
  cc_find_wrappers | awk -F'\t' '{print $2}' | sort -u
}

# cc_is_claude_alive <claude_pid>
# Return 0 if the given Claude PID is still running.
cc_is_claude_alive() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}
