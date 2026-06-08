# context.md

## Last Updated
2026-06-08 — fix-checker prompt mandates `./deploy.sh` for VM apps

## Session Notes (2026-06-08)
- `fix-checker/prompt.md` adds "Deploy Rule (VM apps)": always use `./deploy.sh`, never `npm run build` + `pm2 restart` directly (commit `596bad0`). Root cause: 2026-06-07 fix-checker auto-commit + auto-deploy raced an operator deploy on runeval, deleted `.next/standalone/server.js` mid-flight, crash-looped runeval off PM2 (~10min 503 outage). runeval + health-hub `deploy.sh` are now `flock`-protected; the prompt rule keeps the bot from bypassing the lock.

Full closeout: `privateContext/deliverables/closeouts/2026-06-08-runeval-daily-push-automation-and-deploy-lock.md`

---

## Last Updated (prior)
2026-05-12 — Multi-model pipeline: Gemini codes, CC reviews, Gemini pre-deploy review

## Current State
- **auto-dev** is the autonomous agent runner, executing cron-based jobs on the GCP VM
- **Multi-model pipeline** (added 2026-05-12): Gemini CLI does the coding, Claude Code reviews
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
- **Fix-checker** also uses orchestration (added 2026-05-11): passes failure + crash context to orchestrate.sh

### On-Demand Dispatch (added 2026-05-11)
- `run.sh --repo <name> --task "<description>"` focuses the agent on a specific task
- `--task` injects a "Directed Task" section that overrides the normal priority system
- Discord command `!code <repo> <task>` triggers this from any channel
- Full pipeline runs: orchestration -> execution -> verification -> Discord reporting

### Multi-Model Pipeline (added 2026-05-12)
Each run now executes 4 phases:
1. **Phase 1 — Gemini Coding**: Gemini CLI (`--yolo`) does the actual development work, creates branch + PR
2. **Phase 2 — Build/Test Verification**: `verify.sh` checks out the PR branch, runs `npm run build` + `npm test`
3. **Phase 3 — CC Code Review**: `review.sh` feeds the diff to Claude Code (Sonnet) for bug/security review
4. **Phase 4 — Gemini Pre-Deploy Review**: `pre-deploy-review.sh` has Gemini review the final diff for production safety

**Gating logic:**
- Phase 2 failure: PR blocked, warning posted to #autonomous-dev
- Phase 3 failure: PR blocked with CC review comment on the PR
- Phase 4 only runs if phases 2+3 pass; failure blocks the PR
- Concerns (non-blocking) from phases 3+4 are shown in the merge channel post
- All phase results tracked in `outcomes.jsonl`

**Why Gemini codes, CC reviews:**
- Gemini CLI uses free GCA auth (1K req/day), reducing Claude usage budget impact
- Cross-model review catches bugs that same-model self-review misses
- Pre-deploy review adds a second-opinion safety net before merge approval

### Priority System (updated 2026-04-07)
- **Feature runs** now fire every 2nd run (was every 5th) — 50% of runs are feature-focused
- **Medium priority** (normal runs): UX improvements, new user-facing features, performance, design system alignment, code quality, dep updates
- **Low priority**: tests, a11y, refactoring, types, docs, git cleanup
- **Feature run top-tier work**: UX flows, visual polish, new features, performance, design system. Tests and a11y explicitly excluded from feature runs.
- **Proposal mode**: When 7d usage > 50%, agent scans and proposes but doesn't execute. Proposals posted to #manual-merge-approvals for sign-off.
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

Full session closeout: `privateContext/deliverables/closeouts/2026-05-11-fix-checker-orchestration-code-dispatch.md`

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
