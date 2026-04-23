---
description: One-line summary of tracked Claude sessions, processes, and orphans.
allowed-tools: Bash(shepherd:*)
---

Run `shepherd status` and report the single-line output. If the numbers look interesting (many orphans, many processes in one session), briefly suggest next actions — `/shepherd:processes` to see details, `/shepherd:cleanup` to trim old ones.
