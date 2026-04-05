# context.md

## Last Updated
2026-04-05 — Follow-up: added #cli-interactions scanning, validated run #2, closed open items

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
- **Auto-commit graduation:** 2 of ~10 runs complete. PRs #67-71 all successful. Consider switching after ~10.
- **S6: Branch name collision:** Runner could fail if previous learnings branch isn't cleaned up. Add pre-flight check.
- **Usage gate validation:** Parsing works (tested) but no fallback if output format changes. Low priority.

Full session closeout: `privateContext/deliverables/closeouts/2026-04-05-learning-system-followup.md`

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
