#!/usr/bin/env bash
set -euo pipefail

# Neutralizes a database copy so it behaves like an Odoo.sh staging
# build: no real emails, no cron side effects, no live payments/shipping.
#
# Usage: neutralize.sh <environment>   (e.g. staging)
#
# Note: table/column names below match a stock Odoo 19.0 Community
# install. If your database has customizations to mail/cron/payment
# models, or you're on a different version, double-check these before
# relying on them.

ENVIRONMENT="${1:?Usage: neutralize.sh <environment>}"
DB_CONTAINER="${ENVIRONMENT}-db"
DB_NAME="${DB_NAME:-odoo}"
DB_USER="${DB_USER:-odoo}"

run_sql() {
  docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1
}

echo "==> Disabling outgoing mail servers"
run_sql <<'SQL'
UPDATE ir_mail_server SET active = false;
SQL

echo "==> Disabling scheduled actions (cron jobs)"
run_sql <<'SQL'
UPDATE ir_cron SET active = false;
SQL

echo "==> Putting payment providers into test mode"
run_sql <<'SQL'
UPDATE payment_provider SET state = 'test' WHERE state = 'enabled';
SQL

echo "==> Disabling live shipping connectors"
run_sql <<'SQL'
UPDATE delivery_carrier SET prod_environment = false WHERE prod_environment IS NOT NULL;
SQL

echo "==> ${ENVIRONMENT} database neutralized"
