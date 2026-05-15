#!/usr/bin/env bash
# score.sh — Score a completed agent interaction against ESSENTIAL rules.
#
# Called as a post-run phase by other agent runners, or standalone for
# interactive sessions.
#
# Usage:
#   ./score.sh --agent-type <type> --run-log <path>
#   ./score.sh --agent-type interactive --session-data <path>
#   ./score.sh --agent-type interactive --from-discord   (grabs latest cli-interactions)
#
# Writes score JSON to supervisor/scores/<date>/<id>.json
# Appends to supervisor/scores/<date>/scores.jsonl for aggregation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCORER_PROMPT="$SCRIPT_DIR/scorer-prompt.md"
SCORES_DIR="$SCRIPT_DIR/scores"
LOGS_DIR="$SCRIPT_DIR/logs"

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
AGENT_TYPE=""
RUN_LOG=""
SESSION_DATA=""
FROM_DISCORD=false

while [ $# -gt 0 ]; do
  case "$1" in
    --agent-type) AGENT_TYPE="$2"; shift 2 ;;
    --run-log) RUN_LOG="$2"; shift 2 ;;
    --session-data) SESSION_DATA="$2"; shift 2 ;;
    --from-discord) FROM_DISCORD=true; shift ;;
    *) shift ;;
  esac
done

[ -z "$AGENT_TYPE" ] && echo "ERROR: --agent-type required (autonomous-dev|learning-agent|fix-checker|interactive)" >&2 && exit 1

TODAY=$(date -u +%Y-%m-%d)
mkdir -p "$SCORES_DIR/$TODAY" "$LOGS_DIR"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [scorer] $*" >> "$LOGS_DIR/scorer.log"
}

# ── Build session data for the scorer ────────────────────────────────

SESSION=""

if [ -n "$RUN_LOG" ] && [ -f "$RUN_LOG" ]; then
  # For autonomous agents: extract the result section from run log
  # Try stream-json result first
  RESULT_TEXT=$(grep -m1 '"type":"result"' "$RUN_LOG" 2>/dev/null \
    | jq -r '.result // ""' 2>/dev/null \
    | head -c 4000 || echo "")

  if [ -z "$RESULT_TEXT" ] || [ "$RESULT_TEXT" = "null" ]; then
    # Fallback: last 4000 chars of log
    RESULT_TEXT=$(tail -c 4000 "$RUN_LOG" 2>/dev/null || echo "")
  fi
  SESSION="$RESULT_TEXT"

elif [ -n "$SESSION_DATA" ] && [ -f "$SESSION_DATA" ]; then
  SESSION=$(head -c 5000 "$SESSION_DATA" 2>/dev/null || echo "")

elif [ "$FROM_DISCORD" = true ]; then
  # Grab the most recent cli-interactions messages (last session)
  TOKEN_CACHE="$HOME/.cache/discord-bot-token"
  BOT_TOKEN=""
  [ -f "$TOKEN_CACHE" ] && BOT_TOKEN=$(cat "$TOKEN_CACHE" 2>/dev/null || echo "")

  CLI_CHANNEL_ID="${DISCORD_CLI_INTERACTIONS_CHANNEL_ID:-}"

  # Load from env files if not set
  for envf in "$HOME/.env" "$(dirname "$SCRIPT_DIR")/.env" "$SCRIPT_DIR/.env"; do
    [ -f "$envf" ] && source "$envf" 2>/dev/null || true
  done
  [ -z "$CLI_CHANNEL_ID" ] && CLI_CHANNEL_ID="${DISCORD_CLI_INTERACTIONS_CHANNEL_ID:-}"

  if [ -n "$BOT_TOKEN" ] && [ -n "$CLI_CHANNEL_ID" ]; then
    RAW_MSGS=$(curl -sf --max-time 15 \
      -H "Authorization: Bot ${BOT_TOKEN}" \
      "https://discord.com/api/v10/channels/${CLI_CHANNEL_ID}/messages?limit=5" 2>/dev/null || echo "[]")

    SESSION=$(echo "$RAW_MSGS" | python3 -c "
import json, sys
msgs = json.load(sys.stdin)
# Get the most recent messages (likely from the last session)
for m in msgs[:5]:
    content = m.get('content', '')[:1500]
    if content:
        print(content)
        print('---')
" 2>/dev/null || echo "")
  fi

  if [ -z "$SESSION" ]; then
    log "SKIP: Could not fetch Discord data for interactive scoring"
    exit 0
  fi
else
  log "SKIP: No data source provided (need --run-log, --session-data, or --from-discord)"
  exit 0
fi

# Bail if session data is too short to be meaningful
if [ "${#SESSION}" -lt 50 ]; then
  log "SKIP: Session data too short (${#SESSION} chars) for meaningful scoring"
  exit 0
fi

# ── Run scorer via Claude Haiku ──────────────────────────────────────

# Signal to Stop hooks that this is a scorer session (prevents recursion)
export CLAUDE_SCORER_ACTIVE=1

PROMPT=$(cat "$SCORER_PROMPT")
PROMPT="$PROMPT

## Session Data

Agent type: $AGENT_TYPE
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)

$SESSION"

SCORE_ID="score-$(date -u +%Y%m%d-%H%M%S)-$$"
SCORE_FILE="$SCORES_DIR/$TODAY/$SCORE_ID.json"

log "Scoring $AGENT_TYPE interaction ($SCORE_ID, ${#SESSION} chars of session data)..."

RESULT=$(echo "$PROMPT" | timeout 60 "$CLAUDE_BIN" -p --model haiku 2>/dev/null || echo "")

if [ -z "$RESULT" ]; then
  log "WARN: Scorer returned empty result for $SCORE_ID"
  exit 0
fi

# ── Parse and write score ────────────────────────────────────────────

JSON=$(python3 -c "
import sys, json, re

text = sys.stdin.read()

# Find JSON object containing 'rules' key
for match in re.finditer(r'\{[\s\S]*\}', text):
    try:
        obj = json.loads(match.group())
        if 'rules' in obj:
            # Add metadata
            obj['id'] = '$SCORE_ID'
            obj['timestamp'] = '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
            if 'agent_type' not in obj:
                obj['agent_type'] = '$AGENT_TYPE'

            # Compute summary stats
            rules = obj.get('rules', {})
            applicable = [k for k, v in rules.items() if isinstance(v, dict) and v.get('score') is not None]
            violations = [k for k in applicable if rules[k]['score'] == 0]
            obj['applicable_rules'] = len(applicable)
            obj['violations'] = len(violations)
            obj['score_pct'] = round(100 * (len(applicable) - len(violations)) / max(len(applicable), 1))
            obj['violation_list'] = violations

            print(json.dumps(obj, indent=2))
            sys.exit(0)
    except json.JSONDecodeError:
        continue

sys.exit(1)
" <<< "$RESULT" 2>/dev/null || echo "")

if [ -n "$JSON" ]; then
  echo "$JSON" > "$SCORE_FILE"
  # Append to daily JSONL for easy aggregation
  echo "$JSON" | jq -c . >> "$SCORES_DIR/$TODAY/scores.jsonl" 2>/dev/null || true

  SCORE_PCT=$(echo "$JSON" | jq -r '.score_pct // "?"')
  VIOLATIONS=$(echo "$JSON" | jq -r '.violations // 0')
  TOP_ISSUE=$(echo "$JSON" | jq -r '.top_issue // "none"')

  log "SCORED: $SCORE_ID — ${SCORE_PCT}% ($VIOLATIONS violations). Top issue: $TOP_ISSUE"
  echo "SCORE: ${SCORE_PCT}% | Violations: $VIOLATIONS | $TOP_ISSUE"
else
  log "WARN: Could not extract valid JSON from scorer output for $SCORE_ID"
  # Save raw result for debugging
  echo "$RESULT" > "$SCORES_DIR/$TODAY/$SCORE_ID.raw" 2>/dev/null || true
fi
