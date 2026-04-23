---
description: Re-launch a previously stashed process in its original cwd.
allowed-tools: Bash(claude-clean:*)
---

If `$ARGUMENTS` is empty, run `claude-clean stash list` first and ask the user which snapshot to resume.

Otherwise run `claude-clean unstash $ARGUMENTS` and report the new pid + log file. If the user passed `--attach`, note that the respawned process is now tracked in the current session.
