#!/usr/bin/env bash
set -euo pipefail

# Refreshes staging with the most recent production backup - the same
# "staging = fresh duplicate of production" model Odoo.sh uses for every
# staging build. Run neutralize.sh right after this to disable outgoing
# mail, cron, and live payments on the copy.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LATEST="$("$DIR/latest_backup.sh" production)"

if [ -z "$LATEST" ]; then
  echo "No production backup available to restore into staging yet" >&2
  exit 1
fi

bash "$DIR/restore_from_backup.sh" staging "$LATEST"
