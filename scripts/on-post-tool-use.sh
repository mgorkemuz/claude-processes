#!/usr/bin/env bash
# Claude Code PostToolUse hook (matcher: Bash) — capture persistent
# descendants of the Claude process after each Bash tool call.
#
# The wrapper doesn't exist yet when PreToolUse fires, so PostToolUse is
# the right moment to observe it — after spawn, before Claude tears down.
set -u
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -x "${CLAUDE_PLUGIN_ROOT}/bin/shepherd" ]; then
  exec "${CLAUDE_PLUGIN_ROOT}/bin/shepherd" hook post-tool-use
fi
for p in "$HOME/.local/bin/shepherd" "/usr/local/bin/shepherd" "/opt/homebrew/bin/shepherd"; do
  if [ -x "$p" ]; then exec "$p" hook post-tool-use; fi
done
if command -v shepherd >/dev/null 2>&1; then exec shepherd hook post-tool-use; fi
exit 0
