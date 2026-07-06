#!/bin/bash
set -e

# Render odoo.conf from the template using this container's environment
# variables (ODOO_MASTER_PASSWORD, ODOO_WORKERS), then hand off to the
# official Odoo image's own entrypoint.
envsubst '${ODOO_MASTER_PASSWORD} ${ODOO_WORKERS}' \
  < /etc/odoo/odoo.conf.template > /etc/odoo/odoo.conf

exec /entrypoint.sh "$@"
