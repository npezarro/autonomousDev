#!/usr/bin/env bash
# score-interactive.sh — Score an interactive Claude Code session.
#
# Grabs recent cli-interactions from Discord and scores the latest session.
# Can also accept a session summary file.
#
# Usage:
#   ./score-interactive.sh                     # Score latest from Discord
#   ./score-interactive.sh --file <path>       # Score from a file
#   ./score-interactive.sh --text "summary"    # Score from inline text
#
# Integrates with session wrapup: call after posting to #cli-interactions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCORE_SCRIPT="$SCRIPT_DIR/score.sh"

FILE=""
TEXT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    --text) TEXT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -n "$FILE" ]; then
  exec "$SCORE_SCRIPT" --agent-type interactive --session-data "$FILE"
elif [ -n "$TEXT" ]; then
  TMPFILE=$(mktemp)
  echo "$TEXT" > "$TMPFILE"
  "$SCORE_SCRIPT" --agent-type interactive --session-data "$TMPFILE"
  rm -f "$TMPFILE"
else
  exec "$SCORE_SCRIPT" --agent-type interactive --from-discord
fi
