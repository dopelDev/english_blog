#!/usr/bin/env bash
# ------------------------------------------------------------
# generate_seed_dump.sh
# Generate SQL seed dumps from real database
# Creates both uncompressed (.sql) and compressed (.sql.gz) versions
# Requires database connection to generate real data
#
# Usage:
#   ./generate_seed_dump.sh [options]
#
# Options:
#   --database DATABASE    Database name (default: wordpress)
#   --output-dir DIR       Output directory (default: ./db-seed)
#   --filename NAME        Base filename (default: seed)
#   --help                 Show this help message
#
# Requirements:
#   - Docker containers must be running (docker compose up)
#   - Database must be healthy and accessible
#   - Credentials must be correct in env_simple.env
# ------------------------------------------------------------
set -euo pipefail

# Default values
DATABASE="wordpress"
OUTPUT_DIR="./db-seed"
FILENAME="seed"
MYSQL_HOST="localhost"
MYSQL_USER="wpuser"
MYSQL_PASSWORD=""
MYSQL_ROOT_PASSWORD=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --database)
      DATABASE="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --filename)
      FILENAME="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --database DATABASE    Database name (default: wordpress)"
      echo "  --output-dir DIR       Output directory (default: ./db-seed)"
      echo "  --filename NAME        Base filename (default: seed)"
      echo "  --help                 Show this help message"
      echo ""
      echo "Environment variables:"
      echo "  MYSQL_HOST            Database host (default: localhost)"
      echo "  MYSQL_USER            Database user (default: wpuser)"
      echo "  MYSQL_PASSWORD        Database password"
      echo "  MYSQL_ROOT_PASSWORD   Root password"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Load environment variables from env_simple.env if it exists
if [ -f "./env_simple.env" ]; then
  echo "📋 Loading environment from env_simple.env..."
  source ./env_simple.env
fi

# Set database credentials
MYSQL_PASSWORD="${MYSQL_PASSWORD:-change-me-user}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-change-me-root}"

# Detect if running inside Docker or on host
if [ -f "/.dockerenv" ] || [ -n "${DOCKER_CONTAINER:-}" ]; then
  # Running inside Docker container
  DB_HOST="$MYSQL_HOST"
  USE_DOCKER_EXEC=false
  echo "🐳 Running inside Docker container, using host: $DB_HOST"
else
  # Running on host, need to use docker exec to access container
  DB_HOST="localhost"
  USE_DOCKER_EXEC=true
  echo "🖥️  Running on host, using docker exec to access container"
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Generate timestamp for unique filenames
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SQL_FILE="${OUTPUT_DIR}/${FILENAME}_${TIMESTAMP}.sql"
GZ_FILE="${OUTPUT_DIR}/${FILENAME}_${TIMESTAMP}.sql.gz"

echo "🗄️  Generating SQL seed dump from database: ${DATABASE}"
echo "📁 Output directory: ${OUTPUT_DIR}"
echo "📄 SQL file: ${SQL_FILE}"
echo "🗜️  Compressed file: ${GZ_FILE}"
echo "------------------------------------------------------------"

# Check if database exists and is accessible
echo "➡️  Checking database connection..."
if [ "$USE_DOCKER_EXEC" = true ]; then
  # Use docker exec to connect to database inside container using mariadb client
  if ! docker exec db mariadb -h"$DB_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "USE $DATABASE;" 2>/dev/null; then
    CONNECTION_FAILED=true
  else
    CONNECTION_FAILED=false
  fi
else
  # Direct connection (running inside container)
  if ! mariadb -h"$DB_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "USE $DATABASE;" 2>/dev/null; then
    CONNECTION_FAILED=true
  else
    CONNECTION_FAILED=false
  fi
fi

if [ "$CONNECTION_FAILED" = true ]; then
  echo "❌ Cannot connect to database '$DATABASE' or database doesn't exist"
  echo "   Host: $DB_HOST"
  echo "   Port: ${DB_PORT:-3306}"
  echo "   User: $MYSQL_USER"
  echo "   Database: $DATABASE"
  echo ""
  echo "💡 Make sure:"
  echo "   1. Docker containers are running (docker compose up)"
  echo "   2. Database is healthy and accessible"
  echo "   3. Credentials in env_simple.env are correct"
  echo ""
  echo "🔄 Generating sample SQL dump instead..."
  
  # Generate sample SQL dump when database is not accessible
  cat > "$SQL_FILE" << 'EOF'
-- Sample SQL Seed Dump
-- Generated when database connection is not available
-- Database: wordpress
-- Generated: $(date)

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET AUTOCOMMIT = 0;
START TRANSACTION;
SET time_zone = "+00:00";

-- Create database
CREATE DATABASE IF NOT EXISTS `wordpress` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `wordpress`;

-- Create sample tables
CREATE TABLE IF NOT EXISTS `wp_posts` (
  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `post_author` bigint(20) unsigned NOT NULL DEFAULT 0,
  `post_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `post_date_gmt` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `post_content` longtext NOT NULL,
  `post_title` text NOT NULL,
  `post_excerpt` text NOT NULL,
  `post_status` varchar(20) NOT NULL DEFAULT 'publish',
  `comment_status` varchar(20) NOT NULL DEFAULT 'open',
  `ping_status` varchar(20) NOT NULL DEFAULT 'open',
  `post_password` varchar(255) NOT NULL DEFAULT '',
  `post_name` varchar(200) NOT NULL DEFAULT '',
  `to_ping` text NOT NULL,
  `pinged` text NOT NULL,
  `post_modified` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `post_modified_gmt` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `post_content_filtered` longtext NOT NULL,
  `post_parent` bigint(20) unsigned NOT NULL DEFAULT 0,
  `guid` varchar(255) NOT NULL DEFAULT '',
  `menu_order` int(11) NOT NULL DEFAULT 0,
  `post_type` varchar(20) NOT NULL DEFAULT 'post',
  `post_mime_type` varchar(100) NOT NULL DEFAULT '',
  `comment_count` bigint(20) NOT NULL DEFAULT 0,
  PRIMARY KEY (`ID`),
  KEY `post_name` (`post_name`(191)),
  KEY `type_status_date` (`post_type`,`post_status`,`post_date`,`ID`),
  KEY `post_parent` (`post_parent`),
  KEY `post_author` (`post_author`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `wp_users` (
  `ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_login` varchar(60) NOT NULL DEFAULT '',
  `user_pass` varchar(255) NOT NULL DEFAULT '',
  `user_nicename` varchar(50) NOT NULL DEFAULT '',
  `user_email` varchar(100) NOT NULL DEFAULT '',
  `user_url` varchar(100) NOT NULL DEFAULT '',
  `user_registered` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `user_activation_key` varchar(255) NOT NULL DEFAULT '',
  `user_status` int(11) NOT NULL DEFAULT 0,
  `display_name` varchar(250) NOT NULL DEFAULT '',
  PRIMARY KEY (`ID`),
  KEY `user_login_key` (`user_login`),
  KEY `user_nicename` (`user_nicename`),
  KEY `user_email` (`user_email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Insert sample data
INSERT INTO `wp_users` (`ID`, `user_login`, `user_pass`, `user_nicename`, `user_email`, `user_url`, `user_registered`, `user_activation_key`, `user_status`, `display_name`) VALUES
(1, 'admin', '$P$B55D6LjfHDkINU5wF.v2BuuzO0/XPk/', 'admin', 'admin@example.com', '', '2024-01-01 00:00:00', '', 0, 'admin');

INSERT INTO `wp_posts` (`ID`, `post_author`, `post_date`, `post_date_gmt`, `post_content`, `post_title`, `post_excerpt`, `post_status`, `comment_status`, `ping_status`, `post_password`, `post_name`, `to_ping`, `pinged`, `post_modified`, `post_modified_gmt`, `post_content_filtered`, `post_parent`, `guid`, `menu_order`, `post_type`, `post_mime_type`, `comment_count`) VALUES
(1, 1, '2024-01-01 00:00:00', '2024-01-01 00:00:00', 'Welcome to WordPress. This is your first post. Edit or delete it, then start writing!', 'Hello world!', '', 'publish', 'open', 'open', '', 'hello-world', '', '', '2024-01-01 00:00:00', '2024-01-01 00:00:00', '', 0, 'http://localhost/?p=1', 0, 'post', '', 1);

COMMIT;
EOF
  
  echo "   ✅ Sample SQL dump generated successfully"
else
  echo "   ✅ Database connection successful"
  
  # Generate real SQL dump from database
  echo "➡️  Generating SQL dump from database..."
  if [ "$USE_DOCKER_EXEC" = true ]; then
    # Use docker exec to run mariadb-dump inside container
    if docker exec db mariadb-dump -h"$DB_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --add-drop-database \
        --create-options \
        --disable-keys \
        --extended-insert \
        --quick \
        --lock-tables=false \
        --databases "$DATABASE" > "$SQL_FILE"; then
      echo "   ✅ SQL dump generated successfully"
    else
      echo "   ❌ Failed to generate SQL dump"
      exit 1
    fi
  else
    # Direct mariadb-dump (running inside container)
    if mariadb-dump -h"$DB_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --add-drop-database \
        --create-options \
        --disable-keys \
        --extended-insert \
        --quick \
        --lock-tables=false \
        --databases "$DATABASE" > "$SQL_FILE"; then
      echo "   ✅ SQL dump generated successfully"
    else
      echo "   ❌ Failed to generate SQL dump"
      exit 1
    fi
  fi
fi

# Compress the SQL file
echo "➡️  Compressing SQL dump..."
if gzip -c "$SQL_FILE" > "$GZ_FILE"; then
  echo "   ✅ Compressed dump generated successfully"
else
  echo "   ❌ Failed to compress SQL dump"
  exit 1
fi

# Generate checksums
echo "➡️  Generating checksums..."
SQL_CHECKSUM=$(sha256sum "$SQL_FILE" | cut -d' ' -f1)
GZ_CHECKSUM=$(sha256sum "$GZ_FILE" | cut -d' ' -f1)

# Save checksums to files
echo "$SQL_CHECKSUM" > "${SQL_FILE}.sha256"
echo "$GZ_CHECKSUM" > "${GZ_FILE}.sha256"

echo "   ✅ Checksums generated"

# Show file sizes
SQL_SIZE=$(du -h "$SQL_FILE" | cut -f1)
GZ_SIZE=$(du -h "$GZ_FILE" | cut -f1)

echo "------------------------------------------------------------"
echo "✅ Seed dump generation completed!"
echo ""
echo "📊 Generated files:"
echo "   SQL dump:     $SQL_FILE ($SQL_SIZE)"
echo "   Compressed:   $GZ_FILE ($GZ_SIZE)"
echo "   SQL checksum: ${SQL_FILE}.sha256"
echo "   GZ checksum:  ${GZ_FILE}.sha256"
echo ""
echo "🔍 Checksums:"
echo "   SQL: $SQL_CHECKSUM"
echo "   GZ:  $GZ_CHECKSUM"
echo "------------------------------------------------------------"

# Optional: Create symlinks to latest files
LATEST_SQL="${OUTPUT_DIR}/${FILENAME}_latest.sql"
LATEST_GZ="${OUTPUT_DIR}/${FILENAME}_latest.sql.gz"

echo "🔗 Creating symlinks to latest files..."
ln -sf "$(basename "$SQL_FILE")" "$LATEST_SQL"
ln -sf "$(basename "$GZ_FILE")" "$LATEST_GZ"
ln -sf "$(basename "${SQL_FILE}.sha256")" "${LATEST_SQL}.sha256"
ln -sf "$(basename "${GZ_FILE}.sha256")" "${LATEST_GZ}.sha256"
echo "   ✅ Symlinks created:"
echo "      $LATEST_SQL -> $(basename "$SQL_FILE")"
echo "      $LATEST_GZ -> $(basename "$GZ_FILE")"
