#!/usr/bin/env bash
set -euo pipefail

# Dumps the production database and filestore, then applies a retention
# policy - 7 daily / 4 weekly / 3 monthly kept, pre-deploy snapshots kept
# 3 days - the same cadence Odoo.sh documents for its own backups.
#
# Usage: backup.sh <daily|weekly|monthly|pre-deploy>
# Called by cron for the scheduled labels, and by deploy-production.yml
# right before every production deploy with the "pre-deploy" label.
#
# Backups live under DATA_ROOT (default /opt/odoo-cicd-data), not inside
# the git checkout - they must survive independently of whatever commit
# happens to be checked out when this runs.

LABEL="${1:?Usage: backup.sh <daily|weekly|monthly|pre-deploy>}"
ENVIRONMENT="production"
DATA_ROOT="${DATA_ROOT:-/opt/odoo-cicd-data}"
BACKUP_ROOT="${DATA_ROOT}/backups/${ENVIRONMENT}"
DB_CONTAINER="${ENVIRONMENT}-db"
DB_NAME="${DB_NAME:-odoo}"
DB_USER="${DB_USER:-odoo}"
FILESTORE_VOLUME="${ENVIRONMENT}-odoo-data"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
DEST_DIR="${BACKUP_ROOT}/${TIMESTAMP}-${LABEL}"

mkdir -p "$DEST_DIR"

echo "==> Dumping database ${DB_NAME} from ${DB_CONTAINER}"
docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" -Fc "$DB_NAME" > "${DEST_DIR}/db.dump"

echo "==> Archiving filestore volume ${FILESTORE_VOLUME}"
docker run --rm \
  -v "${FILESTORE_VOLUME}:/data:ro" \
  -v "${DEST_DIR}:/backup" \
  alpine sh -c "tar -czf /backup/filestore.tar.gz -C /data ."

echo "==> Backup written to ${DEST_DIR}"

echo "==> Applying retention policy (7 daily / 4 weekly / 3 monthly / pre-deploy kept 3 days)"
find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*-daily"      -mtime +7  -exec rm -rf {} \;
find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*-weekly"     -mtime +28 -exec rm -rf {} \;
find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*-monthly"    -mtime +90 -exec rm -rf {} \;
find "$BACKUP_ROOT" -maxdepth 1 -type d -name "*-pre-deploy" -mtime +3  -exec rm -rf {} \;
