#!/usr/bin/env bash
# review.sh — Claude Code review of a PR created by Gemini.
# Fetches the diff, runs CC with a review prompt, reports pass/fail/concerns.
#
# Usage: ./review.sh <repos_root> <repo_name> <pr_number>
# stdout last line: REVIEW_PASS|REVIEW_FAIL|REVIEW_CONCERNS: <details>

set -uo pipefail

REPOS_ROOT="${1:?Usage: review.sh <repos_root> <repo_name> <pr_number>}"
REPO_NAME="${2:?}"
PR_NUMBER="${3:?}"
REPO_DIR="$REPOS_ROOT/$REPO_NAME"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

if [ ! -d "$REPO_DIR" ]; then
  echo "REVIEW_SKIP: repo dir not found"
  exit 0
fi

cd "$REPO_DIR"

# ── Get PR diff ──────────────────────────────────────────────────────

PR_BRANCH=$(gh pr view "$PR_NUMBER" --json headRefName -q '.headRefName' 2>/dev/null || echo "")
if [ -z "$PR_BRANCH" ]; then
  echo "REVIEW_SKIP: could not resolve PR #$PR_NUMBER branch"
  exit 0
fi

git fetch origin "$PR_BRANCH" 2>/dev/null || true

# Get the diff against main
DIFF=$(git diff "origin/main...origin/$PR_BRANCH" 2>/dev/null || git diff "origin/master...origin/$PR_BRANCH" 2>/dev/null || echo "")
if [ -z "$DIFF" ]; then
  echo "REVIEW_SKIP: empty diff"
  exit 0
fi

# Truncate very large diffs to avoid token limits
DIFF=$(echo "$DIFF" | head -500)

# Get PR title and body for context
PR_TITLE=$(gh pr view "$PR_NUMBER" --json title -q '.title' 2>/dev/null || echo "unknown")
PR_BODY=$(gh pr view "$PR_NUMBER" --json body -q '.body' 2>/dev/null | head -50 || echo "")

# ── Build review prompt ──────────────────────────────────────────────

REVIEW_PROMPT="You are a senior code reviewer. Review this PR diff for bugs, security issues, logic errors, and code quality problems.

## PR Context
- **Repo:** $REPO_NAME
- **PR:** #$PR_NUMBER — $PR_TITLE
- **Description:** $PR_BODY

## Diff to Review
\`\`\`diff
$DIFF
\`\`\`

## Review Criteria
1. **Bugs:** Logic errors, off-by-one, null/undefined access, race conditions, incorrect calculations
2. **Security:** Injection (SQL, shell, XSS), missing input validation, exposed secrets, auth bypasses
3. **Data integrity:** Missing error handling at boundaries, silent failures, data loss scenarios
4. **Breaking changes:** API contract changes, removed exports, changed function signatures
5. **Style:** Only flag if it causes functional issues (not cosmetic preferences)

## Output Format
End your response with exactly ONE of these lines (no other text after it):

If no issues found:
REVIEW_PASS: Code looks correct, no bugs or security issues found

If minor concerns (should merge but note for awareness):
REVIEW_CONCERNS: <1-2 sentence summary of concerns>

If blocking issues found (should NOT merge until fixed):
REVIEW_FAIL: <1-2 sentence summary of blocking issues>"

# ── Run Claude Code review ──────────────────────────────────────────

REVIEW_LOG=$(mktemp)
timeout 120 "$CLAUDE_BIN" -p "$REVIEW_PROMPT" --model sonnet > "$REVIEW_LOG" 2>&1 || true

# ── Parse result ─────────────────────────────────────────────────────

REVIEW_RESULT=$(grep -E '^REVIEW_(PASS|FAIL|CONCERNS):' "$REVIEW_LOG" | tail -1 || echo "")

if [ -z "$REVIEW_RESULT" ]; then
  # Try to find it anywhere in the output
  REVIEW_RESULT=$(grep -oE 'REVIEW_(PASS|FAIL|CONCERNS):.*' "$REVIEW_LOG" | tail -1 || echo "")
fi

rm -f "$REVIEW_LOG"

if [ -n "$REVIEW_RESULT" ]; then
  echo "$REVIEW_RESULT"
else
  echo "REVIEW_SKIP: could not parse review result"
fi

exit 0
