#!/usr/bin/env bash
set -euo pipefail

# Deploys a new Odoo image to staging or production and rolls back
# automatically if the new container fails its health check - the same
# safety net documented for Odoo.sh's own builds: a failing build never
# goes live, and the previous one keeps serving traffic untouched.
#
# Usage: deploy.sh <staging|production>
# Reads from the environment:
#   IMAGE            required - image tag to deploy (built locally by the
#                     self-hosted runner, no registry needed)
#   UPDATE_MODULES   optional, production only - comma-separated module
#                     names to update, from detect_module_updates.sh
#   DATA_ROOT        optional, defaults to /opt/odoo-cicd-data
#
# Run from the git checkout (e.g. a self-hosted runner's workspace) - this
# script only reads compose files relative to its own working directory.
# Anything that must survive across checkouts (.env files, backups,
# which color is active, Traefik's routing file) lives under DATA_ROOT
# instead, since actions/checkout resets untracked files in the workspace
# on every run.

ENVIRONMENT="${1:?Usage: deploy.sh <staging|production>}"
DATA_ROOT="${DATA_ROOT:-/opt/odoo-cicd-data}"

DB_NAME="${DB_NAME:-odoo}"
DB_USER="${DB_USER:-odoo}"

case "$ENVIRONMENT" in

staging)
  IMAGE="${IMAGE:?IMAGE env var is required for staging}"
  ENV_FILE="${DATA_ROOT}/.env.staging"
  COMPOSE="docker compose -f docker-compose.staging.yml --env-file ${ENV_FILE}"
  PREVIOUS_IMAGE="$(grep -E '^IMAGE=' "$ENV_FILE" | cut -d= -f2- || true)"

  sed -i "s#^IMAGE=.*#IMAGE=${IMAGE}#" "$ENV_FILE"
  $COMPOSE up -d odoo

  if bash scripts/healthcheck.sh "http://127.0.0.1:8080/web/login"; then
    echo "==> staging healthy on ${IMAGE}"
    exit 0
  fi

  echo "==> staging unhealthy, rolling back to ${PREVIOUS_IMAGE:-<none>}" >&2
  if [ -n "$PREVIOUS_IMAGE" ]; then
    sed -i "s#^IMAGE=.*#IMAGE=${PREVIOUS_IMAGE}#" "$ENV_FILE"
    $COMPOSE up -d odoo
  fi
  exit 1
  ;;

production)
  IMAGE="${IMAGE:?IMAGE env var is required for production}"
  DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD env var is required for production}"
  ENV_FILE="${DATA_ROOT}/.env.production"
  COMPOSE="docker compose -f docker-compose.prod.yml --env-file ${ENV_FILE}"
  STATE_DIR="${DATA_ROOT}/production"
  STATE_FILE="${STATE_DIR}/.active_color"
  TRAEFIK_DYNAMIC="${DATA_ROOT}/traefik/dynamic/production.yml"
  mkdir -p "$STATE_DIR"

  ACTIVE_COLOR="blue"
  [ -f "$STATE_FILE" ] && ACTIVE_COLOR="$(cat "$STATE_FILE")"
  if [ "$ACTIVE_COLOR" = "blue" ]; then TARGET_COLOR="green"; else TARGET_COLOR="blue"; fi
  TARGET_PORT="8081"; [ "$TARGET_COLOR" = "green" ] && TARGET_PORT="8082"

  echo "==> active=${ACTIVE_COLOR} target=${TARGET_COLOR} image=${IMAGE}"

  TARGET_VAR="IMAGE_$(echo "$TARGET_COLOR" | tr '[:lower:]' '[:upper:]')"
  sed -i "s#^${TARGET_VAR}=.*#${TARGET_VAR}=${IMAGE}#" "$ENV_FILE"

  if [ -n "${UPDATE_MODULES:-}" ]; then
    echo "==> running module update: ${UPDATE_MODULES}"
    if ! $COMPOSE run --rm "odoo-${TARGET_COLOR}" \
          odoo -u "${UPDATE_MODULES}" --stop-after-init \
          --db_host=db --db_user="${DB_USER}" --db_password="${DB_PASSWORD}" -d "${DB_NAME}"; then
      echo "==> module update failed, restoring database from pre-deploy backup" >&2
      LATEST="$(DATA_ROOT="$DATA_ROOT" bash scripts/latest_backup.sh production pre-deploy)"
      [ -n "$LATEST" ] && DATA_ROOT="$DATA_ROOT" bash scripts/restore_from_backup.sh production "$LATEST"
      exit 1
    fi
  fi

  $COMPOSE up -d "odoo-${TARGET_COLOR}"

  if bash scripts/healthcheck.sh "http://127.0.0.1:${TARGET_PORT}/web/login"; then
    echo "==> ${TARGET_COLOR} healthy, cutting traffic over"
    sed -i -E "s#(url: \"http://)[^:]+(:8069\")#\\1production-odoo-${TARGET_COLOR}\\2#" \
      "$TRAEFIK_DYNAMIC"
    echo "$TARGET_COLOR" > "$STATE_FILE"
    $COMPOSE stop "odoo-${ACTIVE_COLOR}"
    echo "==> production is now serving ${IMAGE} (${TARGET_COLOR})"
    exit 0
  fi

  echo "==> ${TARGET_COLOR} failed health check - ${ACTIVE_COLOR} keeps serving traffic" >&2
  $COMPOSE stop "odoo-${TARGET_COLOR}"
  if [ -n "${UPDATE_MODULES:-}" ]; then
    echo "==> restoring database from pre-deploy backup (update may have partially applied)" >&2
    LATEST="$(DATA_ROOT="$DATA_ROOT" bash scripts/latest_backup.sh production pre-deploy)"
    [ -n "$LATEST" ] && DATA_ROOT="$DATA_ROOT" bash scripts/restore_from_backup.sh production "$LATEST"
  fi
  exit 1
  ;;

*)
  echo "Unknown environment: ${ENVIRONMENT} (expected staging or production)" >&2
  exit 1
  ;;

esac
