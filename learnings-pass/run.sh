#!/usr/bin/env bash
# run.sh — Learning agent runner.
# Called by cron every hour. Reviews recent activity across all repos,
# identifies uncaptured learnings and user corrections not reflected
# in rule sets, and stages PRs for review.
#
# Usage: ./run.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
PROMPT_TEMPLATE="$SCRIPT_DIR/prompt.md"
LOGS_DIR="$SCRIPT_DIR/logs"
LOCK_FILE="$SCRIPT_DIR/.running.lock"
STATE_FILE="$SCRIPT_DIR/state.json"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
DRY_RUN="${1:-}"

# ── Load secrets ────────────────────────────────────────────────────

# System-level env (journal channel ID, bot tokens, webhooks)
if [ -f "$HOME/.env" ]; then
  set -a
  source "$HOME/.env"
  set +a
fi

if [ -f "$PARENT_DIR/.env" ]; then
  set -a
  source "$PARENT_DIR/.env"
  set +a
fi

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

LEARNINGS_WEBHOOK="${DISCORD_LEARNINGS_WEBHOOK_URL:-}"
AUTONOMOUS_DEV_WEBHOOK="${AUTONOMOUS_DEV_WEBHOOK:-}"

# ── Logging ─────────────────────────────────────────────────────────

mkdir -p "$LOGS_DIR"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*" | tee -a "$LOGS_DIR/runner.log"
}

# ── Lock (prevent overlapping runs) ────────────────────────────────

if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    log "SKIP: Previous learning agent still active (PID $LOCK_PID)"
    exit 0
  else
    log "WARN: Stale lock file found (PID $LOCK_PID dead), removing"
    rm -f "$LOCK_FILE"
  fi
fi

echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# ── Also skip if autonomous-dev or fix-checker are running ──────────

for sibling_lock in "$PARENT_DIR/.running.lock" "$PARENT_DIR/fix-checker/.running.lock"; do
  if [ -f "$sibling_lock" ]; then
    SIBLING_PID=$(cat "$sibling_lock" 2>/dev/null || echo "")
    if [ -n "$SIBLING_PID" ] && kill -0 "$SIBLING_PID" 2>/dev/null; then
      log "SKIP: Sibling agent running (PID $SIBLING_PID from $sibling_lock)"
      exit 0
    fi
  fi
done

# ── Usage check (90% threshold for learning agent) ──────────────────

USAGE_SCRIPT=""
for p in "$HOME/repos/privateContext/check-usage.sh" "$HOME/privateContext/check-usage.sh"; do
  [ -x "$p" ] && USAGE_SCRIPT="$p" && break
done
if [ -n "$USAGE_SCRIPT" ]; then
  # Get raw percentages and check 90% threshold
  USAGE_OUTPUT=$("$USAGE_SCRIPT" --force 2>/dev/null || echo "")
  USAGE_5H=$(echo "$USAGE_OUTPUT" | grep -oP '5h:\s*\K[\d.]+' | head -1 || echo "0")
  USAGE_7D=$(echo "$USAGE_OUTPUT" | grep -oP '7d:\s*\K[\d.]+' | head -1 || echo "0")

  MAX_USAGE=$(python3 -c "print(max(float('${USAGE_5H:-0}'), float('${USAGE_7D:-0}')))" 2>/dev/null || echo "0")

  if python3 -c "exit(0 if float('$MAX_USAGE') >= 90 else 1)" 2>/dev/null; then
    log "SKIP: Usage at ${MAX_USAGE}% (5h: ${USAGE_5H}%, 7d: ${USAGE_7D}%) — threshold is 90%"
    exit 0
  fi
  log "Usage check: 5h=${USAGE_5H}%, 7d=${USAGE_7D}% (threshold: 90%)"
fi

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

# ── Fetch journal entries (last 48h from Discord #agent-journal) ────

JOURNAL_ENTRIES=""
TOKEN_CACHE="$HOME/.cache/discord-bot-token"
BOT_TOKEN=""

if [ -f "$TOKEN_CACHE" ]; then
  BOT_TOKEN=$(cat "$TOKEN_CACHE")
fi

JOURNAL_CHANNEL_ID="${DISCORD_JOURNAL_CHANNEL_ID:-}"

if [ -n "$BOT_TOKEN" ] && [ -n "$JOURNAL_CHANNEL_ID" ]; then
  RAW_MSGS=$(curl -sf --max-time 15 \
    -H "Authorization: Bot ${BOT_TOKEN}" \
    "https://discord.com/api/v10/channels/${JOURNAL_CHANNEL_ID}/messages?limit=50" 2>/dev/null || echo "[]")

  JOURNAL_ENTRIES=$(echo "$RAW_MSGS" | python3 -c "
import json, sys
from datetime import datetime, timedelta, timezone
cutoff = datetime.now(timezone.utc) - timedelta(hours=48)
msgs = json.load(sys.stdin)
for m in msgs:
    ts = m.get('timestamp', '')
    try:
        dt = datetime.fromisoformat(ts.replace('+00:00', '+00:00'))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
    except:
        continue
    if dt >= cutoff and '[JOURNAL]' in m.get('content', ''):
        print(m['content'][:500])
        print()
" 2>/dev/null || echo "")

  log "Fetched journal entries: $(echo "$JOURNAL_ENTRIES" | grep -c '\[JOURNAL\]' || echo 0) entries"
else
  log "WARN: No bot token or journal channel ID — journal entries unavailable"
fi

# ── Fetch #cli-interactions messages (for correction detection) ──────

CLI_CHANNEL_ID="${DISCORD_CLI_INTERACTIONS_CHANNEL_ID:-}"
CLI_INTERACTIONS=""

if [ -n "$BOT_TOKEN" ] && [ -n "$CLI_CHANNEL_ID" ]; then
  RAW_CLI=$(curl -sf --max-time 15 \
    -H "Authorization: Bot ${BOT_TOKEN}" \
    "https://discord.com/api/v10/channels/${CLI_CHANNEL_ID}/messages?limit=50" 2>/dev/null || echo "[]")

  CLI_INTERACTIONS=$(echo "$RAW_CLI" | python3 -c "
import json, sys
from datetime import datetime, timedelta, timezone
cutoff = datetime.now(timezone.utc) - timedelta(hours=24)
msgs = json.load(sys.stdin)
for m in msgs:
    ts = m.get('timestamp', '')
    try:
        dt = datetime.fromisoformat(ts.replace('+00:00', '+00:00'))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
    except:
        continue
    if dt >= cutoff:
        print(m['content'][:600])
        print()
" 2>/dev/null || echo "")

  log "Fetched cli-interactions: $(echo "$CLI_INTERACTIONS" | grep -c '^.' || echo 0) messages"
else
  log "WARN: No bot token or cli-interactions channel ID — correction detection limited"
fi

# ── Fetch recent merged PRs across repos ────────────────────────────

REPOS_ROOT="$HOME/repos"
ALL_REPOS=$(jq -r '.repos[]' "$PARENT_DIR/config.json" 2>/dev/null || echo "")

MERGED_PRS=""
SINCE_DATE=$(date -u -d '48 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-48H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")

if [ -n "$SINCE_DATE" ]; then
  for repo in $ALL_REPOS; do
    repo_dir="$REPOS_ROOT/$repo"
    [ -d "$repo_dir/.git" ] || continue
    PR_DATA=$(cd "$repo_dir" && gh pr list --state merged --json title,body,mergedAt,number,url \
      --jq "[.[] | select(.mergedAt >= \"$SINCE_DATE\")] | .[] | \"PR #\\(.number) [\\(.title)] — \\(.url)\\n\\(.body[:300])\"" 2>/dev/null || echo "")
    if [ -n "$PR_DATA" ]; then
      MERGED_PRS="$MERGED_PRS
### $repo
$PR_DATA
"
    fi
  done
  log "Collected merged PRs from $(echo "$ALL_REPOS" | wc -w) repos"
fi

# ── Read current agentGuidance file list ────────────────────────────

GUIDANCE_DIR="$REPOS_ROOT/agentGuidance"
GUIDANCE_FILES=""
if [ -d "$GUIDANCE_DIR/guidance" ]; then
  GUIDANCE_FILES=$(ls -1 "$GUIDANCE_DIR/guidance/"*.md 2>/dev/null | while read f; do
    echo "- $(basename "$f") ($(wc -l < "$f") lines)"
  done)
fi

# ── Scan memory files for memory-only learnings ─────────────────────

MEMORY_DIR="$HOME/.claude/projects/-mnt-c-Users-npeza/memory"
MEMORY_SCAN=""
if [ -d "$MEMORY_DIR" ]; then
  MEMORY_SCAN=$(find "$MEMORY_DIR" -name "*.md" ! -name "MEMORY.md" -newer "$MEMORY_DIR/MEMORY.md" -mtime -7 2>/dev/null | while read f; do
    echo "### $(basename "$f")"
    head -20 "$f"
    echo ""
  done 2>/dev/null || echo "")

  # If no files newer than MEMORY.md, scan all recent files
  if [ -z "$MEMORY_SCAN" ]; then
    MEMORY_SCAN=$(find "$MEMORY_DIR" -name "*.md" ! -name "MEMORY.md" -mtime -7 2>/dev/null | while read f; do
      echo "### $(basename "$f")"
      head -20 "$f"
      echo ""
    done 2>/dev/null || echo "")
  fi

  MEMORY_COUNT=$(echo "$MEMORY_SCAN" | grep -c "^###" || echo 0)
  log "Scanned $MEMORY_COUNT memory files from last 7 days"
fi

# ── Collect recent git activity (last 24h across all repos) ──────────

GIT_ACTIVITY=""
GIT_SINCE=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")

if [ -n "$GIT_SINCE" ]; then
  for repo in $ALL_REPOS; do
    repo_dir="$REPOS_ROOT/$repo"
    [ -d "$repo_dir/.git" ] || continue
    COMMITS=$(cd "$repo_dir" && git log --since="$GIT_SINCE" --oneline --all 2>/dev/null | head -20 || echo "")
    if [ -n "$COMMITS" ]; then
      GIT_ACTIVITY="$GIT_ACTIVITY
### $repo
$COMMITS
"
    fi
  done
  log "Collected git activity from repos"
fi

# ── Build prompt ────────────────────────────────────────────────────

PROMPT=$(cat "$PROMPT_TEMPLATE")
PROMPT="${PROMPT//\{\{JOURNAL_ENTRIES\}\}/$JOURNAL_ENTRIES}"
PROMPT="${PROMPT//\{\{MERGED_PRS\}\}/$MERGED_PRS}"
PROMPT="${PROMPT//\{\{GUIDANCE_FILES\}\}/$GUIDANCE_FILES}"
PROMPT="${PROMPT//\{\{GUIDANCE_DIR\}\}/$GUIDANCE_DIR}"
PROMPT="${PROMPT//\{\{REPOS_ROOT\}\}/$REPOS_ROOT}"
PROMPT="${PROMPT//\{\{DATE\}\}/$(date -u +%Y-%m-%d)}"
PROMPT="${PROMPT//\{\{RUN_NUMBER\}\}/$RUN_NUMBER}"
PROMPT="${PROMPT//\{\{MEMORY_SCAN\}\}/$MEMORY_SCAN}"
PROMPT="${PROMPT//\{\{GIT_ACTIVITY\}\}/$GIT_ACTIVITY}"
PROMPT="${PROMPT//\{\{CLI_INTERACTIONS\}\}/$CLI_INTERACTIONS}"

MAX_TIMEOUT=1800

log "START: Learning agent run #$RUN_NUMBER (timeout: ${MAX_TIMEOUT}s)"

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
  log "TIMEOUT: Learning agent run #$RUN_NUMBER exceeded ${MAX_TIMEOUT}s timeout"
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
  log "DONE: Learning agent run #$RUN_NUMBER completed (cost: $COST)"
  log "Result preview: ${RESULT:0:200}"
else
  log "FAIL: Learning agent run #$RUN_NUMBER exited with code $EXIT_CODE (cost: $COST)"
fi

# ── Post to Discord #learnings ──────────────────────────────────────

post_to_discord() {
  local webhook="$1" msg="$2" username="${3:-Learning Agent}"
  [ -z "$webhook" ] && return 0
  msg="${msg:0:1990}"
  local payload
  payload=$(jq -n --arg content "$msg" --arg user "$username" '{"username": $user, "content": $content}')
  curl -s -X POST "$webhook" \
    -H "Content-Type: application/json" \
    -d "$payload" > /dev/null 2>&1 || true
}

GUIDANCE_UPDATED=$(echo "$RESULT" | grep -oP 'GUIDANCE_UPDATED:\s*\K\S+' | head -1 || echo "unknown")
CORRECTIONS_FOUND=$(echo "$RESULT" | grep -oP 'CORRECTIONS_FOUND:\s*\K\S+' | head -1 || echo "0")
MEMORY_GAPS=$(echo "$RESULT" | grep -oP 'MEMORY_GAPS:\s*\K\S+' | head -1 || echo "0")
SUGGESTIONS=$(echo "$RESULT" | grep -oP 'SUGGESTIONS:\s*\K\S+' | head -1 || echo "0")

# Determine which webhook to use (prefer #learnings, fall back to #autonomous-dev)
POST_WEBHOOK="${LEARNINGS_WEBHOOK:-$AUTONOMOUS_DEV_WEBHOOK}"

if [ "$GUIDANCE_UPDATED" = "no" ] || [ "$GUIDANCE_UPDATED" = "none" ]; then
  # Only heartbeat every 12 runs (every 12 hours at hourly cadence)
  if (( RUN_NUMBER % 12 == 0 )); then
    post_to_discord "$POST_WEBHOOK" "📚 **Learning Agent heartbeat** — run #$RUN_NUMBER, no gaps found (cost: $COST)"
  fi
  log "No guidance updates — no Discord post"
elif [ $EXIT_CODE -eq 0 ]; then
  SUMMARY="📚 **Learning Agent #$RUN_NUMBER** (cost: $COST)"
  [ "$CORRECTIONS_FOUND" != "0" ] && SUMMARY="$SUMMARY | ⚠️ $CORRECTIONS_FOUND uncaptured corrections"
  [ "$MEMORY_GAPS" != "0" ] && SUMMARY="$SUMMARY | 🔄 $MEMORY_GAPS memory-only learnings migrated"
  [ "$SUGGESTIONS" != "0" ] && SUMMARY="$SUMMARY | 💡 $SUGGESTIONS suggestions"

  post_to_discord "$POST_WEBHOOK" "$SUMMARY

${RESULT:0:1600}"
else
  post_to_discord "$POST_WEBHOOK" "⚠️ **Learning Agent #$RUN_NUMBER FAILED** (exit: $EXIT_CODE, cost: $COST)

Check logs at ~/repos/autonomousDev/learnings-pass/logs/"
fi

# ── Post to agent journal ───────────────────────────────────────────

JOURNAL_SCRIPT="$HOME/repos/privateContext/journal-post.sh"
if [ -x "$JOURNAL_SCRIPT" ] && [ $EXIT_CODE -eq 0 ] && [ "$GUIDANCE_UPDATED" != "no" ] && [ "$GUIDANCE_UPDATED" != "none" ]; then
  JOURNAL_SUMMARY=$(echo "$RESULT" | head -c 400)
  "$JOURNAL_SCRIPT" "discovery" "learning-agent run #$RUN_NUMBER: $JOURNAL_SUMMARY" || true
fi

# ── Clean up old logs (keep last 30) ────────────────────────────────

ls -t "$LOGS_DIR"/run-*.log 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
