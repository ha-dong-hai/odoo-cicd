#!/usr/bin/env bash
set -euo pipefail

# Compares __manifest__.py `version` fields between two git revisions and
# prints a comma-separated list of module names whose version changed.
# This is the same signal Odoo.sh uses to decide whether a merge should
# trigger a module update (and therefore a pre-update backup) - a commit
# that doesn't bump any module version is treated as safe to skip.
#
# Usage: detect_module_updates.sh <old-sha> <new-sha>

OLD_SHA="${1:?Usage: detect_module_updates.sh <old-sha> <new-sha>}"
NEW_SHA="${2:?Usage: detect_module_updates.sh <old-sha> <new-sha>}"

read_version() {
  local sha="$1" manifest="$2"
  git show "${sha}:${manifest}" 2>/dev/null | python3 -c "
import ast, sys
try:
    print(ast.literal_eval(sys.stdin.read()).get('version', ''))
except Exception:
    print('')
"
}

CHANGED=()
while IFS= read -r manifest; do
  [ -z "$manifest" ] && continue
  module_name="$(basename "$(dirname "$manifest")")"
  old_version="$(read_version "$OLD_SHA" "$manifest")"
  new_version="$(read_version "$NEW_SHA" "$manifest")"
  if [ "$old_version" != "$new_version" ]; then
    CHANGED+=("$module_name")
  fi
done < <(git ls-tree -r --name-only "$NEW_SHA" -- addons | grep '__manifest__\.py$' || true)

IFS=,
echo "${CHANGED[*]-}"
