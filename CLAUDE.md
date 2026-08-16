# autonomousDev (public mirror)

canonical-copy: ~/repos/autonomousDev-private
writer: autonomousDev agents (doc-sync-pass, claudemd-audit only)

**Agents: read this before editing anything here.**

- The LIVE main runner, fix-checker, learnings-pass, and supervisor execute from the private repo (`autonomousDev-private`). Cron points there. Changes made to those components in THIS repo do not run.
- The only components that execute from THIS repo are the `doc-sync-pass/` and `claudemd-audit/` cron jobs.
- This repo's `run.sh` and `learnings-pass/` are a snapshot of an older design; do not review, fix, or extend them here. Route all runner work to the private repo.
- The README is a public-facing project description; keep it accurate but do not add private infrastructure details.

Context: the 2026-06-09 ecosystem review found multiple bugfixes had been applied to this stale copy instead of the live one (and vice versa). This file exists to stop that class of mistake.

## doc-sync prompt template pointed at a nonexistent profile path
The doc-sync-pass cron prompt (~/repos/autonomousDev/doc-sync-pass/prompt.md) told the agent
to "Read your profile: ~/repos/agentGuidance/profiles/doc-sync/profile.md" — that path never
existed. The real doc-sync agent definition is at
~/repos/agentGuidance/claude-agents/doc-sync.md. Confirmed stale across every prior doc-sync
run found in claude-session-logs going back to April 2026 — every run silently skipped its
own "read your profile" step. Fixed in run #434 (commit 94a5059 on autonomousDev main,
following that file's existing direct-to-main convention — doc-sync-pass executes live from
the public autonomousDev mirror per that repo's CLAUDE.md).

Separate observation from the same run: pushing a `claude/doc-sync-<n>` branch to shopper's
sibling repos (foodie, travel-assistant) triggers `pezant-auto-merger[bot]` to open AND merge
a PR (titled "Claude Doc Sync <n>") within seconds of the push — there is no actual "staged
for review" window despite the runner prompt's step 4 ("Stage PRs for review"). Future
doc-sync runs should not expect the PR to sit open; treat a push to those repos as equivalent
to a direct merge to main and write commits accordingly.

## activity digest leaked commits from open/dependabot branches (fixed run #8)
`doc-sync-pass/run.sh`'s git-activity collection used `git log --since=... --oneline --all`,
which scans every ref (all branches, all remotes) instead of the repo's default branch. Every
doc-sync run since #5 (runs 5, 6, 7, 8) received unmerged dependabot/feature-branch commits in
its digest and had to manually re-derive per-SHA reachability checks against main to avoid
documenting unshipped behavior — recommended three times in `claude-agents/doc-sync.md` but
never actually fixed. Root-caused and fixed in run #8 (commit 902d4d7 on autonomousDev main):
`--all` replaced with an explicit `origin/main` (falling back to `origin/master`) ref, resolved
via a local `git show-ref --verify` check (no network call needed — all real checkouts already
have that remote-tracking ref). Verified against runeval/runEvaluator post-fix: digest dropped
from 5 commits (3 of them unmerged dependabot branches) to the 2 that are actually on main.
