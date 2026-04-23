---
description: Snapshot + kill this session's background processes to free RAM. Bring them back with /shepherd:unstash.
allowed-tools: Bash(shepherd:*)
---

Run `shepherd stash $ARGUMENTS`. If `$ARGUMENTS` is empty, default to `--current` — stash the background processes of the Claude session the user is currently in.

Report concisely:
1. Which processes were stashed (commands + stash IDs returned).
2. The RAM that's now freed and any ports that were released.
3. Remind the user: `/shepherd:unstash` (or `/shepherd:unstash <id>`) re-launches in the original cwd.
