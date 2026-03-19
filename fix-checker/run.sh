#!/usr/bin/env bash
# run.sh — Fix checker agent runner.
# Called by cron every 10 minutes. Scans repos for failed builds, broken tests,
# incomplete implementations, and crashed services. Fixes what it finds.
#
# Skips if autonomous-dev is already running (capacity constraint).
#
# Usage: ./run.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG="$SCRIPT_DIR/config.json"
PROMPT_TEMPLATE="$SCRIPT_DIR/prompt.md"
FAILURE_LOG="$SCRIPT_DIR/logs/failures.md"
LOGS_DIR="$SCRIPT_DIR/logs"
LOCK_FILE="$SCRIPT_DIR/.running.lock"
STATE_FILE="$SCRIPT_DIR/state.json"
PARENT_LOCK="$PARENT_DIR/.running.lock"
GUIDANCE_DIR="REDACTED_REPOS_ROOT/agentGuidance/guidance"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
DRY_RUN="${1:-}"

# ── Load secrets ────────────────────────────────────────────────────

# Use parent .env (shares webhooks)
if [ -f "$PARENT_DIR/.env" ]; then
  set -a
  source "$PARENT_DIR/.env"
  set +a
fi

# Fix-checker can also have its own .env overrides
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

WORK_LOG_CHANNEL_ID=$(jq -r '.work_log_channel_id // "REDACTED_WORK_LOG_CHANNEL_ID"' "$CONFIG" 2>/dev/null)

# ── Logging ─────────────────────────────────────────────────────────

mkdir -p "$LOGS_DIR"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a "$LOGS_DIR/runner.log"
}

# ── Capacity check: skip if autonomous-dev is running ───────────────

if [ -f "$PARENT_LOCK" ]; then
  PARENT_PID=$(cat "$PARENT_LOCK" 2>/dev/null || echo "")
  if [ -n "$PARENT_PID" ] && kill -0 "$PARENT_PID" 2>/dev/null; then
    log "SKIP: Autonomous-dev is running (PID $PARENT_PID), deferring"
    exit 0
  fi
fi

# ── Lock (prevent overlapping runs) ────────────────────────────────

if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    log "SKIP: Previous fix-checker still active (PID $LOCK_PID)"
    exit 0
  else
    log "WARN: Stale lock file found (PID $LOCK_PID dead), removing"
    rm -f "$LOCK_FILE"
  fi
fi

echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# ── Helper: atomic JSON state write ─────────────────────────────────

write_state() {
  local tmp="$STATE_FILE.tmp"
  echo "$1" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# ── State management ────────────────────────────────────────────────

RUN_NUMBER=1
if [ -f "$STATE_FILE" ]; then
  RUN_NUMBER=$(( $(jq -r '.run_number // 0' "$STATE_FILE" 2>/dev/null || echo 0) + 1 ))
fi

# ── Build repo list ─────────────────────────────────────────────────

REPOS_ROOT=$(jq -r '.repos_root // "REDACTED_REPOS_ROOT"' "$CONFIG")
REPOS=$(jq -r '.repos[]' "$CONFIG")

REPO_LIST=""
for repo in $REPOS; do
  repo_dir="$REPOS_ROOT/$repo"
  if [ -d "$repo_dir" ]; then
    branch=$(cd "$repo_dir" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    dirty=$(cd "$repo_dir" && git status --porcelain 2>/dev/null | wc -l)
    open_prs=$(cd "$repo_dir" && gh pr list --state open --json number 2>/dev/null | jq 'length' 2>/dev/null || echo "?")
    last_commit=$(cd "$repo_dir" && git log --oneline -1 2>/dev/null || echo "no commits")
    REPO_LIST="$REPO_LIST- **$repo** ($repo_dir) — branch: $branch, uncommitted: $dirty files, open PRs: $open_prs, last: $last_commit
"
  fi
done

# ── Build prior context (from autonomous-dev progress log) ──────────

PROGRESS_LOG="$PARENT_DIR/logs/progress.md"
PRIOR_CONTEXT="No prior sessions."
if [ -f "$PROGRESS_LOG" ]; then
  PRIOR_CONTEXT=$(tail -40 "$PROGRESS_LOG" 2>/dev/null || echo "No prior sessions.")
fi

# ── Build failure log context ───────────────────────────────────────

FAILURE_CONTEXT="No prior failure checks."
if [ -f "$FAILURE_LOG" ]; then
  FAILURE_CONTEXT=$(tail -30 "$FAILURE_LOG" 2>/dev/null || echo "No prior failure checks.")
fi

# ── Build prompt ────────────────────────────────────────────────────

PROMPT=$(cat "$PROMPT_TEMPLATE")
PROMPT="${PROMPT//\{\{REPO_LIST\}\}/$REPO_LIST}"
PROMPT="${PROMPT//\{\{PRIOR_CONTEXT\}\}/$PRIOR_CONTEXT}"
PROMPT="${PROMPT//\{\{PROGRESS_LOG\}\}/$PROGRESS_LOG}"
PROMPT="${PROMPT//\{\{FAILURE_LOG\}\}/$FAILURE_LOG}"
PROMPT="${PROMPT//\{\{REPOS_ROOT\}\}/$REPOS_ROOT}"
PROMPT="${PROMPT//\{\{SCRIPT_DIR\}\}/$SCRIPT_DIR}"
PROMPT="${PROMPT//\{\{GUIDANCE_DIR\}\}/$GUIDANCE_DIR}"
PROMPT="${PROMPT//\{\{DATE\}\}/$(date -u +%Y-%m-%d)}"
PROMPT="${PROMPT//\{\{RUN_NUMBER\}\}/$RUN_NUMBER}"

MAX_TIMEOUT=$(jq -r '.max_timeout_seconds // 900' "$CONFIG" 2>/dev/null || echo 900)

log "START: Fix-checker run #$RUN_NUMBER (repos: $(echo "$REPOS" | wc -w), timeout: ${MAX_TIMEOUT}s)"

if [ "$DRY_RUN" = "--dry-run" ]; then
  log "DRY RUN — prompt would be:"
  echo "$PROMPT"
  exit 0
fi

# ── Pre-flight: verify Claude auth ──────────────────────────────────

AUTH_CHECK=$(echo "Say: OK" | "$CLAUDE_BIN" -p 2>&1)
if echo "$AUTH_CHECK" | grep -qi "authentication_failed\|does not have access\|login again"; then
  log "SKIP: Claude auth failed"
  write_state "$(jq -n \
    --argjson num "$RUN_NUMBER" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{run_number: $num, last_run: $ts, last_exit_code: 1, last_error: "auth_failed"}')"
  exit 1
fi

# ── Run Claude ──────────────────────────────────────────────────────

RUN_LOG="$LOGS_DIR/run-$(date -u +%Y%m%d-%H%M%S).log"
touch "$RUN_LOG" && chmod 600 "$RUN_LOG"

timeout "$MAX_TIMEOUT" "$CLAUDE_BIN" \
  -p \
  --dangerously-skip-permissions \
  --verbose \
  --output-format stream-json \
  <<< "$PROMPT" \
  > "$RUN_LOG" 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
  log "TIMEOUT: Fix-checker run #$RUN_NUMBER exceeded ${MAX_TIMEOUT}s timeout"
fi

# ── Extract result ──────────────────────────────────────────────────

RESULT=$(grep -m1 '"type":"result"' "$RUN_LOG" 2>/dev/null \
  | jq -r '.result // "No result extracted"' 2>/dev/null \
  | head -c 2000 \
  || echo "No result extracted")

COST=$(grep '"type":"result"' "$RUN_LOG" 2>/dev/null \
  | jq -r 'select(.total_cost_usd) | "$\(.total_cost_usd | tostring | .[0:6])"' 2>/dev/null \
  | tail -1 \
  || echo "unknown")
[ -z "$COST" ] && COST="unknown"

# ── Update state ────────────────────────────────────────────────────

write_state "$(jq -n \
  --argjson num "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson exit "$EXIT_CODE" \
  --arg cost "$COST" \
  '{run_number: $num, last_run: $ts, last_exit_code: $exit, last_cost: $cost}')"

# ── Log result ──────────────────────────────────────────────────────

if [ $EXIT_CODE -eq 0 ]; then
  log "DONE: Fix-checker run #$RUN_NUMBER completed (cost: $COST)"
  log "Result preview: ${RESULT:0:200}"
else
  log "FAIL: Fix-checker run #$RUN_NUMBER exited with code $EXIT_CODE (cost: $COST)"
fi

# ── Post to Discord #work-log ───────────────────────────────────────

post_to_work_log() {
  local msg="$1"
  local token_cache="$HOME/.cache/discord-bot-token"
  local token=""

  if [ -f "$token_cache" ]; then
    token=$(cat "$token_cache")
  else
    token=$(ssh REDACTED_VM_HOST 'REDACTED_BOT_TOKEN_RETRIEVAL_COMMAND' 2>/dev/null || true)
    if [ -n "$token" ]; then
      mkdir -p "$(dirname "$token_cache")"
      echo "$token" > "$token_cache"
      chmod 600 "$token_cache"
    fi
  fi

  [ -z "$token" ] && { log "WARN: No bot token — Discord notification skipped"; return 0; }

  msg="${msg:0:1990}"

  curl -s -X POST "https://discord.com/api/v10/channels/${WORK_LOG_CHANNEL_ID}/messages" \
    -H "Authorization: Bot ${token}" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "import json,sys; print(json.dumps({'content': sys.argv[1]}))" "$msg")" \
    > /dev/null 2>&1 || true
}

# Extract status from result
STATUS=$(echo "$RESULT" | grep -oP 'STATUS:\s*\K\S+' | head -1 || echo "unknown")

if [ "$STATUS" = "all_clear" ]; then
  # Don't spam #work-log when nothing is broken
  log "All clear — no Discord post"
elif [ $EXIT_CODE -eq 0 ]; then
  post_to_work_log "🔧 **Fix Checker #$RUN_NUMBER** (cost: $COST)

${RESULT:0:1800}"
else
  post_to_work_log "⚠️ **Fix Checker #$RUN_NUMBER FAILED** (exit: $EXIT_CODE, cost: $COST)

Check logs at ~/repos/auto-dev/fix-checker/logs/"
fi

# ── Clean up old logs (keep last 50) ────────────────────────────────

ls -t "$LOGS_DIR"/run-*.log 2>/dev/null | tail -n +51 | xargs rm -f 2>/dev/null || true
