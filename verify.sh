#!/usr/bin/env bash
# verify.sh — Independent build/test verification of a PR branch.
# Called by run.sh after the agent creates a PR. Checks out the branch,
# runs build + tests, and reports pass/fail.
#
# Usage: ./verify.sh <repos_root> <repo_name> <pr_number>
# Exit codes: 0 = verified or skipped, 1 = verification failed
# stdout last line: VERIFY_PASS|VERIFY_FAIL|VERIFY_SKIP: <details>

# No set -e: we handle errors explicitly so partial failures don't abort
set -uo pipefail

REPOS_ROOT="${1:?Usage: verify.sh <repos_root> <repo_name> <pr_number>}"
REPO_NAME="${2:?}"
PR_NUMBER="${3:?}"
REPO_DIR="$REPOS_ROOT/$REPO_NAME"

if [ ! -d "$REPO_DIR" ]; then
  echo "VERIFY_SKIP: repo dir not found"
  exit 0
fi

cd "$REPO_DIR"

# ── Resolve PR branch ───────────────────────────────────────────────

PR_BRANCH=$(gh pr view "$PR_NUMBER" --json headRefName -q '.headRefName' 2>/dev/null || echo "")
if [ -z "$PR_BRANCH" ]; then
  echo "VERIFY_SKIP: could not resolve PR #$PR_NUMBER branch"
  exit 0
fi

# ── Checkout PR branch ──────────────────────────────────────────────

ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
cleanup() {
  cd "$REPO_DIR" 2>/dev/null || true
  git checkout "$ORIGINAL_BRANCH" 2>/dev/null || git checkout main 2>/dev/null || true
}
trap cleanup EXIT

git fetch origin "$PR_BRANCH" 2>/dev/null || true
if ! git checkout "$PR_BRANCH" 2>/dev/null; then
  echo "VERIFY_SKIP: could not checkout $PR_BRANCH"
  exit 0
fi

# ── Check for package.json ──────────────────────────────────────────

if [ ! -f "package.json" ]; then
  echo "VERIFY_SKIP: no package.json"
  exit 0
fi

RESULTS=""
FAILED=false

# ── Install deps if needed ──────────────────────────────────────────

NEEDS_INSTALL=false
if [ ! -d "node_modules" ]; then
  NEEDS_INSTALL=true
elif git diff --name-only "origin/main..HEAD" 2>/dev/null | grep -q "package-lock.json\|package.json"; then
  NEEDS_INSTALL=true
fi

if [ "$NEEDS_INSTALL" = true ]; then
  timeout 120 npm install 2>&1 | tail -5 || true
fi

# ── Build ────────────────────────────────────────────────────────────

HAS_BUILD=$(node -e "const p=require('./package.json'); console.log(p.scripts?.build ? 'yes' : 'no')" 2>/dev/null || echo "no")
if [ "$HAS_BUILD" = "yes" ]; then
  echo "verify: running build..."
  if timeout 180 npm run build > /dev/null 2>&1; then
    RESULTS="build:pass"
  else
    FAILED=true
    RESULTS="build:FAIL"
  fi
fi

# ── Tests ────────────────────────────────────────────────────────────

# Skip the default npm "no test specified" placeholder
HAS_TEST=$(node -e "
const p = require('./package.json');
const t = p.scripts?.test || '';
console.log(t && !t.includes('no test specified') ? 'yes' : 'no');
" 2>/dev/null || echo "no")

if [ "$HAS_TEST" = "yes" ]; then
  echo "verify: running tests..."
  if timeout 120 npm test > /dev/null 2>&1; then
    RESULTS="${RESULTS:+$RESULTS }test:pass"
  else
    FAILED=true
    RESULTS="${RESULTS:+$RESULTS }test:FAIL"
  fi
fi

# ── Report ───────────────────────────────────────────────────────────

if [ -z "$RESULTS" ]; then
  echo "VERIFY_SKIP: no build or test scripts"
  exit 0
fi

if [ "$FAILED" = true ]; then
  echo "VERIFY_FAIL: $RESULTS"
  exit 1
else
  echo "VERIFY_PASS: $RESULTS"
  exit 0
fi
