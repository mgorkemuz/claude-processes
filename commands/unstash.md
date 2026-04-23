---
description: Re-launch a previously stashed process in its original cwd.
allowed-tools: Bash(shepherd:*)
---

If `$ARGUMENTS` is empty, default to `shepherd unstash --latest --attach` — respawn the most recent stash AND register it with the current session so it keeps showing up in `/shepherd:processes`. Report which stash that was (command + cwd).

If the user gave a stash id, default to `shepherd unstash $ARGUMENTS --attach` unless they explicitly passed `--no-attach` or their args already include `--attach`. Attaching is almost always what you want — without it, `/processes` won't see the respawned pid.

After respawn, remind the user the pid is now tracked under this session (so `/shepherd:processes` will list it and `/shepherd:stash` can snapshot it again).
