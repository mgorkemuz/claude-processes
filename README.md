# claude-processes

> Inspect and reclaim the background processes Claude Code's Bash tool leaves running.

A Claude Code plugin. Tracks `npm run dev`, `next dev`, `vitest --watch`, and every other long-running process the agent spawns. Surfaces them per session, kills them surgically, stashes them to free RAM, and nudges Claude when things grow out of control.

## The problem

Claude Code runs background commands through its Bash tool. When a session ends — `/clear`, a closed terminal, a crashed Claude — those children don't always die. On macOS they reparent to `launchd` and keep running: holding ports, eating RAM, accumulating across days. An orphaned `next dev` can grow past 8 GB.

Upstream issues confirming the problem: [anthropics/claude-code#43944](https://github.com/anthropics/claude-code/issues/43944), [#33947](https://github.com/anthropics/claude-code/issues/33947), [#33979](https://github.com/anthropics/claude-code/issues/33979), [#29011](https://github.com/anthropics/claude-code/issues/29011), [#22978](https://github.com/anthropics/claude-code/issues/22978), [#7069](https://github.com/anthropics/claude-code/issues/7069). No official fix shipped in 2+ years. This is the gap claude-processes fills.

## Install

As a Claude Code plugin (recommended):

```
/plugin install claude-processes
```

From a local clone for development:

```sh
claude --plugin-dir /path/to/claude-processes
```

After any plugin update: `/reload-plugins`.

Requires `jq`. macOS and Linux supported.

## Features

1. **Visibility** — `claude-processes list` groups tracked processes by Claude session, with ports, RSS, uptime, FD count, and a friendly dev-server label (`Next.js :3000`).
2. **Control** — `kill <pid> | --session <id> | --orphans` with a SIGTERM → grace → SIGKILL cascade. Surgical: killing session A never touches session B.
3. **Stash / Resume** — snapshot a session's background processes (command + cwd + allowlisted env) and kill them to free RAM; respawn later in the original cwd with a single command.
4. **Awareness** — PostToolUse RAM-threshold nudges (default 2 GB; rate-limited) and PreToolUse port-conflict warnings go back to Claude as `additionalContext` so the agent can reason about them.
5. **Cleanup + digest** — `cleanup --older-than 24h` / `--over-ram 2GB` with TTY confirmation and `--dry-run`; opt-in `digest` aggregates activity over the last N days.

## Commands

| Command | What it does |
|---|---|
| `claude-processes list [--session <id>] [--orphans]` | Tracked processes, grouped. |
| `claude-processes status` | One-line summary. |
| `claude-processes kill <pid \| --session <id> \| --orphans \| --all> [--grace <sec>]` | Terminate a tree; logs to history. |
| `claude-processes stash <pid \| --session <id> \| --current>` | Snapshot + kill. Frees RAM and ports. |
| `claude-processes stash list` | Show stashes with cwd, command, timestamp. |
| `claude-processes unstash <stash_id> [--attach]` | Respawn in the original cwd. `--attach` registers the new pid with the current session. |
| `claude-processes cleanup --older-than <dur> [--over-ram <size>] [--dry-run]` | Kill matching tracked processes after TTY confirm. |
| `claude-processes digest [--since <dur>]` | Aggregate history.jsonl (opt-in). |
| `claude-processes sessions` | List tracked session IDs. |
| `claude-processes version` | Print version. |

Each subcommand supports `--help`.

## Slash commands (from inside Claude)

Invoke with the namespaced form `/claude-processes:<name>` (TAB-completes after `/claude-p`).

| Command | Behavior |
|---|---|
| `/claude-processes:processes [args]` | Run `list`, narrate notable findings. |
| `/claude-processes:status`           | One-line sessions/processes/orphans count. |
| `/claude-processes:stash [args]`     | Default `--current`. Report what was stashed + RAM freed. |
| `/claude-processes:stashes`          | Show all saved snapshots (table). |
| `/claude-processes:unstash [stash_id]`| Default `--latest --attach`. Respawn in original cwd, attach to current session. |
| `/claude-processes:adopt <pid> [label]`| Register an externally-spawned pid as tracked (survived a Claude restart, started outside Claude, etc). |
| `/claude-processes:rm [args]`        | Default `--latest`. Delete a stash without resuming. |
| `/claude-processes:kill [args]`      | Terminate by pid / `--session` / `--orphans`. |
| `/claude-processes:cleanup [args]`   | Default `--dry-run --older-than 24h`. |

## Config

`~/.claude/.processes/config.json` — optional, defaults in effect if missing.

```json
{
  "version": 1,
  "awareness": {
    "ram_threshold_kb": 2097152,
    "ram_alert_once_per_crossing": true,
    "port_conflict_warn": true
  },
  "digest": { "enabled": false, "default_since": "7d" },
  "stash": {
    "env_allowlist": ["PATH", "NODE_ENV", "PORT", "NODE_OPTIONS"],
    "env_allowlist_prefix": ["X_", "APP_"]
  },
  "kill": { "grace_seconds": 3, "safe_pgid_leader": false },
  "notifications": { "macos_osascript": false },
  "history": { "max_bytes": 1048576 }
}
```

Edit with `jq` or by hand; no restart needed.

## How it works

Claude Code hooks drive the event stream. The plugin registers:

- **SessionStart** → record `session_id`, `cwd`, `claude_pid` in `~/.claude/.processes/<id>.json`.
- **PreToolUse** (Bash) → parse the incoming command for port-binding patterns; warn if another tracked session already holds one.
- **PostToolUse** (Bash) → walk the descendants of `claude_pid`, record any new persistent processes; run the RAM-threshold check.
- **Stop** → print a summary of still-running tracked processes with the exact kill command.

`list` intersects tracked PIDs with live `ps` output and walks each tracked PID's descendants, so it finds children the hook never saw directly (like `next-server` forked by `next dev`).

`kill` sends SIGTERM to the tree deepest-first, waits up to `kill.grace_seconds`, then SIGKILLs survivors.

`stash` reads the tracked command + cwd, captures allowlisted env vars (`ps -wwE` on macOS — may return `{}` due to recent hardening, falls back to inheriting current shell env; `/proc/<pid>/environ` on Linux), writes a snapshot to `~/.claude/.processes/stashed/<id>.json`, then kills. `unstash` respawns via `( ... & exec env -i ... nohup bash -c ... )` inside the original cwd.

Awareness hooks emit `{"hookSpecificOutput": {"additionalContext": "..."}}` so Claude sees the warnings in conversation context, not just on stderr.

## Relationship to cc-reaper

[theQuert/cc-reaper](https://github.com/theQuert/cc-reaper) solves a **different** problem: it cleans up Claude's own internal spawns (MCP servers, subagents). claude-processes targets the processes *you* told Claude to start in the background (`run_in_background: true`). They're safe to run side-by-side:

| | cc-reaper | claude-processes |
|---|---|---|
| Target | Claude's MCP/subagent leaks | User's backgrounded commands |
| Detection | PGID + `stream-json` pattern | Shell-snapshot signature + tracked state |
| Surgical per-session kill | No | Yes |
| Port / RAM / FD surfacing | Partial | Yes |
| Stash / resume | No | Yes |

Borrowed from cc-reaper with gratitude: the FD count, the TTY-filter orphan heuristic, the PGID-leader safety gate (opt-in via `config.kill.safe_pgid_leader`).

## Upgrading from v0.1.0

v0.1.0 was a shell-mode install (`./install.sh`). v0.2.0+ is a plugin. To migrate:

```sh
./uninstall.sh                    # removes ~/.local/bin/claude-processes, hook scripts, settings.json entries
/plugin install claude-processes
```

## Uninstall

Plugin users: `/plugin uninstall claude-processes`.

Legacy shell users: `./uninstall.sh` — clears the state dir unless you pass `--keep-state`.

## Testing

```sh
./test/test-detect.sh
./test/test-tree.sh
./test/test-plugin-install.sh
./test/test-config.sh
./test/test-stash.sh
./test/test-awareness.sh
./test/test-cleanup.sh
```

All tests spawn synthetic processes and verify against a sandbox `HOME`. Run `for t in test/*.sh; do $t; done` to regress everything in ~10 seconds.

## License

MIT. See [LICENSE](LICENSE).
