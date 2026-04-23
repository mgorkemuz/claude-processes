#!/usr/bin/env bash
# Claude Code SessionStart hook — record session in tracking state.
# Plugin-bundled binary first, then fallbacks for shell-mode (v0.1.0) users.
# Errors never block Claude.
set -u
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -x "${CLAUDE_PLUGIN_ROOT}/bin/shepherd" ]; then
  exec "${CLAUDE_PLUGIN_ROOT}/bin/shepherd" hook session-start
fi
for p in "$HOME/.local/bin/shepherd" "/usr/local/bin/shepherd" "/opt/homebrew/bin/shepherd"; do
  if [ -x "$p" ]; then exec "$p" hook session-start; fi
done
if command -v shepherd >/dev/null 2>&1; then exec shepherd hook session-start; fi
exit 0
