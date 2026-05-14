#!/usr/bin/env bash
# run.sh — Ecosystem Supervisor daily runner.
# Aggregates session scores, analyzes trends, and generates improvement proposals.
#
# Usage: ./run.sh [--dry-run]
#
# Schedule: daily via cron (recommended: 6 AM local time, after overnight runs)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
PROMPT_TEMPLATE="$SCRIPT_DIR/prompt.md"
SCORES_DIR="$SCRIPT_DIR/scores"
REPORTS_DIR="$SCRIPT_DIR/reports"
LOGS_DIR="$SCRIPT_DIR/logs"
LOCK_FILE="$SCRIPT_DIR/.running.lock"
STATE_FILE="$SCRIPT_DIR/state.json"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
DRY_RUN="${1:-}"

# ── Load secrets ────────────────────────────────────────────────────

if [ -f "$HOME/.env" ]; then
  set -a; source "$HOME/.env"; set +a
fi
if [ -f "$PARENT_DIR/.env" ]; then
  set -a; source "$PARENT_DIR/.env"; set +a
fi
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
fi

SUPERVISOR_WEBHOOK="${DISCORD_SUPERVISOR_WEBHOOK_URL:-}"

# ── Logging ─────────────────────────────────────────────────────────

mkdir -p "$LOGS_DIR" "$REPORTS_DIR" "$SCORES_DIR"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [supervisor] $*" | tee -a "$LOGS_DIR/runner.log"
}

# ── Lock ────────────────────────────────────────────────────────────

if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    log "SKIP: Previous supervisor still active (PID $LOCK_PID)"
    exit 0
  else
    rm -f "$LOCK_FILE"
  fi
fi

echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# ── Skip if sibling agents are running ──────────────────────────────

for sibling_lock in "$PARENT_DIR/.running.lock" "$PARENT_DIR/fix-checker/.running.lock" "$PARENT_DIR/learnings-pass/.running.lock"; do
  if [ -f "$sibling_lock" ]; then
    SIBLING_PID=$(cat "$sibling_lock" 2>/dev/null || echo "")
    if [ -n "$SIBLING_PID" ] && kill -0 "$SIBLING_PID" 2>/dev/null; then
      log "SKIP: Sibling agent running (PID $SIBLING_PID from $sibling_lock)"
      exit 0
    fi
  fi
done

# ── Usage check (85% threshold — supervisor is low priority) ────────

USAGE_SCRIPT=""
for p in "$HOME/repos/privateContext/check-usage.sh" "$HOME/privateContext/check-usage.sh"; do
  [ -x "$p" ] && USAGE_SCRIPT="$p" && break
done
if [ -n "$USAGE_SCRIPT" ]; then
  USAGE_OUTPUT=$("$USAGE_SCRIPT" --force 2>/dev/null || echo "")
  USAGE_5H=$(echo "$USAGE_OUTPUT" | grep -oP '5h:\s*\K[\d.]+' | head -1 || echo "0")
  USAGE_7D=$(echo "$USAGE_OUTPUT" | grep -oP '7d:\s*\K[\d.]+' | head -1 || echo "0")
  MAX_USAGE=$(python3 -c "print(max(float('${USAGE_5H:-0}'), float('${USAGE_7D:-0}')))" 2>/dev/null || echo "0")

  if python3 -c "exit(0 if float('$MAX_USAGE') >= 85 else 1)" 2>/dev/null; then
    log "SKIP: Usage at ${MAX_USAGE}% (>= 85%) — supervisor is low priority"
    exit 0
  fi
  log "Usage: 5h=${USAGE_5H}%, 7d=${USAGE_7D}%"
fi

# ── State management ────────────────────────────────────────────────

write_state() {
  local tmp="$STATE_FILE.tmp"
  echo "$1" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

RUN_NUMBER=1
if [ -f "$STATE_FILE" ]; then
  RUN_NUMBER=$(( $(jq -r '.run_number // 0' "$STATE_FILE" 2>/dev/null || echo 0) + 1 ))
fi

# ── Gather recent scores (last 24h) ────────────────────────────────

TODAY=$(date -u +%Y-%m-%d)
YESTERDAY=$(date -u -d 'yesterday' +%Y-%m-%d 2>/dev/null || date -u -v-1d +%Y-%m-%d 2>/dev/null || echo "")

RECENT_SCORES=""
for day in "$TODAY" "$YESTERDAY"; do
  [ -z "$day" ] && continue
  JSONL="$SCORES_DIR/$day/scores.jsonl"
  if [ -f "$JSONL" ]; then
    RECENT_SCORES="$RECENT_SCORES
### $day
$(cat "$JSONL" | jq -r '
  "- \(.id // "?") | \(.agent_type // "?") | \(.repo // "?") | score: \(.score_pct // "?")% | violations: \(.violation_list // [] | join(", "))"
' 2>/dev/null || echo "(parse error)")"
  fi
done

if [ -z "$RECENT_SCORES" ]; then
  RECENT_SCORES="No scores collected yet. This is the first run or no agents have been scored in the last 24h."
fi

# ── Gather historical scores (last 7 days, aggregated) ──────────────

HISTORICAL_SCORES=""
for i in $(seq 2 7); do
  DAY=$(date -u -d "$i days ago" +%Y-%m-%d 2>/dev/null || date -u -v-${i}d +%Y-%m-%d 2>/dev/null || echo "")
  [ -z "$DAY" ] && continue
  JSONL="$SCORES_DIR/$DAY/scores.jsonl"
  if [ -f "$JSONL" ]; then
    COUNT=$(wc -l < "$JSONL" 2>/dev/null || echo 0)
    AVG_SCORE=$(jq -s '[.[].score_pct // 0] | add / length | floor' "$JSONL" 2>/dev/null || echo "?")
    # Aggregate violations by rule
    RULE_VIOLATIONS=$(jq -s '
      [.[].violation_list // []] | flatten | group_by(.) | map({(.[0]): length}) | add // {}
    ' "$JSONL" 2>/dev/null || echo "{}")
    HISTORICAL_SCORES="$HISTORICAL_SCORES
- **$DAY**: $COUNT sessions, avg ${AVG_SCORE}%, violations: $RULE_VIOLATIONS"
  fi
done

if [ -z "$HISTORICAL_SCORES" ]; then
  HISTORICAL_SCORES="No historical data yet. Scores will accumulate over the coming days."
fi

# ── Read ESSENTIAL.md ───────────────────────────────────────────────

ESSENTIAL_MD=""
ESSENTIAL_PATH="$HOME/repos/agentGuidance/guidance/ESSENTIAL.md"
if [ -f "$ESSENTIAL_PATH" ]; then
  ESSENTIAL_MD=$(cat "$ESSENTIAL_PATH")
fi

# ── Read active proposals ──────────────────────────────────────────

ACTIVE_PROPOSALS=""
if [ -d "$REPORTS_DIR" ]; then
  # Read the most recent report's proposals section
  LATEST_REPORT=$(ls -t "$REPORTS_DIR"/*.md 2>/dev/null | head -1 || echo "")
  if [ -n "$LATEST_REPORT" ] && [ -f "$LATEST_REPORT" ]; then
    ACTIVE_PROPOSALS=$(sed -n '/## Improvement Proposals/,/## Profile/p' "$LATEST_REPORT" 2>/dev/null | head -50 || echo "")
  fi
fi
[ -z "$ACTIVE_PROPOSALS" ] && ACTIVE_PROPOSALS="No prior proposals."

# ── Read learning agent suggestions ────────────────────────────────

SUGGESTIONS=""
SUGG_FILE="$PARENT_DIR/learnings-pass/suggestions.md"
if [ -f "$SUGG_FILE" ]; then
  SUGGESTIONS=$(tail -50 "$SUGG_FILE" 2>/dev/null || echo "")
fi
[ -z "$SUGGESTIONS" ] && SUGGESTIONS="No suggestions from learning agent."

# ── Fetch recent cli-interactions ──────────────────────────────────

CLI_INTERACTIONS=""
TOKEN_CACHE="$HOME/.cache/discord-bot-token"
BOT_TOKEN=""
[ -f "$TOKEN_CACHE" ] && BOT_TOKEN=$(cat "$TOKEN_CACHE" 2>/dev/null || echo "")
CLI_CHANNEL_ID="${DISCORD_CLI_INTERACTIONS_CHANNEL_ID:-}"

if [ -n "$BOT_TOKEN" ] && [ -n "$CLI_CHANNEL_ID" ]; then
  RAW_CLI=$(curl -sf --max-time 15 \
    -H "Authorization: Bot ${BOT_TOKEN}" \
    "https://discord.com/api/v10/channels/${CLI_CHANNEL_ID}/messages?limit=30" 2>/dev/null || echo "[]")

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
        print(m['content'][:400])
        print('---')
" 2>/dev/null || echo "")
fi
[ -z "$CLI_INTERACTIONS" ] && CLI_INTERACTIONS="No cli-interactions data available."

# ── Read autonomous dev outcomes ────────────────────────────────────

OUTCOMES_LOG=""
OUTCOME_FILE="$PARENT_DIR/logs/outcomes.jsonl"
if [ -f "$OUTCOME_FILE" ]; then
  # Last 7 days of outcomes
  OUTCOMES_LOG=$(tail -50 "$OUTCOME_FILE" | jq -r '
    "Run #\(.run // "?") | \(.timestamp // "?") | \(.repo // "?") | PR#\(.pr // 0) | verify: \(.verify // "?") | review: \(.cc_review // "?")"
  ' 2>/dev/null || echo "(parse error)")
fi
[ -z "$OUTCOMES_LOG" ] && OUTCOMES_LOG="No outcome data available."

# ── Build prompt ────────────────────────────────────────────────────
# Use Python for template substitution to avoid bash's & back-reference
# bug in ${var//pattern/replacement} (& in replacement = matched text).

PROMPT_FILE=$(mktemp)
export PROMPT_TEMPLATE RECENT_SCORES HISTORICAL_SCORES ESSENTIAL_MD
export ACTIVE_PROPOSALS SUGGESTIONS CLI_INTERACTIONS OUTCOMES_LOG
export TODAY PROMPT_FILE
export RUN_NUMBER_STR="$RUN_NUMBER"

python3 << 'PYEOF'
import os

template_path = os.environ.get('PROMPT_TEMPLATE', '')
with open(template_path) as f:
    prompt = f.read()

replacements = {
    '{{RECENT_SCORES}}': os.environ.get('RECENT_SCORES', ''),
    '{{HISTORICAL_SCORES}}': os.environ.get('HISTORICAL_SCORES', ''),
    '{{ESSENTIAL_MD}}': os.environ.get('ESSENTIAL_MD', ''),
    '{{ACTIVE_PROPOSALS}}': os.environ.get('ACTIVE_PROPOSALS', ''),
    '{{SUGGESTIONS}}': os.environ.get('SUGGESTIONS', ''),
    '{{CLI_INTERACTIONS}}': os.environ.get('CLI_INTERACTIONS', ''),
    '{{OUTCOMES_LOG}}': os.environ.get('OUTCOMES_LOG', ''),
    '{{DATE}}': os.environ.get('TODAY', ''),
    '{{RUN_NUMBER}}': os.environ.get('RUN_NUMBER_STR', ''),
}

for key, value in replacements.items():
    prompt = prompt.replace(key, value)

output_path = os.environ.get('PROMPT_FILE', '/dev/stdout')
with open(output_path, 'w') as f:
    f.write(prompt)
PYEOF

PROMPT=$(cat "$PROMPT_FILE")
rm -f "$PROMPT_FILE"

MAX_TIMEOUT=1200

log "START: Supervisor run #$RUN_NUMBER (timeout: ${MAX_TIMEOUT}s)"

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

RUN_LOG_FILE="$LOGS_DIR/run-$(date -u +%Y%m%d-%H%M%S).log"
touch "$RUN_LOG_FILE" && chmod 600 "$RUN_LOG_FILE"

timeout "$MAX_TIMEOUT" "$CLAUDE_BIN" \
  -p \
  --model sonnet \
  --verbose \
  --output-format stream-json \
  <<< "$PROMPT" \
  > "$RUN_LOG_FILE" 2>&1

EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
  log "TIMEOUT: Supervisor run #$RUN_NUMBER exceeded ${MAX_TIMEOUT}s"
fi

# ── Extract result ──────────────────────────────────────────────────

RESULT=$(grep -m1 '"type":"result"' "$RUN_LOG_FILE" 2>/dev/null \
  | jq -r '.result // "No result extracted"' 2>/dev/null \
  | head -c 10000 \
  || echo "No result extracted")

COST=$(grep '"type":"result"' "$RUN_LOG_FILE" 2>/dev/null \
  | jq -r 'select(.total_cost_usd) | "$\(.total_cost_usd | tostring | .[0:6])"' 2>/dev/null \
  | tail -1 \
  || echo "unknown")
[ -z "$COST" ] && COST="unknown"

# ── Save report ─────────────────────────────────────────────────────

REPORT_FILE="$REPORTS_DIR/$TODAY.md"
echo "$RESULT" > "$REPORT_FILE"
log "Report saved to $REPORT_FILE"

# ── Update state ────────────────────────────────────────────────────

write_state "$(jq -n \
  --argjson num "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson exit "$EXIT_CODE" \
  --arg cost "$COST" \
  '{run_number: $num, last_run: $ts, last_exit_code: $exit, last_cost: $cost}')"

# ── Post to Discord #supervisor ─────────────────────────────────────

post_to_discord() {
  local webhook="$1" msg="$2" username="${3:-Ecosystem Supervisor}"
  [ -z "$webhook" ] && return 0
  msg="${msg:0:1990}"
  local payload
  payload=$(jq -n --arg content "$msg" --arg user "$username" '{"username": $user, "content": $content}')
  local response
  response=$(curl -s -X POST "${webhook}?wait=true" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null || echo "")
  echo "$response" | jq -r '.id // empty' 2>/dev/null || echo ""
}

# Extract summary section from report
SUMMARY=$(echo "$RESULT" | head -20)

# Determine which webhook to use
POST_WEBHOOK="${SUPERVISOR_WEBHOOK:-${AUTONOMOUS_DEV_WEBHOOK:-}}"

if [ -n "$POST_WEBHOOK" ]; then
  if [ $EXIT_CODE -eq 0 ]; then
    MSG_ID=$(post_to_discord "$POST_WEBHOOK" "**Ecosystem Supervisor #$RUN_NUMBER** (cost: $COST)

$SUMMARY")

    # Post full report as thread
    if [ -n "$MSG_ID" ]; then
      SUPERVISOR_CHANNEL_ID="${DISCORD_SUPERVISOR_CHANNEL_ID:-}"
      if [ -n "$SUPERVISOR_CHANNEL_ID" ]; then
        BOT_TOKEN=""
        [ -f "$HOME/.cache/discord-bot-token" ] && BOT_TOKEN=$(cat "$HOME/.cache/discord-bot-token" 2>/dev/null || echo "")

        if [ -n "$BOT_TOKEN" ]; then
          THREAD_NAME="Supervisor #$RUN_NUMBER — $TODAY"
          THREAD_RESPONSE=$(curl -s -X POST \
            "https://discord.com/api/v10/channels/${SUPERVISOR_CHANNEL_ID}/messages/$MSG_ID/threads" \
            -H "Authorization: Bot $BOT_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg name "$THREAD_NAME" '{"name": $name, "auto_archive_duration": 1440}')" \
            2>/dev/null || echo "")

          THREAD_ID=$(echo "$THREAD_RESPONSE" | jq -r '.id // empty' 2>/dev/null || echo "")

          if [ -n "$THREAD_ID" ]; then
            # Post full report in chunks
            DETAIL="${RESULT:20}"
            while [ -n "$DETAIL" ]; do
              CHUNK="${DETAIL:0:1990}"
              DETAIL="${DETAIL:1990}"
              curl -s -X POST \
                "https://discord.com/api/v10/channels/$THREAD_ID/messages" \
                -H "Authorization: Bot $BOT_TOKEN" \
                -H "Content-Type: application/json" \
                -d "$(jq -n --arg content "$CHUNK" '{"content": $content}')" \
                >/dev/null 2>&1 || true
              [ -n "$DETAIL" ] && sleep 1
            done
          fi
        fi
      fi
    fi
  else
    post_to_discord "$POST_WEBHOOK" "**Ecosystem Supervisor #$RUN_NUMBER FAILED** (exit: $EXIT_CODE, cost: $COST)"
  fi
fi

# ── Post to agent journal ──────────────────────────────────────────

JOURNAL_SCRIPT="$HOME/repos/privateContext/journal-post.sh"
if [ -x "$JOURNAL_SCRIPT" ] && [ $EXIT_CODE -eq 0 ]; then
  JOURNAL_SUMMARY=$(echo "$RESULT" | head -c 400)
  "$JOURNAL_SCRIPT" "discovery" "supervisor run #$RUN_NUMBER: $JOURNAL_SUMMARY" || true
fi

log "DONE: Supervisor run #$RUN_NUMBER (exit: $EXIT_CODE, cost: $COST)"

# ── Clean up old logs and scores ────────────────────────────────────

# Keep 30 days of scores
find "$SCORES_DIR" -maxdepth 1 -type d -name "20*" -mtime +30 -exec rm -rf {} \; 2>/dev/null || true

# Keep 30 run logs
ls -t "$LOGS_DIR"/run-*.log 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
