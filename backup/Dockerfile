# Dockerfile for automated backup system
# Includes Borg Backup + MariaDB client for database dumps

FROM alpine:3.18

# Install necessary dependencies
RUN apk add --no-cache \
    borgbackup \
    mariadb-client \
    bash \
    dcron \
    tzdata \
    openssh-client \
    rsync \
    && rm -rf /var/cache/apk/*

# Create working directory
WORKDIR /backup

# Copy backup scripts
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY run_once.sh /usr/local/bin/run_once.sh
COPY crontab /etc/cron.d/backup-cron

# Make scripts executable
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/run_once.sh \
    && chmod 0644 /etc/cron.d/backup-cron

# Create directories for Borg repositories
RUN mkdir -p /backup/repos \
    && mkdir -p /backup/data \
    && mkdir -p /backup/logs

# Default environment variables (can be overridden by docker-compose)
ENV BORG_REPO=/backup/repos/backup-repo
ENV BACKUP_RETENTION_DAILY=7
ENV BACKUP_RETENTION_WEEKLY=4
ENV BACKUP_RETENTION_MONTHLY=6

# Default command
CMD ["/usr/local/bin/entrypoint.sh"]
