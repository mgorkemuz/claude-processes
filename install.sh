#!/usr/bin/env bash
# claude-clean installer. Idempotent — safe to re-run.
# Usage: ./install.sh [--prefix <dir>] [--no-path]
set -eu

# ---- paths ------------------------------------------------------------------

PREFIX="$HOME/.local"
NO_PATH=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#--prefix=}"; shift ;;
    --no-path) NO_PATH=1; shift ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--prefix <dir>] [--no-path]

  --prefix <dir>   Install root (default: ~/.local)
  --no-path        Skip updating shell rc for PATH
EOF
      exit 0 ;;
    *) echo "install.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

BIN_DIR="$PREFIX/bin"
SHARE_DIR="$PREFIX/share/claude-clean"
HOOKS_DEST="$HOME/.claude/hooks/claude-clean"
SETTINGS="$HOME/.claude/settings.json"

# ---- resolve source dir -----------------------------------------------------

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
for f in bin/claude-clean lib/detect.sh lib/tree.sh lib/kill.sh lib/track.sh \
         hooks/session-start.sh hooks/post-tool-use.sh hooks/stop.sh; do
  if [ ! -f "$SRC_DIR/$f" ]; then
    echo "install.sh: missing source file: $SRC_DIR/$f" >&2
    exit 1
  fi
done

# ---- preflight --------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  echo "install.sh: jq is required but not found on PATH." >&2
  echo "  macOS:  brew install jq" >&2
  echo "  Linux:  apt install jq   or   dnf install jq" >&2
  exit 1
fi

mkdir -p "$BIN_DIR" "$SHARE_DIR/lib" "$HOOKS_DEST" "$HOME/.claude" "$HOME/.claude/.clean"

# ---- copy binary + libs -----------------------------------------------------

cp "$SRC_DIR/bin/claude-clean" "$BIN_DIR/claude-clean"
chmod 755 "$BIN_DIR/claude-clean"

cp "$SRC_DIR/lib/detect.sh"  "$SHARE_DIR/lib/detect.sh"
cp "$SRC_DIR/lib/tree.sh"    "$SHARE_DIR/lib/tree.sh"
cp "$SRC_DIR/lib/kill.sh"    "$SHARE_DIR/lib/kill.sh"
cp "$SRC_DIR/lib/track.sh"   "$SHARE_DIR/lib/track.sh"

# ---- copy hooks -------------------------------------------------------------

cp "$SRC_DIR/hooks/session-start.sh"  "$HOOKS_DEST/session-start.sh"
cp "$SRC_DIR/hooks/post-tool-use.sh"  "$HOOKS_DEST/post-tool-use.sh"
cp "$SRC_DIR/hooks/stop.sh"           "$HOOKS_DEST/stop.sh"
chmod 755 "$HOOKS_DEST"/*.sh

# ---- merge hooks into ~/.claude/settings.json -------------------------------

# Backup first.
if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "${SETTINGS}.bak.$(date +%Y%m%d%H%M%S)"
else
  echo '{}' > "$SETTINGS"
fi

SS_HOOK="$HOOKS_DEST/session-start.sh"
PT_HOOK="$HOOKS_DEST/post-tool-use.sh"
ST_HOOK="$HOOKS_DEST/stop.sh"

tmp=$(mktemp)
# Strip any existing claude-clean hook entries (identified by command path
# containing "hooks/claude-clean/"), then append our entries.
jq \
  --arg ss "$SS_HOOK" --arg pt "$PT_HOOK" --arg st "$ST_HOOK" \
  '
  def strip_cc:
    if type == "array" then
      map(
        if (.hooks? | type == "array") then
          .hooks |= map(select((.command // "") | contains("hooks/claude-clean/") | not))
        else . end
      ) | map(select((.hooks? | length) > 0))
    else . end;

  .hooks //= {}
  | .hooks.SessionStart = ((.hooks.SessionStart // []) | strip_cc) + [
      {hooks: [{type: "command", command: $ss}]}
    ]
  | .hooks.PostToolUse = ((.hooks.PostToolUse // []) | strip_cc) + [
      {matcher: "Bash", hooks: [{type: "command", command: $pt}]}
    ]
  | .hooks.Stop = ((.hooks.Stop // []) | strip_cc) + [
      {hooks: [{type: "command", command: $st}]}
    ]
  ' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"

# ---- PATH integration -------------------------------------------------------

path_hint_added=0
add_path_line() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  if grep -q 'claude-clean PATH' "$rc" 2>/dev/null; then return 0; fi
  case ":$PATH:" in
    *":$BIN_DIR:"*) return 0 ;;  # already on PATH in current shell
  esac
  printf '\n# claude-clean PATH\ncase ":$PATH:" in *":%s:"*) ;; *) export PATH="%s:$PATH" ;; esac\n' \
    "$BIN_DIR" "$BIN_DIR" >> "$rc"
  path_hint_added=1
  echo "  added PATH line to $rc"
}

if [ "$NO_PATH" -eq 0 ]; then
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      # Prefer the shell the user is actually in.
      case "${SHELL:-}" in
        *zsh*) add_path_line "$HOME/.zshrc" ;;
        *bash*) [ -f "$HOME/.bashrc" ] && add_path_line "$HOME/.bashrc" || add_path_line "$HOME/.bash_profile" ;;
        *) add_path_line "$HOME/.zshrc" ;;
      esac
      ;;
  esac
fi

# ---- done -------------------------------------------------------------------

cat <<EOF

claude-clean installed.
  binary:    $BIN_DIR/claude-clean
  libs:      $SHARE_DIR/lib/
  hooks:     $HOOKS_DEST/
  settings:  $SETTINGS (merged)
  state:     $HOME/.claude/.clean/
EOF

if [ "$path_hint_added" -eq 1 ]; then
  echo
  echo "Restart your shell (or 'source ~/.zshrc' / '~/.bashrc') to pick up the PATH change."
fi

echo
echo "Try:  claude-clean status"
