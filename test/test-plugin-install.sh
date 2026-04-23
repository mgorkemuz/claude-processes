#!/usr/bin/env bash
# test-plugin-install.sh — validate plugin manifest + hooks registration.
#
# Phase 0: xfails cleanly if `.claude-plugin/plugin.json` does not exist.
# Phase 1: real assertions run once the manifest + hooks.json are in place.
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { echo "ok: $*"; }
skip() { echo "skip: $*"; exit 0; }

command -v jq >/dev/null 2>&1 || fail "jq not installed"

MANIFEST="$ROOT/.claude-plugin/plugin.json"
HOOKS="$ROOT/hooks/hooks.json"

if [ ! -f "$MANIFEST" ]; then
  skip "plugin manifest not present yet (Phase 1 creates it) — expected at $MANIFEST"
fi

# ---- manifest ---------------------------------------------------------------

jq -e 'type == "object"' "$MANIFEST" >/dev/null || fail "manifest is not a JSON object"

for field in name version description; do
  val=$(jq -r --arg f "$field" '.[$f] // empty' "$MANIFEST")
  [ -n "$val" ] || fail "manifest missing required field: $field"
done
ok "manifest required fields (name, version, description) present"

name=$(jq -r '.name' "$MANIFEST")
[ "$name" = "claude-clean" ] || fail "manifest.name expected 'claude-clean', got '$name'"
ok "manifest.name = claude-clean"

version=$(jq -r '.version' "$MANIFEST")
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+' || fail "version '$version' not semver-like"
ok "manifest.version '$version' looks like semver"

# ---- hooks.json -------------------------------------------------------------

[ -f "$HOOKS" ] || fail "hooks registration missing at $HOOKS"

jq -e '.hooks' "$HOOKS" >/dev/null || fail "hooks.json has no .hooks root key"

for event in SessionStart PostToolUse Stop; do
  jq -e --arg e "$event" '.hooks[$e] | type == "array" and length > 0' "$HOOKS" >/dev/null \
    || fail "hooks.json missing or empty entry for $event"
done
ok "hooks.json registers SessionStart, PostToolUse, Stop"

# PostToolUse should have a Bash matcher
jq -e '.hooks.PostToolUse[] | select(.matcher == "Bash")' "$HOOKS" >/dev/null \
  || fail "PostToolUse entry missing matcher: \"Bash\""
ok "PostToolUse has Bash matcher"

# All hook commands should reference the scripts/ directory via ${CLAUDE_PLUGIN_ROOT}
jq -r '.hooks | to_entries[] | .value[] | .hooks[]? | .command // empty' "$HOOKS" | \
  while IFS= read -r cmd; do
    case "$cmd" in
      *'${CLAUDE_PLUGIN_ROOT}'*) : ;;
      "") continue ;;
      *) fail "hook command does not use \${CLAUDE_PLUGIN_ROOT}: $cmd" ;;
    esac
  done
ok "all hook commands reference \${CLAUDE_PLUGIN_ROOT}"

# ---- referenced scripts exist ----------------------------------------------

jq -r '.hooks | to_entries[] | .value[] | .hooks[]? | .command // empty' "$HOOKS" | \
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    rel="${cmd#*'${CLAUDE_PLUGIN_ROOT}'/}"
    [ -f "$ROOT/$rel" ] || fail "hook command targets missing script: $rel"
    [ -x "$ROOT/$rel" ] || fail "hook script not executable: $rel"
  done
ok "all referenced hook scripts exist and are executable"

echo "--- test-plugin-install: all passed ---"
