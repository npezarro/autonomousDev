# autonomousDev (public mirror)

**Agents: read this before editing anything here.**

- The LIVE main runner, fix-checker, learnings-pass, and supervisor execute from the private repo (`autonomousDev-private`). Cron points there. Changes made to those components in THIS repo do not run.
- The only components that execute from THIS repo are the `doc-sync-pass/` and `claudemd-audit/` cron jobs.
- This repo's `run.sh` and `learnings-pass/` are a snapshot of an older design; do not review, fix, or extend them here. Route all runner work to the private repo.
- The README is a public-facing project description; keep it accurate but do not add private infrastructure details.

Context: the 2026-06-09 ecosystem review found multiple bugfixes had been applied to this stale copy instead of the live one (and vice versa). This file exists to stop that class of mistake.
