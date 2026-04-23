---
description: Re-launch a previously stashed process in its original cwd.
allowed-tools: Bash(claude-processes:*)
---

If `$ARGUMENTS` is empty, default to `claude-processes unstash --latest` — the most recent stash is almost always what the user wants back. Report which stash that was (command + cwd).

If the user gave a stash id, run `claude-processes unstash $ARGUMENTS` directly.

If the user passed `--attach`, note that the respawned process is now tracked in the current session.
