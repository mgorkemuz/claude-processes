#!/usr/bin/env bash
# test-cleanup.sh — units parsers + digest aggregation.
# cleanup's interactive kill flow is exercised manually — too brittle to
# script reliably without a live TTY harness.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

TMP=$(mktemp -d)
cleanup() { set +e; rm -rf "$TMP"; return 0; }
trap cleanup EXIT
export HOME="$TMP"
export CC_STATE_DIR="$TMP/.claude/.shepherd"
mkdir -p "$CC_STATE_DIR"

. "$ROOT/lib/track.sh"
. "$ROOT/lib/config.sh"
. "$ROOT/lib/history.sh"
. "$ROOT/lib/units.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok: $*"; }

# --- cc_parse_duration -------------------------------------------------------

assert_dur() {
  local want="$1" in="$2"
  local got; got=$(cc_parse_duration "$in")
  [ "$got" = "$want" ] || fail "parse_duration '$in' expected '$want' got '$got'"
  ok "parse_duration '$in' → ${got}s"
}

assert_dur 30     30
assert_dur 30     30s
assert_dur 900    15m
assert_dur 14400  4h
assert_dur 172800 2d
assert_dur ""     hello
assert_dur ""     "15x"

# --- cc_parse_ram_size -------------------------------------------------------

assert_ram() {
  local want="$1" in="$2"
  local got; got=$(cc_parse_ram_size "$in")
  [ "$got" = "$want" ] || fail "parse_ram '$in' expected '$want' got '$got'"
  ok "parse_ram '$in' → ${got}kb"
}

assert_ram 512      512
assert_ram 512      512KB
assert_ram 512      512kb
assert_ram 2048     2MB
assert_ram 4194304  4GB
assert_ram ""       "4tb"
assert_ram ""       garbage

# --- cc_etime_to_seconds -----------------------------------------------------

assert_et() {
  local want="$1" in="$2"
  local got; got=$(cc_etime_to_seconds "$in")
  [ "$got" = "$want" ] || fail "etime '$in' expected '$want' got '$got'"
  ok "etime '$in' → ${got}s"
}

assert_et 45        45
assert_et 780       13:00
assert_et 7200      "02:00:00"
assert_et 86400     "01-00:00:00"
assert_et 90061     "01-01:01:01"

# --- cmd_digest: seed history + verify aggregation --------------------------

CLI="$ROOT/bin/shepherd"
cc_config_init

# Digest while disabled → should print opt-in message
out=$("$CLI" digest --since 7d)
echo "$out" | grep -qi "opt-in" || fail "digest didn't mention opt-in"
ok "digest disabled → prints opt-in hint"

# Enable
tmp=$(mktemp)
jq '.digest.enabled = true' "$(cc_config_file)" > "$tmp" && mv "$tmp" "$(cc_config_file)"

# Seed a few history events with recent timestamps
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
hfile=$(cc_history_file)
mkdir -p "$(dirname "$hfile")"
jq -cn --arg t "$ts" '{ts:$t, event:"spawned", session_id:"s-a", pid:101, command:"npm run dev"}' >> "$hfile"
jq -cn --arg t "$ts" '{ts:$t, event:"spawned", session_id:"s-a", pid:102, command:"next dev"}'    >> "$hfile"
jq -cn --arg t "$ts" '{ts:$t, event:"killed",  session_id:"s-a", pid:101, reason:"user", ram_kb:102400}' >> "$hfile"
jq -cn --arg t "$ts" '{ts:$t, event:"stashed", session_id:"s-b", pid:200, command:"vite"}'        >> "$hfile"
jq -cn --arg t "$ts" '{ts:$t, event:"resumed", session_id:"s-b", pid:201, command:"vite"}'        >> "$hfile"

out=$("$CLI" digest --since 30d)
echo "$out" | grep -qE "total events:[[:space:]]+5"  || fail "digest total != 5: $out"
echo "$out" | grep -qE "sessions:[[:space:]]+2"       || fail "digest sessions != 2: $out"
echo "$out" | grep -qE "spawned:[[:space:]]+2"        || fail "digest spawned != 2: $out"
echo "$out" | grep -qE "killed:[[:space:]]+1"         || fail "digest killed != 1: $out"
echo "$out" | grep -qE "stashed:[[:space:]]+1"        || fail "digest stashed != 1: $out"
echo "$out" | grep -qE "resumed:[[:space:]]+1"        || fail "digest resumed != 1: $out"
echo "$out" | grep -qE "RAM freed.*100 MB"            || fail "digest ram freed != 100MB: $out"
ok "digest aggregates spawned/killed/stashed/resumed + RAM freed"

# --since filter should exclude old events
old_ts="2020-01-01T00:00:00Z"
jq -cn --arg t "$old_ts" '{ts:$t, event:"spawned", session_id:"old", pid:999}' >> "$hfile"
out=$("$CLI" digest --since 1h)
echo "$out" | grep -qE "total events:[[:space:]]+5" || fail "--since 1h should still include the 5 recent: $out"
ok "digest --since filter excludes old events"

echo "--- test-cleanup: all passed ---"
