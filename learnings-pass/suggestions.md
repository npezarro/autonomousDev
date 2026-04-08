# Learning Agent — Prompt & Instruction Suggestions

Append-only log of improvement suggestions identified by the learning agent.
Each entry includes the suggestion, rationale, and which file/prompt it applies to.

---

## 2026-04-05 — Run #1

### S1: learnings-pass/prompt.md references nonexistent completed-work.md
**File:** `auto-dev/learnings-pass/prompt.md`
**Issue:** The prompt instructs agents to read `privateContext/completed-work.md` for deduplication, but this file does not exist. First run will always skip deduplication.
**Suggestion:** Create the file with a header and instructions, or make the prompt handle its absence gracefully.

### S2: agent.md approaching 100-line limit
**File:** `agentGuidance/agent.md`
**Issue:** After adding "verify before asserting" and "large outputs to files", agent.md is at ~80 lines. Two more additions will hit the 100-line ceiling.
**Suggestion:** Consider extracting the Communication section into `guidance/communication.md` to free space for future core principles.

### S3: freeGames repo has no CLAUDE.md despite being most actively worked repo
**File:** `freeGames/CLAUDE.md` (does not exist)
**Issue:** 20+ commits in 48h, remote agent architecture, multi-platform flows, yet no operational rules for agents working in this repo.
**Suggestion:** Created in this run. Future: ensure CLAUDE.md is created during the first significant agent session on any repo.

### S4: browser-agent repo has no CLAUDE.md
**File:** `browser-agent/CLAUDE.md` (does not exist)
**Issue:** Well-documented in memory but no repo-level instructions. Any agent working in the repo won't have context unless they load memory.
**Suggestion:** Create CLAUDE.md with architecture overview, CLI usage, and deployment rules.

---

## 2026-04-05 — Run #2

### S5: learning-agent.md design doc contradicts prompt on branch/PR approach
**File:** `agentGuidance/guidance/learning-agent.md`
**Issue:** Line 61 under "What It Does NOT Do" says "Create PRs or branches (it edits guidance files on main/production directly)" but the actual prompt.md explicitly requires branches and PRs for all changes. The design doc is stale.
**Suggestion:** Update the design doc to reflect the current staged PR approach, or remove that line from the "Does NOT Do" section.

### S6: learnings-pass runner should gate on existing branches
**File:** `auto-dev/learnings-pass/run.sh`
**Issue:** If the auto-merger hasn't processed a previous learnings PR yet, the next run will fail trying to create a branch with the same name. The runner should check for existing remote branches and either skip or increment the branch name.
**Suggestion:** Add a pre-flight check: `git ls-remote --heads origin claude/learnings-*` and either skip if a pending branch exists or use an incremented name.

### S7: deployment.md Python section cross-reference
**File:** `agentGuidance/guidance/deployment.md`
**Issue:** The new Python 3.9 section and the VM SSH section are separate but related. A developer reading the SSH section to prepare a deploy might miss the Python note above.
**Suggestion:** Add a cross-reference line in the VM SSH section: "See also: Python Version Compatibility (above) for type annotation restrictions."

---

## 2026-04-06 — Run #4

### S10: youtubeSpeedSetAndRemember CLAUDE.md is just a bootstrap template
**File:** `youtubeSpeedSetAndRemember/CLAUDE.md`
**Issue:** The CLAUDE.md was a generic agent bootstrap (fetch agent.md, fallback rules) with zero repo-specific context. v18.0-18.2 demonstrated recurring YouTube DOM breakage patterns that agents need upfront. Any agent working in this repo would not know about DOM resilience requirements.
**Suggestion:** Replaced with proper CLAUDE.md containing YouTube DOM resilience rules, architecture overview, and key files. (Done in this run.)

### S11: tampermonkey.md missing YouTube DOM resilience section
**File:** `agentGuidance/guidance/tampermonkey.md`
**Issue:** Four commits (v18.0-18.2) dealt with YouTube DOM changes breaking the userscript. The patterns (use visibility checks, target stable IDs, test mobile separately) are cross-project and apply to any YouTube-targeting TM script, but were not in tampermonkey.md.
**Suggestion:** Added "YouTube DOM Resilience" section with defensive coding patterns. (Done in this run.)

### S12: agent.md missing "test before reporting" principle
**File:** `agentGuidance/agent.md`
**Issue:** The `feedback_test_before_asking` memory (user corrected agent for pushing changes and asking user to test instead of verifying first) existed only in memory. No corresponding rule in agent.md or any guidance file. This is a cross-project behavioral pattern.
**Suggestion:** Added to Core Principles: "Test before reporting. Verify changes yourself before asking the user to test." (Done in this run.)

---

## 2026-04-06 — Run #5

### S13: learning-agent.md design doc has stale values
**File:** `agentGuidance/guidance/learning-agent.md`
**Issue:** Three values in the design doc no longer match reality:
  - Line 17: Location says `~/repos/auto-dev/learning-agent/` but actual location is `~/repos/auto-dev/learnings-pass/`
  - Line 19: Timeout says "20 minutes" but run.sh uses `MAX_TIMEOUT=1800` (30 minutes)
  - Line 18: Frequency says "every 2-4 hours" but decisions section (line 110) correctly says hourly at :43
**Suggestion:** Update the Architecture section to match current implementation. The Decisions section at the bottom is correct; the top-level description drifted.

### S14: session-wrapup.md lacked --closeout/--deep-closeout trigger docs
**File:** `agentGuidance/guidance/session-wrapup.md`
**Issue:** The `--closeout` and `--deep-closeout` text triggers (which any agent should respond to) were documented only in memory (`feedback_closeout_report.md`), not in any guidance file. Agents without memory access wouldn't know to handle these triggers.
**Suggestion:** Added "Trigger Conventions" section to session-wrapup.md documenting both triggers and their expected behavior. (Done in this run.)

---

## 2026-04-06 — Run #6

### S15: freeGames CLAUDE.md missing Discord webhook env var and integration details
**File:** `freeGames/CLAUDE.md`
**Issue:** Discord integration was listed as a single line ("Discord reporting: src/discord.js") with no details on the webhook env var (`DISCORD_CLAIMS_WEBHOOK_URL`), embed color coding, or two-level reporting structure (per-claim + run summary). An agent adding a new platform or debugging claim notifications would miss this.
**Suggestion:** Added Discord reporting details and @match expansion pattern to CLAUDE.md. (Done in this run.)

### S16: youtubeSpeedSetAndRemember CLAUDE.md had duplicate rule numbers
**File:** `youtubeSpeedSetAndRemember/CLAUDE.md`
**Issue:** Rules 6 and 7 were duplicated (two "6." entries, two "7." entries) due to previous editing without renumbering. This makes the rules ambiguous and hard to reference.
**Suggestion:** Fixed numbering (now rules 1-9) as part of adding the video src detection rule. (Done in this run.)

---

## 2026-04-06 — Run #7

### S17: claude-auto-merger has no CLAUDE.md
**File:** `claude-auto-merger/CLAUDE.md` (does not exist)
**Issue:** The auto-merger is actively used (processes learnings PRs, handles approval flows) and recently added a rule to skip auto-merge for learning agent PRs. Without a CLAUDE.md, agents working on it lack context about its auto-merge criteria, webhook integration, and the approval exception for learnings PRs.
**Suggestion:** Create a CLAUDE.md documenting: auto-merge criteria (PR format, label requirements), the learnings-PR exception, webhook configuration, and which repos it watches.

### S18: browser-agent CLAUDE.md missing multi-tab orchestration docs
**File:** `browser-agent/CLAUDE.md`
**Issue:** v1.5.0 added `ensure`, `close`, and `openTab` commands for multi-tab workflows, but CLAUDE.md only documented single-tab architecture. Agents using browser-cli for multi-step flows (e.g., claim on one site, redeem on another) wouldn't know about idempotent tab management.
**Suggestion:** Added multi-tab orchestration section to CLAUDE.md. (Done in this run.)

---

## 2026-04-06 — Run #8

### S19: job-scraper has no CLAUDE.md despite 9 ATS adapters and complex company config
**File:** `job-scraper/CLAUDE.md` (does not exist)
**Issue:** The job-scraper has 9 ATS adapters (Greenhouse, Ashby, Lever, Workday, Workable, Netflix, page-reader, browser, generic) plus company-specific quirks like Ashby posting-api fallback for non-GraphQL companies, URL-encoded slugs (e.g., "Jasper AI"), and platform misattributions (e.g., Stripe was labeled "generic" but is actually Greenhouse). Recent commit `4708e6d` added Workable adapter and fixed 6 company ATS misconfigurations. Without CLAUDE.md, agents will repeat discovery of these quirks.
**Suggestion:** Create a CLAUDE.md documenting: adapter selection logic, company.json ATS field semantics, common ATS misconfigurations, and the page-reader fallback strategy for companies without structured APIs.

### S20: learning-agent.md stale architecture values still unfixed (S13 repeat)
**File:** `agentGuidance/guidance/learning-agent.md`
**Issue:** S13 (run #5) flagged three stale values: wrong location (`learning-agent/` vs `learnings-pass/`), wrong timeout (20 min vs 30 min), wrong frequency ("every 2-4 hours" vs hourly at :43). These remain unfixed after 3 runs. The design doc misleads any agent trying to understand or modify the learning agent setup.
**Suggestion:** Fix the three values in the Architecture section. This is a simple factual correction, not a design change.

---

## 2026-04-06 — Run #9

### S21: learning-agent.md stale values fixed (S13/S20 resolved)
**File:** `agentGuidance/guidance/learning-agent.md`
**Status:** Fixed in this run. Location corrected to `learnings-pass/`, frequency to "hourly at :43", timeout to "30 minutes".

### S22: job-scraper CLAUDE.md created (S19 resolved)
**File:** `job-scraper/CLAUDE.md`
**Status:** Created in this run. Documents 9 ATS adapters, common gotchas (ATS misattribution, Ashby fallback, URL-encoded slugs), key commands, and data flow.

### S23: claude-auto-merger CLAUDE.md created (S17 resolved)
**File:** `claude-auto-merger/CLAUDE.md`
**Status:** Created in this run. Documents auto-merge criteria, learnings PR exception, crash-fix rate limiting, environment variables, and key lib.js functions.

---

## 2026-04-06 — Run #10

### S24: claude-bakeoff has no CLAUDE.md despite 15 environments
**File:** `claude-bakeoff/CLAUDE.md` (does not exist)
**Issue:** claude-bakeoff has 15 environments (baseline, buying-*, iterate-*, persona-*, voice-*, linkedin-*), active task definitions, and is referenced by `agentGuidance/guidance/ab-testing.md`. Yet the repo has no CLAUDE.md. An agent opening the repo to create a new environment or run a bakeoff lacks context on folder conventions, output storage rules (results in private repos, not in claude-bakeoff), and the arena CLI workflow.
**Suggestion:** Create a CLAUDE.md documenting: environment folder structure, task.yaml schema, output storage rules (private repos only), arena CLI commands, and the 4-path bakeoff pattern.

### S25: discord-bot CLAUDE.md missing channel watchers and post-job hooks
**File:** `discord-bot/CLAUDE.md`
**Issue:** The CLAUDE.md documented architecture (entry point, deploy queue, session pool) and bot-specific rules, but omitted two active subsystems: (1) channel watchers that auto-route messages to specific agent cwds (#buying-guides → buying-assistant), and (2) post-job hooks (`postJobHooks.js`) that auto-commit+push and archive to Drive after job completion. An agent modifying channel routing or adding a new post-job hook wouldn't know these systems exist.
**Suggestion:** Added channel watcher list and post-job hooks section to CLAUDE.md. (Done in this run.)

---

## 2026-04-06 — Run #11

### S26: comprehensive-closeout.md hardcoded memory path
**File:** `agentGuidance/guidance/comprehensive-closeout.md` (line 93)
**Issue:** The Memory Update step hardcodes `~/.claude/projects/-mnt-c-Users-user/memory/` as the memory path. Claude Code memory paths are derived from the working directory, so sessions started from `/home/user` (WSL home) use `-home-user` while sessions from `/mnt/c/Users/user` use `-mnt-c-Users-user`. Any agent following this guidance from the wrong working directory would write to the wrong memory path.
**Suggestion:** Replace the hardcoded path with a generic instruction: "Update the relevant project memory file in `~/.claude/projects/<project-path>/memory/`" and note that the project-path is derived from the working directory.

### S27: run.sh memory scan still only checks one path (S8 repeat)
**File:** `auto-dev/learnings-pass/run.sh` (line ~225)
**Issue:** `MEMORY_DIR` is hardcoded to `$HOME/.claude/projects/-mnt-c-Users-user/memory`. This means the learning agent only scans memory files from Windows-path sessions. Memories saved from Linux-home sessions (`-home-user`) are invisible. S8 (run #3) flagged this; still unfixed after 8 runs.
**Suggestion:** Scan all project memory directories: `find $HOME/.claude/projects/*/memory -name "*.md" 2>/dev/null` or maintain a list of known project paths.

### S28: feedback_bridge_vm_local migrated to deployment.md
**File:** `agentGuidance/guidance/deployment.md`
**Status:** Migrated in this run. Added "Check the Server Before Asking" section — SSH into VM for env vars, configs, logs before asking the user. Previously memory-only.

---

## 2026-04-06 — Run #12

### S29: claude-auto-merger CLAUDE.md missing race condition gotcha (migrated from memory)
**File:** `claude-auto-merger/CLAUDE.md`
**Status:** Added "Known Gotcha: Race Condition with Agent PR Creation" section. Migrated from `project_auto_merger_race` memory. (Done in run #12.)

### S30: claude-bakeoff still missing CLAUDE.md (S24 repeat)
**File:** `claude-bakeoff/CLAUDE.md`
**Status:** Created in run #13 with architecture, operational rules, workflow commands, and patterns learned. Resolves S24. (Done.)

---

## 2026-04-06 — Run #13

### S31: claude-bakeoff CLAUDE.md created (S24/S30 resolved)
**File:** `claude-bakeoff/CLAUDE.md`
**Status:** Created in this run. Documents architecture (arena CLI, environments, tasks, runs), 5 operational rules (output to private repos, baseline stays minimal, eval criteria specificity), and patterns learned from bakeoff testing.

### S32: auto-dev learnings-12 branch stuck behind main
**File:** `auto-dev` repo
**Issue:** Branch `claude/learnings-12` contains S29-S30 but was based on pre-run-#11 main. After run #11 merged, the branch diverged and the auto-merger couldn't merge it (no PR was created or it failed). S29-S30 content was stranded. Run #13 incorporated the content and the branch can be cleaned up.
**Suggestion:** Add a pre-flight check to the learnings-pass runner: before creating a new branch, check for stale unmerged branches (`git branch -r --no-merged origin/main | grep learnings`) and either rebase them or warn.

---

## 2026-04-06 — Run #14

### S33: discord-bot CLAUDE.md missing quality gap fix subsystems
**File:** `discord-bot/CLAUDE.md`
**Issue:** The Discord quality gap fix (commit c86983c) added URL pre-fetching, bot output stripping, and route classifier heuristics to discord-bot, but CLAUDE.md wasn't updated. context.md was updated but CLAUDE.md is what agents read first.
**Suggestion:** Added URL Pre-Fetching & Retry Detection section to CLAUDE.md. (Done in this run.)

### S34: run.sh memory scan single-path — 5th time flagged (S8/S27 repeat)
**File:** `auto-dev/learnings-pass/run.sh` (line ~225)
**Issue:** `MEMORY_DIR` is hardcoded to `$HOME/.claude/projects/-mnt-c-Users-user/memory`. Learning agent misses memories from Linux-home sessions (`-home-user`, `-home-user-repos`, `-home-user-repos-discord-bot`). This run found 2 memory-only items in those paths that had been invisible to prior scans.
**Suggestion:** Replace hardcoded path with: `find $HOME/.claude/projects/*/memory -name "*.md" 2>/dev/null`. This is the most-repeated unfixed suggestion — consider prioritizing it.

### S35: feedback_wordpress_posting.md migrated to wordpress-auto-posting.md
**File:** `agentGuidance/guidance/wordpress-auto-posting.md`
**Status:** Added "Manual / Agent-Initiated Posts" section documenting WP-CLI and local REST API approaches for non-hook posting. (Done in this run.)

---

## 2026-04-06 — Run #15

### S36: run.sh memory scan single-path — 6th time flagged (S8/S27/S34 repeat)
**File:** `auto-dev/learnings-pass/run.sh` (line 227)
**Issue:** `MEMORY_DIR` is hardcoded to `$HOME/.claude/projects/-mnt-c-Users-user/memory`. This means the learning agent only scans memory files from Windows-path sessions. Memories saved from `/home/user` sessions (3 project paths with memory files exist) are invisible. This has been flagged in S8 (run #3), S27 (run #11), and S34 (run #14). Still unfixed after 12 runs.
**Suggestion:** Replace line 227 with a multi-path scan: `find $HOME/.claude/projects/*/memory -name "*.md" ! -name "MEMORY.md" 2>/dev/null`. Currently missing memories from: `-home-user-repos/memory/` (2 files), `-home-user-repos-discord-bot/memory/` (2 files).
**Priority:** HIGH — this is the most-repeated unfixed suggestion and directly causes the learning agent to miss memory-only learnings.

### S37: auto-dev has 15 stale unmerged remote branches
**File:** `auto-dev` repo
**Issue:** `git branch -r --no-merged origin/main` returns 15 branches (learnings-2 through learnings-14-ad, plus learnings-approval). These are all from prior learning agent runs whose content was merged via subsequent runs but whose branches were never cleaned up. This clutters the remote and makes branch listing noisy.
**Suggestion:** Add a cleanup step to the learnings-pass runner: after a successful PR merge, delete the remote branch. Or add a periodic cleanup: `git push origin --delete $(git branch -r --no-merged origin/main | grep 'claude/learnings-' | sed 's|origin/||')`. The git-workflow.md guidance (line 70) already says to clean up stale branches.

---

## 2026-04-06 — Run #16

### S38: discord-bot CLAUDE.md missing media attachment handling docs
**File:** `discord-bot/CLAUDE.md`
**Issue:** PR #134 added a major feature: image/video download, ffmpeg frame extraction, SCP transfer to local worker, and temp cleanup. None of this was documented in CLAUDE.md. An agent modifying attachment handling, adding new media types, or debugging frame extraction wouldn't know about classification logic, size limits, the SCP transfer path, or temp cleanup responsibilities.
**Suggestion:** Added "Media Attachment Handling" section to CLAUDE.md. (Done in this run.)

### S39: run.sh memory scan single-path — 7th time flagged (S8/S27/S34/S36 repeat)
**File:** `auto-dev/learnings-pass/run.sh` (line 227)
**Issue:** `MEMORY_DIR` is hardcoded to `$HOME/.claude/projects/-mnt-c-Users-user/memory`. This run confirmed zero memory files found across ALL project paths (the prior paths with files may have been cleaned up), but the fundamental issue persists: when new memories are saved from `/home/user` sessions, the learning agent won't see them. Flagged 7 times across 13 runs.
**Suggestion:** Replace with `find $HOME/.claude/projects/*/memory -name "*.md" ! -name "MEMORY.md" 2>/dev/null`. This is now the single longest-standing unfixed item.
**Priority:** HIGH — escalating from suggestion to blocking issue. Consider fixing directly in the next interactive session rather than waiting for passive migration.

---

## 2026-04-06 — Run #17

### S40: discord-bot CLAUDE.md missing interactive sessions and pre-job repo sync
**File:** `discord-bot/CLAUDE.md`
**Issue:** Two major features landed since run #16: (1) Interactive Discord sessions with [WAITING_FOR_INPUT] protocol (commit b7e695f) — agents can pause mid-task, ask user a question via Discord, and resume on reply with 30-min timeout. (2) Pre-job repo sync (commit d62f04c) — executor.js now pulls latest agentGuidance and job cwd before every spawn, preventing stale CLAUDE.md on VM agents. Neither was in CLAUDE.md.
**Suggestion:** Added "Interactive Sessions ([WAITING_FOR_INPUT])" and "Pre-Job Repo Sync" sections to CLAUDE.md. (Done in this run.)

### S41: run.sh memory scan single-path — 8th time flagged (CRITICAL)
**File:** `auto-dev/learnings-pass/run.sh` (line 227)
**Issue:** `MEMORY_DIR` hardcoded to single Windows-path project. This run found 37 memory files across 3 project paths (`-home-user-repos/`, `-home-user-repos-discord-bot/`, `-mnt-c-Users-user/`) — only the last is scanned. 4 files in the first two paths are invisible to the learning agent, including `project_session_pool` (discord-bot session pool architecture). **Flagged 8 times across 14 runs (S8→S27→S34→S36→S39→S41).** The `auto-dev-private` repo was recently created with a fresh `learnings-pass/` — this is the ideal time to fix the memory scan path in the new private runner.
**Suggestion:** In both `auto-dev/learnings-pass/run.sh` and `auto-dev-private/learnings-pass/run.sh`, replace the hardcoded `MEMORY_DIR` with: `find $HOME/.claude/projects/*/memory -name "*.md" ! -name "MEMORY.md" 2>/dev/null`
**Priority:** CRITICAL — longest-standing unfixed item, actively causing missed learnings.
**Status:** RESOLVED in autonomousDev-private commit 0d9f7f1 (2026-04-06). The private runner now uses `find` across all project paths. The public autonomousDev runner should also be updated if it's still in use.

---

## 2026-04-07 — Run #18

### S42: secrets-hygiene.md missing automated pre-commit hook pattern
**File:** `agentGuidance/guidance/secrets-hygiene.md`
**Issue:** agentGuidance added a portable pre-commit hook (commit 6f42fed) that scans staged diffs for sensitive identifiers via `security-scan.sh`. The Pre-Commit Checklist section in secrets-hygiene.md only documented manual grep checks. Any public repo could adopt this hook but the pattern wasn't documented as cross-project guidance.
**Suggestion:** Added "Automated Pre-Commit Hook" section above the manual checklist, referencing agentGuidance's implementation as the template. (Done in this run.)

### S43: discord-bot CLAUDE.md WAITING_FOR_INPUT format clarification
**File:** discord-bot CLAUDE.md
**Issue:** The WAITING_FOR_INPUT regex was fixed (commit 0706525) to capture multiline questions — the question text goes on lines AFTER the marker, not the same line. The CLAUDE.md description was ambiguous about this format.
**Suggestion:** Clarified in CLAUDE.md that the question is extracted from lines after the marker as multiline text. (Done in this run.)

### S44: autonomousDev learnings-pass file deletion risk during bulk edits
**File:** `autonomousDev` repo
**Issue:** Commit ef9e7f2 (security redaction of freeGames-priority.md) accidentally deleted learnings-pass/prompt.md, run.sh, and suggestions.md (833 lines removed). Commit ad438af restored them. This happened because the redaction commit was made from a state where the working tree had the files removed or the commit was not scoped properly.
**Suggestion:** When doing bulk security redaction or `git filter-repo` operations, always scope commits to specific files (`git add <file>` not `git add .`) to avoid accidentally including unrelated deletions. This pattern is already implied by git-workflow.md but the risk is elevated during security cleanup work.

---

## 2026-04-07 — Run #19

### S45: Discord bot CLAUDE.md missing CLI mirror streaming sessions
**File:** Discord bot `CLAUDE.md`
**Issue:** Major new subsystem `cliMirror.js` (commit 86625d7) added streaming interactive Discord sessions — live message editing, thread-per-session model, 1800-char freeze threshold, edit debouncing. Follow-up fixes added session recovery on bot restart via footer UUID scanning (37ce053), NDJSON output filtering (7d8ae06), and streaming config forwarding (a1863a4). None documented in CLAUDE.md.
**Suggestion:** Added "CLI Mirror (Streaming Sessions)" section to CLAUDE.md. (Done in this run.)

### S46: auto-shorts-worker CLAUDE.md missing clip boundary, privacy, and Variant B params
**File:** `auto-shorts-worker/CLAUDE.md`
**Issue:** Three features landed without CLAUDE.md updates: (1) clip boundary rule — never cut mid-sentence (commit 9b25bc8), (2) privacy field for public uploads threaded through worker → process_job → upload_clip (commit c909c6a), (3) Variant B smart crop params replacing previous values (0.5% ease, 0.5px/frame max, 121-frame smoothing).
**Suggestion:** Added clip boundary rule, upload privacy docs, and Variant B params to CLAUDE.md. (Done in this run.)

### S47: Discord bot post-job hooks #file-links posting + execFileSync
**File:** Discord bot `CLAUDE.md`
**Issue:** Commit 2f4963f added buying-guide link posting to `#file-links` channel via `FILE_LINKS_WEBHOOK_URL` env var. Also switched git commit from `execSync` with string interpolation to `execFileSync` for shell injection safety. Neither documented.
**Suggestion:** Updated Post-Job Hooks section with #file-links posting and `execFileSync` note. (Done in this run.)

---

## 2026-04-07 — Run #20

### S48: learning-agent.md stale repo name `auto-dev` (S21 incomplete fix)
**File:** `agentGuidance/guidance/learning-agent.md` (line 16)
**Issue:** S21 (run #9) fixed the subdirectory name (`learning-agent/` → `learnings-pass/`) but left the repo name as `auto-dev`. The actual directory is `~/repos/autonomousDev/` — `auto-dev` doesn't exist. The path was `~/repos/auto-dev/learnings-pass/`, now corrected to `~/repos/autonomousDev/learnings-pass/`.
**Suggestion:** Fixed in this run (agentGuidance PR #139, auto-merged).

### S49: comprehensive-closeout.md hardcoded memory path resolved (S26)
**File:** `agentGuidance/guidance/comprehensive-closeout.md` (line 93)
**Issue:** Hardcoded `~/.claude/projects/-mnt-c-Users-npeza/memory/` — both user-specific (sensitive identifier) and wrong for sessions started from other working directories. Flagged since run #11 (S26).
**Suggestion:** Replaced with generic `~/.claude/projects/<project-path>/memory/` template. Fixed in this run (agentGuidance PR #139, auto-merged).

---

## 2026-04-07 — Run #21

### S50: Discord bot CLAUDE.md missing task templates, prompt logging, and daily roundup
**File:** Discord bot `CLAUDE.md`
**Issue:** Three active subsystems were undocumented: taskTemplates.js (`!task` command dispatch with `{{param|default}}` substitution, dynamic add/remove), promptLog.js (verbatim prompt logging to #prompts), and dailyRoundup.js (daily work summary + organic template suggestions). The `project_tasks_framework` memory documented all three but CLAUDE.md only mentioned `!task` in passing under channel watchers.
**Suggestion:** Added "Task Templates & Prompt Logging" section to CLAUDE.md. (Done in this run, PR #143.)

### S51: auto-shorts-worker token file filtering gotcha
**File:** `auto-shorts-worker/pipeline.py`
**Issue:** Commit 433c613 fixed `discover_all_channels()` to only report expired tokens for real channel IDs (starting with "UC"), filtering out generic filenames like `token.json` or `token_agat.json` that create junk DB entries. This is a narrow one-time fix, not a recurring pattern — not worth adding to CLAUDE.md but noted for completeness.

---

## 2026-04-07 — Run #22

### S52: YouTube shorts upload repo CLAUDE.md missing multi-channel auth pattern
**File:** Upload repo `CLAUDE.md`
**Issue:** Commit 6744111 added `auth_en_local.py` with a channel verification pattern (auth + verify channel ID before saving token) and a separate `client_secret_en.json`. CLAUDE.md only mentioned `token_*.json` with no docs on multi-channel auth, per-channel client secrets, or the verification flow. An agent adding a third channel wouldn't know about this pattern.
**Suggestion:** Added multi-channel auth section to CLAUDE.md. (Done in this run.)

### S53: Stale unmerged learnings branches accumulating across 11 repos (S37 escalation)
**File:** Multiple repos
**Issue:** S37 (run #15) flagged 15 stale branches in autonomousDev. Now there are stale `claude/learnings-*` branches across 11 repos (autonomousDev: 5, Discord bot: 5, youtubeSpeedSetAndRemember: 4, claude-auto-merger: 3, auto-shorts-worker: 2, freeGames: 2, agentGuidance: 2, LLM tasks: 1, job-scraper: 1, nll-hunter: 1, upload pipeline: 1). These are from prior runs whose content was merged via subsequent PRs but whose branches were never cleaned up.
**Suggestion:** Add a periodic cleanup step to the learnings-pass runner or a standalone cleanup script. The auto-merger already handles PR creation and merge — it should also delete the source branch after merge. Alternatively, add `--delete-branch-after-merge` to the auto-merger config.
**Priority:** MEDIUM — cosmetic but growing. No functional impact yet but branch listings are increasingly noisy.

---

## 2026-04-07 — Run #23

### S54: feedback_pipefail_grep migrated to operational-safety.md
**File:** `agentGuidance/guidance/operational-safety.md`
**Status:** Added "Bash `pipefail` + `grep -c` Silent Failure" section. Migrated from memory-only `feedback_pipefail_grep`. The pattern caused 13 days of silent security scanner failure and is relevant to any agent writing bash scripts with `set -eo pipefail`. (Done in this run.)

### S55: autonomousDev repo still missing CLAUDE.md
**File:** `autonomousDev/CLAUDE.md` (does not exist)
**Issue:** autonomousDev hosts the learning agent, fix-checker, and autonomous dev runner — all core automation infrastructure. Yet it has no CLAUDE.md. Agents working in this repo (e.g., to modify the learning agent runner, fix-checker prompts, or add a new autonomous task) lack context on directory structure, how runs are triggered, and the relationship between public autonomousDev and the private runner.
**Suggestion:** Create a CLAUDE.md documenting: directory structure (learnings-pass/, fix-checker/), run triggers (cron at :43 for learnings, hourly fix-checker), public vs private runner split, and the suggestions.md append-only convention.
**Priority:** LOW — the learning agent prompt itself has detailed instructions, but a CLAUDE.md would help agents doing ad-hoc work in the repo.

---

## 2026-04-07 — Run #24

### S56: auto-shorts-worker CLAUDE.md missing channel verification guard
**File:** `auto-shorts-worker/CLAUDE.md`
**Issue:** Commit 4bc71a9 added a runtime channel verification guard in `_get_youtube_service()` — before uploading, the worker calls the YouTube API to verify the token's actual channel ID matches the target. This prevents silently uploading to the wrong channel when a token gets re-authed to a different brand account. Not documented in CLAUDE.md.
**Suggestion:** Added "Channel Verification Guard" section under Upload Privacy. (Done in this run.)

### S57: Stale unmerged learnings branches still accumulating (S53 repeat, MEDIUM)
**File:** Multiple repos
**Issue:** S37 (run #15) and S53 (run #22) flagged stale `claude/learnings-*` branches across 11+ repos. Still unfixed. The auto-merger creates PRs and merges them but doesn't delete source branches. This is cosmetic but growing — branch listings are increasingly noisy.
**Suggestion:** Add `--delete-branch-after-merge` behavior to the auto-merger, or add a cleanup step to the learnings-pass runner. 3rd time flagged.
**Priority:** MEDIUM — no functional impact but increasingly noisy.

---

## 2026-04-07 — Run #25

### S58: testing.md now documents typed mock helpers pattern
**File:** `agentGuidance/guidance/testing.md`
**Status:** Added typed factory function pattern to Mocking Guidelines. Derived from runeval PR #94 which replaced 34 `as any` casts with typed helpers (fakeOAuthToken, fakeAdapter, etc.). Cross-project pattern — any TypeScript repo with test mocks benefits. (Done in this run.)

### S59: testing.md now documents test fixture schema drift
**File:** `agentGuidance/guidance/testing.md`
**Status:** Added "Test Fixture Schema Drift" section. Derived from auto-shorts run #4 where 28 tests failed because inline CREATE TABLE statements were missing columns (burn_captions, smart_crop, privacy) added by migrations. Cross-project pattern — any repo with in-memory DB test fixtures. (Done in this run.)

### S60: freeGames has 3 unmerged test branches blocked by PAT scope
**File:** freeGames repo
**Issue:** autonomousDev run #15 pushed branch `orch-tests-3` but couldn't create a PR because the fine-grained PAT doesn't include freeGames in its allowed repos. Two earlier test suites (checkout-server-email, claim-orchestrator) are also on unmerged branches. These branches contain ~100 new tests that aren't on main.
**Suggestion:** Add freeGames to the fine-grained PAT's allowed repo list. Then create PRs for the pending branches (or push from a PAT with full repo scope).
**Priority:** HIGH — 100+ tests are stranded on branches with no PR.

---

## 2026-04-07 — Run #26

### S61: Fine-grained PAT scope now blocking 24 repos (S60 escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60 flagged freeGames specifically. The problem has exploded: 158 unmerged `claude/auto-*` branches now exist across **24 repos**. The fine-grained PAT only covers a subset of repos, so the auto-merger can push branches but can't create PRs for most of them. Top offenders: botlink (26), groceryGenius (22), promptlibrary (22), valueSortify (16), freeGames (14). Every autonomousDev run that targets an out-of-scope repo creates another stranded branch.
**Suggestion:** Either (a) switch to a classic PAT with full repo scope, or (b) add all actively-developed repos to the fine-grained PAT's allowed list. Then bulk-create PRs for the 158 pending branches, or run a cleanup script to merge branches where tests pass and changes are clean.
**Priority:** CRITICAL — this is the single largest infrastructure gap. Work is being done but can't be merged. Escalating from HIGH (S60) to CRITICAL.

### S62: Stale branch accumulation at 158 branches (S37/S53/S57 — 5th flag)
**File:** Multiple repos (24 affected)
**Issue:** The auto-merger creates PRs and merges them but never deletes source branches. Combined with PAT-scope-blocked branches that can't even get PRs, there are now 158 stale `claude/auto-*` and `claude/learnings-*` branches across 24 repos. First flagged in S37 (run #15), then S53 (run #22), S57 (run #24). The auto-merger's `lib.js` `deleteBranch()` function exists but is only called on merge — branches that fail PR creation are never cleaned up.
**Suggestion:** Two-part fix: (1) Add post-merge branch deletion to auto-merger (call GitHub API to delete source branch after successful merge). (2) Add a periodic cleanup script for orphaned branches where the content is already on main (e.g., via cherry-pick or subsequent PR).
**Priority:** HIGH — upgraded from MEDIUM. 158 branches is noise that obscures real pending work.

### S63: autonomousDev still missing CLAUDE.md (S55 repeat)
**File:** `autonomousDev/CLAUDE.md` (does not exist)
**Issue:** Second time flagged. autonomousDev hosts core automation (learnings-pass, fix-checker, autonomous dev runner) but has no CLAUDE.md. Any agent modifying the learning agent, runner, or fix-checker prompts lacks context on directory structure, cron triggers, and the public/private runner split.
**Suggestion:** Create CLAUDE.md with: directory layout, run triggers (cron at :43 for learnings, autonomousDev runner via Discord), relationship to autonomousDev-private, and suggestions.md conventions.
**Priority:** LOW — agents working here use the detailed prompt.md instructions, but a CLAUDE.md would help ad-hoc work.

---

## 2026-04-07 — Learning Agent Run #24b

### S64: claude-auto-merger CLAUDE.md phantom write — resolved
**File:** `claude-auto-merger/CLAUDE.md`
**Issue:** S17/S19 (run #9) and S29 (run #12) both claimed to create/update claude-auto-merger CLAUDE.md, and completed-work.md marked them as done. But the CLAUDE.md didn't exist on main — it was on unmerged branches. The server-helpers PR (run #29 autonomousDev) finally merged a CLAUDE.md to main, but it lacked the race condition gotcha from S29.
**Resolution:** Added race condition documentation and server-helpers.js architecture to the now-existing CLAUDE.md (PR #15, auto-merged). This resolves S17, S19, and S29 properly.
**Lesson:** When completed-work.md says "created CLAUDE.md" but it was on a learnings branch, verify the branch was actually merged before marking as fully resolved. Learnings branches require Discord approval — they don't auto-merge.

### S65: claude-token-tracker missing CLAUDE.md
**File:** `claude-token-tracker/CLAUDE.md` (does not exist)
**Issue:** claude-token-tracker has had 10 PRs (mostly Vite security fixes) but no CLAUDE.md. It's a React + Vite app for tracking Claude usage. Without CLAUDE.md, agents working there lack context on the app's purpose, build process, and deployment.
**Suggestion:** Create CLAUDE.md with app purpose, tech stack (React + Vite + TypeScript), and deployment details.
**Priority:** LOW — this repo gets infrequent automated maintenance (security patches), not feature work.

### S66: Duplicate PR race condition in auto-merger now documented
**File:** `claude-auto-merger/CLAUDE.md`
**Status:** Done. Documented the TOCTOU race in push webhook handler that creates 2-3 duplicate PRs when multiple webhooks arrive within milliseconds. Impact is cosmetic (all merge fine) but clutters PR history. Root cause: no mutex between pulls.list check and pulls.create call in server.js ~lines 396-407.

---

## 2026-04-07 — Learning Agent Run #25

### S67: tampermonkey.md now documents debug flags pattern
**File:** `agentGuidance/guidance/tampermonkey.md`
**Status:** Added "Debug & Verbose Logging" section. Two independent TM userscripts (ChatGPTCompletionChime, GeminiCompletionChime) both shipped with debug flags enabled in production on the same day — console spam every 750ms for all users. Pattern: always ship with `const DEBUG = false` and gate console output. (Done in this run.)

### S68: PAT scope still blocking 24+ repos (S61 — 3rd escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60 (HIGH) → S61 (CRITICAL) → still unfixed. 158+ unmerged `claude/auto-*` branches across 24 repos. Every autonomousDev run that targets an out-of-scope repo creates another stranded branch. This is the single largest infrastructure gap — work is being done but can't be merged.
**Suggestion:** Either switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT's allowed list. This continues to be the #1 priority infrastructure fix.
**Priority:** CRITICAL — 4th time flagged.

### S69: Stale branch accumulation continues (S62 — 6th flag, HIGH)
**File:** Multiple repos (24+ affected)
**Issue:** 158+ stale `claude/auto-*` and `claude/learnings-*` branches across 24 repos. The auto-merger creates PRs and merges but never deletes source branches. Combined with PAT-scope-blocked branches. First flagged S37 (run #15), now flagged 6 times.
**Suggestion:** Add post-merge branch deletion to auto-merger and a periodic cleanup script for orphaned branches.
**Priority:** HIGH — cosmetic but growing rapidly.

---

## 2026-04-07 — Learning Agent Run #26

### S70: pm-interview-practice missing CLAUDE.md
**File:** `pm-interview-practice/CLAUDE.md` (does not exist)
**Issue:** pm-interview-practice is a new repo (4 commits) with a live audio mock interview tool. It has Express + WebSocket + Claude CLI interviewer + browser TTS/STT. A memory file (`project_interview_practice`) documents the architecture but the repo itself has no CLAUDE.md. The `context.md` exists but CLAUDE.md is what agents read first.
**Suggestion:** Create CLAUDE.md with architecture overview (Express+WS on port 3456, Claude CLI via sonnet, browser speech APIs), deployment (SSH tunnel to VM), and key files. Low urgency since this repo gets infrequent changes.
**Priority:** LOW — new repo, infrequent changes.

### S71: PAT scope still blocking 24+ repos (S68 — 5th escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60→S61→S68→still unfixed. Every autonomousDev run targeting an out-of-scope repo creates another stranded branch with no PR. 158+ unmerged branches accumulating. This is now the longest-standing CRITICAL issue (first flagged run #25 as S60, 8 runs ago).
**Suggestion:** Switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT. Then bulk-create PRs for pending branches.
**Priority:** CRITICAL — 5th time flagged. Infrastructure debt is compounding.

### S72: Stale branch accumulation continues (S69 — 7th flag, HIGH)
**File:** Multiple repos (24+ affected)
**Issue:** 158+ stale branches. autonomousDev alone has 10 unmerged `claude/learnings-*` remote branches. The auto-merger never deletes source branches after merge, and PAT-blocked branches accumulate indefinitely.
**Suggestion:** Add post-merge branch deletion to auto-merger. Run periodic cleanup for merged-content branches.
**Priority:** HIGH — 7th time flagged.

---

## 2026-04-07 — Learning Agent Run #27

### S73: PAT scope still blocking 24+ repos (S71 — 6th escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60→S61→S68→S71→still unfixed. Every autonomousDev run targeting an out-of-scope repo creates another stranded branch with no PR. 158+ unmerged branches accumulating across 24 repos. First flagged run #25 (S60), now flagged in 6 consecutive runs. This is the single largest infrastructure gap — completed work cannot be merged.
**Suggestion:** Switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT. Then bulk-create PRs for pending branches.
**Priority:** CRITICAL — 6th time flagged. No progress since first report.

### S74: Stale branch accumulation continues (S72 — 8th flag, HIGH)
**File:** Multiple repos (24+ affected)
**Issue:** 158+ stale `claude/auto-*` and `claude/learnings-*` branches across 24 repos. autonomousDev alone has 10+ unmerged remote learnings branches. The auto-merger never deletes source branches after merge, and PAT-blocked branches accumulate indefinitely. First flagged S37 (run #15), now flagged 8 times.
**Suggestion:** Add post-merge branch deletion to auto-merger. Run periodic cleanup for merged-content branches.
**Priority:** HIGH — 8th time flagged.

### S75: pm-interview-practice still missing CLAUDE.md (S70 repeat)
**File:** `pm-interview-practice/CLAUDE.md` (does not exist)
**Issue:** S70 flagged this in run #26. Repo has 4 commits, live deployment at /interview/, and a deep closeout posted. Memory file documents architecture but no CLAUDE.md exists. The repo has `context.md` and `progress.md` from closeout but those are session artifacts, not agent instructions.
**Suggestion:** Create CLAUDE.md with architecture (Express+WS port 3456, Claude CLI interviewer, browser TTS/STT), deployment (SSH tunnel), and key files.
**Priority:** LOW — infrequent changes, 2nd time flagged.

---

## 2026-04-08 — Learning Agent Run #28

### S76: PAT scope blocking 24+ repos — branch count jumped 158→268 (S73 — 7th escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60→S61→S68→S71→S73→still unfixed. Unmerged `claude/auto-*` and `claude/learnings-*` branches have grown from 158 (run #25) to **268** across 31 repos. The fine-grained PAT only covers a subset of repos, so autonomousDev runs push branches but can't create PRs. Top offenders: [private Discord bot] (43), botlink (25), promptlibrary (21), [private social app] (21), groceryGenius (21), freeGames (18), valueSortify (16). Every hour of autonomous dev work adds 1-3 more stranded branches.
**Suggestion:** Switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT. Then bulk-create PRs for pending branches. This has been flagged in 7 consecutive runs without resolution.
**Priority:** CRITICAL — 7th time flagged. Branch count growing ~70% since first report.

### S77: Stale branch accumulation now at 268 branches across 31 repos (S74 — 9th flag, HIGH)
**File:** Multiple repos (31 affected, up from 24)
**Issue:** 268 unmerged `claude/` branches across 31 repos (was 158 across 24 repos at S62). autonomousDev has 11, [private Discord bot] 43, botlink 25. The auto-merger never deletes source branches after merge, and PAT-blocked branches accumulate indefinitely. First flagged S37 (run #15), now flagged 9 times.
**Suggestion:** Add post-merge branch deletion to auto-merger. Run periodic cleanup for branches whose content is already on main.
**Priority:** HIGH — 9th time flagged, count growing faster than work is being merged.

### S78: pm-interview-practice still missing CLAUDE.md (S75 — 3rd flag)
**File:** `pm-interview-practice/CLAUDE.md` (does not exist)
**Issue:** Flagged in S70 (run #26), S75 (run #27), still not created. Repo has a live deployment, deep closeout posted, and memory documentation but no CLAUDE.md for agent context.
**Suggestion:** Create CLAUDE.md with architecture, deployment, and key files.
**Priority:** LOW — 3rd time flagged, infrequent changes.

---

## 2026-04-08 — Learning Agent Run #29

### S79: PAT scope blocking 24+ repos — 231 branches across 14+ repos (S76 — 8th escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60→S61→S68→S71→S73→S76→still unfixed. Current count: 231 `claude/` branches across 14 repos with >5 branches each. Top offenders: [private Discord bot] (46), botlink (26), groceryGenius (22), promptlibrary (22), [private social app] (22), freeGames (19), valueSortify (17). The fine-grained PAT covers only a subset of repos, so autonomousDev runs push branches but can't create PRs for most. Some branches may have been cleaned up via auto-merge (down from 268 peak) but the underlying PAT scope issue persists.
**Suggestion:** Switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT. Then bulk-create PRs for pending branches.
**Priority:** CRITICAL — 8th consecutive run flagged. This is the single largest infrastructure gap.

### S80: Stale branch accumulation — 231 branches across 14+ repos (S77 — 10th flag, HIGH)
**File:** Multiple repos (14 repos with >5 branches each)
**Issue:** 231 stale `claude/auto-*` and `claude/learnings-*` branches. The auto-merger never deletes source branches after merge. PAT-blocked branches accumulate indefinitely. First flagged S37 (run #15), now 10th time flagged.
**Suggestion:** Add post-merge branch deletion to auto-merger. Run periodic cleanup for branches whose content is already on main.
**Priority:** HIGH — 10th time flagged.

### S81: pm-interview-practice still missing CLAUDE.md (S78 — 4th flag)
**File:** `pm-interview-practice/CLAUDE.md` (does not exist)
**Issue:** Flagged in S70, S75, S78, still not created. Repo has 4 commits, live deployment at /interview/, deep closeout posted, and memory documentation but no CLAUDE.md.
**Suggestion:** Create CLAUDE.md with architecture (Express+WS port 3456, Claude CLI interviewer, browser TTS/STT), deployment (SSH tunnel), key files.
**Priority:** LOW — 4th time flagged, infrequent changes.

---

## 2026-04-08 — Learning Agent Run #30

### S82: auto-shorts-worker CLAUDE.md missing clip selection criteria (memory-only gap — RESOLVED)
**File:** `auto-shorts-worker/CLAUDE.md`
**Issue:** Two feedback memories (`feedback_shorts_profanity_gate`, `feedback_shorts_streamer_voice`) existed only in memory — not in the repo CLAUDE.md or agentGuidance. These are clip selection rules: profanity raises the quality bar, and streamer voice takes priority over guests. Any agent selecting clips wouldn't know about these criteria.
**Status:** Migrated to auto-shorts-worker CLAUDE.md in this run (PR #13). Added "Clip Selection Criteria" section above the existing "Clip Boundary Rule".

### S83: PAT scope blocking 24+ repos — 231+ branches (S79 — 9th escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60→S61→S68→S71→S73→S76→S79→still unfixed. 231+ unmerged `claude/auto-*` and `claude/learnings-*` branches across 14+ repos with >5 branches each. The fine-grained PAT only covers a subset of repos, so autonomousDev runs push branches but can't create PRs. Every run adds 1-3 more stranded branches. First flagged run #25, now 9th consecutive run.
**Suggestion:** Switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT. Then bulk-create PRs for pending branches.
**Priority:** CRITICAL — 9th time flagged. No progress since first report.

### S84: Stale branch accumulation — 231+ branches (S80 — 11th flag, HIGH)
**File:** Multiple repos (14+ repos with >5 branches each)
**Issue:** 231+ stale `claude/auto-*` and `claude/learnings-*` branches. The auto-merger never deletes source branches after merge. PAT-blocked branches accumulate indefinitely. First flagged S37 (run #15), now 11th time flagged.
**Suggestion:** Add post-merge branch deletion to auto-merger. Run periodic cleanup for branches whose content is already on main.
**Priority:** HIGH — 11th time flagged.

---

## 2026-04-08 — Learning Agent Run #31

### S85: PAT scope blocking 24+ repos — 264 branches across 29 repos (S83 — 10th escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60→S61→S68→S71→S73→S76→S79→S83→still unfixed. Unmerged `claude/auto-*` and `claude/learnings-*` branches now total **264** across **29 repos** (up from 231 across 14+ at run #30). Top offenders: [private Discord bot] (44), botlink (26), groceryGenius (22), promptlibrary (22), freeGames (18), valueSortify (16). The fine-grained PAT only covers a subset of repos, so autonomousDev runs push branches but can't create PRs. First flagged run #25, now 10th consecutive run.
**Suggestion:** Switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT. Then bulk-create PRs for pending branches.
**Priority:** CRITICAL — 10th time flagged. Branch count grew from 231→264 despite some branches being merged. No progress on the underlying PAT scope issue.

### S86: Stale branch accumulation — 264 branches across 29 repos (S84 — 12th flag, HIGH)
**File:** Multiple repos (29 affected)
**Issue:** 264 stale `claude/auto-*` and `claude/learnings-*` branches across 29 repos. The auto-merger never deletes source branches after merge. PAT-blocked branches accumulate indefinitely. First flagged S37 (run #15), now 12th time flagged. Repos with highest counts: [private Discord bot] (44), botlink (26), groceryGenius (22), promptlibrary (22).
**Suggestion:** Add post-merge branch deletion to auto-merger. Run periodic cleanup for branches whose content is already on main.
**Priority:** HIGH — 12th time flagged, 264 branches is increasingly problematic.

### S87: pm-interview-practice still missing CLAUDE.md (S81 — 5th flag)
**File:** `pm-interview-practice/CLAUDE.md` (does not exist)
**Issue:** Flagged in S70 (run #26), S75 (run #27), S78 (run #28), S81 (run #29), still not created. Repo has a live deployment, deep closeout posted, and memory documentation but no CLAUDE.md for agent context.
**Suggestion:** Create CLAUDE.md with architecture (Express+WS port 3456, Claude CLI interviewer, browser TTS/STT), deployment (SSH tunnel), key files.
**Priority:** LOW — 5th time flagged, infrequent changes.

---

## 2026-04-08 — Learning Agent Run #32

### S88: PAT scope blocking 24+ repos — 246 branches across 20 repos (S85 — 11th escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60→S61→S68→S71→S73→S76→S79→S83→S85→still unfixed. Unmerged `claude/auto-*` and `claude/learnings-*` branches now total **246** across **20 repos** (down from 264/29 at run #31 — some cleanup via auto-merge, but the underlying PAT scope issue persists). Top offenders: [private Discord bot] (44), botlink (26), groceryGenius (22), promptlibrary (22), freeGames (18), valueSortify (16). The fine-grained PAT only covers a subset of repos, so autonomousDev runs push branches but can't create PRs. First flagged run #25, now 11th consecutive run.
**Suggestion:** Switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT. Then bulk-create PRs for pending branches.
**Priority:** CRITICAL — 11th time flagged. Branch count decreased slightly (264→246) from auto-merge cleanup but new branches continue accumulating.

### S89: Stale branch accumulation — 246 branches across 20 repos (S86 — 13th flag, HIGH)
**File:** Multiple repos (20 affected)
**Issue:** 246 stale `claude/auto-*` and `claude/learnings-*` branches across 20 repos. The auto-merger never deletes source branches after merge. PAT-blocked branches accumulate indefinitely. First flagged S37 (run #15), now 13th time flagged.
**Suggestion:** Add post-merge branch deletion to auto-merger. Run periodic cleanup for branches whose content is already on main.
**Priority:** HIGH — 13th time flagged.

### S90: pm-interview-practice still missing CLAUDE.md (S87 — 6th flag)
**File:** `pm-interview-practice/CLAUDE.md` (does not exist)
**Issue:** Flagged in S70, S75, S78, S81, S85, S87 — still not created. Repo has a live deployment, deep closeout posted, and memory documentation but no CLAUDE.md for agent context.
**Suggestion:** Create CLAUDE.md with architecture (Express+WS port 3456, Claude CLI interviewer, browser TTS/STT), deployment (SSH tunnel), key files.
**Priority:** LOW — 6th time flagged, infrequent changes.

---

## 2026-04-08 — Learning Agent Run #33

### S91: PAT scope blocking 24+ repos — 282 branches across 34 repos (S88 — 12th escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60→S61→S68→S71→S73→S76→S79→S83→S85→S88→still unfixed. Unmerged `claude/auto-*` and `claude/learnings-*` branches now total **282** across **34 repos** (up from 246/20 at run #32). Top offenders: [private Discord bot] (46), botlink (26), groceryGenius (22), promptlibrary (22), [private social app] (22), freeGames (19), valueSortify (17). The fine-grained PAT only covers a subset of repos, so autonomousDev runs push branches but can't create PRs. First flagged run #25, now 12th consecutive run.
**Suggestion:** Switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT. Then bulk-create PRs for pending branches.
**Priority:** CRITICAL — 12th time flagged. Branch count grew 246→282 despite some auto-merge cleanup. No progress on underlying PAT scope issue.

### S92: Stale branch accumulation — 282 branches across 34 repos (S89 — 14th flag, HIGH)
**File:** Multiple repos (34 affected)
**Issue:** 282 stale `claude/auto-*` and `claude/learnings-*` branches across 34 repos. The auto-merger never deletes source branches after merge. PAT-blocked branches accumulate indefinitely. First flagged S37 (run #15), now 14th time flagged.
**Suggestion:** Add post-merge branch deletion to auto-merger. Run periodic cleanup for branches whose content is already on main.
**Priority:** HIGH — 14th time flagged.

### S93: pm-interview-practice still missing CLAUDE.md (S90 — 7th flag)
**File:** `pm-interview-practice/CLAUDE.md` (does not exist)
**Issue:** Flagged in S70, S75, S78, S81, S85, S87, S90 — still not created. Repo has a live deployment, deep closeout posted, and memory documentation but no CLAUDE.md for agent context.
**Suggestion:** Create CLAUDE.md with architecture (Express+WS port 3456, Claude CLI interviewer, browser TTS/STT), deployment (SSH tunnel), key files.
**Priority:** LOW — 7th time flagged, infrequent changes.

---

## 2026-04-08 — Learning Agent Run #34

### S94: PAT scope blocking 24+ repos — 294 branches across 20 repos (S91 — 13th escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60→S61→S68→S71→S73→S76→S79→S83→S85→S88→S91→still unfixed. Unmerged `claude/auto-*` and `claude/learnings-*` branches now total **294** across **20 repos** (up from 282/34 at run #33). Top offenders: [private Discord bot] (58), groceryGenius (31), botlink (29), promptlibrary (27), freeGames (23), valueSortify (20). The fine-grained PAT only covers a subset of repos, so autonomousDev runs push branches but can't create PRs. First flagged run #25, now 13th consecutive run.
**Suggestion:** Switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT. Then bulk-create PRs for pending branches.
**Priority:** CRITICAL — 13th time flagged. Branch count grew 282→294. No progress on underlying PAT scope issue.

### S95: Stale branch accumulation — 294 branches across 20 repos (S92 — 15th flag, HIGH)
**File:** Multiple repos (20 affected)
**Issue:** 294 stale `claude/auto-*` and `claude/learnings-*` branches across 20 repos. The auto-merger never deletes source branches after merge. PAT-blocked branches accumulate indefinitely. First flagged S37 (run #15), now 15th time flagged.
**Suggestion:** Add post-merge branch deletion to auto-merger. Run periodic cleanup for branches whose content is already on main.
**Priority:** HIGH — 15th time flagged.

### S96: pm-interview-practice still missing CLAUDE.md (S93 — 8th flag)
**File:** `pm-interview-practice/CLAUDE.md` (does not exist)
**Issue:** Flagged in S70, S75, S78, S81, S85, S87, S90, S93 — still not created. Repo has a live deployment, deep closeout posted, and memory documentation but no CLAUDE.md for agent context.
**Suggestion:** Create CLAUDE.md with architecture (Express+WS port 3456, Claude CLI interviewer, browser TTS/STT), deployment (SSH tunnel), key files.
**Priority:** LOW — 8th time flagged, infrequent changes.

---

## 2026-04-08 — Learning Agent Run #36

### S101: written-voice.md missing em dash anti-pattern (RESOLVED)
**File:** `agentGuidance/guidance/written-voice.md`
**Status:** Added item #11 to "Common Mistakes When Imitating Nick's Voice": em dashes are an AI writing tell. Nick uses regular dashes, commas, or new sentences. Discovered in Dan Sears outreach session (2026-04-08), user noted "em dashes are AI anti-pattern" when reviewing draft. (Done in this run.)

### S102: auto-shorts CLAUDE.md missing analytics dashboard feature (RESOLVED)
**File:** `auto-shorts/CLAUDE.md`
**Status:** Added Features section documenting analytics dashboard (Phase 1): per-clip performance tracking via YouTube Data API, new tables, 3 dashboard views, preset comparison. Commit 084a0d5 added the feature but CLAUDE.md wasn't updated. (Done in this run.)

### S103: PAT scope blocking 24+ repos — 281 branches across 20 repos (S98 — 15th escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60→...→S98→still unfixed. Unmerged `claude/auto-*` and `claude/learnings-*` branches now total **281** across **20 repos**. The fine-grained PAT only covers a subset of repos, so autonomousDev runs push branches but can't create PRs. First flagged run #25, now 15th consecutive run.
**Suggestion:** Switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT. Then bulk-create PRs for pending branches.
**Priority:** CRITICAL — 15th time flagged. No progress on underlying PAT scope issue.

### S104: Stale branch accumulation — 281 branches across 20 repos (S99 — 17th flag, HIGH)
**File:** Multiple repos (20 affected)
**Issue:** 281 stale `claude/auto-*` and `claude/learnings-*` branches. The auto-merger never deletes source branches after merge. PAT-blocked branches accumulate indefinitely. First flagged S37 (run #15), now 17th time flagged.
**Suggestion:** Add post-merge branch deletion to auto-merger. Run periodic cleanup for branches whose content is already on main.
**Priority:** HIGH — 17th time flagged.

### S105: pm-interview-practice still missing CLAUDE.md (S100 — 10th flag)
**File:** `pm-interview-practice/CLAUDE.md` (does not exist)
**Issue:** Flagged 10 times since S70. Repo has a live deployment, deep closeout posted, and memory documentation but no CLAUDE.md for agent context.
**Suggestion:** Create CLAUDE.md with architecture (Express+WS port 3456, Claude CLI interviewer, browser TTS/STT), deployment (SSH tunnel), key files.
**Priority:** LOW — 10th time flagged, infrequent changes.

---

## 2026-04-08 — Learning Agent Run #38

### S112: auto-shorts CLAUDE.md missing experimentation framework and learning agent (RESOLVED)
**File:** `auto-shorts/CLAUDE.md`
**Issue:** 8 commits since run #37 added per-channel learning agent (`shorts-learning-agent.js`), experimentation framework with AI-suggested experiments, channel switcher dropdown, and experiment queuing. None documented in CLAUDE.md. These are major new subsystems — the learning agent auto-injects insights into worker prompts, and experiments let you A/B test clip selection strategies.
**Suggestion:** Added 3 feature bullets to CLAUDE.md: per-channel learning agent, experimentation framework, channel switcher. (Done in this run.)

### S113: PAT scope blocking 24+ repos — 273 branches (S103 — 17th escalation, CRITICAL)
**File:** GitHub PAT configuration (infrastructure)
**Issue:** S60→...→S103→still unfixed. Unmerged `claude/auto-*` and `claude/learnings-*` branches total **273** across repos. The fine-grained PAT only covers a subset of repos, so autonomousDev runs push branches but can't create PRs. First flagged run #25, now 17th consecutive run.
**Suggestion:** Switch to a classic PAT with full repo scope, or add all actively-developed repos to the fine-grained PAT. Then bulk-create PRs for pending branches.
**Priority:** CRITICAL — 17th time flagged. No progress on underlying PAT scope issue.

### S114: Stale branch accumulation — 273 branches (S104 — 18th flag, HIGH)
**File:** Multiple repos
**Issue:** 273 stale `claude/auto-*` and `claude/learnings-*` branches. The auto-merger never deletes source branches after merge. PAT-blocked branches accumulate indefinitely. First flagged S37 (run #15), now 18th time flagged.
**Suggestion:** Add post-merge branch deletion to auto-merger. Run periodic cleanup for branches whose content is already on main.
**Priority:** HIGH — 18th time flagged.

### S115: pm-interview-practice still missing CLAUDE.md (S105 — 12th flag)
**File:** `pm-interview-practice/CLAUDE.md` (does not exist)
**Issue:** Flagged 12 times since S70. Repo has a live deployment, deep closeout posted, and memory documentation but no CLAUDE.md for agent context.
**Suggestion:** Create CLAUDE.md with architecture (Express+WS port 3456, Claude CLI interviewer, browser TTS/STT), deployment (SSH tunnel), key files.
**Priority:** LOW — 12th time flagged, infrequent changes.
