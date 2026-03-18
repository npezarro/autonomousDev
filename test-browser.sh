#!/usr/bin/env bash
# test-browser.sh — Start a local dev server for a project and run browser checks.
#
# Usage: ./test-browser.sh <project-dir> [port]
#
# Starts the project's dev server, waits for it to be ready, then exits
# with the server PID so the caller can run browser tests and kill it.
#
# The autonomous agent calls this to spin up a project before visual testing.

set -euo pipefail

PROJECT_DIR="${1:?Usage: test-browser.sh <project-dir> [port]}"
PORT="${2:-3099}"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "ERROR: Project directory not found: $PROJECT_DIR" >&2
  exit 1
fi

cd "$PROJECT_DIR"

# Detect the dev/start command
if [ -f package.json ]; then
  HAS_DEV=$(node -e "const p=require('./package.json'); console.log(p.scripts?.dev ? 'yes' : 'no')")
  HAS_START=$(node -e "const p=require('./package.json'); console.log(p.scripts?.start ? 'yes' : 'no')")
  HAS_BUILD=$(node -e "const p=require('./package.json'); console.log(p.scripts?.build ? 'yes' : 'no')")
else
  echo "ERROR: No package.json found in $PROJECT_DIR" >&2
  exit 1
fi

# Build first if needed
if [ "$HAS_BUILD" = "yes" ] && [ ! -d ".next" ] && [ ! -d "dist" ]; then
  echo "Building project..."
  npm run build 2>&1 | tail -3
fi

# Start dev server
if [ "$HAS_DEV" = "yes" ]; then
  PORT=$PORT npm run dev &
  SERVER_PID=$!
elif [ "$HAS_START" = "yes" ]; then
  PORT=$PORT npm start &
  SERVER_PID=$!
else
  echo "ERROR: No dev or start script in package.json" >&2
  exit 1
fi

# Wait for server to be ready (up to 30s)
echo "Waiting for server on port $PORT..."
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT" 2>/dev/null | grep -qE '200|301|302'; then
    echo "SERVER_READY PID=$SERVER_PID PORT=$PORT"
    exit 0
  fi
  sleep 1
done

echo "ERROR: Server failed to start within 30s" >&2
kill $SERVER_PID 2>/dev/null || true
exit 1
