#!/usr/bin/env bash
# test-awareness.sh — port-parser + RAM threshold + hook JSON wrapping.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

TMP=$(mktemp -d)
cleanup() {
  set +e
  rm -rf "$TMP" 2>/dev/null
  [ -n "${BG_PID:-}" ] && kill -9 "$BG_PID" 2>/dev/null
  return 0
}
trap cleanup EXIT
export HOME="$TMP"
export CC_STATE_DIR="$TMP/.claude/.shepherd"
mkdir -p "$CC_STATE_DIR"

. "$ROOT/lib/track.sh"
. "$ROOT/lib/detect.sh"
. "$ROOT/lib/tree.sh"
. "$ROOT/lib/kill.sh"
. "$ROOT/lib/config.sh"
. "$ROOT/lib/history.sh"
. "$ROOT/lib/portparse.sh"
. "$ROOT/lib/awareness.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok: $*"; }

cc_config_init

# -- cc_parse_ports_from_cmd -------------------------------------------------

assert_ports() {
  local want="$1" cmd="$2"
  local got; got=$(cc_parse_ports_from_cmd "$cmd" | awk 'NF' | sort -un | paste -sd, -)
  [ "$got" = "$want" ] || fail "parse: '$cmd' expected '$want' got '$got'"
  ok "parse: '$cmd' → $got"
}

assert_ports 3001       'next dev -p 3001'
assert_ports 3000       'next dev'
assert_ports 4000       'npm run dev -- --port 4000'
assert_ports 8000       'uvicorn app:api --port 8000'
assert_ports 9000       'python -m http.server 9000'
assert_ports 8000       'python3 -m http.server'         # default 8000
assert_ports 5173       'vite'
assert_ports 8080       'webpack serve --config foo.js'
assert_ports 4321       'astro dev'
assert_ports ''         'ls -la'
assert_ports ''         'grep -p pattern file'           # -p inside an unrelated word context

# -- cc_ram_threshold_check --------------------------------------------------

bash -c 'sleep 300' &
BG_PID=$!
sleep 0.2
SID="aware-$RANDOM"
cc_session_init "$SID" "$$" "$TMP/fake-project"
cc_session_add_spawn "$SID" "$BG_PID" "sleep 300" "" "$BG_PID"

# Force threshold to 1 KB so any process trips it on first check.
tmp=$(mktemp)
jq '.awareness.ram_threshold_kb = 1' "$(cc_config_file)" > "$tmp" && mv "$tmp" "$(cc_config_file)"

out=$(cc_ram_threshold_check "$SID")
echo "$out" | grep -q "pid $BG_PID" || fail "ram-check missed pid $BG_PID in '$out'"
echo "$out" | grep -q "stash"        || fail "ram-check didn't suggest stash: '$out'"
ok "ram_threshold_check warns on first crossing"

# Second call: state says already over, should be silent (rate-limited).
out2=$(cc_ram_threshold_check "$SID")
[ -z "$out2" ] || fail "ram-check should be silent on repeat: '$out2'"
ok "ram_threshold_check rate-limits repeat alerts"

# Alerts state file was written
alerts=$(cc_alerts_file "$SID")
[ -f "$alerts" ] || fail "alerts state file missing: $alerts"
ok "alerts state persisted at $alerts"

# -- cc_emit_context ---------------------------------------------------------

wrapped=$(echo "test warning line" | cc_emit_context)
echo "$wrapped" | jq -e '.hookSpecificOutput.additionalContext | contains("test warning line")' >/dev/null \
  || fail "cc_emit_context didn't wrap correctly: $wrapped"
ok "cc_emit_context wraps lines in hookSpecificOutput.additionalContext"

# Empty input → empty output
empty=$(printf '' | cc_emit_context)
[ -z "$empty" ] || fail "cc_emit_context should output nothing for empty input, got '$empty'"
ok "cc_emit_context is a no-op on empty input"

echo "--- test-awareness: all passed ---"
