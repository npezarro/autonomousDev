# Learning Agent — Prompt & Instruction Suggestions

Append-only log of improvement suggestions identified by the learning agent.
Each entry includes the suggestion, rationale, and which file/prompt it applies to.

---

## 2026-04-05 — Run #1

### S1: learnings-pass/prompt.md references nonexistent completed-work.md
**File:** `autonomousDev/learnings-pass/prompt.md`
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
**File:** `autonomousDev/learnings-pass/run.sh`
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
  - Line 17: Location says `~/repos/autonomousDev/learning-agent/` but actual location is `~/repos/autonomousDev/learnings-pass/`
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
