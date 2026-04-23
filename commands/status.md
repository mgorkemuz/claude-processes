---
description: One-line summary of tracked Claude sessions, processes, and orphans.
allowed-tools: Bash(claude-processes:*)
---

Run `claude-processes status` and report the single-line output. If the numbers look interesting (many orphans, many processes in one session), briefly suggest next actions — `/claude-processes:processes` to see details, `/claude-processes:cleanup` to trim old ones.
