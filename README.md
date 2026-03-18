# Autonomous Development Agent

Continuous improvement agent that works across all repos. Runs every 30 minutes via cron, discovers productive work, and executes it through Claude Code CLI.

## Architecture

- `run.sh` — Entry point. Called by cron every 30 minutes.
- `context/` — Per-repo context and progress logs.
- `config.json` — Repo manifest, thresholds, exclusions.
- `logs/` — Run history and output.

