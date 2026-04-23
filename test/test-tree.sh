#!/usr/bin/env bash
# test-tree.sh — spawn a parent/child/grandchild tree, verify walk and kill.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/lib/tree.sh"
. "$ROOT/lib/kill.sh"

fail() { echo "FAIL: $*" >&2; cleanup; exit 1; }
ok()   { echo "ok: $*"; }

PARENT_PID=""
cleanup() {
  [ -n "$PARENT_PID" ] && kill -9 "$PARENT_PID" 2>/dev/null || true
}
trap cleanup EXIT

# Spawn: parent bash -> child bash -> grandchild sleep
# The `; :` guards against bash's single-command tail-exec optimization —
# without it, the inner bash would exec sleep directly and the grandchild
# layer would collapse.
bash -c '
  bash -c "sleep 30; :" &
  wait
' &
PARENT_PID=$!
sleep 0.4

CHILD_PID=$(pgrep -P "$PARENT_PID" | head -1)
GRAND_PID=$(pgrep -P "$CHILD_PID" | head -1)

[ -n "$CHILD_PID" ] || fail "no child of $PARENT_PID"
[ -n "$GRAND_PID" ] || fail "no grandchild of $CHILD_PID"
ok "tree: parent=$PARENT_PID child=$CHILD_PID grand=$GRAND_PID"

# cc_children
kids=$(cc_children "$PARENT_PID")
[ "$kids" = "$CHILD_PID" ] || fail "cc_children expected $CHILD_PID got '$kids'"
ok "cc_children returns immediate child"

# cc_descendants: must include both child and grandchild
descendants=$(cc_descendants "$PARENT_PID" | sort)
expected=$(printf '%s\n%s\n' "$CHILD_PID" "$GRAND_PID" | sort)
[ "$descendants" = "$expected" ] || fail "cc_descendants mismatch: got '$descendants' want '$expected'"
ok "cc_descendants returns child + grandchild"

# cc_tree: includes root
tree=$(cc_tree "$PARENT_PID" | sort)
expected=$(printf '%s\n%s\n%s\n' "$PARENT_PID" "$CHILD_PID" "$GRAND_PID" | sort)
[ "$tree" = "$expected" ] || fail "cc_tree mismatch: got '$tree' want '$expected'"
ok "cc_tree includes root + descendants"

# cc_process_info: non-empty TSV for a live pid, empty for dead
info=$(cc_process_info "$GRAND_PID")
[ -n "$info" ] || fail "cc_process_info empty for live pid"
ok "cc_process_info: $(echo "$info" | cut -f1-4)"

# cc_format_rss
[ "$(cc_format_rss 512)"      = "512KB" ] || fail "cc_format_rss 512"
[ "$(cc_format_rss 8192)"     = "8MB"   ] || fail "cc_format_rss 8192"
[ "$(cc_format_rss 2097152)"  = "2.0GB" ] || fail "cc_format_rss 2097152"
ok "cc_format_rss buckets"

# cc_format_etime
[ "$(cc_format_etime 45)"       = "45s" ] || fail "cc_format_etime 45"
[ "$(cc_format_etime 13:00)"    = "13m" ] || fail "cc_format_etime 13:00"
[ "$(cc_format_etime 02:00:00)" = "2h"  ] || fail "cc_format_etime 02:00:00"
[ "$(cc_format_etime 01-00:00:00)" = "1d" ] || fail "cc_format_etime 1d"
ok "cc_format_etime buckets"

# cc_kill_tree: whole tree dies
cc_kill_tree "$PARENT_PID" 2 || fail "cc_kill_tree returned non-zero"
sleep 0.2
for p in "$PARENT_PID" "$CHILD_PID" "$GRAND_PID"; do
  if kill -0 "$p" 2>/dev/null; then fail "pid $p still alive after cc_kill_tree"; fi
done
PARENT_PID=""   # don't re-kill in cleanup
ok "cc_kill_tree terminated the whole tree"

echo "--- test-tree: all passed ---"
