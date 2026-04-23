#!/usr/bin/env bash
# claude-clean uninstaller. Removes every file install.sh put down, plus
# tracking state. Leaves shell rc entries alone (PATH is cheap to keep).
set -eu

PREFIX="$HOME/.local"
KEEP_STATE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#--prefix=}"; shift ;;
    --keep-state) KEEP_STATE=1; shift ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--prefix <dir>] [--keep-state]

  --prefix <dir>    Install root used at install time (default: ~/.local)
  --keep-state      Preserve ~/.claude/.clean/ tracking files
EOF
      exit 0 ;;
    *) echo "uninstall.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

BIN="$PREFIX/bin/claude-clean"
SHARE_DIR="$PREFIX/share/claude-clean"
HOOKS_DEST="$HOME/.claude/hooks/claude-clean"
SETTINGS="$HOME/.claude/settings.json"
STATE_DIR="$HOME/.claude/.clean"

rm -f "$BIN"
rm -rf "$SHARE_DIR"
rm -rf "$HOOKS_DEST"

# Strip our hook entries from settings.json.
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  cp "$SETTINGS" "${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
  tmp=$(mktemp)
  jq '
    def strip_cc:
      if type == "array" then
        map(
          if (.hooks? | type == "array") then
            .hooks |= map(select((.command // "") | contains("hooks/claude-clean/") | not))
          else . end
        ) | map(select((.hooks? | length) > 0))
      else . end;

    if .hooks? then
      .hooks.SessionStart = ((.hooks.SessionStart // []) | strip_cc)
      | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | strip_cc)
      | .hooks.Stop         = ((.hooks.Stop // [])         | strip_cc)
      | .hooks |= with_entries(select(.value | length > 0))
      | if (.hooks | length == 0) then del(.hooks) else . end
    else . end
  ' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
fi

if [ "$KEEP_STATE" -eq 0 ]; then
  rm -rf "$STATE_DIR"
fi

echo "claude-clean removed."
[ "$KEEP_STATE" -eq 1 ] && echo "  (tracking state preserved at $STATE_DIR)"
