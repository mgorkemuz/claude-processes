---
description: Show all saved stash snapshots with their command, cwd, and timestamp.
allowed-tools: Bash(shepherd:*)
---

Run `shepherd stash list` and present the table. For each stash, note the command and how long ago it was stashed. If there are many, suggest the user can `/shepherd:unstash` (loads the latest) or `/shepherd:rm --all` to clean up.
