---
description: Show all saved stash snapshots with their command, cwd, and timestamp.
allowed-tools: Bash(claude-processes:*)
---

Run `claude-processes stash list` and present the table. For each stash, note the command and how long ago it was stashed. If there are many, suggest the user can `/claude-processes:unstash` (loads the latest) or `/claude-processes:rm --all` to clean up.
