#!/usr/bin/env bash
# run.sh — Doc-Sync Agent runner.
# Reviews recent commits across repos and detects CLAUDE.md drift.
# When committed code adds undocumented functionality, stages PRs
# with minimal CLAUDE.md patches.
#
# Usage: ./run.sh [--dry-run]
# Schedule: every 4 hours via cron (or on-demand)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
PROMPT_TEMPLATE="$SCRIPT_DIR/prompt.md"
LOGS_DIR="$SCRIPT_DIR/logs"
LOCK_FILE="$SCRIPT_DIR/.running.lock"
STATE_FILE="$SCRIPT_DIR/state.json"
CONFIG_FILE="$PARENT_DIR/config.json"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
DRY_RUN="${1:-}"
LOOKBACK_HOURS=6
REPOS_ROOT="$HOME/repos"

# ── Load secrets ────────────────��───────────────────────────────────

if [ -f "$HOME/.env" ]; then
  set -a; source "$HOME/.env"; set +a
fi

if [ -f "$PARENT_DIR/.env" ]; then
  set -a; source "$PARENT_DIR/.env"; set +a
fi

LEARNINGS_WEBHOOK="${DISCORD_LEARNINGS_WEBHOOK_URL:-}"

# ── Logging ──────────��──────────────────────────────────────────────

mkdir -p "$LOGS_DIR"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOGS_DIR/runner.log"
}

# ── Lock management ─────────────────────────────────────────────────

cleanup() { rm -f "$LOCK_FILE"; }
trap cleanup EXIT

if [ -f "$LOCK_FILE" ]; then
  OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    log "SKIP: Another doc-sync run is active (PID $OLD_PID)"
    exit 0
  fi
  log "Cleaning stale lock (PID $OLD_PID)"
  rm -f "$LOCK_FILE"
fi

# Check if sibling agents are running
for SIBLING_LOCK in "$PARENT_DIR"/*/".running.lock"; do
  [ -f "$SIBLING_LOCK" ] || continue
  [ "$SIBLING_LOCK" = "$LOCK_FILE" ] && continue
  SIBLING_PID=$(cat "$SIBLING_LOCK" 2>/dev/null || echo "")
  if [ -n "$SIBLING_PID" ] && kill -0 "$SIBLING_PID" 2>/dev/null; then
    SIBLING_NAME=$(basename "$(dirname "$SIBLING_LOCK")")
    log "SKIP: Sibling agent $SIBLING_NAME is active (PID $SIBLING_PID)"
    exit 0
  fi
done

echo $$ > "$LOCK_FILE"

# ── Usage gate ────────────��─────────────────────────────────────────

USAGE_SCRIPT="$HOME/repos/privateContext/check-usage.sh"
if [ -x "$USAGE_SCRIPT" ]; then
  USAGE_OUT=$("$USAGE_SCRIPT" --force 2>/dev/null || echo "")
  if echo "$USAGE_OUT" | grep -qE "5h:.*[89][0-9]\.[0-9]%|5h:.*100"; then
    log "SKIP: 5h usage too high: $USAGE_OUT"
    exit 0
  fi
  if echo "$USAGE_OUT" | grep -qE "7d:.*[89][0-9]\.[0-9]%|7d:.*100"; then
    log "SKIP: 7d usage too high: $USAGE_OUT"
    exit 0
  fi
fi

# ── State management ──────────────���─────────────────────────────────

write_state() {
  local tmp; tmp=$(mktemp)
  echo "$1" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

RUN_NUMBER=1
if [ -f "$STATE_FILE" ]; then
  PREV=$(jq -r '.run_number // 0' "$STATE_FILE" 2>/dev/null || echo 0)
  RUN_NUMBER=$((PREV + 1))
fi

# ── Get repo list from config ──────────────────────────────────────

ALL_REPOS=""
if [ -f "$CONFIG_FILE" ]; then
  ALL_REPOS=$(jq -r '.repos[]' "$CONFIG_FILE" 2>/dev/null || echo "")
fi

if [ -z "$ALL_REPOS" ]; then
  log "ERROR: No repos configured in $CONFIG_FILE"
  exit 1
fi

# ── Collect recent git activity ────────────────────────────────────

GIT_SINCE=$(date -u -d "${LOOKBACK_HOURS} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-${LOOKBACK_HOURS}H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")

GIT_ACTIVITY=""
ACTIVE_REPOS=0

if [ -n "$GIT_SINCE" ]; then
  for repo in $ALL_REPOS; do
    repo_dir="$REPOS_ROOT/$repo"
    [ -d "$repo_dir/.git" ] || continue
    [ -f "$repo_dir/CLAUDE.md" ] || continue

    COMMITS=$(cd "$repo_dir" && git log --since="$GIT_SINCE" --oneline --all 2>/dev/null | head -20 || true)
    if [ -n "$COMMITS" ]; then
      ACTIVE_REPOS=$((ACTIVE_REPOS + 1))
      COMMIT_COUNT=$(echo "$COMMITS" | wc -l | tr -d ' ')
      GIT_ACTIVITY="${GIT_ACTIVITY}
### $repo ($COMMIT_COUNT commits)
$COMMITS
"
    fi
  done
fi

if [ "$ACTIVE_REPOS" -eq 0 ]; then
  log "No repos with recent commits and CLAUDE.md — nothing to sync"
  write_state "$(jq -n \
    --argjson num "$RUN_NUMBER" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{run_number: $num, last_run: $ts, last_exit_code: 0, repos_scanned: 0, drift_found: 0}')"
  exit 0
fi

log "Found $ACTIVE_REPOS repos with recent activity"

# ── Build prompt ─────────────────────────────────────────────���──────

PROMPT=$(cat "$PROMPT_TEMPLATE")
PROMPT="${PROMPT//\{\{GIT_ACTIVITY\}\}/$GIT_ACTIVITY}"
PROMPT="${PROMPT//\{\{REPOS_ROOT\}\}/$REPOS_ROOT}"
PROMPT="${PROMPT//\{\{DATE\}\}/$(date -u +%Y-%m-%d)}"
PROMPT="${PROMPT//\{\{RUN_NUMBER\}\}/$RUN_NUMBER}"
PROMPT="${PROMPT//\{\{LOOKBACK_HOURS\}\}/$LOOKBACK_HOURS}"

MAX_TIMEOUT=900  # 15 minutes (shorter than learning agent — simpler task)

log "START: Doc-sync run #$RUN_NUMBER ($ACTIVE_REPOS repos, timeout: ${MAX_TIMEOUT}s)"

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
  log "TIMEOUT: Doc-sync run #$RUN_NUMBER exceeded ${MAX_TIMEOUT}s"
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

# ── Parse output keywords ──────────���───────────────────────────────

REPOS_SCANNED=$(echo "$RESULT" | grep -oP 'REPOS_SCANNED:\s*\K\S+' | head -1 || echo "0")
REPOS_WITH_DRIFT=$(echo "$RESULT" | grep -oP 'REPOS_WITH_DRIFT:\s*\K\S+' | head -1 || echo "0")
UPDATES_MADE=$(echo "$RESULT" | grep -oP 'UPDATES_MADE:\s*\K\S+' | head -1 || echo "0")

# ── Update state ─────────────────────────────────────────────���──────

write_state "$(jq -n \
  --argjson num "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson exit "$EXIT_CODE" \
  --arg cost "$COST" \
  --argjson scanned "${REPOS_SCANNED:-0}" \
  --argjson drift "${REPOS_WITH_DRIFT:-0}" \
  '{run_number: $num, last_run: $ts, last_exit_code: $exit, last_cost: $cost, repos_scanned: $scanned, drift_found: $drift}')"

# ── Log result ────��─────────────────────────────────────────────────

if [ $EXIT_CODE -eq 0 ]; then
  log "DONE: Doc-sync run #$RUN_NUMBER — scanned $REPOS_SCANNED repos, $REPOS_WITH_DRIFT with drift (cost: $COST)"
else
  log "FAIL: Doc-sync run #$RUN_NUMBER exited with code $EXIT_CODE (cost: $COST)"
fi

# ── Post to Discord ───────────���─────────────────────────────────────

post_to_discord() {
  local webhook="$1" msg="$2" username="${3:-Doc-Sync Agent}"
  [ -z "$webhook" ] && return 0
  msg="${msg:0:1990}"
  local payload
  payload=$(jq -n --arg content "$msg" --arg user "$username" '{"username": $user, "content": $content}')
  curl -s -X POST "$webhook" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1 || true
}

if [ "$REPOS_WITH_DRIFT" = "0" ] || [ -z "$REPOS_WITH_DRIFT" ]; then
  # Heartbeat every 6 runs (every 24h at 4h cadence)
  if (( RUN_NUMBER % 6 == 0 )); then
    post_to_discord "$LEARNINGS_WEBHOOK" "📋 **Doc-Sync heartbeat** — run #$RUN_NUMBER, $REPOS_SCANNED repos scanned, no drift (cost: $COST)"
  fi
  log "No drift found — no Discord post"
elif [ $EXIT_CODE -eq 0 ]; then
  post_to_discord "$LEARNINGS_WEBHOOK" "📋 **Doc-Sync #$RUN_NUMBER** — $REPOS_WITH_DRIFT repos with CLAUDE.md drift, $UPDATES_MADE updates staged (cost: $COST)

${RESULT:0:1600}"
else
  post_to_discord "$LEARNINGS_WEBHOOK" "⚠️ **Doc-Sync #$RUN_NUMBER FAILED** (exit: $EXIT_CODE, cost: $COST)

Check logs at ~/repos/autonomousDev/doc-sync-pass/logs/"
fi

# ── Post PR review requests ────────────────────────────────────────

AUTONOMOUS_MERGES_WEBHOOK="${AUTONOMOUS_MERGES_WEBHOOK:-}"
if [ $EXIT_CODE -eq 0 ] && [ -n "$AUTONOMOUS_MERGES_WEBHOOK" ]; then
  PR_REVIEW=$(echo "$RESULT" | sed -n '/PR_FOR_REVIEW:/,/^$/p' | head -20)
  if [ -n "$PR_REVIEW" ] && ! echo "$PR_REVIEW" | grep -q "PR_FOR_REVIEW: $"; then
    post_to_discord "$AUTONOMOUS_MERGES_WEBHOOK" "📋 **Doc-Sync #$RUN_NUMBER — PR For Review**

$PR_REVIEW

React with :white_check_mark: to approve and merge."
    log "Posted PR review request to #autonomous-dev-merges"
  fi
fi

# ── Post to agent journal ───────────────────────────────────────────

JOURNAL_SCRIPT="$HOME/repos/privateContext/journal-post.sh"
if [ -x "$JOURNAL_SCRIPT" ] && [ $EXIT_CODE -eq 0 ] && [ "$REPOS_WITH_DRIFT" != "0" ] && [ -n "$REPOS_WITH_DRIFT" ]; then
  JOURNAL_SUMMARY=$(echo "$RESULT" | head -c 400)
  "$JOURNAL_SCRIPT" "discovery" "doc-sync run #$RUN_NUMBER: $JOURNAL_SUMMARY" || true
fi

# ── Clean up old logs ───────────────────────────────────────────────

ls -t "$LOGS_DIR"/run-*.log 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
