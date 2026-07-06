#!/usr/bin/env bash
set -euo pipefail

# Polls an Odoo instance's login page until it responds or times out.
#
# Usage: healthcheck.sh <url> [max_attempts] [delay_seconds]

URL="${1:?Usage: healthcheck.sh <url> [max_attempts] [delay_seconds]}"
MAX_ATTEMPTS="${2:-30}"
DELAY="${3:-5}"

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  STATUS="$(curl -s -o /dev/null -w '%{http_code}' "$URL" || echo "000")"
  if [ "$STATUS" = "200" ] || [ "$STATUS" = "303" ]; then
    echo "==> Healthy after ${attempt} attempt(s) (HTTP ${STATUS})"
    exit 0
  fi
  echo "==> Attempt ${attempt}/${MAX_ATTEMPTS}: HTTP ${STATUS}, retrying in ${DELAY}s"
  sleep "$DELAY"
done

echo "==> Health check failed after ${MAX_ATTEMPTS} attempts" >&2
exit 1
