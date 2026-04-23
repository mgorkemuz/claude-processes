# Changelog

All notable changes to claude-clean. This project follows [SemVer](https://semver.org).

## [Unreleased]

### Added
- Changelog file + plugin-install test scaffold (Phase 0).

### Planned (see `/Users/gorkemuz/.claude/plans/silly-purring-lantern.md`)
- Plugin restructure (`.claude-plugin/plugin.json`, `hooks/hooks.json`, `scripts/on-*.sh`).
- `/processes`, `/stash`, `/resume`, `/cleanup` slash commands.
- FD column + dev-server URL labels in `list`.
- Config file at `~/.claude/.clean/config.json`.
- History log + `digest` aggregate.
- RAM threshold + port-conflict awareness (additionalContext in hooks).
- `cleanup --older-than`, `--over-ram` with TTY confirmation.
- cc-reaper-style PGID leader safety check (opt-in).

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
