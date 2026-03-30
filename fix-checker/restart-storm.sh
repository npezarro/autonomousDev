#!/usr/bin/env bash
# restart-storm.sh — Detect and auto-rollback PM2 restart storms on the VM.
# Called by fix-checker when it detects elevated restart counts.
#
# Usage: ./restart-storm.sh <process-name> [--dry-run]
#
# Exits 0 on successful rollback, 1 on failure, 2 if no storm detected.

set -euo pipefail

PROCESS_NAME="${1:-}"
DRY_RUN="${2:-}"
STORM_THRESHOLD=5          # restarts in current check window = storm
STABILITY_WAIT=30          # seconds to wait after rollback before verifying
VM_HOST="REDACTED_VM_HOST"

if [ -z "$PROCESS_NAME" ]; then
  echo "Usage: $0 <process-name> [--dry-run]"
  exit 1
fi

log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) [restart-storm] $*"; }

# ── Map PM2 process name to repo and deploy name ──────────────────
declare -A PROCESS_TO_REPO=(
  [claude-bot]=REDACTED_DISCORD_BOT_REPO
  [runeval]=runEvaluator
  [promptlibrary]=promptlibrary
  [pezant-tools]=pezantTools
  [claude-auto-merger]=claude-auto-merger
  [runeval-staging]=runeval
  [grocerygenius-staging]=groceryGenius
  [promptlibrary-staging]=promptlibrary
  [free-games]=freeGames
  [epic-claimer]=freeGames
)

REPO_NAME="${PROCESS_TO_REPO[$PROCESS_NAME]:-}"
if [ -z "$REPO_NAME" ]; then
  log "ERROR: Unknown process '$PROCESS_NAME' — no repo mapping"
  exit 1
fi

# ── Check current restart count ───────────────────────────────────
RESTART_COUNT=$(ssh "$VM_HOST" "pm2 jlist 2>/dev/null" \
  | jq -r ".[] | select(.name == \"$PROCESS_NAME\") | .pm2_env.restart_time // 0" 2>/dev/null \
  || echo 0)

log "Process '$PROCESS_NAME' restart count: $RESTART_COUNT (threshold: $STORM_THRESHOLD)"

if [ "$RESTART_COUNT" -lt "$STORM_THRESHOLD" ]; then
  log "No storm detected"
  exit 2
fi

log "STORM DETECTED: $PROCESS_NAME has $RESTART_COUNT restarts"

# ── Stop the crashing process ─────────────────────────────────────
if [ "$DRY_RUN" = "--dry-run" ]; then
  log "DRY RUN: Would stop $PROCESS_NAME and rollback"
  exit 0
fi

log "Stopping $PROCESS_NAME..."
ssh "$VM_HOST" "pm2 stop $PROCESS_NAME" 2>/dev/null || true

# ── Find last stable commit (before crash window) ────────────────
# Look at the VM's repo for the last 5 commits
REPO_PATH="REDACTED_VM_HOME/$REPO_NAME"
RECENT_COMMITS=$(ssh "$VM_HOST" "cd '$REPO_PATH' 2>/dev/null && git log --oneline -5 2>/dev/null" || echo "")

if [ -z "$RECENT_COMMITS" ]; then
  log "ERROR: Cannot read git log from $REPO_PATH on VM"
  # Restart the process anyway — better than leaving it stopped
  ssh "$VM_HOST" "pm2 restart $PROCESS_NAME" 2>/dev/null || true
  exit 1
fi

# Current HEAD
CURRENT_SHA=$(ssh "$VM_HOST" "cd '$REPO_PATH' && git rev-parse HEAD" 2>/dev/null)
# Roll back to parent of HEAD (one commit back)
ROLLBACK_SHA=$(ssh "$VM_HOST" "cd '$REPO_PATH' && git rev-parse HEAD~1" 2>/dev/null)

if [ -z "$ROLLBACK_SHA" ]; then
  log "ERROR: Cannot determine rollback target"
  ssh "$VM_HOST" "pm2 restart $PROCESS_NAME" 2>/dev/null || true
  exit 1
fi

log "Rolling back $REPO_NAME from $CURRENT_SHA to $ROLLBACK_SHA"

# ── Deploy rollback commit ────────────────────────────────────────
ssh "$VM_HOST" "cd '$REPO_PATH' && git checkout $ROLLBACK_SHA" 2>/dev/null

# Reinstall deps if needed
ssh "$VM_HOST" "cd '$REPO_PATH' && [ -f package.json ] && npm install --production 2>/dev/null" || true

# Restart the process
ssh "$VM_HOST" "pm2 restart $PROCESS_NAME" 2>/dev/null

# ── Verify stability ─────────────────────────────────────────────
log "Waiting ${STABILITY_WAIT}s to verify stability..."
sleep "$STABILITY_WAIT"

POST_RESTART_COUNT=$(ssh "$VM_HOST" "pm2 jlist 2>/dev/null" \
  | jq -r ".[] | select(.name == \"$PROCESS_NAME\") | .pm2_env.restart_time // 0" 2>/dev/null \
  || echo 999)

UPTIME=$(ssh "$VM_HOST" "pm2 jlist 2>/dev/null" \
  | jq -r ".[] | select(.name == \"$PROCESS_NAME\") | .pm2_env.pm_uptime // 0" 2>/dev/null \
  || echo 0)

UPTIME_SECS=$(( ($(date +%s%3N) - UPTIME) / 1000 ))

if [ "$POST_RESTART_COUNT" -eq 0 ] && [ "$UPTIME_SECS" -ge "$((STABILITY_WAIT - 5))" ]; then
  log "STABLE: $PROCESS_NAME is running on rollback commit $ROLLBACK_SHA (uptime: ${UPTIME_SECS}s)"
  echo "ROLLBACK_SUCCESS"
  echo "PROCESS=$PROCESS_NAME"
  echo "REPO=$REPO_NAME"
  echo "FROM=$CURRENT_SHA"
  echo "TO=$ROLLBACK_SHA"
  echo "RECENT_COMMITS:"
  echo "$RECENT_COMMITS"
  exit 0
else
  log "UNSTABLE: $PROCESS_NAME still crashing after rollback (restarts: $POST_RESTART_COUNT)"
  # Stop it to prevent further damage
  ssh "$VM_HOST" "pm2 stop $PROCESS_NAME" 2>/dev/null || true
  echo "ROLLBACK_FAILED"
  echo "PROCESS=$PROCESS_NAME"
  echo "REPO=$REPO_NAME"
  echo "MANUAL_INTERVENTION_REQUIRED"
  exit 1
fi
