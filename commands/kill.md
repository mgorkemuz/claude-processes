---
description: Terminate tracked background processes. Supports kill by pid, by session, or all orphans.
allowed-tools: Bash(claude-processes:*)
---

Run `claude-processes kill $ARGUMENTS`.

If `$ARGUMENTS` is empty, first run `claude-processes list` and ask the user which target they want to kill (a specific pid, `--session <id>`, or `--orphans`). Don't pick for them — this is destructive.

If arguments are provided, forward them unchanged and report what was terminated.
