#!/usr/bin/env sh
# shellcheck shell=sh

# ------------------------------------------------------------
# prep-volumes-only.sh
# Complete prep logic: volume detection + volume snapshots only
# No SQL dumps, only volume snapshots
# ------------------------------------------------------------

set -eu

# Default paths and variables
DB_VOLUME_PATH="${DB_VOLUME_PATH:-/check_db_data}"
WP_VOLUME_PATH="${WP_VOLUME_PATH:-/check_wp_data}"
STATUS_FILE="${STATUS_FILE:-/tmp/prep_status}"
BORG_REPO="${BORG_REPO:-/backup/repos/backup-repo}"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

log "🔍 Prep: Starting volume-only prep process..."

# ========================================
# STEP 1: Volume Detection
# ========================================

log "📋 Step 1: Checking persistent volumes..."

# Check if DB volume has data
DB_HAS_DATA=false
if [ -d "$DB_VOLUME_PATH/mysql" ] && [ "$(ls -A "$DB_VOLUME_PATH/mysql" 2>/dev/null)" ]; then
    log "✅ DB volume has persistent data"
    DB_HAS_DATA=true
else
    log "🆕 DB volume is empty"
fi

# Check if WP volume has data
WP_HAS_DATA=false
if [ -d "$WP_VOLUME_PATH" ] && [ "$(ls -A "$WP_VOLUME_PATH" 2>/dev/null)" ]; then
    log "✅ WP volume has persistent data"
    WP_HAS_DATA=true
else
    log "🆕 WP volume is empty"
fi

# ========================================
# STEP 2: Determine Action
# ========================================

log "📋 Step 2: Determining action based on volume status..."

if [ "$DB_HAS_DATA" = true ] && [ "$WP_HAS_DATA" = true ]; then
    log "✅ Both volumes have data - maintenance restart detected"
    echo "MAINTENANCE_RESTART=true" > "$STATUS_FILE"
    echo "RESTORE_NEEDED=false" >> "$STATUS_FILE"
    echo "MANUAL_BACKUP_NEEDED=true" >> "$STATUS_FILE"
    echo "DB_HAS_DATA=true" >> "$STATUS_FILE"
    echo "WP_HAS_DATA=true" >> "$STATUS_FILE"
    ACTION="manual_backup"
elif [ "$DB_HAS_DATA" = false ] && [ "$WP_HAS_DATA" = false ]; then
    log "🆕 Both volumes empty - checking for backup snapshots"
    echo "MAINTENANCE_RESTART=false" > "$STATUS_FILE"
    echo "RESTORE_NEEDED=true" >> "$STATUS_FILE"
    echo "MANUAL_BACKUP_NEEDED=false" >> "$STATUS_FILE"
    echo "DB_HAS_DATA=false" >> "$STATUS_FILE"
    echo "WP_HAS_DATA=false" >> "$STATUS_FILE"
    ACTION="restore"
else
    log "⚠️ Partial data found - checking for backup snapshots"
    echo "MAINTENANCE_RESTART=false" > "$STATUS_FILE"
    echo "RESTORE_NEEDED=true" >> "$STATUS_FILE"
    echo "MANUAL_BACKUP_NEEDED=false" >> "$STATUS_FILE"
    echo "DB_HAS_DATA=$DB_HAS_DATA" >> "$STATUS_FILE"
    echo "WP_HAS_DATA=$WP_HAS_DATA" >> "$STATUS_FILE"
    ACTION="restore"
fi

log "📋 Action determined: $ACTION"

# ========================================
# STEP 3: Execute Action
# ========================================

case "$ACTION" in
    "manual_backup")
        log "📋 Step 3: Creating volume snapshots..."
        
        # Create timestamp for snapshots
        BACKUP_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
        
        # Create DB volume snapshot
        log "📦 Creating DB volume snapshot..."
        DB_SNAPSHOT_NAME="db_volume_${BACKUP_TIMESTAMP}"
        if borg create \
            --stats \
            --progress \
            --compression lz4 \
            "$BORG_REPO::$DB_SNAPSHOT_NAME" \
            "$DB_VOLUME_PATH/"; then
            
            log "✅ DB volume snapshot created: $DB_SNAPSHOT_NAME"
        else
            log "❌ DB volume snapshot creation failed"
            exit 1
        fi
        
        # Create WP volume snapshot
        log "📦 Creating WP volume snapshot..."
        WP_SNAPSHOT_NAME="wp_volume_${BACKUP_TIMESTAMP}"
        if borg create \
            --stats \
            --progress \
            --compression lz4 \
            "$BORG_REPO::$WP_SNAPSHOT_NAME" \
            "$WP_VOLUME_PATH/"; then
            
            log "✅ WP volume snapshot created: $WP_SNAPSHOT_NAME"
        else
            log "❌ WP volume snapshot creation failed"
            exit 1
        fi
        
        log "✅ Volume snapshots completed successfully"
        ;;
        
    "restore")
        log "📋 Step 3: Restoring from volume snapshots..."
        
        # List available snapshots
        log "📋 Available snapshots:"
        borg list "$BORG_REPO" || log "No snapshots found"
        
        # Find latest paired snapshots (DB + WP volumes)
        LATEST_DB=$(borg list "$BORG_REPO" | grep "db_volume_" | tail -1 | awk '{print $1}')
        LATEST_WP=$(borg list "$BORG_REPO" | grep "wp_volume_" | tail -1 | awk '{print $1}')
        
        if [ -n "$LATEST_DB" ] && [ -n "$LATEST_WP" ]; then
            log "✅ Found paired volume snapshots: $LATEST_DB and $LATEST_WP"
            log "🔄 Restoring from volume snapshots..."
            
            # Restore DB volume
            log "📥 Restoring DB volume..."
            if borg extract "$BORG_REPO::$LATEST_DB"; then
                log "✅ DB volume restored from $LATEST_DB"
            else
                log "⚠️ DB volume restore failed"
            fi
            
            # Restore WP volume
            log "📥 Restoring WP volume..."
            if borg extract "$BORG_REPO::$LATEST_WP"; then
                log "✅ WP volume restored from $LATEST_WP"
            else
                log "⚠️ WP volume restore failed"
            fi
            
            log "✅ Volume restore completed successfully"
        else
            log "ℹ️ No paired volume snapshots found - proceeding with fresh install"
            log "  Available DB volume snapshots: $(borg list "$BORG_REPO" | grep "db_volume_" | wc -l)"
            log "  Available WP volume snapshots: $(borg list "$BORG_REPO" | grep "wp_volume_" | wc -l)"
        fi
        ;;
esac

log "✅ Prep process completed successfully"
exit 0
