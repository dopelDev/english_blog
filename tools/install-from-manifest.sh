#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Reinstall and activate plugins from a manifest file.
#
# Default manifest:
#   - manifests/plugins_active.txt
#
# Usage:
#   ./tools/install-from-manifest.sh
#   ./tools/install-from-manifest.sh path/to/other_manifest.txt
#
# Notes:
#   - Installs plugins even if they already exist (with --force).
#   - Activates all plugins listed in the manifest.
# -----------------------------------------------------------------------------
set -euo pipefail

# Default manifest file is plugins_active.txt
MANIFEST="${1:-manifests/plugins_active.txt}"

# Ensure the file exists and is not empty
if [[ ! -s "$MANIFEST" ]]; then
  echo "[tools] Manifest not found or empty: $MANIFEST"
  exit 1
fi

# Install plugins (forcing reinstallation if necessary)
echo "[tools] Installing plugins from $MANIFEST ..."
docker compose run --rm wpcli --path=/var/www/html plugin install $(tr '\n' ' ' < "$MANIFEST") --force

# Activate plugins
echo "[tools] Activating plugins ..."
docker compose run --rm wpcli --path=/var/www/html plugin activate $(tr '\n' ' ' < "$MANIFEST")

echo "[tools] Plugins installed and activated successfully."

