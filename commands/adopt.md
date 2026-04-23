---
description: Register an externally-spawned pid as tracked in the current session (processes from a previous Claude, from another terminal, etc).
allowed-tools: Bash(claude-processes:*)
---

Run `claude-processes adopt $ARGUMENTS`.

If `$ARGUMENTS` is empty, ask the user which pid to adopt (and optionally a command label for nicer display).

Use cases to surface to the user:
- A dev server from a previous Claude Code session that's still running.
- A process started in another terminal that the user now wants to stash/track from here.
- A respawned stash from a pre-0.5.1 build where `--attach` wasn't the default.

After adoption, the pid shows up in `/shepherd:processes` and can be stash'd, killed, or cleanup-filtered like any natively-tracked process.
