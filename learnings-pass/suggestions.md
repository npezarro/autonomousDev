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
