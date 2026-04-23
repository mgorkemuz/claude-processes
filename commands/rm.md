---
description: Delete a stashed snapshot without resuming it. Safe — does not affect running processes.
allowed-tools: Bash(shepherd:*)
---

Run `shepherd stash rm $ARGUMENTS`.

If `$ARGUMENTS` is empty, default to `--latest` (remove the most recent stash). Report which stash was deleted (id + command + when).

Valid argument forms: `<stash_id>`, `--latest`, `--all`. For `--all`, ask the user for confirmation first — it wipes every snapshot.
