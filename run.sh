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

# ── Load secrets from .env ────────────────────────────────────────────

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

AUTONOMOUS_DEV_WEBHOOK="${AUTONOMOUS_DEV_WEBHOOK:-}"
AUTONOMOUS_MERGES_WEBHOOK="${AUTONOMOUS_MERGES_WEBHOOK:-}"

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

# ── Helper: atomic JSON state write ──────────────────────────────────

write_state() {
  local tmp="$STATE_FILE.tmp"
  echo "$1" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# ── State management ─────────────────────────────────────────────────

RUN_NUMBER=1
if [ -f "$STATE_FILE" ]; then
  RUN_NUMBER=$(( $(jq -r '.run_number // 0' "$STATE_FILE" 2>/dev/null || echo 0) + 1 ))
fi

# ── Cap budget check ─────────────────────────────────────────────────

CAP_THRESHOLD=$(jq -r '.cap_threshold_percent // 70' "$CONFIG" 2>/dev/null || echo 70)

LAST_RUN_LOG="$LOGS_DIR/run-latest.log"
if [ -f "$LAST_RUN_LOG" ] && grep -q '"status":"rejected"' "$LAST_RUN_LOG" 2>/dev/null; then
  log "SKIP: Last run hit rate limit, waiting for next cycle"
  exit 0
fi

# ── Build repo list ──────────────────────────────────────────────────

REPOS_ROOT=$(jq -r '.repos_root // "REDACTED_REPOS_ROOT"' "$CONFIG")
REPOS=$(jq -r '.repos[]' "$CONFIG")

REPO_LIST=""
for repo in $REPOS; do
  repo_dir="$REPOS_ROOT/$repo"
  if [ -d "$repo_dir" ]; then
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

# ── Pre-flight: verify Claude auth ───────────────────────────────────

AUTH_CHECK=$(echo "Say: OK" | "$CLAUDE_BIN" -p 2>&1)
if echo "$AUTH_CHECK" | grep -qi "authentication_failed\|does not have access\|login again"; then
  log "SKIP: Claude auth failed — token may have expired. Run 'claude' interactively to re-auth."
  write_state "$(jq -n \
    --argjson num "$RUN_NUMBER" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{run_number: $num, last_run: $ts, last_exit_code: 1, last_cost: "$0", last_error: "auth_failed"}')"
  exit 1
fi

# ── Run Claude ───────────────────────────────────────────────────────

RUN_LOG="$LOGS_DIR/run-$(date -u +%Y%m%d-%H%M%S).log"
touch "$RUN_LOG" && chmod 600 "$RUN_LOG"

timeout 2700 "$CLAUDE_BIN" \
  -p \
  --dangerously-skip-permissions \
  --verbose \
  --output-format stream-json \
  <<< "$PROMPT" \
  > "$RUN_LOG" 2>&1

EXIT_CODE=$?

# Handle timeout (exit code 124)
if [ $EXIT_CODE -eq 124 ]; then
  log "TIMEOUT: Run #$RUN_NUMBER exceeded 45 minute timeout"
fi

# Copy to latest for cap check on next run
cp "$RUN_LOG" "$LAST_RUN_LOG" 2>/dev/null || true

# ── Extract result ───────────────────────────────────────────────────

# Parse NDJSON log for the result line
RESULT=$(grep -m1 '"type":"result"' "$RUN_LOG" 2>/dev/null \
  | jq -r '.result // "No result extracted"' 2>/dev/null \
  | head -c 2000 \
  || echo "No result extracted")

COST=$(grep '"type":"result"' "$RUN_LOG" 2>/dev/null \
  | jq -r 'select(.total_cost_usd) | "$\(.total_cost_usd | tostring | .[0:6])"' 2>/dev/null \
  | tail -1 \
  || echo "unknown")
[ -z "$COST" ] && COST="unknown"

# ── Update state (atomic write) ─────────────────────────────────────

write_state "$(jq -n \
  --argjson num "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson exit "$EXIT_CODE" \
  --arg cost "$COST" \
  '{run_number: $num, last_run: $ts, last_exit_code: $exit, last_cost: $cost}')"

# ── Log result ───────────────────────────────────────────────────────

if [ $EXIT_CODE -eq 0 ]; then
  log "DONE: Run #$RUN_NUMBER completed (cost: $COST)"
  log "Result preview: ${RESULT:0:200}"
else
  log "FAIL: Run #$RUN_NUMBER exited with code $EXIT_CODE (cost: $COST)"
fi

# ── Post to Discord #autonomous-dev ──────────────────────────────────

post_to_discord() {
  local webhook="$1" msg="$2"
  [ -z "$webhook" ] && return 0
  msg="${msg:0:1990}"
  # Use jq to safely JSON-encode the message content
  local payload
  payload=$(jq -n --arg content "$msg" '{"username": "Autonomous Dev", "content": $content}')
  curl -s -X POST "$webhook" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1 || true
}

if [ -z "$AUTONOMOUS_DEV_WEBHOOK" ]; then
  log "WARN: AUTONOMOUS_DEV_WEBHOOK not set — Discord notifications disabled"
fi

if [ $EXIT_CODE -eq 0 ]; then
  post_to_discord "$AUTONOMOUS_DEV_WEBHOOK" "**Run #$RUN_NUMBER completed** (cost: $COST)

${RESULT:0:1800}"

  # Post PR review requests to #autonomous-dev-merges if any
  PR_REVIEW=$(echo "$RESULT" | sed -n '/PR_FOR_REVIEW:/,/^$/p' | head -20)
  if [ -n "$PR_REVIEW" ]; then
    post_to_discord "$AUTONOMOUS_MERGES_WEBHOOK" "**Run #$RUN_NUMBER — PR For Review**

$PR_REVIEW

React with :white_check_mark: to approve and merge this PR."
  fi

  # Post production proposals to #autonomous-dev-merges if any
  PROPOSAL=$(echo "$RESULT" | sed -n '/PRODUCTION_PROPOSAL:/,/^$/p' | head -20)
  if [ -n "$PROPOSAL" ]; then
    post_to_discord "$AUTONOMOUS_MERGES_WEBHOOK" "**Run #$RUN_NUMBER — Production Deploy Proposal**

$PROPOSAL

These changes are on main and verified on staging.
React with :white_check_mark: to approve deploying to production."
  fi
else
  post_to_discord "$AUTONOMOUS_DEV_WEBHOOK" "**Run #$RUN_NUMBER FAILED** (exit: $EXIT_CODE, cost: $COST)

Check logs at ~/repos/auto-dev/logs/"
fi

# ── Clean up old logs (keep last 50) ─────────────────────────────────

ls -t "$LOGS_DIR"/run-*.log 2>/dev/null | tail -n +51 | xargs rm -f 2>/dev/null || true
