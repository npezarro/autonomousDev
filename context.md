# context.md

## Last Updated
2026-04-05 — Learning agent upgraded to hourly 5-pass review system

## Current State
- **autonomousDev** is the autonomous agent runner, executing cron-based jobs on the GCP VM
- Three active jobs:
  - `autonomousDev/` (main pass): runs every 30min at :00/:30, usage gate 75%
  - `learnings-pass/`: runs hourly at :43, usage gate 90%
  - `fix-checker/`: runs on its own schedule
- Learning agent (learnings-pass) was upgraded 2026-04-05 from daily single-pass to hourly 5-pass:
  1. Uncaptured learnings from journal/PRs/commits
  2. Memory-only learnings (enforces 3-destination rule)
  3. Uncaptured user corrections not in any rule set (highest priority)
  4. Prompt & instruction observation across all agents
  5. Profile experience updates
- All learning agent changes go on branches with PRs for review (staged, not auto-commit)
- Learning agent posts to #learnings Discord channel
- First automated run found 4 real gaps and created PRs #67-69 on agentGuidance

## Open Work
- **Usage gate parsing fragility:** run.sh parses check-usage.sh output with grep -oP. If output format changes, silently passes (defaults to 0%). Needs validation check.
- **Correction detection scope:** Pass 3 needs Discord bot token + #cli-interactions channel ID to scan messages. Verify these are available in the agent's env.
- **Auto-commit graduation:** After ~10 successful staged PRs, consider switching to auto-commit for guidance-only changes.
- **agent.md line budget:** At ~80 lines with 100-line ceiling. Learning agent flagged this (S2). Consider extracting sections to guidance files.

Full session closeout: `privateContext/deliverables/closeouts/2026-04-05-learning-system-full-session.md`

## Environment Notes
- **Deploy target:** GCP VM (pezant.ca)
- **Process manager:** Cron (not PM2)
- **SSH user:** generatedByTermius (not npezarro)
- **Node version:** N/A (bash + Claude CLI)
- **Python:** 3.9 on VM (no 3.10+ features like match/case)
- **Key paths on VM:** ~/repos/autonomousDev/, ~/repos/privateContext/, ~/repos/agentGuidance/

## Active Branch
main

---
**For change history**, see `progress.md`.
