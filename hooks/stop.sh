#!/usr/bin/env bash
# Claude Code Stop hook — surface any background processes the ended
# session is leaving behind, plus the exact command to kill them.
set -u
for p in "$HOME/.local/bin/claude-clean" "/usr/local/bin/claude-clean" "/opt/homebrew/bin/claude-clean"; do
  if [ -x "$p" ]; then exec "$p" hook stop; fi
done
if command -v claude-clean >/dev/null 2>&1; then exec claude-clean hook stop; fi
exit 0
