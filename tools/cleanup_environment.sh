#!/usr/bin/env bash
# ------------------------------------------------------------
# cleanup_environment.sh
# Clean up the current Docker Compose project in this order:
#   1) Stop containers
#   2) Remove containers
#   3) Remove volumes (by default) - includes db_data and wp_data named volumes
#   4) Remove networks (by default)
#   5) Remove bind mount directories (db_data) - requires sudo
#   6) Remove generated SQL seed files
#
# Flags:
#   --volumes    Keep volumes (do not delete them)
#
# Environment:
#   PROJECT_NAME   Optional: project name
#                  Defaults to COMPOSE_PROJECT_NAME or current directory name
#
# Note: This script requires sudo privileges to remove db_data directory
#       (MariaDB files are created with restricted permissions)
# ------------------------------------------------------------
set -euo pipefail

KEEP_VOLUMES=false
if [ "${1:-}" = "--volumes" ]; then
  KEEP_VOLUMES=true
fi

PROJECT_NAME="${PROJECT_NAME:-${COMPOSE_PROJECT_NAME:-$(basename "$(pwd)")}}"

echo "🧹 Cleaning Docker Compose project: ${PROJECT_NAME}"
echo "------------------------------------------------------------"

# === 1) Stop containers ===
echo "➡️  Stopping containers..."
CONTAINERS=$(docker ps -q --filter "label=com.docker.compose.project=${PROJECT_NAME}")
if [ -n "$CONTAINERS" ]; then
  echo "$CONTAINERS" | xargs -r docker stop || true
else
  echo "   No running containers found."
fi

# === 2) Remove containers ===
echo "➡️  Removing containers..."
ALL_CONTAINERS=$(docker ps -aq --filter "label=com.docker.compose.project=${PROJECT_NAME}")
if [ -n "$ALL_CONTAINERS" ]; then
  echo "$ALL_CONTAINERS" | xargs -r docker rm -f || true
else
  echo "   No containers to remove."
fi

# === 3) Remove volumes (unless --volumes flag is set) ===
if [ "$KEEP_VOLUMES" = false ]; then
  echo "➡️  Removing volumes..."
  VOLUMES=$(docker volume ls -q --filter "label=com.docker.compose.project=${PROJECT_NAME}")
  if [ -n "$VOLUMES" ]; then
    echo "$VOLUMES" | xargs -r docker volume rm || true
  else
    echo "   No volumes to remove."
  fi
  
  # Also remove specific named volumes that might not have labels
  echo "   Removing named volumes (db_data, wp_data)..."
  docker volume rm "${PROJECT_NAME}_db_data" 2>/dev/null || true
  docker volume rm "${PROJECT_NAME}_wp_data" 2>/dev/null || true
else
  echo "🔹 Keeping volumes (flag --volumes is active)"
fi

# === 4) Remove networks ===
echo "➡️  Removing networks..."
NETWORKS=$(docker network ls -q --filter "label=com.docker.compose.project=${PROJECT_NAME}")
if [ -n "$NETWORKS" ]; then
  echo "$NETWORKS" | xargs -r docker network rm || true
else
  echo "   No networks to remove."
fi

# === 5) Remove bind mount directories ===
echo "➡️  Removing bind mount directories..."
if [ -d "./db_data" ]; then
  echo "   Removing ./db_data directory (requires sudo)..."
  sudo rm -rf ./db_data || true
  echo "   ✅ ./db_data directory removed."
else
  echo "   No ./db_data directory found."
fi

# === 6) Remove generated SQL seed files ===
echo "➡️  Removing generated SQL seed files..."
SEED_FILES_FOUND=false

# Remove timestamped seed files (pattern: seed_YYYYMMDD_HHMMSS.sql*)
if ls ./db-seed/seed_*.sql* 1> /dev/null 2>&1; then
  echo "   Removing timestamped seed files..."
  rm -f ./db-seed/seed_*.sql* || true
  SEED_FILES_FOUND=true
fi

# Remove latest symlinks
if [ -L "./db-seed/seed_latest.sql" ] || [ -L "./db-seed/seed_latest.sql.gz" ]; then
  echo "   Removing latest symlinks..."
  rm -f ./db-seed/seed_latest.sql* || true
  SEED_FILES_FOUND=true
fi

# Remove any other generated seed files
if ls ./db-seed/*.sql* 1> /dev/null 2>&1; then
  echo "   Removing other SQL files..."
  rm -f ./db-seed/*.sql* || true
  SEED_FILES_FOUND=true
fi

if [ "$SEED_FILES_FOUND" = true ]; then
  echo "   ✅ Generated SQL seed files removed."
else
  echo "   No generated SQL seed files found."
fi

# === 7) Final summary ===
echo "------------------------------------------------------------"
echo "✅ Cleanup completed."
echo "Remaining resources for project '${PROJECT_NAME}':"
echo
echo "Containers:"
docker ps -a --filter "label=com.docker.compose.project=${PROJECT_NAME}" || true
echo
echo "Volumes:"
docker volume ls --filter "label=com.docker.compose.project=${PROJECT_NAME}" || true
echo
echo "Networks:"
docker network ls --filter "label=com.docker.compose.project=${PROJECT_NAME}" || true
echo "------------------------------------------------------------"

