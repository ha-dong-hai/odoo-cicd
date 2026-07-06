#!/usr/bin/env bash
set -euo pipefail

# Drops an environment's database, then restores it and its filestore
# from a given backup directory produced by backup.sh. Shared by
# restore_to_staging.sh (restore prod's latest backup into staging) and
# deploy.sh's production rollback path (restore the pre-deploy snapshot
# if a failed module update touched the database).
#
# Usage: restore_from_backup.sh <environment> <backup_dir>

ENVIRONMENT="${1:?Usage: restore_from_backup.sh <environment> <backup_dir>}"
BACKUP_DIR="${2:?Usage: restore_from_backup.sh <environment> <backup_dir>}"
DB_CONTAINER="${ENVIRONMENT}-db"
FILESTORE_VOLUME="${ENVIRONMENT}-odoo-data"
DB_NAME="${DB_NAME:-odoo}"
DB_USER="${DB_USER:-odoo}"

if [ ! -f "${BACKUP_DIR}/db.dump" ]; then
  echo "No db.dump found in ${BACKUP_DIR}" >&2
  exit 1
fi

echo "==> Restoring ${ENVIRONMENT} from ${BACKUP_DIR}"

docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${DB_NAME}';"
docker exec "$DB_CONTAINER" dropdb -U "$DB_USER" --if-exists "$DB_NAME"
docker exec "$DB_CONTAINER" createdb -U "$DB_USER" -O "$DB_USER" "$DB_NAME"
docker exec -i "$DB_CONTAINER" pg_restore -U "$DB_USER" -d "$DB_NAME" --no-owner < "${BACKUP_DIR}/db.dump"

if [ -f "${BACKUP_DIR}/filestore.tar.gz" ]; then
  docker run --rm \
    -v "${FILESTORE_VOLUME}:/data" \
    -v "${BACKUP_DIR}:/backup:ro" \
    alpine sh -c "rm -rf /data/* && tar -xzf /backup/filestore.tar.gz -C /data"
fi

echo "==> ${ENVIRONMENT} restored from $(basename "$BACKUP_DIR")"
