# shepherd

> Track, preserve, and clean up the background processes Claude Code's Bash tool leaves running.

A Claude Code plugin. It watches every `npm run dev`, `next dev`, `vitest --watch`, or long-running command Claude starts in the background, remembers which session spawned it, and gives you single-line controls to stash it, kill it, or bring it back later. When Claude crashes and leaves processes behind, shepherd cleans them automatically on the next launch.

## The problem

Claude Code runs background commands through its Bash tool. When a session ends — `/clear`, a closed terminal, a crashed Claude — those children don't always die. On macOS they reparent to `launchd` and keep running: holding ports, eating RAM, accumulating across days. An orphaned `next dev` can grow past 8 GB.

Upstream issues tracking this: [anthropics/claude-code#43944](https://github.com/anthropics/claude-code/issues/43944), [#33947](https://github.com/anthropics/claude-code/issues/33947), [#33979](https://github.com/anthropics/claude-code/issues/33979), [#29011](https://github.com/anthropics/claude-code/issues/29011), [#22978](https://github.com/anthropics/claude-code/issues/22978), [#7069](https://github.com/anthropics/claude-code/issues/7069). No official fix in 2+ years. shepherd fills the gap.

## Install

```
/plugin marketplace add mgorkemuz/claude-code-shepherd
/plugin install shepherd@shepherd
```

From a local clone for development:

```sh
claude --plugin-dir /path/to/claude-code-shepherd
```

After any plugin update: `/reload-plugins`.

Requires `jq`. macOS and Linux supported.

## How it actually helps

- **Only tracks what Claude spawned.** Uses the Bash tool's shell-snapshot signature to tell Claude-spawned processes apart from processes you started yourself. Kill commands are surgical — they can't touch things outside Claude's tree.
- **Per-session grouping.** Multiple Claude sessions (tmux teammates, background agents) each get their own tracked list. `kill --session <id>` never spills into another session.
- **Orphan detection.** Processes whose originating Claude is dead show up under their own block in `list`.
- **Auto-clean on next launch.** If Claude crashes (SIGKILL, terminal closed hard, OOM), the `SessionStart` hook on the next Claude launch wipes orphans from the crashed session. Default **on** — orphans are residue by definition. Concurrent sessions are safe: their Claude pid is still alive, so they're not orphans.
- **Stash/unstash.** Snapshot a dev server (command + cwd + safe env), kill it to free RAM, respawn later in the original cwd with one command. Like "pause" across a `/clear`.
- **Port-conflict warnings.** Before a Bash command with `next dev` / `vite` / `uvicorn`, shepherd checks if the port is already held by a tracked process and nudges Claude via `systemMessage`.
- **RAM threshold nudges.** When a tracked process crosses 2 GB, shepherd emits `additionalContext` so Claude can suggest stashing in-conversation.

## Slash commands

Invoke from inside Claude with `/shepherd:<name>` (TAB-completes after `/shep`).

| Command | What it does | Default (no args) |
|---|---|---|
| `/shepherd:processes` | Tracked processes grouped by session, with ports, RAM, uptime, FD count, dev-server label. | Show everything (active + orphans). |
| `/shepherd:status` | One-line count: sessions, processes, orphans. | — |
| `/shepherd:stash` | Snapshot + kill background processes. Frees RAM and ports. | `--current` — this session's processes. |
| `/shepherd:stashes` | Table of saved stash snapshots. | — |
| `/shepherd:unstash` | Respawn a stash in its original cwd. | `--latest --attach` — most recent stash, track it in this session. |
| `/shepherd:rm` | Delete a stash without respawning. | `--latest` |
| `/shepherd:kill` | Terminate a process tree. | Kill the most recently-spawned tracked tree. |
| `/shepherd:cleanup` | Kill processes older than a duration or using too much RAM. | `--older-than 24h --dry-run` — safe preview. |
| `/shepherd:adopt <pid>` | Register an externally-spawned pid as tracked (previous Claude, terminal-started, etc). | pid required |

All commands accept arguments that get forwarded to the CLI. E.g. `/shepherd:kill --all`, `/shepherd:stash --session <id>`, `/shepherd:cleanup --over-ram 2GB`.

## Typical flows

Switching projects without losing your dev server:

```
/shepherd:stash         → snapshot npm run dev + kill it, port 3000 freed
/clear                  → new Claude conversation
…                       → work on something else
/shepherd:unstash       → dev server respawns in the original project
```

After a Claude crash, next launch:

```
shepherd auto-cleanup: killed 2 orphan tree(s) from previous session(s):
  pid 39987  next-server (v16.1.0)  (session 214bd4)
  pid 39990  node ...               (session 214bd4)
```

Investigating RAM:

```
/shepherd:processes                            → see what's running, what's heavy
/shepherd:kill --session c1b264                → surgical — touches only this session
/shepherd:cleanup --over-ram 2GB               → dry-run preview of fat processes
```

## Config

`~/.claude/.shepherd/config.json` — optional, defaults used when missing.

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
  "kill": {
    "grace_seconds": 3,
    "safe_pgid_leader": false,
    "auto_orphans_on_session_start": true
  },
  "notifications": { "macos_osascript": false },
  "history": { "max_bytes": 1048576 }
}
```

Edit with `jq` or by hand; no restart needed. The commonly-flipped knobs:

- `kill.auto_orphans_on_session_start` — set to `false` if you deliberately leave processes running across Claude restarts and don't want them killed on the next launch.
- `awareness.ram_threshold_kb` — threshold for in-conversation RAM nudges. Default 2 GB.
- `digest.enabled` — set to `true` to enable the weekly activity digest.

## How it works

Claude Code hooks drive the event stream. The plugin registers:

- **SessionStart** — record session_id, cwd, and the Claude pid in `~/.claude/.shepherd/<id>.json`. If `auto_orphans_on_session_start` is on, sweep orphans from previously-crashed sessions.
- **PreToolUse** (matcher `Bash`) — parse the incoming command for port-binding patterns; warn if another tracked session already holds one.
- **PostToolUse** (matcher `Bash`) — walk direct children of the Claude pid whose argv carries the shell-snapshot signature, record them + their subtree. Run the RAM-threshold check.
- **UserPromptSubmit** — if the prompt looks like `/clear` / "start fresh", warn Claude about still-running tracked processes so it can offer to stash them.
- **Stop** — at turn end, surface a summary of what's still running and the exact command to stop or stash it.

`list` intersects tracked pids with live `ps` output and walks descendants, so it finds children the hook never saw directly (like `next-server` forked by `next dev`).

`kill` sends SIGTERM to the tree deepest-first, waits up to `kill.grace_seconds`, then SIGKILLs survivors.

`stash` reads the command + cwd, captures allowlisted env vars (`ps -wwE` on macOS — returns `{}` on hardened macOS; `/proc/<pid>/environ` on Linux), writes a snapshot, then kills. `unstash` respawns via `( ... & exec env -i ... nohup bash -c ... )` inside the original cwd and re-attaches the new pid to the current session.

## Relationship to cc-reaper

[theQuert/cc-reaper](https://github.com/theQuert/cc-reaper) solves a different problem: it cleans up Claude's own internal spawns (MCP servers, subagents). shepherd targets the processes *you* told Claude to start in the background. Safe to run side by side.

| | cc-reaper | shepherd |
|---|---|---|
| Target | Claude's MCP / subagent leaks | User's backgrounded commands |
| Detection | PGID + `stream-json` pattern | Shell-snapshot signature + tracked state |
| Surgical per-session kill | No | Yes |
| Port / RAM / FD surfacing | Partial | Yes |
| Stash / resume | No | Yes |
| Auto-clean on next launch | LaunchAgent every 10 min | SessionStart hook |

Borrowed from cc-reaper with gratitude: the FD count, the TTY-filter orphan heuristic, the PGID-leader safety gate (opt-in via `config.kill.safe_pgid_leader`).

## Testing

```sh
for t in test/test-*.sh; do $t; done
```

All seven tests spawn synthetic processes against a sandbox `HOME`, covering detection, tree walk, stash/unstash, awareness (port parser + RAM threshold), cleanup + digest parsers, and plugin manifest validation. Regresses in ~10 seconds.

## Uninstall

```
/plugin uninstall shepherd
```

## License

MIT. See [LICENSE](LICENSE).
