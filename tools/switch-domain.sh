#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Safely switch WordPress to a new domain name.
#
# This script:
#   1) Runs wp search-replace across the database to update serialized URLs.
#   2) Updates the 'home' and 'siteurl' options to the new domain.
#
# Usage:
#   ./tools/switch-domain.sh old.example.com new.example.com
#
# Notes:
#   - Requires "wpcli" service running with DB access.
#   - Handles serialized data safely (--precise --recurse-objects).
#   - Skips 'guid' column (best practice).
# -----------------------------------------------------------------------------
set -euo pipefail

OLD="${1:-}"
NEW="${2:-}"

if [[ -z "$OLD" || -z "$NEW" ]]; then
  echo "Usage: $0 old-domain new-domain"
  exit 1
fi

# Replace domain throughout the database
echo "[tools] Replacing domain: $OLD → $NEW"
docker compose run --rm wpcli --path=/var/www/html \
  search-replace "$OLD" "$NEW" --all-tables --precise --recurse-objects --skip-columns=guid

# Update WordPress options explicitly
echo "[tools] Updating siteurl and home ..."
docker compose run --rm wpcli --path=/var/www/html option update home    "https://${NEW}"
docker compose run --rm wpcli --path=/var/www/html option update siteurl "https://${NEW}"

echo "[tools] Domain switched successfully to ${NEW}"

