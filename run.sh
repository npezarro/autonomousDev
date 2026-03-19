#!/usr/bin/env bash
# run.sh — Autonomous development agent runner.
# Called by cron every 30 minutes. Spawns a Claude Code session that
# reviews all repos and picks the most productive improvement to make.
#
# Usage: ./run.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="$SCRIPT_DIR/config.json"
PROMPT_TEMPLATE="$SCRIPT_DIR/prompt.md"
PROGRESS_LOG="$SCRIPT_DIR/logs/progress.md"
LOGS_DIR="$SCRIPT_DIR/logs"
LOCK_FILE="$SCRIPT_DIR/.running.lock"
STATE_FILE="$SCRIPT_DIR/state.json"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
DRY_RUN="${1:-}"

# ── Logging ──────────────────────────────────────────────────────────

mkdir -p "$LOGS_DIR"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a "$LOGS_DIR/runner.log"
}

# ── Lock (prevent overlapping runs) ──────────────────────────────────

if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    log "SKIP: Previous run still active (PID $LOCK_PID)"
    exit 0
  else
    log "WARN: Stale lock file found (PID $LOCK_PID dead), removing"
    rm -f "$LOCK_FILE"
  fi
fi

echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# ── State management ─────────────────────────────────────────────────

RUN_NUMBER=1
if [ -f "$STATE_FILE" ]; then
  RUN_NUMBER=$(python3 -c "import json; d=json.load(open('$STATE_FILE')); print(d.get('run_number', 0) + 1)" 2>/dev/null || echo 1)
fi

# ── Cap budget check ─────────────────────────────────────────────────
# Read the cap threshold from config
CAP_THRESHOLD=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('cap_threshold_percent', 70))" 2>/dev/null || echo 70)

# Check if we recently hit a rate limit (simple heuristic: look at last run's output)
LAST_RUN_LOG="$LOGS_DIR/run-latest.log"
if [ -f "$LAST_RUN_LOG" ] && grep -q '"status":"rejected"' "$LAST_RUN_LOG" 2>/dev/null; then
  log "SKIP: Last run hit rate limit, waiting for next cycle"
  exit 0
fi

# ── Build repo list ──────────────────────────────────────────────────

REPOS_ROOT=$(python3 -c "import json; print(json.load(open('$CONFIG')).get('repos_root', 'REDACTED_REPOS_ROOT'))")
REPOS=$(python3 -c "import json; print('\n'.join(json.load(open('$CONFIG')).get('repos', [])))")

REPO_LIST=""
for repo in $REPOS; do
  repo_dir="$REPOS_ROOT/$repo"
  if [ -d "$repo_dir" ]; then
    # Get git status summary
    branch=$(cd "$repo_dir" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    last_commit=$(cd "$repo_dir" && git log --oneline -1 2>/dev/null || echo "no commits")
    dirty=$(cd "$repo_dir" && git status --porcelain 2>/dev/null | wc -l)
    REPO_LIST="$REPO_LIST- **$repo** ($repo_dir) — branch: $branch, last: $last_commit, uncommitted: $dirty files
"
  fi
done

# ── Build prior context (last 10 entries from progress log) ──────────

PRIOR_CONTEXT="No prior sessions."
if [ -f "$PROGRESS_LOG" ]; then
  # Get last 30 lines of the progress log
  PRIOR_CONTEXT=$(tail -30 "$PROGRESS_LOG" 2>/dev/null || echo "No prior sessions.")
fi

# ── Build prompt ─────────────────────────────────────────────────────

PROMPT=$(cat "$PROMPT_TEMPLATE")
PROMPT="${PROMPT//\{\{REPO_LIST\}\}/$REPO_LIST}"
PROMPT="${PROMPT//\{\{PRIOR_CONTEXT\}\}/$PRIOR_CONTEXT}"
PROMPT="${PROMPT//\{\{PROGRESS_LOG\}\}/$PROGRESS_LOG}"
PROMPT="${PROMPT//\{\{REPOS_ROOT\}\}/$REPOS_ROOT}"
PROMPT="${PROMPT//\{\{SCRIPT_DIR\}\}/$SCRIPT_DIR}"
PROMPT="${PROMPT//\{\{DATE\}\}/$(date -u +%Y-%m-%d)}"
PROMPT="${PROMPT//\{\{RUN_NUMBER\}\}/$RUN_NUMBER}"

log "START: Run #$RUN_NUMBER (repos: $(echo "$REPOS" | wc -w), cap threshold: $CAP_THRESHOLD%)"

if [ "$DRY_RUN" = "--dry-run" ]; then
  log "DRY RUN — prompt would be:"
  echo "$PROMPT"
  exit 0
fi

# ── Run Claude ───────────────────────────────────────────────────────

RUN_LOG="$LOGS_DIR/run-$(date -u +%Y%m%d-%H%M%S).log"

# Use the repos root as CWD so Claude has access to all repos
timeout 2700 "$CLAUDE_BIN" \
  -p \
  --dangerously-skip-permissions \
  --verbose \
  --output-format stream-json \
  <<< "$PROMPT" \
  > "$RUN_LOG" 2>&1

EXIT_CODE=$?

# Copy to latest for cap check on next run
cp "$RUN_LOG" "$LAST_RUN_LOG" 2>/dev/null || true

# ── Extract result ───────────────────────────────────────────────────

RESULT=$(python3 -c "
import json, sys
for line in open('$RUN_LOG'):
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'result' and 'result' in obj:
            print(obj['result'][:2000])
            sys.exit(0)
    except: pass
print('No result extracted')
" 2>/dev/null || echo "Failed to parse output")

COST=$(python3 -c "
import json
for line in open('$RUN_LOG'):
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'result' and 'total_cost_usd' in obj:
            print(f\"\${obj['total_cost_usd']:.4f}\")
    except: pass
" 2>/dev/null || echo "unknown")

# ── Update state ─────────────────────────────────────────────────────

python3 -c "
import json
state = {'run_number': $RUN_NUMBER, 'last_run': '$(date -u +%Y-%m-%dT%H:%M:%SZ)', 'last_exit_code': $EXIT_CODE, 'last_cost': '$COST'}
json.dump(state, open('$STATE_FILE', 'w'), indent=2)
" 2>/dev/null || true

# ── Log result ───────────────────────────────────────────────────────

if [ $EXIT_CODE -eq 0 ]; then
  log "DONE: Run #$RUN_NUMBER completed (cost: $COST)"
  log "Result preview: ${RESULT:0:200}"
else
  log "FAIL: Run #$RUN_NUMBER exited with code $EXIT_CODE (cost: $COST)"
fi

# ── Post to Discord #autonomous-dev ──────────────────────────────────

AUTONOMOUS_DEV_WEBHOOK="REDACTED_AUTONOMOUS_DEV_WEBHOOK"
AUTONOMOUS_MERGES_WEBHOOK="REDACTED_AUTONOMOUS_MERGES_WEBHOOK"

post_to_discord() {
  local webhook="$1" msg="$2"
  msg="${msg:0:1990}"
  curl -s -X POST "$webhook" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json,sys; print(json.dumps({'username': 'Autonomous Dev', 'content': sys.argv[1]}))" "$msg")" > /dev/null 2>&1 || true
}

if [ $EXIT_CODE -eq 0 ]; then
  # Post run summary to #autonomous-dev
  post_to_discord "$AUTONOMOUS_DEV_WEBHOOK" "**Run #$RUN_NUMBER completed** (cost: $COST)

${RESULT:0:1800}"

  # Post merge suggestions to #autonomous-dev-merges if any PRs need review
  NEEDS_REVIEW=$(echo "$RESULT" | grep -i 'NEEDS_REVIEW' | head -5)
  if [ -n "$NEEDS_REVIEW" ]; then
    post_to_discord "$AUTONOMOUS_MERGES_WEBHOOK" "**Run #$RUN_NUMBER — PRs awaiting review:**

$NEEDS_REVIEW

React with :white_check_mark: to approve merge to production. These PRs were left open because they contain higher-risk changes."
  fi
else
  post_to_discord "$AUTONOMOUS_DEV_WEBHOOK" "**Run #$RUN_NUMBER FAILED** (exit: $EXIT_CODE, cost: $COST)

Check logs at ~/repos/auto-dev/logs/"
fi

# ── Clean up old logs (keep last 50) ─────────────────────────────────

ls -t "$LOGS_DIR"/run-*.log 2>/dev/null | tail -n +51 | xargs rm -f 2>/dev/null || true
