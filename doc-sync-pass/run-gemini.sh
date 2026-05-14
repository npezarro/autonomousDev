#!/usr/bin/env bash
# run-gemini.sh — Shadow Gemini version of doc-sync agent.
# Runs alongside the Claude doc-sync for 7-day comparison.
#
# Differences from run.sh:
#   - Calls gemini instead of claude
#   - Separate lock/state/logs
#   - No Claude usage gate
#   - Branch prefix: gemini/doc-sync-* instead of claude/doc-sync-*
#   - Results logged to comparison JSONL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
PROMPT_TEMPLATE="$SCRIPT_DIR/prompt.md"
LOGS_DIR="$SCRIPT_DIR/logs/gemini"
LOCK_FILE="$SCRIPT_DIR/.running-gemini.lock"
STATE_FILE="$SCRIPT_DIR/gemini-state.json"
CONFIG_FILE="$PARENT_DIR/config.json"
COMPARISON_LOG="$PARENT_DIR/logs/gemini-comparison.jsonl"

export GOOGLE_GENAI_USE_GCA=true
GEMINI_BIN="${GEMINI_BIN:-gemini}"
DRY_RUN="${1:-}"
LOOKBACK_HOURS=6
REPOS_ROOT="$HOME/repos"

# ── Load secrets ────────────────────────────────────────────────────

if [ -f "$HOME/.env" ]; then
  set -a; source "$HOME/.env"; set +a
fi
if [ -f "$PARENT_DIR/.env" ]; then
  set -a; source "$PARENT_DIR/.env"; set +a
fi

LEARNINGS_WEBHOOK="${DISCORD_LEARNINGS_WEBHOOK_URL:-}"

# ── Logging ─────────────────────────────────────────────────────────

mkdir -p "$LOGS_DIR" "$(dirname "$COMPARISON_LOG")"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [gemini] $1" | tee -a "$LOGS_DIR/runner.log"
}

# ── Lock management ─────────────────────────────────────────────────

cleanup() { rm -f "$LOCK_FILE"; }
trap cleanup EXIT

if [ -f "$LOCK_FILE" ]; then
  OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
    log "SKIP: Another Gemini doc-sync run is active (PID $OLD_PID)"
    exit 0
  fi
  rm -f "$LOCK_FILE"
fi

# Check for Claude sibling locks (avoid git conflicts)
for SIBLING_LOCK in "$PARENT_DIR"/*/".running.lock" "$SCRIPT_DIR/.running.lock"; do
  [ -f "$SIBLING_LOCK" ] || continue
  SIBLING_PID=$(cat "$SIBLING_LOCK" 2>/dev/null || echo "")
  if [ -n "$SIBLING_PID" ] && kill -0 "$SIBLING_PID" 2>/dev/null; then
    SIBLING_NAME=$(basename "$(dirname "$SIBLING_LOCK")")
    log "SKIP: Claude agent $SIBLING_NAME is active (PID $SIBLING_PID), avoiding conflict"
    exit 0
  fi
done

echo $$ > "$LOCK_FILE"

# ── State management ────────────────────────────────────────────────

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

GIT_SINCE=$(date -u -d "${LOOKBACK_HOURS} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "")
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

# ── Build prompt (reuse template, swap branch prefix) ───────────────

PROMPT=$(cat "$PROMPT_TEMPLATE")
PROMPT="${PROMPT//\{\{GIT_ACTIVITY\}\}/$GIT_ACTIVITY}"
PROMPT="${PROMPT//\{\{REPOS_ROOT\}\}/$REPOS_ROOT}"
PROMPT="${PROMPT//\{\{DATE\}\}/$(date -u +%Y-%m-%d)}"
PROMPT="${PROMPT//\{\{RUN_NUMBER\}\}/$RUN_NUMBER}"
PROMPT="${PROMPT//\{\{LOOKBACK_HOURS\}\}/$LOOKBACK_HOURS}"

# Swap branch prefix
PROMPT=$(echo "$PROMPT" | sed 's/claude\/doc-sync-/gemini\/doc-sync-/g')

PROMPT="NOTE: You are running as a SHADOW TEST alongside the primary Claude agent. Use branch prefix 'gemini/doc-sync-' instead of 'claude/doc-sync-'. Create branches and PRs as normal but leave them open for comparison.

$PROMPT"

MAX_TIMEOUT=900

log "START: Gemini doc-sync run #$RUN_NUMBER ($ACTIVE_REPOS repos, timeout: ${MAX_TIMEOUT}s)"

if [ "$DRY_RUN" = "--dry-run" ]; then
  log "DRY RUN — prompt:"
  echo "$PROMPT"
  exit 0
fi

# ── Pre-flight: verify Gemini auth ──────────────────────────────────

AUTH_CHECK=$(echo "Say: OK" | "$GEMINI_BIN" --skip-trust -o stream-json -p "" 2>&1)
if echo "$AUTH_CHECK" | grep -qi "error\|auth.*fail\|GOOGLE_GENAI_USE_GCA"; then
  log "SKIP: Gemini auth failed"
  write_state "$(jq -n \
    --argjson num "$RUN_NUMBER" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{run_number: $num, last_run: $ts, last_exit_code: 1, last_error: "auth_failed"}')"
  exit 1
fi

# ── Run Gemini ──────────────────────────────────────────────────────

RUN_LOG="$LOGS_DIR/run-$(date -u +%Y%m%d-%H%M%S).log"
touch "$RUN_LOG" && chmod 600 "$RUN_LOG"
START_TIME=$(date +%s)

timeout "$MAX_TIMEOUT" "$GEMINI_BIN" \
  --skip-trust \
  -y \
  -o stream-json \
  -p "" \
  <<< "$PROMPT" \
  > "$RUN_LOG" 2>&1

EXIT_CODE=$?

END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))

if [ $EXIT_CODE -eq 124 ]; then
  log "TIMEOUT: Gemini doc-sync run #$RUN_NUMBER exceeded ${MAX_TIMEOUT}s"
fi

# ── Extract result ──────────────────────────────────────────────────

RESULT=$(grep '"role":"assistant"' "$RUN_LOG" 2>/dev/null \
  | python3 -c "
import json, sys
parts = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        c = d.get('content', '')
        if c: parts.append(c)
    except: pass
print('\n'.join(parts))
" 2>/dev/null | tail -c 4000 || echo "No result extracted")

STATS=$(grep '"type":"result"' "$RUN_LOG" 2>/dev/null | tail -1 || echo "{}")
TOTAL_TOKENS=$(echo "$STATS" | python3 -c "import json,sys; d=json.loads(sys.stdin.read().strip() or '{}'); print(d.get('stats',{}).get('total_tokens',0))" 2>/dev/null || echo "0")
TOOL_CALLS=$(echo "$STATS" | python3 -c "import json,sys; d=json.loads(sys.stdin.read().strip() or '{}'); print(d.get('stats',{}).get('tool_calls',0))" 2>/dev/null || echo "0")

# ── Parse structured output ─────────────────────────────────────────

REPOS_SCANNED=$(echo "$RESULT" | grep -oP 'REPOS_SCANNED:\s*\K\S+' | head -1 || echo "0")
REPOS_WITH_DRIFT=$(echo "$RESULT" | grep -oP 'REPOS_WITH_DRIFT:\s*\K\S+' | head -1 || echo "0")
UPDATES_MADE=$(echo "$RESULT" | grep -oP 'UPDATES_MADE:\s*\K\S+' | head -1 || echo "0")

# ── Update state ────────────────────────────────────────────────────

write_state "$(jq -n \
  --argjson num "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson exit "$EXIT_CODE" \
  --argjson tokens "$TOTAL_TOKENS" \
  --argjson duration "$DURATION" \
  --argjson scanned "${REPOS_SCANNED:-0}" \
  --argjson drift "${REPOS_WITH_DRIFT:-0}" \
  '{run_number: $num, last_run: $ts, last_exit_code: $exit, total_tokens: $tokens, duration_s: $duration, repos_scanned: $scanned, drift_found: $drift}')"

# ── Log to comparison JSONL ─────────────────────────────────────────

jq -n \
  --arg agent "gemini" \
  --arg component "doc-sync" \
  --argjson run "$RUN_NUMBER" \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson exit_code "$EXIT_CODE" \
  --argjson duration "$DURATION" \
  --argjson tokens "$TOTAL_TOKENS" \
  --argjson tool_calls "$TOOL_CALLS" \
  --argjson repos_scanned "${REPOS_SCANNED:-0}" \
  --argjson drift "${REPOS_WITH_DRIFT:-0}" \
  --argjson updates "${UPDATES_MADE:-0}" \
  --arg result_preview "${RESULT:0:500}" \
  '{agent: $agent, component: $component, run: $run, timestamp: $ts, exit_code: $exit_code, duration_s: $duration, total_tokens: $tokens, tool_calls: $tool_calls, repos_scanned: $repos_scanned, drift_found: $drift, updates_made: $updates, result_preview: $result_preview}' \
  >> "$COMPARISON_LOG" 2>/dev/null || true

# ── Log result ──────────────────────────────────────────────────────

if [ $EXIT_CODE -eq 0 ]; then
  log "DONE: Gemini doc-sync #$RUN_NUMBER — scanned $REPOS_SCANNED repos, $REPOS_WITH_DRIFT with drift, tokens=$TOTAL_TOKENS, ${DURATION}s"
else
  log "FAIL: Gemini doc-sync #$RUN_NUMBER exited with code $EXIT_CODE"
fi

# ── Clean up old logs ───────────────────────────────────────────────

ls -t "$LOGS_DIR"/run-*.log 2>/dev/null | tail -n +31 | xargs rm -f 2>/dev/null || true
