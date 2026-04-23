#!/usr/bin/env bash
# tree.sh — walk process trees and report per-process info.

# cc_children <pid>
# Print immediate children PIDs of <pid>, one per line.
cc_children() {
  local pid="$1"
  [ -z "$pid" ] && return 0
  # pgrep -P works on macOS (procps on Linux too)
  pgrep -P "$pid" 2>/dev/null || true
}

# cc_descendants <pid>
# Print all descendant PIDs of <pid> (not including <pid> itself), one per line.
# Order: breadth-first. No output if <pid> has no children or is dead.
cc_descendants() {
  local root="$1"
  [ -z "$root" ] && return 0
  local queue=("$root")
  local seen_root=1
  while [ ${#queue[@]} -gt 0 ]; do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")
    local kid
    while IFS= read -r kid; do
      [ -z "$kid" ] && continue
      echo "$kid"
      queue+=("$kid")
    done < <(cc_children "$current")
  done
}

# cc_tree <pid>
# Print <pid> followed by all its descendants, one PID per line.
cc_tree() {
  local pid="$1"
  [ -z "$pid" ] && return 0
  cc_is_alive "$pid" && echo "$pid"
  cc_descendants "$pid"
}

# cc_is_alive <pid>
cc_is_alive() {
  local pid="$1"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# cc_process_info <pid>
# Print a TSV record for <pid>: pid\tcommand\trss_kb\tetime\tports
# Empty line if the process is dead.
cc_process_info() {
  local pid="$1"
  [ -z "$pid" ] && return 0
  cc_is_alive "$pid" || return 0

  # ps -o rss= (kb), etime= (elapsed [[DD-]HH:]MM:SS), command=
  local info
  info=$(ps -ww -o rss=,etime=,command= -p "$pid" 2>/dev/null) || return 0
  [ -z "$info" ] && return 0

  local rss etime cmd
  rss=$(awk '{print $1}' <<< "$info")
  etime=$(awk '{print $2}' <<< "$info")
  cmd=$(awk '{$1=""; $2=""; sub(/^  */, ""); print}' <<< "$info")

  local ports
  ports=$(cc_listening_ports "$pid")

  printf '%s\t%s\t%s\t%s\t%s\n' "$pid" "$cmd" "$rss" "$etime" "$ports"
}

# cc_fd_count <pid>
# Print the number of open file descriptors held by <pid>. Zero if lsof is
# unavailable or the process is dead. Useful as a leak indicator — a Claude
# tool run that left a hundred sockets open is suspicious.
cc_fd_count() {
  local pid="$1"
  [ -z "$pid" ] && { echo 0; return; }
  command -v lsof >/dev/null 2>&1 || { echo 0; return; }
  lsof -p "$pid" 2>/dev/null | awk 'NR>1 {n++} END {print n+0}'
}

# cc_label_devserver <command> [ports_csv]
# Identify common dev servers from their command line; if ports are given,
# emit a "Label :<port>" string (or just "Label" when no port).
# Returns empty for unrecognized commands.
cc_label_devserver() {
  local cmd="$1" ports="${2:-}"
  local label=""
  case "$cmd" in
    *"next-server"*|*"next dev"*|*"next start"*) label="Next.js" ;;
    *"nuxt dev"*|*"nuxt-dev"*)                    label="Nuxt" ;;
    *"vite"*)                                     label="Vite" ;;
    *"webpack serve"*|*"webpack-dev-server"*)     label="Webpack" ;;
    *"astro dev"*)                                label="Astro" ;;
    *"remix vite"*|*"remix dev"*)                 label="Remix" ;;
    *"uvicorn"*)                                  label="Uvicorn" ;;
    *"gunicorn"*)                                 label="Gunicorn" ;;
    *"http.server"*)                              label="http.server" ;;
    *"rails server"*|*"rails s "*)                label="Rails" ;;
    *"bun run dev"*|*"bun dev"*)                  label="Bun dev" ;;
    *"deno run"*"--watch"*)                       label="Deno" ;;
    *"jekyll serve"*)                             label="Jekyll" ;;
    *"hugo server"*)                              label="Hugo" ;;
  esac
  [ -z "$label" ] && return 0
  if [ -n "$ports" ]; then
    local first="${ports%%,*}"
    echo "$label :$first"
  else
    echo "$label"
  fi
}

# cc_listening_ports <pid>
# Print comma-separated listening TCP ports held by <pid>. Empty if none or
# if lsof is unavailable.
cc_listening_ports() {
  local pid="$1"
  command -v lsof >/dev/null 2>&1 || return 0
  lsof -nP -iTCP -sTCP:LISTEN -a -p "$pid" 2>/dev/null | \
    awk 'NR>1 { n=split($9, a, ":"); print a[n] }' | \
    sort -un | \
    paste -sd, -
}

# cc_format_etime <etime>
# Convert ps etime ([[DD-]HH:]MM:SS) into a short human form: 45s, 13m, 2h, 3d.
cc_format_etime() {
  local e="$1"
  [ -z "$e" ] && { echo ""; return; }
  local days=0 hours=0 mins=0 secs=0
  local rest="$e"
  case "$rest" in
    *-*) days=${rest%%-*}; rest=${rest#*-} ;;
  esac
  # rest is now [HH:]MM:SS
  local colons
  colons=$(awk -F: '{print NF-1}' <<< "$rest")
  case "$colons" in
    2) hours=${rest%%:*}; rest=${rest#*:}; mins=${rest%%:*}; secs=${rest#*:} ;;
    1) mins=${rest%%:*}; secs=${rest#*:} ;;
    0) secs=$rest ;;
  esac
  # Strip leading zeros that would confuse arithmetic
  days=$((10#${days:-0}))
  hours=$((10#${hours:-0}))
  mins=$((10#${mins:-0}))
  secs=$((10#${secs:-0}))
  if [ "$days" -gt 0 ]; then echo "${days}d"
  elif [ "$hours" -gt 0 ]; then echo "${hours}h"
  elif [ "$mins" -gt 0 ]; then echo "${mins}m"
  else echo "${secs}s"
  fi
}

# cc_format_rss <rss_kb>
# Convert rss in KB to short form: 8MB, 1.2GB.
cc_format_rss() {
  local kb="$1"
  [ -z "$kb" ] && { echo ""; return; }
  kb=$((10#$kb))
  if [ "$kb" -lt 1024 ]; then
    echo "${kb}KB"
  elif [ "$kb" -lt 1048576 ]; then
    echo "$((kb / 1024))MB"
  else
    # GB with one decimal
    awk -v k="$kb" 'BEGIN { printf "%.1fGB\n", k/1048576 }'
  fi
}
