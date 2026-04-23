---
description: Terminate tracked background processes. Supports kill by pid, by session, or all orphans.
allowed-tools: Bash(shepherd:*)
---

Run `shepherd kill $ARGUMENTS`.

If `$ARGUMENTS` is empty, the CLI defaults to killing the **latest tracked process tree** (most recent started_at, still alive). Forward the empty args and report which tree was killed plus what the user can do next (e.g., `/shepherd:kill --all` for everything, `/shepherd:unstash` to bring back something recently stashed).

If arguments are provided, forward them unchanged and report what was terminated.
