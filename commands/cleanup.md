---
description: Kill tracked processes older than a duration or using more than a RAM size. Safe by default.
allowed-tools: Bash(shepherd:*)
---

If `$ARGUMENTS` is empty, default to a safe preview: `--dry-run --older-than 24h`.

Run `shepherd cleanup $ARGUMENTS` and report:
1. Which processes match and why (age or RAM).
2. The session each one came from.
3. If the user passed `--dry-run`, remind them how to actually kill (re-run without the flag).

If the user asked to kill without `--dry-run`, the CLI will prompt on the TTY for confirmation — relay that exchange; don't try to answer on the user's behalf.
