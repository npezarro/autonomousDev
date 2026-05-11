# context.md

## Last Updated
2026-05-11 — Added orchestration pipeline (Haiku selects repo + agent profiles) and post-agent verification (independent build/test gate)

## Current State
- **auto-dev** is the autonomous agent runner, executing cron-based jobs on the GCP VM
- Three active jobs:
  - `auto-dev/` (main pass): runs every 30min at :00/:30, usage gate 75%
  - `learnings-pass/`: runs hourly at :43, usage gate 90%
  - `fix-checker/`: runs every 10min, two-tier strategy (Tier 1: restart/rollback, Tier 2: root cause code fix)

### Orchestration Pipeline (added 2026-05-11)
- **Pre-agent**: `orchestrate.sh` calls Haiku with repo list + agent profile catalog from `agentGuidance/profiles/`
- Haiku picks: target repo, 1-2 specialist profiles (e.g. frontend + architect), and a strategy sentence
- Selected profiles (identity + recent experience tail) are injected into the prompt as `## Agent Profile`
- Configurable model via `config.json` field `orchestration_model` (default: haiku)
- Graceful fallback: if orchestration fails, agent picks freely as before

### Post-Agent Verification (added 2026-05-11)
- **Post-agent**: `verify.sh` checks out the PR branch, runs `npm run build` + `npm test` independently
- On FAIL: PR gets a comment, warning posted to #autonomous-dev (not merges), PR blocked from merge channel
- On PASS: verification status shown in merges channel post ("Verified: build:pass test:pass")
- On SKIP: no build/test scripts found, treated as pass
- Verification result tracked in `outcomes.jsonl` (`verify` + `verify_detail` fields)

### Priority System (updated 2026-04-07)
- **Feature runs** now fire every 2nd run (was every 5th) — 50% of runs are feature-focused
- **Medium priority** (normal runs): UX improvements, new user-facing features, performance, design system alignment, code quality, dep updates
- **Low priority**: tests, a11y, refactoring, types, docs, git cleanup
- **Feature run top-tier work**: UX flows, visual polish, new features, performance, design system. Tests and a11y explicitly excluded from feature runs.
- **Proposal mode**: When 7d usage > 50%, agent scans and proposes but doesn't execute. Proposals posted to #autonomous-dev-merges for sign-off.
- Decision rationale: overnight runs were burning ~20% of 7d budget on tests/a11y/lint; user wants UX/feature advancement

### Learning Agent
- Upgraded 2026-04-05 from daily single-pass to hourly 7-pass
- All learning agent changes go on branches with PRs for review
- Posts to #learnings Discord channel on EVERY run (not just when changes found)
- Threaded activity summary on each post: narrative of all observed interactions + conclusions
- `ACTIVITY_OBSERVED` block required in prompt output even on quiet runs

## Open Work
- **Monitor orchestration quality** — Watch whether Haiku picks reasonable repos/profiles; tune prompt if needed
- **Monitor verification false positives** — Some repos may fail build for pre-existing reasons, not agent changes
- **Monitor fix-checker Tier 2** — Watch #work-log for next runs to verify root cause fixes are attempted
- **Fix-checker cost monitoring** — Tier 2 fixes increase per-run cost; watch 24h budget impact
- **PR backlog** — 29 open PRs in Discord bot repo flagged by activity summary, needs triage
- **Proposal mode untested** — Will activate organically when 7d usage crosses 50%
- **S6: Branch name collision:** Runner could fail if previous learnings branch isn't cleaned up

Full session closeout: `privateContext/deliverables/closeouts/2026-04-22-fix-checker-two-tier-strategy.md`

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
