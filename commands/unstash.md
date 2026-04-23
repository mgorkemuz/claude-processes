---
description: Re-launch a previously stashed process in its original cwd.
allowed-tools: Bash(claude-processes:*)
---

If `$ARGUMENTS` is empty, default to `claude-processes unstash --latest --attach` — respawn the most recent stash AND register it with the current session so it keeps showing up in `/claude-processes:processes`. Report which stash that was (command + cwd).

If the user gave a stash id, default to `claude-processes unstash $ARGUMENTS --attach` unless they explicitly passed `--no-attach` or their args already include `--attach`. Attaching is almost always what you want — without it, `/processes` won't see the respawned pid.

After respawn, remind the user the pid is now tracked under this session (so `/claude-processes:processes` will list it and `/claude-processes:stash` can snapshot it again).
