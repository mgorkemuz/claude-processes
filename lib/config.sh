#!/usr/bin/env bash
# config.sh — user-editable config at ~/.claude/.shepherd/config.json

cc_config_file() { echo "${HOME}/.claude/.shepherd/config.json"; }

# cc_config_default — print the default skeleton JSON.
# Single source of truth for new config keys.
cc_config_default() {
  cat <<'JSON'
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
JSON
}

# cc_config_init — write the default skeleton if no config exists. No-op otherwise.
cc_config_init() {
  local f; f=$(cc_config_file)
  [ -f "$f" ] && return 0
  mkdir -p "$(dirname "$f")"
  cc_config_default > "$f"
}

# cc_config_get <jq_path> [default]
# Read a value via jq path (e.g. '.awareness.ram_threshold_kb').
# Falls back to <default> if the key is missing, null, or the file doesn't exist.
# Silently returns <default> if jq is unavailable.
cc_config_get() {
  local path="$1" default="${2:-}"
  command -v jq >/dev/null 2>&1 || { echo "$default"; return; }
  local f; f=$(cc_config_file)
  local source
  if [ -f "$f" ]; then
    source="$f"
  else
    # Read straight from default skeleton — lets callers work before init.
    source=$(mktemp)
    cc_config_default > "$source"
  fi
  local val
  # Use explicit null check — `//` wrongly triggers the default on false/"".
  val=$(jq -r --arg d "$default" "($path) as \$v | if \$v == null then \$d else \$v end" "$source" 2>/dev/null) || val="$default"
  [ -f "$f" ] || rm -f "$source"
  [ "$val" = "null" ] && val="$default"
  echo "$val"
}
