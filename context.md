# context.md

## Last Updated
2026-04-07 — Priority rebalance: UX/features over tests, proposal mode for budget conservation

## Current State
- **auto-dev** is the autonomous agent runner, executing cron-based jobs on the GCP VM
- Three active jobs:
  - `auto-dev/` (main pass): runs every 30min at :00/:30, usage gate 75%
  - `learnings-pass/`: runs hourly at :43, usage gate 90%
  - `fix-checker/`: runs on its own schedule

### Priority System (updated 2026-04-07)
- **Feature runs** now fire every 2nd run (was every 5th) — 50% of runs are feature-focused
- **Medium priority** (normal runs): UX improvements, new user-facing features, performance, design system alignment, code quality, dep updates
- **Low priority**: tests, a11y, refactoring, types, docs, git cleanup
- **Feature run top-tier work**: UX flows, visual polish, new features, performance, design system. Tests and a11y explicitly excluded from feature runs.
- **Proposal mode**: When 7d usage > 50%, agent scans and proposes but doesn't execute. Proposals posted to #autonomous-dev-merges for sign-off.
- Decision rationale: overnight runs were burning ~20% of 7d budget on tests/a11y/lint; user wants UX/feature advancement

### Learning Agent
- Upgraded 2026-04-05 from daily single-pass to hourly 5-pass
- All learning agent changes go on branches with PRs for review
- Posts to #learnings Discord channel

## Open Work
- **Monitor priority rebalance** — Verify 50/50 feature/maintenance split produces good mix
- **Proposal mode untested** — Will activate organically when 7d usage crosses 50%
- **Feature ideas refresh** — Per-repo `context/*-features.md` files written under old regime, may need UX-oriented ideas
- **S6: Branch name collision:** Runner could fail if previous learnings branch isn't cleaned up
- **Usage gate validation:** Parsing works but no fallback if output format changes

Full session closeout: `privateContext/deliverables/closeouts/2026-04-07-ad-priority-rebalance.md`

## Environment Notes
- **Deploy target:** GCP VM (see privateContext for details)
- **Process manager:** Cron (not PM2)
- **SSH user:** see privateContext
- **Node version:** N/A (bash + Claude CLI)
- **Python:** 3.9 on VM (no 3.10+ features like match/case)
- **Key paths on VM:** ~/repos/ (same repo structure as local)

## Active Branch
main

---
**For change history**, see `progress.md`.
