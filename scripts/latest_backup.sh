#!/usr/bin/env bash
set -euo pipefail

# Prints the path to the most recent backup directory for an environment,
# optionally filtered to one label (e.g. "pre-deploy"). Used by both
# restore_to_staging.sh and deploy.sh's rollback path so the "find the
# right backup" logic lives in exactly one place.
#
# Usage: latest_backup.sh <environment> [label]

ENVIRONMENT="${1:?Usage: latest_backup.sh <environment> [label]}"
LABEL="${2:-}"
DATA_ROOT="${DATA_ROOT:-/opt/odoo-cicd-data}"
ROOT="${DATA_ROOT}/backups/${ENVIRONMENT}"
PATTERN="*"
[ -n "$LABEL" ] && PATTERN="*-${LABEL}"

find "$ROOT" -maxdepth 1 -mindepth 1 -type d -name "$PATTERN" 2>/dev/null | sort | tail -n1
