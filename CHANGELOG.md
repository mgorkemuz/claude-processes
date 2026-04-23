# Changelog

All notable changes to claude-clean. This project follows [SemVer](https://semver.org).

## [0.3.0] — 2026-04-23

### Added
- Claude Code plugin distribution via `.claude-plugin/plugin.json` +
  `hooks/hooks.json`. Bundled `bin/`, `lib/`, `scripts/`, `commands/`.
- Slash commands: `/processes`, `/stash`, `/resume`, `/cleanup`.
- `claude-clean stash <pid|--session|--current>` + `unstash <id> [--attach]`
  with 8-hex stash IDs, command+cwd+allowlisted-env snapshots at
  `~/.claude/.clean/stashed/`, and `( ... & exec ...)` spawn pattern for
  stable respawn pids.
- `claude-clean cleanup --older-than <dur> [--over-ram <size>] [--dry-run]`
  with TTY confirmation.
- `claude-clean digest [--since <dur>]` aggregates `history.jsonl`
  (opt-in via `config.digest.enabled`).
- FD column + dev-server URL labels (`Next.js :3000`) in `list`.
- `lib/config.sh` + `~/.claude/.clean/config.json` with schema for
  awareness thresholds, stash env allowlist, kill grace, notifications,
  history rotation.
- `lib/history.sh` append-only JSONL logging at `~/.claude/.clean/history.jsonl`
  with 1 MB rotation.
- PreToolUse hook (matcher: Bash) with `cc_port_conflict_check` emitting
  `hookSpecificOutput.additionalContext` warnings when incoming Bash
  commands target ports already held by other tracked sessions.
- PostToolUse `cc_ram_threshold_check` with below→above rate limiting
  via `<session>.alerts.json`.

### Changed
- Lifted the 200-char command truncation in hook capture — stash needs
  the full command to respawn.
- `cc_find_root` now resolves `$CLAUDE_PLUGIN_ROOT` first, preserving
  the existing PATH-based fallbacks for v0.1.0 shell users.

### Removed
- `install.sh` — plugin install replaces it. `uninstall.sh` is retained
  for v0.1.0 users with a migration preamble.

### Tests
- 7 shell test scripts (`test-{detect,tree,plugin-install,config,stash,awareness,cleanup}.sh`).

## [0.1.0] — 2026-04-22

## [0.1.0] — 2026-04-22

### Added
- POSIX shell CLI: `list`, `status`, `kill`, `prompt`, `sessions`.
- Hook event handler (`hook` subcommand) wired to `SessionStart`,
  `PostToolUse(matcher:Bash)`, `Stop`.
- Process tree walk + graceful SIGTERM → SIGKILL cascade.
- Session-scoped tracking state at `~/.claude/.clean/<session>.json`.
- Orphan detection (session's `claude_pid` dead, children alive).
- Surgical per-session kill.
- `install.sh` + `uninstall.sh` with settings.json merge preserving
  user-defined hooks.

### Notes
- v0.1.0 is a standalone shell install. v0.2.0 will move to a Claude Code
  plugin; existing users should run `./uninstall.sh` before installing the
  plugin to avoid duplicate hook registrations.
