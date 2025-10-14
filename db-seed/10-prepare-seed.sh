#!/usr/bin/env sh
# shellcheck shell=sh

# ------------------------------------------------------------
# 10-prepare-seed.sh
# Purpose: Import/Export DB seed in an idempotent way for MariaDB.
#
# Modes:
#   SEED_MODE=auto    (default) import if DB empty & seed exists; else export
#   SEED_MODE=import  import db-seed/seed.sql (or seed.sql.gz) into $MYSQL_DATABASE
#   SEED_MODE=export  export $MYSQL_DATABASE into db-seed/seed.sql (or .gz if SEED_GZIP=true)
#   SEED_MODE=prep    prepare seed files in init directory for MariaDB initialization
#
# Env required (usually from env_file):
#   MYSQL_HOST=db
#   MYSQL_DATABASE=wordpress
#   MYSQL_USER=wpuser
#   MYSQL_PASSWORD=change-me-user
#
# Optional env:
#   SEED_FILE=seed.sql
#   SEED_MODE=auto
#   SEED_GZIP=false           # true -> write/read .gz
#   WAIT_TIMEOUT=120          # seconds to wait for DB readiness
#   VERBOSE=false
#   SEED_STRICT=false         # true -> if seed missing in import mode, just log & exit 0
#   INIT_DIR=/init            # directory for prepared seed files (prep mode)
#   PREP_ONLY=false           # true -> force prep mode regardless of SEED_MODE
#   SEED_AUTO_SELECT=true     # true -> auto-select best seed file when multiple available
#
# TLS/Client flags:
#   MDB_OPTS="--skip-ssl"     # extra flags for mariadb/mariadb-admin (default: --skip-ssl)
#   MDB_DUMP_OPTS=""          # extra flags for mariadb-dump
#
# Tools used: mariadb, mariadb-dump, gzip (optional), sha256sum (optional)
# ------------------------------------------------------------

set -eu

# -------- Defaults --------
MYSQL_HOST="${MYSQL_HOST:-db}"
MYSQL_DATABASE="${MYSQL_DATABASE:-wordpress}"
MYSQL_USER="${MYSQL_USER:-wpuser}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
SEED_FILE="${SEED_FILE:-seed.sql}"
SEED_MODE="${SEED_MODE:-auto}"
SEED_GZIP="${SEED_GZIP:-false}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-120}"
VERBOSE="${VERBOSE:-false}"
SEED_STRICT="${SEED_STRICT:-false}"
INIT_DIR="${INIT_DIR:-/init}"
PREP_ONLY="${PREP_ONLY:-false}"
SEED_AUTO_SELECT="${SEED_AUTO_SELECT:-true}"

# Default client flags (avoid TLS issues with self-signed in local/dev)
MDB_OPTS="${MDB_OPTS:---skip-ssl}"
MDB_DUMP_OPTS="${MDB_DUMP_OPTS:-}"

# If gzip is enabled, normalize file extension
case "$SEED_GZIP" in
  true|TRUE|True|1) SEED_GZIP=true ;;
  *)                SEED_GZIP=false ;;
esac
[ "$SEED_GZIP" = true ] && SEED_FILE="${SEED_FILE%.gz}.gz"

# -------- Helpers --------
ts() { date '+%Y-%m-%d %H:%M:%S'; }
log() { printf '%s %s\n' "$(ts)" "$*" >&2; }
vlog() { [ "$VERBOSE" = true ] && log "$@" || true; }

fail() { log "❌ $*"; exit 1; }

need_bin() { command -v "$1" >/dev/null 2>&1 || fail "Required binary not found: $1"; }

# -------- Seed file detection --------
detect_seed_files() {
  # Find all available seed files
  local sql_files=""
  local gz_files=""
  
  # Look for .sql files
  for file in *.sql; do
    [ -f "$file" ] && [ "$file" != "*.sql" ] && sql_files="$sql_files $file"
  done
  
  # Look for .sql.gz files
  for file in *.sql.gz; do
    [ -f "$file" ] && [ "$file" != "*.sql.gz" ] && gz_files="$gz_files $file"
  done
  
  echo "SQL_FILES=$sql_files"
  echo "GZ_FILES=$gz_files"
}

select_seed_file() {
  local sql_files="$1"
  local gz_files="$2"
  local selected_file=""
  
  # Count available files
  local sql_count=$(echo "$sql_files" | wc -w)
  local gz_count=$(echo "$gz_files" | wc -w)
  local total_count=$((sql_count + gz_count))
  
  if [ "$total_count" -eq 0 ]; then
    log "ℹ️ No seed files found"
    return 1
  elif [ "$total_count" -eq 1 ]; then
    # Only one file available, use it automatically
    if [ "$sql_count" -eq 1 ]; then
      selected_file=$(echo "$sql_files" | awk '{print $1}')
    else
      selected_file=$(echo "$gz_files" | awk '{print $1}')
    fi
    log "✅ Auto-selected seed file: $selected_file"
  else
    # Multiple files available, show selection
    log "📋 Multiple seed files found:"
    local counter=1
    
    # Show SQL files
    for file in $sql_files; do
      local size=$(du -h "$file" 2>/dev/null | cut -f1)
      log "  [$counter] $file ($size)"
      counter=$((counter + 1))
    done
    
    # Show GZ files
    for file in $gz_files; do
      local size=$(du -h "$file" 2>/dev/null | cut -f1)
      log "  [$counter] $file ($size)"
      counter=$((counter + 1))
    done
    
    # Auto-select based on preferences
    # 1. Prefer real files over symlinks
    # 2. Prefer .sql over .sql.gz
    # 3. Prefer newer files
    
    # First, try to find real files (not symlinks)
    local real_sql_files=""
    local real_gz_files=""
    
    for file in $sql_files; do
      if [ -f "$file" ] && [ ! -L "$file" ]; then
        real_sql_files="$real_sql_files $file"
      fi
    done
    
    for file in $gz_files; do
      if [ -f "$file" ] && [ ! -L "$file" ]; then
        real_gz_files="$real_gz_files $file"
      fi
    done
    
    if [ -n "$real_sql_files" ]; then
      # Use the first real SQL file
      selected_file=$(echo "$real_sql_files" | awk '{print $1}')
      log "✅ Auto-selected: $selected_file (real SQL file)"
    elif [ -n "$real_gz_files" ]; then
      # Use the first real GZ file
      selected_file=$(echo "$real_gz_files" | awk '{print $1}')
      log "✅ Auto-selected: $selected_file (real GZ file)"
    elif echo "$sql_files" | grep -q "seed_latest.sql"; then
      selected_file="seed_latest.sql"
      log "✅ Auto-selected: seed_latest.sql (symlink, preferred)"
    elif echo "$gz_files" | grep -q "seed_latest.sql.gz"; then
      selected_file="seed_latest.sql.gz"
      log "✅ Auto-selected: seed_latest.sql.gz (symlink, preferred)"
    elif [ "$sql_count" -gt 0 ]; then
      # Use the first SQL file
      selected_file=$(echo "$sql_files" | awk '{print $1}')
      log "✅ Auto-selected: $selected_file (first SQL file)"
    else
      # Use the first GZ file
      selected_file=$(echo "$gz_files" | awk '{print $1}')
      log "✅ Auto-selected: $selected_file (first GZ file)"
    fi
  fi
  
  echo "$selected_file"
}

# Use MYSQL_PWD to avoid leaking password in argv / ps
query() {
  # $1 = SQL
  MYSQL_PWD="$MYSQL_PASSWORD" mariadb $MDB_OPTS -h "$MYSQL_HOST" -u "$MYSQL_USER" -N -B -e "$1"
}

exec_sql_file() {
  # $1 = file (.sql or .sql.gz)
  f="$1"
  if [ ! -s "$f" ]; then
    fail "Seed file not found or empty: $f"
  fi
  if [ "${f##*.}" = "gz" ]; then
    need_bin gzip
    log "📥 Importing (gzip) $f into '$MYSQL_DATABASE'…"
    MYSQL_PWD="$MYSQL_PASSWORD" gzip -dc "$f" | mariadb $MDB_OPTS -h "$MYSQL_HOST" -u "$MYSQL_USER" "$MYSQL_DATABASE"
  else
    log "📥 Importing $f into '$MYSQL_DATABASE'…"
    MYSQL_PWD="$MYSQL_PASSWORD" mariadb $MDB_OPTS -h "$MYSQL_HOST" -u "$MYSQL_USER" "$MYSQL_DATABASE" < "$f"
  fi
}

dump_to_file() {
  # $1 = file (.sql or .sql.gz)
  f="$1"
  dir="$(dirname "$f")"
  tmp="${f}.tmp"
  mkdir -p "$dir"
  if [ "${f##*.}" = "gz" ]; then
    need_bin gzip
    log "📤 Exporting '$MYSQL_DATABASE' to (gzip) $f…"
    MYSQL_PWD="$MYSQL_PASSWORD" mariadb-dump $MDB_DUMP_OPTS \
      -h "$MYSQL_HOST" -u "$MYSQL_USER" \
      --single-transaction --routines --triggers --events \
      "$MYSQL_DATABASE" | gzip -c > "$tmp"
  else
    log "📤 Exporting '$MYSQL_DATABASE' to $f…"
    MYSQL_PWD="$MYSQL_PASSWORD" mariadb-dump $MDB_DUMP_OPTS \
      -h "$MYSQL_HOST" -u "$MYSQL_USER" \
      --single-transaction --routines --triggers --events \
      "$MYSQL_DATABASE" > "$tmp"
  fi
  mv "$tmp" "$f"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" > "${f}.sha256"
  fi
  log "✅ Export completed."
}

db_ready() {
  # returns 0 when DB accepts auth'ed queries
  MYSQL_PWD="$MYSQL_PASSWORD" mariadb $MDB_OPTS -h "$MYSQL_HOST" -u "$MYSQL_USER" -e 'SELECT 1;' >/dev/null 2>&1
}

wait_for_db() {
  log "Waiting for database @ ${MYSQL_HOST} (timeout: ${WAIT_TIMEOUT}s)…"
  start="$(date +%s)"
  while ! db_ready; do
    now="$(date +%s)"
    [ $((now - start)) -ge "$WAIT_TIMEOUT" ] && fail "DB not ready after ${WAIT_TIMEOUT}s"
    sleep 3
    vlog "…still waiting"
  done
  log "✅ Database is ready."
}

db_table_count() {
  query "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${MYSQL_DATABASE}';"
}

db_is_empty() {
  cnt="$(db_table_count || echo 0)"
  [ "${cnt:-0}" -eq 0 ]
}

seed_exists() { 
  if [ -s "$SEED_FILE" ]; then
    return 0
  else
    # Try to find alternative seed files
    local seed_files=$(detect_seed_files)
    local sql_files=$(echo "$seed_files" | grep "SQL_FILES=" | cut -d'=' -f2)
    local gz_files=$(echo "$seed_files" | grep "GZ_FILES=" | cut -d'=' -f2)
    
    if [ -n "$sql_files" ] || [ -n "$gz_files" ]; then
      log "🔍 Found alternative seed files, auto-selecting..."
      # select_seed_file outputs logs to stderr, result to stdout
      local selected=$(select_seed_file "$sql_files" "$gz_files")
      selected=$(echo "$selected" | xargs)  # trim whitespace
      if [ -n "$selected" ] && [ -s "$selected" ]; then
        SEED_FILE="$selected"
        log "✅ Using seed file: $SEED_FILE"
        return 0
      else
        vlog "DEBUG: selected='$selected', not found or empty"
      fi
    fi
    return 1
  fi
}

# -------- Volume verification --------
verify_db_volume() {
  # Check if database volume exists and is accessible
  if ! docker volume inspect "${COMPOSE_PROJECT_NAME:-english_blog}_db_data" >/dev/null 2>&1; then
    log "⚠️  Database volume not found. Creating it..."
    docker volume create "${COMPOSE_PROJECT_NAME:-english_blog}_db_data" >/dev/null 2>&1 || true
  fi
  log "✅ Database volume verified"
}

# -------- Data persistence check --------
check_data_persistence() {
  # Check if persistent data already exists in the data directory
  if [ -d "/var/lib/mysql" ] && [ "$(ls -A /var/lib/mysql 2>/dev/null)" ]; then
    log "✅ Persistent data found - DB already initialized"
    return 0
  else
    log "🆕 No persistent data - DB needs initialization"
    return 1
  fi
}

# -------- Check pre-init status --------
check_pre_init_status() {
  # Check pre-init status if available
  if docker exec db_pre_init cat /tmp/db_status 2>/dev/null | grep -q "PERSISTENT_DATA=true"; then
    log "✅ Pre-init detected persistent data"
    return 0
  else
    log "🆕 Pre-init did not detect persistent data"
    return 1
  fi
}

# -------- Check if seed is needed --------
check_seed_needed() {
  # Check if seed is needed based on pre-init status file
  if [ -f "/db-seed/.seed_status" ] && grep -q "SEED_NEEDED=true" /db-seed/.seed_status; then
    log "🌱 Pre-init determined seed is needed"
    return 0
  else
    log "ℹ️ Pre-init determined seed is not needed"
    return 1
  fi
}

# -------- Main --------
log "Seed runner starting (mode=${SEED_MODE}, gzip=${SEED_GZIP}, file=${SEED_FILE}, strict=${SEED_STRICT})"

# Verify database volume first
verify_db_volume

# If PREP_ONLY is true, only run prep mode
if [ "$(echo "$PREP_ONLY" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
  SEED_MODE="prep"
fi

# Only require database tools for non-prep modes
if [ "$SEED_MODE" != "prep" ]; then
  need_bin mariadb
  need_bin mariadb-dump
  [ "$SEED_GZIP" = true ] && need_bin gzip || true

  # Basic sanity
  [ -n "$MYSQL_PASSWORD" ] || fail "MYSQL_PASSWORD is empty"
  [ -n "$MYSQL_DATABASE" ] || fail "MYSQL_DATABASE is empty"

  wait_for_db
fi

case "$(echo "$SEED_MODE" | tr '[:upper:]' '[:lower:]')" in
  prep)
    mkdir -p "$INIT_DIR"
    rm -f "$INIT_DIR"/* "$INIT_DIR/.ready" 2>/dev/null || true
    
    # Show available seed files
    log "🔍 Scanning for available seed files..."
    local seed_files=$(detect_seed_files)
    local sql_files=$(echo "$seed_files" | grep "SQL_FILES=" | cut -d'=' -f2)
    local gz_files=$(echo "$seed_files" | grep "GZ_FILES=" | cut -d'=' -f2)
    
    if [ -n "$sql_files" ] || [ -n "$gz_files" ]; then
      log "📋 Available seed files:"
      for file in $sql_files $gz_files; do
        if [ -f "$file" ]; then
          local size=$(du -h "$file" 2>/dev/null | cut -f1)
          local date=$(stat -c %y "$file" 2>/dev/null | cut -d' ' -f1)
          log "  📄 $file ($size, modified: $date)"
        fi
      done
      
      # Auto-select the best file
      local selected=$(select_seed_file "$sql_files" "$gz_files")
      if [ -n "$selected" ]; then
        SEED_FILE="$selected"
        log "✅ PREP: Using selected seed file: $SEED_FILE"
        
        if [ "${SEED_FILE##*.}" = "gz" ]; then
          need_bin gzip
          log "📦 PREP: found $SEED_FILE (gz) -> $INIT_DIR/seed.sql"
          gzip -dc "$SEED_FILE" > "$INIT_DIR/seed.sql"
        else
          log "✅ PREP: copying $SEED_FILE -> $INIT_DIR/seed.sql"
          cp "$SEED_FILE" "$INIT_DIR/seed.sql"
        fi
      else
        log "⚠️ PREP: No valid seed file could be selected"
        cat > "$INIT_DIR/00-no-seed.sh" <<'SH'
#!/usr/bin/env sh
echo "ℹ️ MariaDB init: no valid seed file found. Starting with a clean DB."
SH
        chmod +x "$INIT_DIR/00-no-seed.sh"
      fi
    else
      log "ℹ️ PREP: no seed files found -> creating notice script."
      cat > "$INIT_DIR/00-no-seed.sh" <<'SH'
#!/usr/bin/env sh
echo "ℹ️ MariaDB init: no seed found (db-seed/seed.sql or .gz). Starting with a clean DB."
SH
      chmod +x "$INIT_DIR/00-no-seed.sh"
    fi
    touch "$INIT_DIR/.ready"
    log "✅ PREP: init dir ready at $INIT_DIR"
    exit 0
    ;;

  import)
    if ! seed_exists; then
      if [ "$(echo "$SEED_STRICT" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
        log "ℹ️ SEED_MODE=import & SEED_STRICT=true: seed not found at $SEED_FILE → skipped import."
        exit 0
      else
        fail "SEED_MODE=import but seed file not found: $SEED_FILE"
      fi
    fi
    exec_sql_file "$SEED_FILE"
    ;;

  export)
    dump_to_file "$SEED_FILE"
    ;;

  auto)
    # AUTO mode: Intelligent decision based on seed availability and DB state
    # Use cases:
    #   1. First deploy:        no seed + empty DB  → start clean
    #   2. Restore from backup: seed + empty DB     → import seed
    #   3. Maintenance reload:  seed + DB with data → do nothing (DB operational)
    #   4. Already initialized: no seed + DB data   → do nothing
    
    # First check if seed is needed based on pre-init
    if ! check_seed_needed; then
      log "AUTO: Pre-init determined seed is not needed → skipping seed process."
      log "✅ DB already has persistent data, no seed required."
      exit 0
    elif ! seed_exists && db_is_empty; then
      # Use case 1: First deploy
      log "AUTO: First deploy detected (no seed, empty DB)."
      log "✅ Starting with clean database. WordPress will initialize on first access."
      exit 0
    elif seed_exists && db_is_empty; then
      # Use case 2: Restore from backup
      log "AUTO: Restore from backup detected (seed exists, empty DB)."
      log "📥 Importing seed file..."
      exec_sql_file "$SEED_FILE"
    elif seed_exists && ! db_is_empty; then
      # Use case 3: Maintenance reload (container restart with existing data)
      log "AUTO: Maintenance reload detected (seed exists, DB has data)."
      log "✅ Database already operational. No action needed."
      exit 0
    else
      # Use case 4: DB was initialized previously without seed
      log "AUTO: No seed file and DB has data → DB already initialized."
      log "✅ No action needed."
      exit 0
    fi
    ;;

  *)
    fail "Unknown SEED_MODE: $SEED_MODE (use prep|auto|import|export)"
    ;;
esac

log "Done."

