#!/usr/bin/env bash
# Claude Code SessionStart hook — record session in tracking state.
# Fails silently: hook errors must never block Claude.
set -u
for p in "$HOME/.local/bin/claude-clean" "/usr/local/bin/claude-clean" "/opt/homebrew/bin/claude-clean"; do
  if [ -x "$p" ]; then exec "$p" hook session-start; fi
done
if command -v claude-clean >/dev/null 2>&1; then exec claude-clean hook session-start; fi
exit 0
