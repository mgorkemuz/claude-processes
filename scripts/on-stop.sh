#!/usr/bin/env bash
# Claude Code Stop hook — surface any background processes the ended
# session is leaving behind, plus the exact command to kill them.
set -u
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -x "${CLAUDE_PLUGIN_ROOT}/bin/shepherd" ]; then
  exec "${CLAUDE_PLUGIN_ROOT}/bin/shepherd" hook stop
fi
for p in "$HOME/.local/bin/shepherd" "/usr/local/bin/shepherd" "/opt/homebrew/bin/shepherd"; do
  if [ -x "$p" ]; then exec "$p" hook stop; fi
done
if command -v shepherd >/dev/null 2>&1; then exec shepherd hook stop; fi
exit 0
