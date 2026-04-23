#!/usr/bin/env bash
# test-detect.sh — verify the ps-signature scanner finds a synthetic wrapper
# and walks its descendants.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/lib/detect.sh"
. "$ROOT/lib/tree.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok: $*"; }

# 1. Fabricate a wrapper-looking process. We can't easily exec /bin/zsh with
# the exact Claude args, so we build a process whose argv contains the
# signature substring via bash -c.
snap_id="snapshot-zsh-$(date +%s)000-testab.sh"
fake_src="/Users/nobody/.claude/shell-snapshots/$snap_id"
# The wrapper sleeps, holding its argv (with the signature) on display for
# ps. Don't use `exec sleep` — it replaces argv and the signature disappears.
/bin/bash -c "source $fake_src 2>/dev/null || true; sleep 30" &
WRAPPER_PID=$!
sleep 0.3

# detect.sh looks for the signature in the command column. On macOS the
# comment "source .../shell-snapshots/snapshot-zsh-..." lives on argv,
# so `ps ... command=` shows it.
found=$(cc_find_wrappers | awk -F'\t' -v p="$WRAPPER_PID" '$1 == p')
if [ -z "$found" ]; then
  # Clean up, then fail — detection didn't see our signature
  kill -9 "$WRAPPER_PID" 2>/dev/null || true
  fail "cc_find_wrappers did not see pid $WRAPPER_PID (ps line: $(ps -o command= -p $WRAPPER_PID 2>/dev/null))"
fi
ok "cc_find_wrappers saw wrapper $WRAPPER_PID"

# Parse output: pid ppid snap cmd
pid=$(cut -f1 <<< "$found")
ppid=$(cut -f2 <<< "$found")
snap=$(cut -f3 <<< "$found")
[ "$pid" = "$WRAPPER_PID" ] || fail "pid mismatch: got $pid"
[ "$ppid" = "$$" ] || fail "ppid mismatch: got $ppid, expected $$"
[ "$snap" = "$snap_id" ] || fail "snap id mismatch: got '$snap' expected '$snap_id'"
ok "parsed fields (pid=$pid ppid=$ppid snap=$snap)"

# 2. cc_find_wrappers_for_claude filters by PPID
filtered=$(cc_find_wrappers_for_claude "$$" | awk -F'\t' -v p="$WRAPPER_PID" '$1 == p')
[ -n "$filtered" ] || fail "cc_find_wrappers_for_claude $$ missed the wrapper"
ok "cc_find_wrappers_for_claude filters by claude_pid"

# 3. cc_is_alive / dead
cc_is_alive "$WRAPPER_PID" || fail "cc_is_alive false for live pid"
ok "cc_is_alive true for live pid"

# Clean up.
kill "$WRAPPER_PID" 2>/dev/null || true
sleep 0.3
kill -9 "$WRAPPER_PID" 2>/dev/null || true

sleep 0.2
cc_is_alive "$WRAPPER_PID" && fail "cc_is_alive true for dead pid"
ok "cc_is_alive false for dead pid"

echo "--- test-detect: all passed ---"
