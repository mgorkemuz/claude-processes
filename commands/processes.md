---
description: List background processes Claude has spawned across all tracked sessions.
allowed-tools: Bash(claude-clean list:*), Bash(claude-clean status:*)
---

Run `claude-clean list $ARGUMENTS` and report what's currently tracked, grouped by Claude session. Highlight:

- Any **orphans** (processes whose originating Claude is no longer alive).
- Any process using more than **2 GB of RAM**.
- Any process holding a port (surface the URL if a dev server was detected).

If `$ARGUMENTS` is empty, show everything. If the user passed `--orphans` or `--session <id>`, forward it unchanged. At the end, offer concrete next steps the user can take — `/stash` to free RAM, `claude-clean kill --session <id>` to terminate, or "everything looks clean" if nothing notable.
