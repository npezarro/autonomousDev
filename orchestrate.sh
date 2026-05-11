#!/usr/bin/env bash
# orchestrate.sh — Pre-flight orchestration: select repo + agent profile(s) via quick LLM call.
# Called by run.sh before spawning the main agent. Uses Haiku for cost efficiency.
#
# Usage: ./orchestrate.sh [options]
#   --repos-file <path>     File containing formatted repo list
#   --context-file <path>   File containing prior context / priority info
#   --feature-run           Enable feature run mode
#   --profiles-dir <path>   Path to agent profiles directory
#   --focus-repo <name>     Override repo selection (orchestrator still picks profiles)
#
# Output: JSON on stdout: {"repo":"name","profiles":["key1"],"strategy":"..."}
# Exit: always 0 (fallback JSON on failure)

set -uo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-claude}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

REPOS_FILE=""
CONTEXT_FILE=""
FEATURE_RUN=false
PROFILES_DIR=""
FOCUS_REPO=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repos-file) REPOS_FILE="$2"; shift 2 ;;
    --context-file) CONTEXT_FILE="$2"; shift 2 ;;
    --feature-run) FEATURE_RUN=true; shift ;;
    --profiles-dir) PROFILES_DIR="$2"; shift 2 ;;
    --focus-repo) FOCUS_REPO="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ── Build compact profile catalog ────────────────────────────────────

PROFILE_LIST=""
if [ -n "$PROFILES_DIR" ] && [ -d "$PROFILES_DIR" ]; then
  for profile_dir in "$PROFILES_DIR"/*/; do
    [ ! -d "$profile_dir" ] && continue
    key=$(basename "$profile_dir")
    [ -f "$profile_dir/profile.md" ] || continue
    expertise=$(grep -A1 "^## Expertise" "$profile_dir/profile.md" 2>/dev/null | tail -1 | head -c 200 || true)
    role=$(grep "^Role:" "$profile_dir/profile.md" 2>/dev/null | head -1 | sed 's/^Role: //' || true)
    [ -n "$expertise" ] && PROFILE_LIST="$PROFILE_LIST- $key ($role): $expertise
"
  done
fi

if [ -z "$PROFILE_LIST" ]; then
  echo '{"repo":"","profiles":[],"strategy":"no profiles found"}'
  exit 0
fi

# ── Build inputs ─────────────────────────────────────────────────────

REPO_LIST=""
[ -n "$REPOS_FILE" ] && [ -f "$REPOS_FILE" ] && REPO_LIST=$(head -c 3000 "$REPOS_FILE")

CONTEXT=""
[ -n "$CONTEXT_FILE" ] && [ -f "$CONTEXT_FILE" ] && CONTEXT=$(head -c 1500 "$CONTEXT_FILE")

RUN_TYPE="MAINTENANCE (prioritize fixes, quality, cleanup)"
[ "$FEATURE_RUN" = true ] && RUN_TYPE="FEATURE (prioritize user-facing improvements, UX, visual polish)"

FOCUS_LINE=""
[ -n "$FOCUS_REPO" ] && FOCUS_LINE="REQUIRED repo: $FOCUS_REPO (must select this repo, just pick profiles)"

# ── Orchestration prompt ─────────────────────────────────────────────

read -r -d '' PROMPT << 'PROMPT_TEMPLATE' || true
You are a task orchestrator for an autonomous coding agent. Pick the best repo and 1-2 agent profiles for the next run.

Repos (with git state):
PROMPT_TEMPLATE

PROMPT="$PROMPT
$REPO_LIST

Recent context (priority items, prior work):
${CONTEXT:-(none)}

Run type: $RUN_TYPE
$FOCUS_LINE

Available agent profiles:
$PROFILE_LIST
Selection rules:
- Pick 1 repo with the highest-impact available work
- Pick 1-2 profiles best suited to that work type:
  - Crash/bug fixes: debugger + domain specialist (backend or frontend)
  - Feature work: frontend or backend + architect if structural changes needed
  - Maintenance/quality/refactor: reviewer or testing
  - Security issues: security + domain specialist
  - Infra/deploy/config: devops
  - Design system alignment: frontend
- strategy: one sentence describing the recommended approach

Respond with ONLY this JSON (no markdown fences, no explanation):
{\"repo\": \"repo-name\", \"profiles\": [\"key1\"], \"strategy\": \"brief approach\"}"

# ── Call LLM ─────────────────────────────────────────────────────────

ORCH_MODEL=$(jq -r '.orchestration_model // "haiku"' "$SCRIPT_DIR/config.json" 2>/dev/null || echo "haiku")

RESULT=$(echo "$PROMPT" | timeout 60 "$CLAUDE_BIN" -p --model "$ORCH_MODEL" 2>/dev/null || echo "")

# ── Parse result ─────────────────────────────────────────────────────

if [ -n "$RESULT" ]; then
  # Direct JSON parse
  if echo "$RESULT" | jq -e '.repo and .profiles and .strategy' >/dev/null 2>&1; then
    echo "$RESULT" | jq -c .
    exit 0
  fi
  # Extract JSON from mixed output
  JSON=$(python3 -c "
import sys, json, re
text = sys.stdin.read()
# Find JSON object containing required fields
for match in re.finditer(r'\{[^{}]*\}', text):
    try:
        obj = json.loads(match.group())
        if 'repo' in obj and 'profiles' in obj and 'strategy' in obj:
            print(json.dumps(obj))
            sys.exit(0)
    except json.JSONDecodeError:
        continue
sys.exit(1)
" <<< "$RESULT" 2>/dev/null || echo "")
  if [ -n "$JSON" ]; then
    echo "$JSON"
    exit 0
  fi
fi

# Fallback: let the agent decide freely
echo '{"repo":"","profiles":[],"strategy":"orchestration unavailable, agent picks freely"}'
exit 0
