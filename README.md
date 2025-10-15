# english_blog
A Simple blog using WordPress with intelligent volume-based backup and restore system

## Overview

This project provides a production-ready WordPress stack with:

* **WordPress (Apache) + MariaDB** with persistent volumes
* **Intelligent volume snapshot system** with automatic detection
* **Borg backup integration** for reliable volume protection
* **Profile-based deployment** (core vs operational services)
* **Simplified architecture** using only volume snapshots (no SQL dumps)

## Architecture

### Core Profile (Essential Services)
- **db**: MariaDB 11.4 with persistent data
- **wordpress**: WordPress with persistent files and integrated WP-CLI
- **backup**: Scheduled backup system with cron jobs

### Ops Profile (Operational Services)
- **prep**: Complete prep process (volume detection + manual backup + restore)

## How It Works

### 🔄 **Intelligent Volume-Based Process**

When you start the stack, the system automatically determines the best action:

**Scenario 1: Volumes Exist (Maintenance Restart)**
1. **Prep** detects existing data in both volumes
2. **Prep** creates Borg snapshots of complete volumes (manual backup)
3. **WordPress** continues with existing data

**Scenario 2: Volumes Empty (Fresh Deploy)**
1. **Prep** detects empty volumes
2. **Prep** searches for volume snapshots and restores if available
3. **WordPress** loads restored data or fresh install

**Scenario 3: Partial Data**
1. **Prep** detects mixed state
2. **Prep** attempts to restore missing volumes
3. **WordPress** continues with available data

### 📦 **Volume Snapshot System**

- **Volume snapshots**: Complete volume backups using Borg
- **Scheduled backups**: Automatic cron-based volume snapshots
- **Borg integration**: Encrypted, deduplicated volume storage
- **Retention policies**: Daily, weekly, monthly keeps
- **Manual triggers**: On-demand volume snapshot creation
- **Always running**: Part of core services for continuous protection
- **Simplified approach**: No SQL dumps, only complete volume snapshots

## Quick Start

### 1. **Configure Environment**

```bash
# Copy environment template
cp env_simple.env .env

# Edit with your values
nano .env
```

**Essential Variables:**
- `MYSQL_ROOT_PASSWORD`: Database root password
- `MYSQL_DATABASE`: Database name (default: wordpress)
- `MYSQL_USER`: Database user (default: wpuser)
- `MYSQL_PASSWORD`: Database password
- `BORG_PASSPHRASE`: Backup encryption key

### 2. **Start the Stack**

```bash
# Full stack (core + ops)
docker compose --env-file env_simple.env --profile core --profile ops up -d --build

# Or start profiles separately
docker compose --env-file env_simple.env --profile core up -d    # Essential services + backup
docker compose --env-file env_simple.env --profile ops up -d     # Prep process only
```

### 3. **Access WordPress**

- **URL**: http://localhost:8080
- **First time**: WordPress installation wizard
- **Existing data**: Your site loads immediately

## Usage Scenarios

### 🆕 **Fresh Deployment**

```bash
# Clean start
docker compose down -v
docker compose up -d --build

# System will:
# 1. Detect empty volumes
# 2. Look for volume snapshots
# 3. Restore if available, or start fresh
```

### 🔧 **Maintenance Restart**

```bash
# Restart with existing data
docker compose down
docker compose up -d

# System will:
# 1. Detect existing volumes
# 2. Create volume snapshots
# 3. Continue with existing data
```

### 🔄 **Data Migration**

```bash
# Migrate to new server
# 1. Copy backup repository
# 2. Set environment variables
# 3. Start stack
docker compose up -d --build

# System will:
# 1. Detect empty volumes
# 2. Find volume snapshots
# 3. Restore complete environment
```

## Testing

### **Test Different Scenarios**

```bash
# Test volume backup functionality
./tools/test-backup-core.sh

# Test profile combinations
./tools/test-profiles.sh

# Test complete flow with WP-CLI
./tools/test-wp-cli-flow.sh
```

### **Available Test Scenarios**

1. **Volume backup** (volumes with data)
2. **Fresh deploy** (no volumes)
3. **Maintenance restart** (existing volumes)
4. **Complete flow** (WP-CLI integration)
5. **Show current status**
6. **Clean up everything**

## Backup Management

### **Manual Volume Backup**

```bash
# Trigger manual volume backup (automatic on maintenance restart)
docker compose --profile core --profile ops up -d

# Check prep logs for manual backup
docker compose logs prep
```

### **Scheduled Volume Backups**

```bash
# View backup status
docker compose logs backup

# List Borg volume archives
docker compose exec backup borg list /backup/repos/backup-repo
```

### **Restore from Volume Snapshots**

```bash
# Restore from volume snapshots (automatic on fresh deploy)
docker compose --profile core --profile ops up -d

# Check prep logs for restore
docker compose logs prep
```

## Project Structure

```
english_blog/
├── docker-compose.yml          # Main compose file
├── env_simple.env              # Environment template
├── .env                        # Your configuration (gitignored)
│
├── prep/                       # Volume detection and management
│   └── prep-volumes-only.sh    # Complete prep logic (volumes only)
│
├── backup/                     # Volume backup system
│   ├── Dockerfile              # Backup container
│   ├── entrypoint.sh          # Cron scheduler
│   ├── run_once.sh            # Single backup
│   └── crontab                # Schedule config
│
└── tools/                      # Testing tools
    ├── test-backup-core.sh     # Volume backup tests
    ├── test-profiles.sh        # Profile tests
    ├── test-wp-cli-flow.sh     # Complete flow tests
    ├── test-complete-flow.sh   # Flow tests
    ├── cleanup_environment.sh  # Environment cleanup
    ├── export-plugins.sh       # Plugin export
    ├── install-from-manifest.sh # Plugin install
    └── switch-domain.sh        # Domain migration
```

## Environment Variables

### **Database Configuration**
```bash
MYSQL_ROOT_PASSWORD=your_secure_root_pass
MYSQL_DATABASE=wordpress
MYSQL_USER=wpuser
MYSQL_PASSWORD=your_secure_user_pass
```

### **Backup Configuration**
```bash
BORG_REPO=/backup/repos/backup-repo
BORG_PASSPHRASE=your_borg_passphrase
BACKUP_RETENTION_DAILY=7
BACKUP_RETENTION_WEEKLY=4
BACKUP_RETENTION_MONTHLY=6
```

### **WordPress Configuration**
```bash
WP_TABLE_PREFIX=wp_
WP_DEBUG=false
```

## Troubleshooting

### **Common Issues**

**Volumes not detected:**
```bash
# Check volume status
docker volume ls
docker volume inspect english_blog_db_data
docker volume inspect english_blog_wp_data
```

**Volume backup not working:**
```bash
# Check backup logs
docker compose logs backup
docker compose logs prep
```

**Volume restore not working:**
```bash
# Check prep logs for restore
docker compose logs prep
```

**Clean restart:**
```bash
# Complete cleanup
docker compose down -v
docker volume rm english_blog_db_data english_blog_wp_data
docker system prune -f
```

### **Logs and Monitoring**

```bash
# View all logs
docker compose logs -f

# View specific service logs
docker compose logs -f prep
docker compose logs -f backup
```

## Advanced Usage

### **Profile Management**

```bash
# Core services only (db + wordpress + backup)
docker compose --profile core up -d

# Ops services only (prep process)
docker compose --profile ops up -d

# Full stack
docker compose up -d
```

### **Custom Backup Schedules**

Edit `backup/crontab` to modify backup frequency:

```bash
# Daily at 2 AM
0 2 * * * /usr/local/bin/run_once.sh

# Weekly on Sunday at 3 AM
0 3 * * 0 /usr/local/bin/run_once.sh
```

### **Domain Migration**

```bash
# Switch domain
./tools/switch-domain.sh old.example.com new.example.com
```

## Security Notes

- **Never commit `.env`** - Contains sensitive data
- **Use strong passwords** - For database and backup encryption
- **Regular backups** - Test restore procedures
- **Monitor logs** - Check for errors and issues

## Support

For issues or questions:

1. **Check logs**: `docker compose logs -f`
2. **Test scenarios**: `./tools/test-backup-core.sh`
3. **Clean restart**: `docker compose down -v && docker compose up -d`
4. **Check volumes**: `docker volume ls`

---

**Happy blogging! 🚀**