#!/usr/bin/env bash
# overnight-summary.sh — Post-run summary of overnight autonomous dev activity.
# Queries GitHub for PRs created by autonomous runs, partitions into
# auto-merged vs pending review, and posts to Discord #autonomous-dev.
#
# Triggering:
#   - Called by run.sh after the final scheduled run of the overnight window
#   - Manual: ./overnight-summary.sh --post-now
#   - Preview: ./overnight-summary.sh --dry-run
#
# Usage:
#   ./overnight-summary.sh [--dry-run] [--post-now] [--lookback HOURS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$SCRIPT_DIR/.state"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/overnight-summary.log"
REPOS_CONF="$SCRIPT_DIR/repos.conf"
STATE_FILE="$SCRIPT_DIR/state.json"

DRY_RUN=false
POST_NOW=false
LOOKBACK_HOURS="${OVERNIGHT_LOOKBACK_HOURS:-10}"

# ── Parse args ────────────────────────────────────────────────────────

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   DRY_RUN=true; shift ;;
    --post-now)  POST_NOW=true; shift ;;
    --lookback)  LOOKBACK_HOURS="$2"; shift 2 ;;
    *)           shift ;;
  esac
done

# ── Load secrets ──────────────────────────────────────────────────────

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  source "$SCRIPT_DIR/.env"
  set +a
fi

WEBHOOK="${AUTONOMOUS_DEV_WEBHOOK:-}"

# ── Logging ───────────────────────────────────────────────────────────

mkdir -p "$LOG_DIR" "$STATE_DIR"

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [overnight-summary] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# Rotate log: keep last 1000 lines
if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt 1000 ]; then
  tail -1000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

log "START: dry_run=$DRY_RUN post_now=$POST_NOW lookback=${LOOKBACK_HOURS}h"

# ── Idempotency guard ────────────────────────────────────────────────

GUARD_FILE="$STATE_DIR/last-summary-date"
TODAY=$(date -u +%Y-%m-%d)

if [ "$POST_NOW" = false ] && [ -f "$GUARD_FILE" ]; then
  LAST_DATE=$(cat "$GUARD_FILE" 2>/dev/null || echo "")
  if [ "$LAST_DATE" = "$TODAY" ]; then
    log "SKIP: Summary already posted today ($TODAY)"
    exit 0
  fi
fi

# ── gh auth preflight ────────────────────────────────────────────────

if ! gh auth status >/dev/null 2>&1; then
  log "ERROR: gh auth failed"
  if [ "$DRY_RUN" = false ] && [ -n "$WEBHOOK" ]; then
    # Post failure notice via raw curl (don't depend on gh)
    curl -s -X POST "$WEBHOOK" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg c "**Overnight Summary Failed** — GitHub auth is broken. Run \`gh auth login\` on the host." \
        '{"username": "Overnight Summary", "content": $c}')" \
      >/dev/null 2>&1 || true
  fi
  exit 1
fi

# ── Rate limit check ─────────────────────────────────────────────────

RATE_REMAINING=$(gh api rate_limit --jq '.rate.remaining' 2>/dev/null || echo "0")
if [ "$RATE_REMAINING" -lt 50 ]; then
  log "ERROR: GitHub API rate limit low (remaining: $RATE_REMAINING)"
  exit 1
fi

# ── Load repo list ───────────────────────────────────────────────────

if [ ! -f "$REPOS_CONF" ]; then
  log "ERROR: repos.conf not found at $REPOS_CONF"
  exit 1
fi

REPOS=()
while IFS= read -r line; do
  line="${line%%#*}"      # strip comments
  line="${line// /}"      # strip spaces
  [ -z "$line" ] && continue
  REPOS+=("$line")
done < "$REPOS_CONF"

log "Scanning ${#REPOS[@]} repos"

# ── Compute time window ──────────────────────────────────────────────

SINCE=$(date -u -d "${LOOKBACK_HOURS} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v-${LOOKBACK_HOURS}H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

log "Window: $SINCE → now"

# ── Query PRs per repo ───────────────────────────────────────────────

MERGED=()
PENDING=()
ERRORS=()
GITHUB_USER="REDACTED_GITHUB_USER"

for repo in "${REPOS[@]}"; do
  sleep 0.5  # rate limit courtesy

  # Get PRs created in the lookback window with auto branch prefixes
  PRS=$(gh pr list \
    --repo "$GITHUB_USER/$repo" \
    --state all \
    --json number,title,state,mergedAt,url,headRefName,createdAt \
    --limit 50 \
    2>/dev/null || echo "[]")

  if [ "$PRS" = "[]" ] || [ -z "$PRS" ]; then
    continue
  fi

  # Filter to auto-created PRs within the time window
  # Branch prefixes: claude/auto, claude-auto, claude/fix
  FILTERED=$(echo "$PRS" | jq -r --arg since "$SINCE" '
    [.[] | select(
      (.createdAt >= $since) and
      (.headRefName | test("^claude[/-](auto|fix)"))
    )]
  ' 2>/dev/null || echo "[]")

  COUNT=$(echo "$FILTERED" | jq 'length' 2>/dev/null || echo "0")
  [ "$COUNT" = "0" ] && continue

  # Partition into merged vs open
  echo "$FILTERED" | jq -c '.[]' | while IFS= read -r pr; do
    STATE=$(echo "$pr" | jq -r '.state')
    TITLE=$(echo "$pr" | jq -r '.title')
    URL=$(echo "$pr" | jq -r '.url')
    NUM=$(echo "$pr" | jq -r '.number')

    if [ "$STATE" = "MERGED" ]; then
      echo "MERGED|$repo|#$NUM $TITLE|$URL" >> "$STATE_DIR/.summary-merged.tmp"
    elif [ "$STATE" = "OPEN" ]; then
      echo "PENDING|$repo|#$NUM $TITLE|$URL" >> "$STATE_DIR/.summary-pending.tmp"
    fi
  done
done

# Read temp files into arrays (subshell piping workaround)
if [ -f "$STATE_DIR/.summary-merged.tmp" ]; then
  while IFS= read -r line; do
    MERGED+=("$line")
  done < "$STATE_DIR/.summary-merged.tmp"
  rm -f "$STATE_DIR/.summary-merged.tmp"
fi

if [ -f "$STATE_DIR/.summary-pending.tmp" ]; then
  while IFS= read -r line; do
    PENDING+=("$line")
  done < "$STATE_DIR/.summary-pending.tmp"
  rm -f "$STATE_DIR/.summary-pending.tmp"
fi

# Clean up any stale temp files
rm -f "$STATE_DIR/.summary-merged.tmp" "$STATE_DIR/.summary-pending.tmp"

# ── Get run count from state.json ────────────────────────────────────

RUN_COUNT=""
if [ -f "$STATE_FILE" ]; then
  RUN_COUNT=$(jq -r '.run_number // ""' "$STATE_FILE" 2>/dev/null || echo "")
fi

# ── Format output ────────────────────────────────────────────────────

MERGED_COUNT=${#MERGED[@]}
PENDING_COUNT=${#PENDING[@]}
TOTAL=$((MERGED_COUNT + PENDING_COUNT))

log "Results: $MERGED_COUNT merged, $PENDING_COUNT pending"

# Build top-level summary line
if [ $TOTAL -eq 0 ]; then
  # Heartbeat: no activity
  SUMMARY_LINE="Overnight: no PRs created in the last ${LOOKBACK_HOURS}h."
  DETAIL=""
else
  PARTS=()
  [ $MERGED_COUNT -gt 0 ] && PARTS+=("$MERGED_COUNT auto-merged")
  [ $PENDING_COUNT -gt 0 ] && PARTS+=("$PENDING_COUNT need your review")
  SUMMARY_LINE="**Overnight Summary** — $TOTAL PRs: $(IFS=', '; echo "${PARTS[*]}")"

  # Build threaded detail — grouped by repo for readability
  format_section() {
    local section_name="$1"
    shift
    local entries=("$@")
    local result=""
    local current_repo=""

    result+="**$section_name**"$'\n'
    for entry in "${entries[@]}"; do
      IFS='|' read -r _ repo title url <<< "$entry"
      if [ "$repo" != "$current_repo" ]; then
        current_repo="$repo"
        result+="**$repo**"$'\n'
      fi
      result+="  - $title — $url"$'\n'
    done
    echo "$result"
  }

  DETAIL=""

  if [ $MERGED_COUNT -gt 0 ]; then
    DETAIL+=$(format_section "Auto-Merged" "${MERGED[@]}")
  fi

  if [ $PENDING_COUNT -gt 0 ]; then
    [ -n "$DETAIL" ] && DETAIL+=$'\n'
    DETAIL+=$(format_section "Pending Your Approval" "${PENDING[@]}")
  fi
fi

# ── Post to Discord ──────────────────────────────────────────────────

post_to_discord() {
  local webhook="$1" msg="$2"
  [ -z "$webhook" ] && return 0
  msg="${msg:0:1990}"
  local payload
  payload=$(jq -n --arg content "$msg" '{"username": "Overnight Summary", "content": $content}')
  local response
  response=$(curl -s -X POST "$webhook" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null || echo "")
  # Extract message ID for threading
  echo "$response" | jq -r '.id // empty' 2>/dev/null || echo ""
}

post_thread_reply() {
  local msg_id="$1" msg="$2"

  # Get bot token (same approach as discord-webhook.sh)
  local bot_token=""
  if [ -f "$HOME/.cache/discord-bot-token" ]; then
    bot_token=$(cat "$HOME/.cache/discord-bot-token" 2>/dev/null || echo "")
  fi
  if [ -z "$bot_token" ]; then
    log "WARN: No bot token available for threading, skipping thread"
    return 1
  fi

  # Create thread from message
  local thread_name="${SUMMARY_LINE:0:100}"
  local thread_response
  thread_response=$(curl -s -X POST \
    "https://discord.com/api/v10/channels/REDACTED_AUTONOMOUS_DEV_CHANNEL_ID/messages/$msg_id/threads" \
    -H "Authorization: Bot $bot_token" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg name "$thread_name" '{"name": $name, "auto_archive_duration": 1440}')" \
    2>/dev/null || echo "")

  local thread_id
  thread_id=$(echo "$thread_response" | jq -r '.id // empty' 2>/dev/null || echo "")

  if [ -z "$thread_id" ]; then
    log "WARN: Failed to create thread"
    return 1
  fi

  # Post detail in chunks
  while [ -n "$msg" ]; do
    local chunk="${msg:0:1990}"
    msg="${msg:1990}"

    curl -s -X POST \
      "https://discord.com/api/v10/channels/$thread_id/messages" \
      -H "Authorization: Bot $bot_token" \
      -H "Content-Type: application/json" \
      -d "$(jq -n --arg content "$chunk" '{"content": $content}')" \
      >/dev/null 2>&1 || true

    [ -n "$msg" ] && sleep 1
  done
}

if [ "$DRY_RUN" = true ]; then
  echo "=== DRY RUN ==="
  echo ""
  echo "--- Top-level message ---"
  echo "$SUMMARY_LINE"
  if [ -n "${DETAIL:-}" ]; then
    echo ""
    echo "--- Threaded detail ---"
    echo "$DETAIL"
  fi
  echo ""
  echo "=== Would post to: #autonomous-dev ==="
  log "DRY RUN completed"
  exit 0
fi

if [ -z "$WEBHOOK" ]; then
  log "ERROR: AUTONOMOUS_DEV_WEBHOOK not set"
  echo "ERROR: No webhook configured. Set AUTONOMOUS_DEV_WEBHOOK in .env"
  exit 1
fi

# Post summary
MSG_ID=$(post_to_discord "$WEBHOOK" "$SUMMARY_LINE")
log "Posted summary (msg_id: $MSG_ID)"

# Post threaded detail if we have it
if [ -n "${DETAIL:-}" ] && [ -n "$MSG_ID" ]; then
  post_thread_reply "$MSG_ID" "$DETAIL" || {
    # Fallback: post detail as a follow-up message (no thread)
    log "WARN: Threading failed, posting as follow-up"
    post_to_discord "$WEBHOOK" "$DETAIL"
  }
fi

# ── Update idempotency guard ─────────────────────────────────────────

echo "$TODAY" > "$GUARD_FILE"
log "DONE: Summary posted, guard updated to $TODAY"
