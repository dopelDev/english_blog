#!/bin/bash

# run_once.sh - Executes volume-based backup using Borg snapshots
# This script performs complete volume snapshots using Borg

set -e

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /backup/logs/backup.log
}

log "=== Starting volume-based backup ==="

# Check environment variables
if [ -z "$BORG_REPO" ]; then
    log "ERROR: BORG_REPO is not defined"
    exit 1
fi

# Initialize Borg repo if it doesn't exist
if ! borg info "$BORG_REPO" >/dev/null 2>&1; then
    log "Initializing Borg repository at $BORG_REPO"
    borg init --encryption=repokey "$BORG_REPO" || {
        log "ERROR: Could not initialize Borg repository"
        exit 1
    }
    log "Borg repository initialized successfully"
else
    log "Borg repository already exists at $BORG_REPO"
fi

BACKUP_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# 1. Create Borg snapshot for DB volume
log "Creating Borg snapshot for DB volume: /var/lib/mysql"
DB_SNAPSHOT_NAME="db_volume_backup_${BACKUP_TIMESTAMP}"
if borg create \
    --stats \
    --progress \
    --compression lz4 \
    "$BORG_REPO::$DB_SNAPSHOT_NAME" \
    "/var/lib/mysql"; then
    log "DB volume snapshot created successfully: $DB_SNAPSHOT_NAME"
else
    log "ERROR: DB volume snapshot creation failed"
    exit 1
fi

# 2. Create Borg snapshot for WP volume
log "Creating Borg snapshot for WP volume: /var/www/html"
WP_SNAPSHOT_NAME="wp_volume_backup_${BACKUP_TIMESTAMP}"
if borg create \
    --stats \
    --progress \
    --compression lz4 \
    "$BORG_REPO::$WP_SNAPSHOT_NAME" \
    "/var/www/html"; then
    log "WP volume snapshot created successfully: $WP_SNAPSHOT_NAME"
else
    log "ERROR: WP volume snapshot creation failed"
    exit 1
fi

# 3. Apply retention policies
log "Applying retention policies..."

# DB volume backups retention
if [ -n "$BACKUP_RETENTION_DAILY" ] && [ "$BACKUP_RETENTION_DAILY" -gt 0 ]; then
    log "Cleaning up DB volume backups (keeping last $BACKUP_RETENTION_DAILY days)"
    borg prune \
        --list \
        --prefix "db_volume_backup_" \
        --keep-daily="$BACKUP_RETENTION_DAILY" \
        "$BORG_REPO" || log "WARNING: DB volume backup cleanup failed"
fi

# WP volume backups retention
if [ -n "$BACKUP_RETENTION_DAILY" ] && [ "$BACKUP_RETENTION_DAILY" -gt 0 ]; then
    log "Cleaning up WP volume backups (keeping last $BACKUP_RETENTION_DAILY days)"
    borg prune \
        --list \
        --prefix "wp_volume_backup_" \
        --keep-daily="$BACKUP_RETENTION_DAILY" \
        "$BORG_REPO" || log "WARNING: WP volume backup cleanup failed"
fi

# Weekly retention
if [ -n "$BACKUP_RETENTION_WEEKLY" ] && [ "$BACKUP_RETENTION_WEEKLY" -gt 0 ]; then
    log "Applying weekly retention (keeping last $BACKUP_RETENTION_WEEKLY weeks)"
    borg prune \
        --list \
        --keep-weekly="$BACKUP_RETENTION_WEEKLY" \
        "$BORG_REPO" || log "WARNING: Weekly retention cleanup failed"
fi

# Monthly retention
if [ -n "$BACKUP_RETENTION_MONTHLY" ] && [ "$BACKUP_RETENTION_MONTHLY" -gt 0 ]; then
    log "Applying monthly retention (keeping last $BACKUP_RETENTION_MONTHLY months)"
    borg prune \
        --list \
        --keep-monthly="$BACKUP_RETENTION_MONTHLY" \
        "$BORG_REPO" || log "WARNING: Monthly retention cleanup failed"
fi

# 4. Show repository statistics
log "=== Repository statistics ==="
borg info "$BORG_REPO" | while read line; do
    log "  $line"
done

log "=== Snapshot list ==="
borg list "$BORG_REPO" | while read line; do
    log "  $line"
done

log "=== Volume backup completed successfully ==="
log "DB volume snapshot: $DB_SNAPSHOT_NAME"
log "WP volume snapshot: $WP_SNAPSHOT_NAME"
log "Repository: $BORG_REPO"