#!/usr/bin/env bash
# test-config.sh — exercise lib/config.sh + lib/history.sh against a sandbox HOME.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
. "$ROOT/lib/track.sh"
. "$ROOT/lib/config.sh"
. "$ROOT/lib/history.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP"
mkdir -p "$TMP/.claude/.shepherd"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok: $*"; }

# ---- config -----------------------------------------------------------------

[ ! -f "$(cc_config_file)" ] || fail "config file pre-existing"
cc_config_init
[ -f "$(cc_config_file)" ] || fail "cc_config_init did not create file"
ok "cc_config_init created skeleton at $(cc_config_file)"

val=$(cc_config_get '.awareness.ram_threshold_kb')
[ "$val" = "2097152" ] || fail "expected 2097152, got '$val'"
ok "cc_config_get reads default .awareness.ram_threshold_kb = $val"

val=$(cc_config_get '.nonexistent.field' 'fallback')
[ "$val" = "fallback" ] || fail "expected 'fallback', got '$val'"
ok "cc_config_get returns default on missing key"

val=$(cc_config_get '.digest.enabled')
[ "$val" = "false" ] || fail "expected 'false', got '$val'"
ok "cc_config_get reads nested boolean correctly"

# Overwrite + re-read
tmp=$(mktemp)
jq '.awareness.ram_threshold_kb = 1000' "$(cc_config_file)" > "$tmp" && mv "$tmp" "$(cc_config_file)"
val=$(cc_config_get '.awareness.ram_threshold_kb')
[ "$val" = "1000" ] || fail "override not reflected: '$val'"
ok "cc_config_get picks up overrides"

# Before init: still returns defaults via fallback skeleton read
rm -f "$(cc_config_file)"
val=$(cc_config_get '.awareness.ram_threshold_kb')
[ "$val" = "2097152" ] || fail "pre-init default read expected 2097152, got '$val'"
ok "cc_config_get works pre-init via default skeleton"

# ---- history ----------------------------------------------------------------

[ ! -f "$(cc_history_file)" ] || fail "history file pre-existing"

cc_history_append spawned "s-abc" 12345 "npm run dev"
cc_history_append killed  "s-abc" 12345 "npm run dev" "user-kill" 8192

[ -f "$(cc_history_file)" ] || fail "history file not created"
lines=$(wc -l < "$(cc_history_file)")
[ "$lines" -eq 2 ] || fail "history expected 2 lines, got $lines"
ok "cc_history_append wrote 2 lines"

# Validate record structure
last=$(tail -1 "$(cc_history_file)")
echo "$last" | jq -e '.event == "killed" and .session_id == "s-abc" and .pid == 12345 and .reason == "user-kill" and .ram_kb == 8192' >/dev/null \
  || fail "last record unexpected shape: $last"
ok "history record structure correct ($last)"

# Rotation
cc_config_init
tmp=$(mktemp)
jq '.history.max_bytes = 200' "$(cc_config_file)" > "$tmp" && mv "$tmp" "$(cc_config_file)"
for i in $(seq 1 20); do
  cc_history_append spawned "s-rot" "$((10000 + i))" "padding-cmd-$i"
done
[ -f "$(cc_history_file).old" ] || fail "rotation did not create .old"
ok "cc_history_rotate moved file to .old at threshold"

echo "--- test-config: all passed ---"
