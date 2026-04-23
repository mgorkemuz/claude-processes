#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook — warn (via additionalContext) when
# the user is about to /clear or /new with tracked background processes
# still alive. Non-blocking; just surfaces the fact.
set -u
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -x "${CLAUDE_PLUGIN_ROOT}/bin/claude-processes" ]; then
  exec "${CLAUDE_PLUGIN_ROOT}/bin/claude-processes" hook user-prompt-submit
fi
for p in "$HOME/.local/bin/claude-processes" "/usr/local/bin/claude-processes" "/opt/homebrew/bin/claude-processes"; do
  if [ -x "$p" ]; then exec "$p" hook user-prompt-submit; fi
done
if command -v claude-processes >/dev/null 2>&1; then exec claude-processes hook user-prompt-submit; fi
exit 0
