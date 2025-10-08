#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Export WordPress plugin information into local manifest files.
#
# Produces:
#   - manifests/plugins.json          → full plugin list with version and status
#   - manifests/plugins_active.txt    → only the slugs of active plugins
#
# Usage:
#   ./tools/export-plugins.sh
#
# Notes:
#   - Uses WP-CLI via docker compose run (requires "wpcli" service).
#   - Can be run at any time, independent of automated cron exports.
# -----------------------------------------------------------------------------
set -euo pipefail

# Ensure manifests directory exists
mkdir -p manifests

# Export full plugin list as JSON
docker compose run --rm wpcli --path=/var/www/html plugin list --format=json \
  > manifests/plugins.json

# Export only active plugin names into plain text list
docker compose run --rm wpcli --path=/var/www/html plugin list \
  --format=csv --fields=name,status \
  | awk -F, 'NR>1 && $2=="active"{print $1}' > manifests/plugins_active.txt

echo "[tools] Generated: manifests/plugins.json and manifests/plugins_active.txt"

