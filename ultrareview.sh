#!/usr/bin/env bash
# ultrareview.sh — Cloud-based multi-agent code review for PRs.
# Runs `claude ultrareview` on a PR for deeper bug-finding than single-pass review.sh.
# Only triggered for complex PRs (high file/line count or security-adjacent paths).
#
# Usage: ./ultrareview.sh <repos_root> <repo_name> <pr_number> [<files_changed>]
# stdout last line: ULTRAREVIEW_PASS|ULTRAREVIEW_FAIL|ULTRAREVIEW_CONCERNS|ULTRAREVIEW_SKIP: <details>

set -uo pipefail

REPOS_ROOT="${1:?Usage: ultrareview.sh <repos_root> <repo_name> <pr_number> [files_changed]}"
REPO_NAME="${2:?}"
PR_NUMBER="${3:?}"
FILES_CHANGED="${4:-0}"
REPO_DIR="$REPOS_ROOT/$REPO_NAME"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"

MIN_FILES_FOR_ULTRAREVIEW="${MIN_FILES_FOR_ULTRAREVIEW:-8}"

if [ ! -d "$REPO_DIR" ]; then
  echo "ULTRAREVIEW_SKIP: repo dir not found"
  exit 0
fi

cd "$REPO_DIR"

if [ "$FILES_CHANGED" -lt "$MIN_FILES_FOR_ULTRAREVIEW" ] 2>/dev/null; then
  SECURITY_PATHS=$(gh pr diff "$PR_NUMBER" --name-only 2>/dev/null \
    | grep -cE '(auth|security|middleware|password|token|secret|oauth|session|crypto|\.env)' || true)
  if [ "${SECURITY_PATHS:-0}" -eq 0 ]; then
    echo "ULTRAREVIEW_SKIP: PR too small ($FILES_CHANGED files, no security paths)"
    exit 0
  fi
fi

REPO_FULL=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")
if [ -z "$REPO_FULL" ]; then
  echo "ULTRAREVIEW_SKIP: could not resolve repo"
  exit 0
fi

REVIEW_LOG=$(mktemp)
timeout 600 "$CLAUDE_BIN" ultrareview "$PR_NUMBER" > "$REVIEW_LOG" 2>&1
REVIEW_EXIT=$?

if [ $REVIEW_EXIT -ne 0 ]; then
  STDERR_MSG=$(tail -5 "$REVIEW_LOG" 2>/dev/null || echo "unknown error")
  rm -f "$REVIEW_LOG"
  echo "ULTRAREVIEW_SKIP: ultrareview exited $REVIEW_EXIT ($STDERR_MSG)"
  exit 0
fi

REVIEW_CONTENT=$(cat "$REVIEW_LOG")
rm -f "$REVIEW_LOG"

BUG_COUNT=$(echo "$REVIEW_CONTENT" | grep -ciE '(bug|issue|vulnerability|error|flaw)' || true)

if echo "$REVIEW_CONTENT" | grep -qiE '(no (bugs|issues|problems) found|all checks passed|looks good)'; then
  echo "ULTRAREVIEW_PASS: Cloud review found no issues"
elif [ "${BUG_COUNT:-0}" -ge 3 ]; then
  SUMMARY=$(echo "$REVIEW_CONTENT" | grep -iE '(bug|issue|vulnerability|error|flaw)' | head -3 | tr '\n' '; ')
  echo "ULTRAREVIEW_FAIL: Cloud review found $BUG_COUNT issues: ${SUMMARY:0:200}"
elif [ "${BUG_COUNT:-0}" -ge 1 ]; then
  SUMMARY=$(echo "$REVIEW_CONTENT" | grep -iE '(bug|issue|vulnerability|error|flaw)' | head -2 | tr '\n' '; ')
  echo "ULTRAREVIEW_CONCERNS: Cloud review found $BUG_COUNT minor issues: ${SUMMARY:0:200}"
else
  echo "ULTRAREVIEW_PASS: Cloud review completed, no blocking issues"
fi

exit 0
