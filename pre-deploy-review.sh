#!/usr/bin/env bash
# pre-deploy-review.sh — Gemini reviews the final diff before posting for merge.
# A second-opinion check focused on bugs, regressions, and security issues
# that the original coding pass may have introduced.
#
# Usage: ./pre-deploy-review.sh <repos_root> <repo_name> <pr_number>
# stdout last line: PREDEPLOY_PASS|PREDEPLOY_FAIL|PREDEPLOY_CONCERNS: <details>

set -uo pipefail

REPOS_ROOT="${1:?Usage: pre-deploy-review.sh <repos_root> <repo_name> <pr_number>}"
REPO_NAME="${2:?}"
PR_NUMBER="${3:?}"
REPO_DIR="$REPOS_ROOT/$REPO_NAME"
GEMINI_BIN="${GEMINI_BIN:-gemini}"

if [ ! -d "$REPO_DIR" ]; then
  echo "PREDEPLOY_SKIP: repo dir not found"
  exit 0
fi

cd "$REPO_DIR"

# ── Get PR diff ──────────────────────────────────────────────────────

PR_BRANCH=$(gh pr view "$PR_NUMBER" --json headRefName -q '.headRefName' 2>/dev/null || echo "")
if [ -z "$PR_BRANCH" ]; then
  echo "PREDEPLOY_SKIP: could not resolve PR #$PR_NUMBER branch"
  exit 0
fi

git fetch origin "$PR_BRANCH" 2>/dev/null || true

# Get the diff against main
DIFF=$(git diff "origin/main...origin/$PR_BRANCH" 2>/dev/null || git diff "origin/master...origin/$PR_BRANCH" 2>/dev/null || echo "")
if [ -z "$DIFF" ]; then
  echo "PREDEPLOY_SKIP: empty diff"
  exit 0
fi

# Truncate very large diffs
DIFF=$(echo "$DIFF" | head -500)

# Get changed file list for context
FILES_CHANGED=$(git diff --name-only "origin/main...origin/$PR_BRANCH" 2>/dev/null || echo "")

# ── Build pre-deploy review prompt ───────────────────────────────────

REVIEW_PROMPT="You are a pre-deploy code reviewer. This diff is about to be merged and deployed. Your job is to catch bugs, regressions, and security issues that could cause production incidents.

## Repo: $REPO_NAME
## PR: #$PR_NUMBER
## Files Changed:
$FILES_CHANGED

## Diff
\`\`\`diff
$DIFF
\`\`\`

## What to Check
1. **Runtime errors:** Will any of these changes crash at runtime? Missing imports, undefined variables, wrong function signatures, type mismatches?
2. **Data corruption:** Could these changes cause data loss, duplication, or corruption? Check database operations, file writes, API calls.
3. **Security regressions:** Does this introduce injection vectors, bypass auth checks, expose secrets, or weaken validation?
4. **Edge cases:** What happens with empty input, null values, very large data, concurrent access?
5. **Breaking changes:** Will this break existing callers, API consumers, or dependent services?

Focus ONLY on real, concrete issues. Do not flag style preferences, minor naming choices, or hypothetical concerns.

## Output
End your response with exactly ONE of these lines:

PREDEPLOY_PASS: No blocking issues found, safe to merge
PREDEPLOY_CONCERNS: <concrete issue summary>
PREDEPLOY_FAIL: <blocking issue that will cause production problems>"

# ── Run Gemini review ────────────────────────────────────────────────

REVIEW_LOG=$(mktemp)
timeout 120 "$GEMINI_BIN" --yolo -p "$REVIEW_PROMPT" > "$REVIEW_LOG" 2>&1 || true

# ── Parse result ─────────────────────────────────────────────────────

REVIEW_RESULT=$(grep -E '^PREDEPLOY_(PASS|FAIL|CONCERNS):' "$REVIEW_LOG" | tail -1 || echo "")

if [ -z "$REVIEW_RESULT" ]; then
  REVIEW_RESULT=$(grep -oE 'PREDEPLOY_(PASS|FAIL|CONCERNS):.*' "$REVIEW_LOG" | tail -1 || echo "")
fi

rm -f "$REVIEW_LOG"

if [ -n "$REVIEW_RESULT" ]; then
  echo "$REVIEW_RESULT"
else
  echo "PREDEPLOY_SKIP: could not parse review result"
fi

exit 0
