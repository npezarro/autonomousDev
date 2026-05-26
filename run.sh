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

GEMINI_BIN="${GEMINI_BIN:-gemini}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
DRY_RUN=""
FOCUS_REPO=""
FOCUS_TASK=""

# Parse args
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN="--dry-run"; shift ;;
    --repo) FOCUS_REPO="$2"; shift 2 ;;
    --task) FOCUS_TASK="$2"; shift 2 ;;
    *) shift ;;
  esac
done

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

# ── Usage check: nightly 2% budget cap with last-24h uncap ───────────
#
# Budget rules:
#   1. Normal nights: autonomous dev may consume at most 2% of usage per night
#   2. Last 24h before 7d refresh: uncapped (can run freely up to 80% total)
#   3. Hard stop at 80% usage always
#
# A "night" is one cron window (UTC date). A snapshot of usage is taken on the
# first run of each night. Subsequent runs compare current usage to the snapshot.

NIGHTLY_BUDGET_CAP=$(jq -r '.nightly_budget_cap_percent // 2' "$CONFIG" 2>/dev/null || echo 2)
HARD_STOP=$(jq -r '.hard_stop_percent // 80' "$CONFIG" 2>/dev/null || echo 80)
BUDGET_SNAPSHOT="$SCRIPT_DIR/.nightly-usage-snapshot.json"

USAGE_SCRIPT=""
for p in "$HOME/repos/privateContext/check-usage.sh" "$HOME/privateContext/check-usage.sh" "$HOME/repos/claude-usage-monitor/check-usage.sh"; do
  [ -x "$p" ] && USAGE_SCRIPT="$p" && break
done
if [ -n "$USAGE_SCRIPT" ]; then
  # Force-refresh the cache to get live numbers
  USAGE_OUTPUT=$("$USAGE_SCRIPT" --force 2>/dev/null || echo "")

  # Extract usage percentages
  USAGE_5H=$(echo "$USAGE_OUTPUT" | grep -oP '5h: \K[0-9.]+' | head -1)
  USAGE_7D=$(echo "$USAGE_OUTPUT" | grep -oP '7d: \K[0-9.]+' | head -1)
  MAX_USAGE=$(python3 -c "print(max(${USAGE_5H:-0}, ${USAGE_7D:-0}))" 2>/dev/null || echo 0)

  # Extract 7d reset time from cached state
  USAGE_STATE="$HOME/.cache/claude-usage-state.json"
  RESET_7D=$(jq -r '.seven_day.resets_at // ""' "$USAGE_STATE" 2>/dev/null || echo "")

  log "USAGE: 5h=${USAGE_5H:-?}% 7d=${USAGE_7D:-?}% max=${MAX_USAGE}%"

  # Hard stop at 80% always
  if python3 -c "exit(0 if $MAX_USAGE >= $HARD_STOP else 1)" 2>/dev/null; then
    log "SKIP: Usage at ${MAX_USAGE}% (>= ${HARD_STOP}%) — hard stop"
    rm -f "$LOCK_FILE"
    exit 0
  fi

  # Check if we're in the last 24h before 7d refresh (uncapped mode)
  UNCAPPED=false
  if [ -n "$RESET_7D" ]; then
    UNCAPPED=$(python3 -c "
from datetime import datetime, timezone, timedelta
try:
    reset = datetime.fromisoformat('$RESET_7D'.replace('Z', '+00:00'))
    now = datetime.now(timezone.utc)
    hours_until_reset = (reset - now).total_seconds() / 3600
    print('true' if 0 < hours_until_reset <= 24 else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")
  fi

  if [ "$UNCAPPED" = "true" ]; then
    log "UNCAPPED: Within 24h of 7d refresh — bypassing nightly cap (hard stop at ${HARD_STOP}%)"
  else
    # Normal night: enforce 2% nightly budget cap
    TODAY_UTC=$(date -u +%Y-%m-%d)

    # Check if we need a new nightly snapshot
    SNAPSHOT_DATE=""
    if [ -f "$BUDGET_SNAPSHOT" ]; then
      SNAPSHOT_DATE=$(jq -r '.date // ""' "$BUDGET_SNAPSHOT" 2>/dev/null || echo "")
    fi

    if [ "$SNAPSHOT_DATE" != "$TODAY_UTC" ]; then
      # First run of the night: take snapshot
      jq -n \
        --arg date "$TODAY_UTC" \
        --argjson usage_5h "${USAGE_5H:-0}" \
        --argjson usage_7d "${USAGE_7D:-0}" \
        '{date: $date, usage_5h: $usage_5h, usage_7d: $usage_7d}' \
        > "$BUDGET_SNAPSHOT"
      log "SNAPSHOT: New nightly snapshot — 5h=${USAGE_5H:-0}% 7d=${USAGE_7D:-0}%"
    else
      # Subsequent run: check delta from snapshot
      SNAP_5H=$(jq -r '.usage_5h // 0' "$BUDGET_SNAPSHOT" 2>/dev/null || echo 0)
      SNAP_7D=$(jq -r '.usage_7d // 0' "$BUDGET_SNAPSHOT" 2>/dev/null || echo 0)

      BUDGET_EXCEEDED=$(python3 -c "
snap_5h, snap_7d = $SNAP_5H, $SNAP_7D
now_5h, now_7d = ${USAGE_5H:-0}, ${USAGE_7D:-0}
delta_5h = now_5h - snap_5h
delta_7d = now_7d - snap_7d
# Use the max delta (whichever bucket grew more)
max_delta = max(delta_5h, delta_7d, 0)
print(f'{max_delta:.1f}')
" 2>/dev/null || echo "0")

      log "BUDGET: Nightly delta=${BUDGET_EXCEEDED}% (cap=${NIGHTLY_BUDGET_CAP}%)"

      if python3 -c "exit(0 if float('$BUDGET_EXCEEDED') >= $NIGHTLY_BUDGET_CAP else 1)" 2>/dev/null; then
        log "SKIP: Nightly budget exhausted (${BUDGET_EXCEEDED}% >= ${NIGHTLY_BUDGET_CAP}%) — stopping for tonight"
        rm -f "$LOCK_FILE"
        exit 0
      fi
    fi
  fi
fi

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

# ── Build repo list (auto-discover new repos) ───────────────────────

REPOS_ROOT=$(jq -r '.repos_root // "REDACTED_REPOS_ROOT"' "$CONFIG")
PROTECTED=$(jq -r '.protected_repos[]' "$CONFIG" 2>/dev/null)
CONFIGURED=$(jq -r '.repos[]' "$CONFIG")

# Auto-discover: scan repos_root for git repos not in config or protected
DISCOVERED=""
for d in "$REPOS_ROOT"/*/; do
  repo_name=$(basename "$d")
  [ ! -d "$d/.git" ] && continue
  echo "$CONFIGURED" | grep -qx "$repo_name" && continue
  echo "$PROTECTED" | grep -qx "$repo_name" && continue
  # Skip tiny repos (< 5 commits)
  commit_count=$(cd "$d" && git rev-list --count HEAD 2>/dev/null || echo 0)
  [ "$commit_count" -lt 5 ] && continue
  DISCOVERED="$DISCOVERED$repo_name
"
done

if [ -n "$DISCOVERED" ]; then
  log "Auto-discovered repos: $(echo "$DISCOVERED" | tr '\n' ', ')"
  # Add discovered repos to config
  for repo in $DISCOVERED; do
    jq --arg r "$repo" '.repos += [$r] | .repos |= unique' "$CONFIG" > "$CONFIG.tmp" && mv "$CONFIG.tmp" "$CONFIG"
  done
fi

# If --repo flag is set, focus on that repo only
if [ -n "$FOCUS_REPO" ]; then
  REPOS="$FOCUS_REPO"
  log "FOCUSED RUN: $FOCUS_REPO"
else
  REPOS=$(jq -r '.repos[]' "$CONFIG")
fi

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

# ── Inject priority context files ────────────────────────────────────

PRIORITY_CONTEXT=""
if [ -d "$SCRIPT_DIR/context" ]; then
  for ctx in "$SCRIPT_DIR/context"/*-priority.md; do
    [ -f "$ctx" ] || continue
    # If focused on a specific repo, only include matching context
    if [ -n "$FOCUS_REPO" ]; then
      echo "$ctx" | grep -qi "$FOCUS_REPO" || continue
    fi
    PRIORITY_CONTEXT="$PRIORITY_CONTEXT

$(cat "$ctx")
"
  done
fi

if [ -n "$PRIORITY_CONTEXT" ]; then
  PRIOR_CONTEXT="$PRIOR_CONTEXT

## Priority Tasks
$PRIORITY_CONTEXT"
fi

# ── Inject crash context from fix-checker ──────────────────────────

CRASH_CONTEXT=""
if [ -d "$SCRIPT_DIR/context" ]; then
  for ctx in "$SCRIPT_DIR/context"/*-priority.md; do
    [ -f "$ctx" ] || continue
    if grep -q "crash-priority\|restart_time\|CRASH CONTEXT" "$ctx" 2>/dev/null; then
      CRASH_CONTEXT="$CRASH_CONTEXT
$(cat "$ctx")"
    fi
  done
fi

if [ -n "$CRASH_CONTEXT" ]; then
  PRIOR_CONTEXT="$PRIOR_CONTEXT

## Crash Context (from fix-checker)
These processes are experiencing elevated restarts. Investigate the root cause and create a fix PR.
$CRASH_CONTEXT"
fi

# ── Determine run mode (standard vs feature) ──────────────────────────

FEATURE_RUN=false
if (( RUN_NUMBER % 2 == 0 )); then
  FEATURE_RUN=true
  log "FEATURE RUN: Run #$RUN_NUMBER is a feature run (every 2nd run)"
fi

# ── Orchestration: select repo + agent profile(s) ────────────────────

PROFILES_DIR="$HOME/repos/agentGuidance/profiles"
AGENT_PROFILE_SECTION=""

if [ -x "$SCRIPT_DIR/orchestrate.sh" ] && [ -d "$PROFILES_DIR" ]; then
  # Write inputs to temp files (avoids arg-length limits and quoting issues)
  ORCH_REPOS_TMP=$(mktemp)
  ORCH_CTX_TMP=$(mktemp)
  echo "$REPO_LIST" > "$ORCH_REPOS_TMP"
  echo "$PRIOR_CONTEXT" > "$ORCH_CTX_TMP"

  ORCH_ARGS=(
    --repos-file "$ORCH_REPOS_TMP"
    --context-file "$ORCH_CTX_TMP"
    --profiles-dir "$PROFILES_DIR"
  )
  [ "$FEATURE_RUN" = true ] && ORCH_ARGS+=(--feature-run)
  [ -n "$FOCUS_REPO" ] && ORCH_ARGS+=(--focus-repo "$FOCUS_REPO")

  log "ORCHESTRATING: calling orchestrate.sh..."
  ORCH_JSON=$("$SCRIPT_DIR/orchestrate.sh" "${ORCH_ARGS[@]}" 2>/dev/null || echo "")
  rm -f "$ORCH_REPOS_TMP" "$ORCH_CTX_TMP"

  if [ -n "$ORCH_JSON" ] && echo "$ORCH_JSON" | jq -e '.repo' >/dev/null 2>&1; then
    ORCH_REPO=$(echo "$ORCH_JSON" | jq -r '.repo // ""')
    ORCH_PROFILES=$(echo "$ORCH_JSON" | jq -r '.profiles[]' 2>/dev/null || echo "")
    ORCH_STRATEGY=$(echo "$ORCH_JSON" | jq -r '.strategy // ""')

    log "ORCHESTRATION: repo=$ORCH_REPO profiles=$(echo $ORCH_PROFILES | tr '\n' ',') strategy=$ORCH_STRATEGY"

    # Load selected profile(s) into prompt section
    for profile_key in $ORCH_PROFILES; do
      PROFILE_FILE="$PROFILES_DIR/$profile_key/profile.md"
      EXPERIENCE_FILE="$PROFILES_DIR/$profile_key/experience.md"
      if [ -f "$PROFILE_FILE" ]; then
        AGENT_PROFILE_SECTION="$AGENT_PROFILE_SECTION
---
$(cat "$PROFILE_FILE")"
        if [ -f "$EXPERIENCE_FILE" ]; then
          RECENT_EXP=$(tail -30 "$EXPERIENCE_FILE" 2>/dev/null || echo "")
          [ -n "$RECENT_EXP" ] && AGENT_PROFILE_SECTION="$AGENT_PROFILE_SECTION

### Recent Experience
$RECENT_EXP"
        fi
      fi
    done

    # Build the full profile section with header and strategy
    if [ -n "$AGENT_PROFILE_SECTION" ]; then
      AGENT_PROFILE_SECTION="## Agent Profile

You are operating with the following specialist perspective(s). Apply this expertise and working style to all decisions this session.

**Recommended repo:** ${ORCH_REPO:-(your choice)}
**Strategy:** ${ORCH_STRATEGY:-(your judgment)}
$AGENT_PROFILE_SECTION"
    fi
  else
    log "ORCHESTRATION: no result, agent picks freely"
  fi
else
  log "ORCHESTRATION: skipped (script or profiles dir missing)"
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
PROMPT="${PROMPT//\{\{FEATURE_RUN\}\}/$FEATURE_RUN}"
PROMPT="${PROMPT//\{\{AGENT_PROFILE\}\}/$AGENT_PROFILE_SECTION}"

# Inject feature ideas context on feature runs
if [ "$FEATURE_RUN" = true ] && [ -d "$SCRIPT_DIR/context" ]; then
  FEATURE_IDEAS=""
  for fctx in "$SCRIPT_DIR/context"/*-features.md; do
    [ -f "$fctx" ] || continue
    FEATURE_IDEAS="$FEATURE_IDEAS
$(cat "$fctx")"
  done
  if [ -n "$FEATURE_IDEAS" ]; then
    PROMPT="$PROMPT

## Feature Ideas (from previous runs)
$FEATURE_IDEAS"
  fi
fi

# Inject specific task directive if provided via --task
if [ -n "$FOCUS_TASK" ]; then
  PROMPT="$PROMPT

## Directed Task

**You have a specific task assigned for this run. This overrides the normal priority system.**

**Task:** $FOCUS_TASK
**Repo:** ${FOCUS_REPO:-(choose the most relevant repo for this task)}

Complete this task, create a PR, and report results. All other rules (staging only, branch naming, testing, output format) still apply."
fi

log "START: Run #$RUN_NUMBER (Gemini+CC, repos: $(echo "$REPOS" | wc -w), feature_run: $FEATURE_RUN${FOCUS_TASK:+, task: $FOCUS_TASK})"

if [ -n "$DRY_RUN" ]; then
  log "DRY RUN — prompt would be:"
  echo "$PROMPT"
  exit 0
fi

# ── Pre-flight: verify Gemini auth ───────────────────────────────────

AUTH_CHECK=$(timeout 30 "$GEMINI_BIN" -p "Say: OK" 2>&1 || echo "auth_failed")
if echo "$AUTH_CHECK" | grep -qi "auth.*fail\|not authenticated\|login\|credential\|UNAUTHENTICATED"; then
  log "SKIP: Gemini auth failed — run 'gemini' interactively to re-auth."
  write_state "$(jq -n \
    --argjson num "$RUN_NUMBER" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{run_number: $num, last_run: $ts, last_exit_code: 1, last_cost: "$0", last_error: "gemini_auth_failed"}')"
  exit 1
fi

# ── Phase 1: Run Gemini (coding) ─────────────────────────────────────

RUN_LOG="$LOGS_DIR/run-$(date -u +%Y%m%d-%H%M%S).log"
touch "$RUN_LOG" && chmod 600 "$RUN_LOG"

# Write prompt to temp file to avoid shell argument length limits
PROMPT_FILE=$(mktemp)
printf '%s' "$PROMPT" > "$PROMPT_FILE"

log "PHASE 1: Gemini coding pass starting..."
timeout 2700 "$GEMINI_BIN" \
  --yolo \
  -p "$(< "$PROMPT_FILE")" \
  > "$RUN_LOG" 2>&1

EXIT_CODE=$?
rm -f "$PROMPT_FILE"

# Handle timeout (exit code 124)
if [ $EXIT_CODE -eq 124 ]; then
  log "TIMEOUT: Run #$RUN_NUMBER exceeded 45 minute timeout"
fi

# Copy to latest for cap check on next run
cp "$RUN_LOG" "$LAST_RUN_LOG" 2>/dev/null || true

# ── Extract result ───────────────────────────────────────────────────

# Try stream-json parsing first (works if Gemini used -o stream-json)
RESULT=$(grep -m1 '"type":"result"' "$RUN_LOG" 2>/dev/null \
  | jq -r '.result // ""' 2>/dev/null \
  | head -c 2000 \
  || echo "")

# Fallback: extract from plain text output (grep structured output blocks)
if [ -z "$RESULT" ] || [ "$RESULT" = "null" ]; then
  # Extract the last 200 lines which should contain the structured summary
  RESULT=$(tail -200 "$RUN_LOG" 2>/dev/null | head -c 2000 || echo "No result extracted")
fi

# Gemini with free GCA auth has no cost tracking
COST="$0 (Gemini)"

# ── Update state (atomic write) ─────────────────────────────────────

write_state "$(jq -n \
  --argjson num "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson exit "$EXIT_CODE" \
  --arg cost "$COST" \
  '{run_number: $num, last_run: $ts, last_exit_code: $exit, last_cost: $cost}')"

# ── Log result ───────────────────────────────────────────────────────

if [ $EXIT_CODE -eq 0 ]; then
  log "PHASE 1 DONE: Gemini coding pass completed"
  log "Result preview: ${RESULT:0:200}"
else
  log "PHASE 1 FAIL: Gemini exited with code $EXIT_CODE"
fi

# ── Outcome tracking ─────────────────────────────────────────────

OUTCOME_LOG="$LOGS_DIR/outcomes.jsonl"

RUN_TYPE=$(echo "$RESULT" | grep -oP 'RUN_TYPE:\s*\K\S+' | head -1 || echo "standard")
FILES_CHANGED=$(echo "$RESULT" | grep -oP 'FILES_CHANGED:\s*\K\d+' | head -1 || echo "0")
LINES_CHANGED=$(echo "$RESULT" | grep -oP 'LINES_CHANGED:\s*\K\d+' | head -1 || echo "0")
RESULT_REPO=$(echo "$RESULT" | grep -oP 'REPO:\s*\K\S+' | head -1 || echo "unknown")
RESULT_PR=$(echo "$RESULT" | grep -oP 'PR:\s*#\K\d+' | head -1 || echo "0")

# ── Post-agent verification: independent build/test check ────────────

VERIFY_STATUS="skip"
VERIFY_DETAIL=""

if [ $EXIT_CODE -eq 0 ] && [ "${RESULT_PR:-0}" != "0" ] && [ "$RESULT_REPO" != "unknown" ]; then
  if [ -x "$SCRIPT_DIR/verify.sh" ]; then
    log "PHASE 2: Build/test verification of PR #$RESULT_PR in $RESULT_REPO..."
    VERIFY_OUTPUT=$("$SCRIPT_DIR/verify.sh" "$REPOS_ROOT" "$RESULT_REPO" "$RESULT_PR" 2>&1 || true)

    # Parse the last line for status
    VERIFY_LAST=$(echo "$VERIFY_OUTPUT" | tail -1)
    if echo "$VERIFY_LAST" | grep -q "^VERIFY_PASS"; then
      VERIFY_STATUS="pass"
      VERIFY_DETAIL=$(echo "$VERIFY_LAST" | sed 's/^VERIFY_PASS: //')
      log "VERIFY: PASS ($VERIFY_DETAIL)"
    elif echo "$VERIFY_LAST" | grep -q "^VERIFY_FAIL"; then
      VERIFY_STATUS="fail"
      VERIFY_DETAIL=$(echo "$VERIFY_LAST" | sed 's/^VERIFY_FAIL: //')
      log "VERIFY: FAIL ($VERIFY_DETAIL)"
      # Add failure comment to the PR
      gh pr comment "$RESULT_PR" \
        --repo "$(cd "$REPOS_ROOT/$RESULT_REPO" && gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")" \
        --body "**Automated Verification Failed**

Post-agent build/test check detected failures:
\`$VERIFY_DETAIL\`

This PR needs fixes before merge. The agent's own testing may have missed this." 2>/dev/null || true
    else
      VERIFY_STATUS="skip"
      VERIFY_DETAIL=$(echo "$VERIFY_LAST" | sed 's/^VERIFY_SKIP: //')
      log "VERIFY: SKIP ($VERIFY_DETAIL)"
    fi
  fi
fi

# ── Phase 3: Claude Code review of Gemini's PR ────────────────────────

CC_REVIEW_STATUS="skip"
CC_REVIEW_DETAIL=""

if [ $EXIT_CODE -eq 0 ] && [ "${RESULT_PR:-0}" != "0" ] && [ "$RESULT_REPO" != "unknown" ]; then
  if [ -x "$SCRIPT_DIR/review.sh" ]; then
    log "PHASE 3: Claude Code reviewing PR #$RESULT_PR in $RESULT_REPO..."
    CC_REVIEW_OUTPUT=$("$SCRIPT_DIR/review.sh" "$REPOS_ROOT" "$RESULT_REPO" "$RESULT_PR" 2>&1 || true)

    CC_REVIEW_LAST=$(echo "$CC_REVIEW_OUTPUT" | tail -1)
    if echo "$CC_REVIEW_LAST" | grep -q "^REVIEW_PASS"; then
      CC_REVIEW_STATUS="pass"
      CC_REVIEW_DETAIL=$(echo "$CC_REVIEW_LAST" | sed 's/^REVIEW_PASS: //')
      log "CC REVIEW: PASS ($CC_REVIEW_DETAIL)"
    elif echo "$CC_REVIEW_LAST" | grep -q "^REVIEW_FAIL"; then
      CC_REVIEW_STATUS="fail"
      CC_REVIEW_DETAIL=$(echo "$CC_REVIEW_LAST" | sed 's/^REVIEW_FAIL: //')
      log "CC REVIEW: FAIL ($CC_REVIEW_DETAIL)"
      # Add review failure comment to the PR
      gh pr comment "$RESULT_PR" \
        --repo "$(cd "$REPOS_ROOT/$RESULT_REPO" && gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")" \
        --body "**Claude Code Review — Issues Found**

Code review detected potential issues:
\`$CC_REVIEW_DETAIL\`

This PR needs attention before merge." 2>/dev/null || true
    elif echo "$CC_REVIEW_LAST" | grep -q "^REVIEW_CONCERNS"; then
      CC_REVIEW_STATUS="concerns"
      CC_REVIEW_DETAIL=$(echo "$CC_REVIEW_LAST" | sed 's/^REVIEW_CONCERNS: //')
      log "CC REVIEW: CONCERNS ($CC_REVIEW_DETAIL)"
    else
      CC_REVIEW_STATUS="skip"
      CC_REVIEW_DETAIL=$(echo "$CC_REVIEW_LAST" | sed 's/^REVIEW_SKIP: //')
      log "CC REVIEW: SKIP ($CC_REVIEW_DETAIL)"
    fi
  fi
fi

# ── Phase 3.5: Cloud ultrareview for complex PRs ─────────────────────

ULTRAREVIEW_STATUS="skip"
ULTRAREVIEW_DETAIL=""

if [ $EXIT_CODE -eq 0 ] && [ "${RESULT_PR:-0}" != "0" ] && [ "$RESULT_REPO" != "unknown" ] \
   && [ "$CC_REVIEW_STATUS" != "fail" ] && [ "$VERIFY_STATUS" != "fail" ]; then
  if [ -x "$SCRIPT_DIR/ultrareview.sh" ]; then
    log "PHASE 3.5: Cloud ultrareview of PR #$RESULT_PR in $RESULT_REPO..."
    ULTRAREVIEW_OUTPUT=$("$SCRIPT_DIR/ultrareview.sh" "$REPOS_ROOT" "$RESULT_REPO" "$RESULT_PR" "${FILES_CHANGED:-0}" 2>&1 || true)

    ULTRAREVIEW_LAST=$(echo "$ULTRAREVIEW_OUTPUT" | tail -1)
    if echo "$ULTRAREVIEW_LAST" | grep -q "^ULTRAREVIEW_PASS"; then
      ULTRAREVIEW_STATUS="pass"
      ULTRAREVIEW_DETAIL=$(echo "$ULTRAREVIEW_LAST" | sed 's/^ULTRAREVIEW_PASS: //')
      log "ULTRAREVIEW: PASS ($ULTRAREVIEW_DETAIL)"
    elif echo "$ULTRAREVIEW_LAST" | grep -q "^ULTRAREVIEW_FAIL"; then
      ULTRAREVIEW_STATUS="fail"
      ULTRAREVIEW_DETAIL=$(echo "$ULTRAREVIEW_LAST" | sed 's/^ULTRAREVIEW_FAIL: //')
      log "ULTRAREVIEW: FAIL ($ULTRAREVIEW_DETAIL)"
      gh pr comment "$RESULT_PR" \
        --repo "$(cd "$REPOS_ROOT/$RESULT_REPO" && gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")" \
        --body "**Cloud Ultrareview -- Issues Found**

Multi-agent cloud review detected issues:
\`$ULTRAREVIEW_DETAIL\`

This PR needs attention before merge." 2>/dev/null || true
    elif echo "$ULTRAREVIEW_LAST" | grep -q "^ULTRAREVIEW_CONCERNS"; then
      ULTRAREVIEW_STATUS="concerns"
      ULTRAREVIEW_DETAIL=$(echo "$ULTRAREVIEW_LAST" | sed 's/^ULTRAREVIEW_CONCERNS: //')
      log "ULTRAREVIEW: CONCERNS ($ULTRAREVIEW_DETAIL)"
    else
      ULTRAREVIEW_STATUS="skip"
      ULTRAREVIEW_DETAIL=$(echo "$ULTRAREVIEW_LAST" | sed 's/^ULTRAREVIEW_SKIP: //')
      log "ULTRAREVIEW: SKIP ($ULTRAREVIEW_DETAIL)"
    fi
  fi
fi

# ── Phase 4: Gemini pre-deploy review ─────────────────────────────────

PREDEPLOY_STATUS="skip"
PREDEPLOY_DETAIL=""

if [ $EXIT_CODE -eq 0 ] && [ "${RESULT_PR:-0}" != "0" ] && [ "$RESULT_REPO" != "unknown" ] \
   && [ "$VERIFY_STATUS" != "fail" ] && [ "$CC_REVIEW_STATUS" != "fail" ]; then
  if [ -x "$SCRIPT_DIR/pre-deploy-review.sh" ]; then
    log "PHASE 4: Gemini pre-deploy review of PR #$RESULT_PR..."
    PREDEPLOY_OUTPUT=$("$SCRIPT_DIR/pre-deploy-review.sh" "$REPOS_ROOT" "$RESULT_REPO" "$RESULT_PR" 2>&1 || true)

    PREDEPLOY_LAST=$(echo "$PREDEPLOY_OUTPUT" | tail -1)
    if echo "$PREDEPLOY_LAST" | grep -q "^PREDEPLOY_PASS"; then
      PREDEPLOY_STATUS="pass"
      PREDEPLOY_DETAIL=$(echo "$PREDEPLOY_LAST" | sed 's/^PREDEPLOY_PASS: //')
      log "PRE-DEPLOY: PASS ($PREDEPLOY_DETAIL)"
    elif echo "$PREDEPLOY_LAST" | grep -q "^PREDEPLOY_FAIL"; then
      PREDEPLOY_STATUS="fail"
      PREDEPLOY_DETAIL=$(echo "$PREDEPLOY_LAST" | sed 's/^PREDEPLOY_FAIL: //')
      log "PRE-DEPLOY: FAIL ($PREDEPLOY_DETAIL)"
    elif echo "$PREDEPLOY_LAST" | grep -q "^PREDEPLOY_CONCERNS"; then
      PREDEPLOY_STATUS="concerns"
      PREDEPLOY_DETAIL=$(echo "$PREDEPLOY_LAST" | sed 's/^PREDEPLOY_CONCERNS: //')
      log "PRE-DEPLOY: CONCERNS ($PREDEPLOY_DETAIL)"
    else
      PREDEPLOY_STATUS="skip"
      log "PRE-DEPLOY: SKIP"
    fi
  fi
fi

jq -n \
  --argjson run "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg run_type "$RUN_TYPE" \
  --arg repo "$RESULT_REPO" \
  --argjson pr "${RESULT_PR:-0}" \
  --argjson files "${FILES_CHANGED:-0}" \
  --argjson lines "${LINES_CHANGED:-0}" \
  --argjson exit_code "$EXIT_CODE" \
  --arg cost "$COST" \
  --argjson feature_run "$( [ "$FEATURE_RUN" = true ] && echo true || echo false )" \
  --arg verify "$VERIFY_STATUS" \
  --arg verify_detail "$VERIFY_DETAIL" \
  --arg cc_review "$CC_REVIEW_STATUS" \
  --arg cc_review_detail "$CC_REVIEW_DETAIL" \
  --arg predeploy "$PREDEPLOY_STATUS" \
  --arg predeploy_detail "$PREDEPLOY_DETAIL" \
  --arg ultrareview "$ULTRAREVIEW_STATUS" \
  --arg ultrareview_detail "$ULTRAREVIEW_DETAIL" \
  '{run: $run, timestamp: $ts, run_type: $run_type, repo: $repo, pr: $pr, files_changed: $files, lines_changed: $lines, exit_code: $exit_code, cost: $cost, feature_run: $feature_run, verify: $verify, verify_detail: $verify_detail, cc_review: $cc_review, cc_review_detail: $cc_review_detail, predeploy: $predeploy, predeploy_detail: $predeploy_detail, ultrareview: $ultrareview, ultrareview_detail: $ultrareview_detail}' \
  >> "$OUTCOME_LOG" 2>/dev/null || true

# ── Phase 5: Ecosystem Supervisor scoring ────────────────────────────

SCORER="$SCRIPT_DIR/supervisor/score.sh"
if [ -x "$SCORER" ] && [ $EXIT_CODE -eq 0 ] && [ -f "$RUN_LOG" ]; then
  log "PHASE 5: Scoring session against ESSENTIAL rules..."
  SCORE_OUTPUT=$("$SCORER" --agent-type autonomous-dev --run-log "$RUN_LOG" 2>&1 || true)
  log "SCORE: $SCORE_OUTPUT"
fi

# ── Post to agent journal ────────────────────────────────────────────

JOURNAL_SCRIPT="$HOME/repos/privateContext/journal-post.sh"
if [ -x "$JOURNAL_SCRIPT" ] && [ $EXIT_CODE -eq 0 ] && [ -n "$RESULT" ]; then
  JOURNAL_SUMMARY=$(echo "$RESULT" | head -c 400)
  "$JOURNAL_SCRIPT" "discovery" "auto-dev run #$RUN_NUMBER: $JOURNAL_SUMMARY" || true
elif [ -x "$JOURNAL_SCRIPT" ] && [ $EXIT_CODE -ne 0 ]; then
  "$JOURNAL_SCRIPT" "blocker" "auto-dev run #$RUN_NUMBER failed (exit $EXIT_CODE, cost $COST)" || true
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
  post_to_discord "$AUTONOMOUS_DEV_WEBHOOK" "**Run #$RUN_NUMBER completed** (Gemini coded, CC reviewed)

${RESULT:0:1800}"

  # Post PR review requests to #manual-merge-approvals (gated on all checks)
  PR_REVIEW=$(echo "$RESULT" | sed -n '/PR_FOR_REVIEW:/,/^$/p' | head -20)
  if [ -n "$PR_REVIEW" ]; then
    # Determine if any phase blocked the PR
    BLOCKED=false
    BLOCK_REASON=""
    if [ "$VERIFY_STATUS" = "fail" ]; then
      BLOCKED=true
      BLOCK_REASON="Build/test verification failed: \`$VERIFY_DETAIL\`"
    elif [ "$CC_REVIEW_STATUS" = "fail" ]; then
      BLOCKED=true
      BLOCK_REASON="CC code review found blocking issues: \`$CC_REVIEW_DETAIL\`"
    elif [ "$ULTRAREVIEW_STATUS" = "fail" ]; then
      BLOCKED=true
      BLOCK_REASON="Cloud ultrareview found blocking issues: \`$ULTRAREVIEW_DETAIL\`"
    elif [ "$PREDEPLOY_STATUS" = "fail" ]; then
      BLOCKED=true
      BLOCK_REASON="Pre-deploy review found blocking issues: \`$PREDEPLOY_DETAIL\`"
    fi

    if [ "$BLOCKED" = true ]; then
      post_to_discord "$AUTONOMOUS_DEV_WEBHOOK" "**Run #$RUN_NUMBER — PR Created but BLOCKED**

$PR_REVIEW

$BLOCK_REASON
PR needs fixes before it can be merged."
    else
      # Build status line with all phases
      STATUS_LINE=""
      [ "$VERIFY_STATUS" = "pass" ] && STATUS_LINE="Build: \`$VERIFY_DETAIL\`"
      [ -n "$CC_REVIEW_DETAIL" ] && STATUS_LINE="$STATUS_LINE | CC Review: \`$CC_REVIEW_STATUS\`"
      [ "$ULTRAREVIEW_STATUS" != "skip" ] && STATUS_LINE="$STATUS_LINE | Ultrareview: \`$ULTRAREVIEW_STATUS\`"
      [ -n "$PREDEPLOY_DETAIL" ] && STATUS_LINE="$STATUS_LINE | Pre-deploy: \`$PREDEPLOY_STATUS\`"

      CONCERNS_NOTE=""
      [ "$CC_REVIEW_STATUS" = "concerns" ] && CONCERNS_NOTE="
CC review note: $CC_REVIEW_DETAIL"
      [ "$ULTRAREVIEW_STATUS" = "concerns" ] && CONCERNS_NOTE="$CONCERNS_NOTE
Ultrareview note: $ULTRAREVIEW_DETAIL"
      [ "$PREDEPLOY_STATUS" = "concerns" ] && CONCERNS_NOTE="$CONCERNS_NOTE
Pre-deploy note: $PREDEPLOY_DETAIL"

      post_to_discord "$AUTONOMOUS_MERGES_WEBHOOK" "**Run #$RUN_NUMBER — PR For Review** (Gemini + CC)

$PR_REVIEW
${STATUS_LINE:+$STATUS_LINE}$CONCERNS_NOTE
React with :white_check_mark: to approve and merge this PR."
    fi
  fi

  # Post scan-only proposals to #manual-merge-approvals if any
  SCAN_PROPOSAL=$(echo "$RESULT" | sed -n '/PROPOSAL:/,/^$/p' | head -20)
  if [ -n "$SCAN_PROPOSAL" ]; then
    post_to_discord "$AUTONOMOUS_MERGES_WEBHOOK" "**Run #$RUN_NUMBER — Proposal (budget-saving mode)**

$SCAN_PROPOSAL

React with :white_check_mark: to approve execution on next run."
  fi

  # Post production proposals to #manual-merge-approvals if any
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

# ── Post-run: trigger overnight summary if this is the morning window ─

SUMMARY_SCRIPT="$SCRIPT_DIR/overnight-summary.sh"
if [ -x "$SUMMARY_SCRIPT" ]; then
  HOUR=$(date +%H)
  # Between 6-8 AM local = end of overnight window, trigger summary
  if [ "$HOUR" -ge 6 ] && [ "$HOUR" -le 8 ]; then
    log "Morning window — triggering overnight summary"
    "$SUMMARY_SCRIPT" &  # fire-and-forget, don't block next run
  fi
fi

# ── Clean up old logs (keep last 50) ─────────────────────────────────

ls -t "$LOGS_DIR"/run-*.log 2>/dev/null | tail -n +51 | xargs rm -f 2>/dev/null || true
