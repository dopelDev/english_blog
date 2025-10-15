#!/bin/bash

# entrypoint.sh - Starts cron scheduler for automated backups
# This script configures and runs the cron daemon to schedule backups

set -e

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /backup/logs/backup.log
}

log "Starting automated backup system..."

# Create necessary directories if they don't exist
mkdir -p /backup/repos
mkdir -p /backup/data
mkdir -p /backup/logs

# Check critical environment variables
if [ -z "$BORG_REPO" ]; then
    log "ERROR: BORG_REPO is not defined"
    exit 1
fi

if [ -z "$DB_HOST" ]; then
    log "ERROR: DB_HOST is not defined"
    exit 1
fi

# Initialize Borg repository if it doesn't exist
if [ ! -d "$BORG_REPO" ]; then
    log "Initializing Borg repository at $BORG_REPO"
    borg init --encryption=repokey "$BORG_REPO" || {
        log "ERROR: Could not initialize Borg repository"
        exit 1
    }
    log "Borg repository initialized successfully"
else
    log "Borg repository already exists at $BORG_REPO"
fi

# Configure crontab permissions
chmod 0644 /etc/cron.d/backup-cron

# Verify crontab is properly formatted
if ! crontab -l >/dev/null 2>&1; then
    log "Installing crontab..."
    crontab /etc/cron.d/backup-cron
fi

# Create log file if it doesn't exist
touch /backup/logs/backup.log

log "Backup system configured successfully"
log "Repository: $BORG_REPO"
log "DB Host: $DB_HOST"
log "Database: $DB_NAME"

# Show cron configuration
log "Cron configuration:"
crontab -l | while read line; do
    log "  $line"
done

# Run initial backup if specified
if [ "$RUN_INITIAL_BACKUP" = "true" ]; then
    log "Running initial backup..."
    /usr/local/bin/run_once.sh
fi

log "Starting cron daemon..."

# Try to start cron daemon, if it fails, keep container running with sleep
if ! crond -f -l 2; then
    log "WARNING: Cron daemon failed to start, running in sleep mode"
    log "Backup system is ready but cron scheduling is disabled"
    log "Manual backups can still be triggered with: docker compose exec backup /usr/local/bin/run_once.sh"
    
    # Keep container running
    while true; do
        sleep 3600
    done
fi
