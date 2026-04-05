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
