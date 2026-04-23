#!/usr/bin/env bash
# Claude Code PreToolUse hook (matcher: Bash) — warn Claude when the
# pending Bash command looks like it will bind a port already held by
# another tracked session. Advisory only; never blocks.
set -u
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -x "${CLAUDE_PLUGIN_ROOT}/bin/shepherd" ]; then
  exec "${CLAUDE_PLUGIN_ROOT}/bin/shepherd" hook pre-tool-use
fi
for p in "$HOME/.local/bin/shepherd" "/usr/local/bin/shepherd" "/opt/homebrew/bin/shepherd"; do
  if [ -x "$p" ]; then exec "$p" hook pre-tool-use; fi
done
if command -v shepherd >/dev/null 2>&1; then exec shepherd hook pre-tool-use; fi
exit 0
