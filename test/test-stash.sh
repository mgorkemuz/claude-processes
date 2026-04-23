#!/usr/bin/env bash
# test-stash.sh — end-to-end stash + respawn against synthetic processes.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

TMP=$(mktemp -d)
cleanup() {
  set +e
  rm -rf "$TMP" 2>/dev/null
  [ -n "${BG_PID:-}" ]  && kill -9 "$BG_PID"  2>/dev/null
  [ -n "${NEW_PID:-}" ] && kill -9 "$NEW_PID" 2>/dev/null
  return 0
}
trap cleanup EXIT
export HOME="$TMP"
export CC_STATE_DIR="$TMP/.claude/.shepherd"
mkdir -p "$CC_STATE_DIR"
mkdir -p "$TMP/fake-project"

. "$ROOT/lib/track.sh"
. "$ROOT/lib/detect.sh"
. "$ROOT/lib/tree.sh"
. "$ROOT/lib/kill.sh"
. "$ROOT/lib/config.sh"
. "$ROOT/lib/history.sh"
. "$ROOT/lib/stash.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok: $*"; }

cc_config_init

# Spawn a long-running fake dev server
bash -c 'sleep 600' &
BG_PID=$!
sleep 0.2
cc_is_alive "$BG_PID" || fail "bg pid not alive"
ok "spawned bg pid $BG_PID"

# Track it in a fake session
SID="stash-test-$RANDOM"
cc_session_init "$SID" "$$" "$TMP/fake-project"
# Store a real runnable command so respawn can actually re-exec it.
cc_session_add_spawn "$SID" "$BG_PID" "sleep 600" "" "$BG_PID"
ok "tracked as session $SID"

# --- cc_stash_kill_target: snapshot + kill in one shot ---
STASH_ID=$(cc_stash_kill_target "$BG_PID")
[ -n "$STASH_ID" ] || fail "cc_stash_kill_target returned empty"
ok "stashed as $STASH_ID"

sleep 0.4
kill -0 "$BG_PID" 2>/dev/null && fail "pid $BG_PID still alive after stash"
ok "original pid dead after stash"

# Snapshot file present + fields correct
SNAP="$(cc_stash_dir)/${STASH_ID}.json"
[ -f "$SNAP" ] || fail "snapshot file missing: $SNAP"
stored_cmd=$(jq -r '.command' "$SNAP")
stored_cwd=$(jq -r '.cwd' "$SNAP")
echo "$stored_cmd" | grep -q "sleep 600" || fail "stored command wrong: $stored_cmd"
[ "$stored_cwd" = "$TMP/fake-project" ] || fail "stored cwd wrong: $stored_cwd"
ok "snapshot contents: command='$stored_cmd' cwd='$stored_cwd'"

# List includes it
out=$(cc_stash_list)
echo "$out" | grep -q "$STASH_ID" || fail "stash list missing $STASH_ID"
ok "cc_stash_list includes $STASH_ID"

# --- stash snapshot captures origin_ram_kb ---
ram=$(jq -r '.origin_ram_kb // 0' "$SNAP")
case "$ram" in ''|*[!0-9]*) fail "origin_ram_kb not numeric: '$ram'" ;; esac
[ "$ram" -ge 0 ] || fail "origin_ram_kb negative: $ram"
ok "origin_ram_kb captured: $ram KB"

# --- stashed history event carries ram_kb ---
hist="$(cc_history_file)"
stashed_ram=$(grep '"event":"stashed"' "$hist" | tail -1 | jq -r '.ram_kb // 0')
case "$stashed_ram" in ''|*[!0-9]*) fail "stashed event ram_kb not numeric: '$stashed_ram'" ;; esac
ok "stashed history event carries ram_kb = $stashed_ram"

# --- cc_respawn: bring it back in the original cwd ---
NEW_PID=$(cc_respawn "$STASH_ID")
[ -n "$NEW_PID" ] || fail "cc_respawn returned empty"
sleep 0.5
kill -0 "$NEW_PID" 2>/dev/null || fail "new pid $NEW_PID not alive"
ok "respawned as pid $NEW_PID"

# Snapshot consumed
[ ! -f "$SNAP" ] || fail "snapshot still present after respawn"
ok "snapshot consumed after respawn"

# History captures both events
hist="$(cc_history_file)"
grep -q '"event":"stashed"' "$hist" || fail "no stashed event in history"
grep -q '"event":"resumed"' "$hist" || fail "no resumed event in history"
ok "history captured stashed + resumed events"

# --- cc_capture_env: filters by allowlist (best-effort on macOS) ---
# Modern macOS restricts ps -wwE env display for security. cc_capture_env
# degrades gracefully to {} and cc_respawn falls back to current env. We
# only assert structure + allowlist enforcement *if* any env is captured.
env_json=$(cc_capture_env "$NEW_PID")
echo "$env_json" | jq -e '. | type == "object"' >/dev/null || fail "env capture not a JSON object"
env_keys=$(echo "$env_json" | jq -r 'keys | length')
if [ "$env_keys" -gt 0 ]; then
  ok "cc_capture_env returned $env_keys allowlisted var(s)"
  # A non-allowlisted var (PWD) should NOT appear
  echo "$env_json" | jq -e '.PWD // empty' >/dev/null && fail "PWD leaked despite not being on allowlist"
  ok "cc_capture_env filtered out non-allowlisted vars"
else
  ok "cc_capture_env returned empty {} (expected on hardened macOS — respawn uses current env)"
fi

kill -9 "$NEW_PID" 2>/dev/null || true
NEW_PID=""

# --- cc_stash_rm / rm_all ---
# Seed a couple of dummy stashes
mkdir -p "$(cc_stash_dir)"
jq -cn '{stash_id:"dummy001",cwd:"/tmp",command:"x",env:{},stashed_at:"2026-01-01T00:00:00Z",origin_ram_kb:0}' > "$(cc_stash_dir)/dummy001.json"
jq -cn '{stash_id:"dummy002",cwd:"/tmp",command:"y",env:{},stashed_at:"2026-01-02T00:00:00Z",origin_ram_kb:0}' > "$(cc_stash_dir)/dummy002.json"
cc_stash_rm dummy001
[ ! -f "$(cc_stash_dir)/dummy001.json" ] || fail "cc_stash_rm didn't delete dummy001"
[ -f "$(cc_stash_dir)/dummy002.json" ]   || fail "cc_stash_rm over-reached to dummy002"
ok "cc_stash_rm removes one by id"

# Seed another, test rm_all
jq -cn '{stash_id:"dummy003",cwd:"/tmp",command:"z",env:{},stashed_at:"2026-01-03T00:00:00Z",origin_ram_kb:0}' > "$(cc_stash_dir)/dummy003.json"
count=$(cc_stash_rm_all)
[ "$count" -eq 2 ] || fail "cc_stash_rm_all count expected 2, got $count"
[ -z "$(ls -A "$(cc_stash_dir)" 2>/dev/null)" ] || fail "cc_stash_rm_all didn't clear the dir"
ok "cc_stash_rm_all removed $count stashes"

echo "--- test-stash: all passed ---"
