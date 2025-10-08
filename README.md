# english_blog
A Simple blog using Wordpress

# Overview 

This project gives you a production-leaning WordPress stack with:

* **WordPress (Apache) + MariaDB** with persistent volumes
* **Nginx reverse proxy** with **Let’s Encrypt (Certbot)** for HTTPS
* A **seed/restore flow**:

  * On a **fresh** DB volume: if there’s a `db-seed/*.sql` → it’s imported once; otherwise → **clean install**
  * After every backup, the **latest dump** is written to `db-seed/seed.sql` so a future fresh boot can auto-restore
* A **backup service** (cron) that does:

  1. `mysqldump` (database)
  2. **Borg** snapshot of: database dumps, **WordPress files** (plugins/themes/uploads + `wp-config.php`), and **plugin manifests**
* **WP-CLI** for admin tasks and a **WP-CLI cron sidecar** that exports **plugin manifests** daily
* **Domain migration tools**: a script to switch the site domain safely (serialized URLs handled), and manifest-based plugin reinstalls

## Components

* **db**: `mariadb:11` with `db_data` volume; imports `db-seed/*.sql` only on first boot with an empty volume
* **wordpress**: `wordpress:php8.2-apache` with `wp_data` volume
* **nginx**: reverse proxy for :80/:443 and ACME webroot
* **certbot**: renews certificates periodically (webroot method)
* **backup**: Alpine container with `mariadb-client + borgbackup + crond`
* **wpcli**: `wordpress:cli` for manual commands
* **wpcli-cron**: periodically exports **plugin manifests** into `./manifests/`, which are also backed up by Borg

## Volumes & important folders

* Docker volumes:

  * `db_data`: MariaDB data directory
  * `wp_data`: WordPress files (`/var/www/html`)
  * `dumps`: raw `.sql` dumps created before Borg snapshots
  * `borg_repo`: local Borg repository (archives)
  * `letsencrypt`: persisted TLS certs and metadata
* Bind mounts in the repo:

  * `db-seed/`: contains **only one** file after backups → `seed.sql` (latest DB dump)
  * `manifests/`: `plugins.json` and `plugins_active.txt` plus timestamped versions
  * `reverse-proxy/`: nginx config + ACME webroot

## First-boot behavior

* If `db_data` is **empty**:

  * If `db-seed/seed.sql` (or any `*.sql`) exists → MariaDB auto-imports it once
  * If there’s **no** seed → WordPress runs a **clean install**
* If `db_data` already has data → **no import occurs** (MariaDB’s native behavior)

## Backups & retention

* The `backup` service’s cron job:

  * Runs `mysqldump` to `/dumps/<db>_<timestamp>.sql`
  * Updates `db-seed/seed.sql` to that **latest** dump (and removes other `*.sql` there)
  * Creates a **Borg** archive named `wpdb-files-<timestamp>` containing:

    * `/dumps` (all SQL dumps)
    * WordPress files (`/var/www/html/wp-content`, `wp-config.php`) excluding caches
    * `/manifests` (plugin manifests exported by `wpcli-cron`)
  * Optionally prunes old Borg archives (daily/weekly/monthly keeps)

## TLS

* ACME HTTP-01 (webroot) via Nginx + Certbot:

  * You run a **one-time issuance** command
  * Certbot container auto-renews twice a day
  * After issuance/renewal, reload Nginx (`nginx -s reload`) so it picks up new certs

## Plugin manifests

* `wpcli-cron` writes:

  * `manifests/plugins.json` (full list with status)
  * `manifests/plugins_active.txt` (slugs of active plugins)
  * Timestamped snapshots of both (useful for history)
* Manifests are **included** in Borg backups for reliable rebuilds

## Domain switching

* `tools/switch-domain.sh OLD NEW` uses `wp search-replace` (safe for serialized data) and updates `home`/`siteurl`.
* You can move the entire instance to a new domain and correct URLs in the DB.

---

# Usage (Step-by-Step)

## 0) Prerequisites

* **DNS**: `LE_DOMAIN` A/AAAA record must point to this server’s IP
* **Firewall**: open TCP **80** and **443**
* **Docker & Compose** installed
* A Borg passphrase set in `.env` (and enough disk space)

## 1) Project layout (already provided)

```
/english_blog
├─ docker-compose.yml          # main compose file
├─ .env                        # secrets/config (gitignored)
├─ env_simple.env              # example .env
├─ .gitignore                  # excludes .env etc.
│
├─ db-seed/                    # DB seed logic
│  └─ 10-prepare-seed.sh       # runs on first boot (if empty volume)
│
├─ backup/                     # backup container
│  ├─ Dockerfile               # builds backup image
│  ├─ entrypoint.sh            # starts cron, ensures borg repo
│  ├─ run_once.sh              # one backup run (dump + borg snapshot)
│  └─ crontab                  # placeholder (real cron written at runtime)
│
├─ wpcli-cron/                 # WP-CLI sidecar for plugin manifests
│  ├─ entrypoint.sh            # loop runner (calls export_once.sh periodically)
│  └─ export_once.sh           # single manifest export
│
├─ certbot/                    # Let's Encrypt handling
│  ├─ entrypoint.sh            # renewal loop
│  └─ issue.sh                 # one-time certificate issuance
│
├─ reverse-proxy/              # Nginx reverse proxy + ACME webroot
│  ├─ nginx.conf               # base nginx config
│  ├─ certbot-www/             # ACME webroot (empty dir, used by certbot)
│  └─ conf.d/
│     └─ wordpress.conf        # vhost config (http→https, proxy pass)
│
├─ manifests/                  # plugin manifests (exported daily by wpcli-cron)
│
└─ tools/                      # helper scripts
   ├─ export-plugins.sh        # manual manifest export
   ├─ install-from-manifest.sh # reinstall/activate from manifest
   └─ switch-domain.sh         # safe domain switch
```

> Ensure `db-seed/10-prepare-seed.sh`, `backup/entrypoint.sh`, and `tools/*.sh` are executable.

```bash
chmod +x db-seed/10-prepare-seed.sh backup/entrypoint.sh tools/*.sh
```

## 2) Configure environment

Copy the example and edit values:

```bash
cp env_simple.env .env
```

**Key variables (from `.env`):**

| Variable                   | Required | Example                     | Notes                                  |
| -------------------------- | -------- | --------------------------- | -------------------------------------- |
| `TZ`                       | yes      | `America/Lima`              | Container timezone                     |
| `MYSQL_ROOT_PASSWORD`      | yes      | `change_me_root`            | MariaDB root                           |
| `MYSQL_DATABASE`           | yes      | `wordpress`                 | DB name                                |
| `MYSQL_USER`               | yes      | `wpuser`                    | App user                               |
| `MYSQL_PASSWORD`           | yes      | `change_me_user`            | App password                           |
| `CRON_SCHEDULE`            | yes      | `0 3 * * *`                 | Backup time (cron)                     |
| `BORG_PASSPHRASE`          | yes      | `change_me_borg_passphrase` | Borg repo key                          |
| `PLUGINS_INTERVAL_SECONDS` | optional | `86400`                     | How often wpcli-cron exports manifests |
| `LE_DOMAIN`                | yes      | `your-domain.com`           | Public domain                          |
| `LE_EMAIL`                 | yes      | `admin@your-domain.com`     | For Let’s Encrypt                      |

> `.env` is already in `.gitignore`. Keep it secret.

## 3) Start the stack

```bash
docker compose up -d --build
```

* This creates volumes and starts db, wordpress, nginx, certbot, backup, wpcli-cron
* First boot: if `db_data` is empty and there’s a `db-seed/seed.sql`, it will be imported automatically; otherwise, WordPress launches clean

## 4) Issue the initial TLS certificate (one-time)

1. Make sure Nginx is up and serving `/.well-known/acme-challenge/`:

```bash
docker compose ps nginx
```

2. Run certbot issuance:

```bash
docker compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d "${LE_DOMAIN}" \
  --email "${LE_EMAIL}" --agree-tos --non-interactive --rsa-key-size 4096
```

3. Reload Nginx to pick the new cert:

```bash
docker compose exec nginx nginx -s reload
```

4. Visit: `https://your-domain.com`

> Renewals happen automatically inside the `certbot` container.
> After a renewal, run `docker compose exec nginx nginx -s reload`.
> (If you want this automated, we can add a tiny watcher later.)

## 5) Verify everything

* WordPress should respond over **HTTPS**
* `wpcli-cron` will create:

  * `manifests/plugins.json`
  * `manifests/plugins_active.txt`
    (and timestamped copies) within its interval (default \~24h). To run once immediately:

```bash
docker compose run --rm wpcli --path=/var/www/html plugin list --format=json > manifests/plugins.json
docker compose run --rm wpcli --path=/var/www/html plugin list \
  --format=csv --fields=name,status \
  | awk -F, 'NR>1 && $2=="active"{print $1}' > manifests/plugins_active.txt
```

## 6) Run a backup **now** (on-demand test)

```bash
docker compose exec wp_backup /bin/sh -lc '/opt/backup/run_once.sh'
```

This will:

* Create a DB dump in `/dumps`
* Update `db-seed/seed.sql` with that latest dump
* Create a Borg archive with `/dumps`, WordPress files (plugins/uploads/themes + `wp-config.php`), and `/manifests`
* Optionally prune older Borg archives (based on keep-policies)

### Check Borg archives

```bash
# inside the backup container
docker compose exec wp_backup sh -lc 'borg list "${BORG_REPO}"'
```

## 7) Routine operations

### Trigger manual backups

```bash
docker compose exec wp_backup /bin/sh -lc '/opt/backup/run_once.sh'
```

### Export plugin manifests (manual)

```bash
./tools/export-plugins.sh
```

### Reinstall plugins from a manifest

```bash
./tools/install-from-manifest.sh               # uses manifests/plugins_active.txt
# or
./tools/install-from-manifest.sh path/to/another_list.txt
```

### Switch domain (e.g., migration to a new hostname)

```bash
./tools/switch-domain.sh old.example.com new.example.com
```

This:

* Rewrites all serialized URLs in DB
* Updates `home` and `siteurl` to `https://new.example.com`

## 8) Restore & Migration Scenarios

### A) Rebuild the site from the **latest seed** (DB only)

Use this if you want to **reset** DB to the latest backup:

```bash
# Stop stack
docker compose down

# Remove ONLY the DB volume so MariaDB boots fresh
docker volume rm wordpress-borg_db_data   # adjust prefix if your project dir name differs

# Ensure a seed exists (created by your last backup)
ls -l db-seed/seed.sql

# Start again
docker compose up -d
# MariaDB auto-imports db-seed/seed.sql on first boot
```

### B) Full recovery from **Borg** (DB + files) to a new server

1. Prepare new server: clone repo, set `.env`, DNS for new domain, open ports 80/443
2. Bring up the stack to create volumes:

```bash
docker compose up -d --build
```

3. **Restore files** from a chosen Borg archive:

* Extract to a local folder (on the host):

```bash
mkdir -p /tmp/wp-restore
# List archives
docker compose exec wp_backup sh -lc 'borg list "${BORG_REPO}"'
# Choose a snapshot, then extract
docker compose exec -T wp_backup sh -lc 'borg extract --list "${BORG_REPO}::wpdb-files-YYYY-MM-DD_HH-MM-SS" var/www/html/wp-content' \
  > /tmp/wp-restore/extract.log 2>&1
# Copy from the backup container to host if needed (alternative: mount)
```

* Copy restored files into the `wp_data` volume (preserve ownership for www-data):

```bash
# Example approach: run a helper container with both a bind and the volume mounted
docker run --rm -v wordpress-borg_wp_data:/wpdata -v /tmp/wp-restore/var/www/html:/restore alpine \
  sh -lc 'cp -a /restore/wp-content /wpdata/ && chown -R 33:33 /wpdata/wp-content'
```

> UID/GID `33:33` = `www-data` in Debian/Ubuntu images.

4. **Restore DB** using the seed mechanism:

* Place the desired `.sql` into `db-seed/seed.sql` (you can extract from `/dumps` in the same Borg archive)
* Recreate the DB volume to force import:

```bash
docker compose down
docker volume rm wordpress-borg_db_data
docker compose up -d
```

5. **Issue TLS** for the new domain (see Section 4), then:

```bash
./tools/switch-domain.sh old.example.com new.example.com
```

6. Reload Nginx after TLS issuance/renewals:

```bash
docker compose exec nginx nginx -s reload
```

## 9) Maintenance cheatsheet

```bash
# View logs
docker compose logs -f db wordpress nginx wp_backup wp_cli wp_cli_cron certbot

# List Borg archives
docker compose exec wp_backup sh -lc 'borg list "${BORG_REPO}"'

# Prune explicitly (if needed)
docker compose exec wp_backup sh -lc 'borg prune "${BORG_REPO}" --keep-daily 7 --keep-weekly 4 --keep-monthly 6'

# Fix ownership after manual file copies
docker compose exec wordpress chown -R www-data:www-data /var/www/html/wp-content

# Run WP-CLI (any command)
docker compose run --rm wpcli --path=/var/www/html plugin list
```

## 10) Troubleshooting

* **Seed not imported?** DB volume probably not empty. Remove `db_data` and start again.
* **Certbot issuance fails:** confirm DNS A/AAAA points to this server; port 80 open; Nginx serving `/.well-known/acme-challenge/`.
* **`mysqldump` auth error:** check `MYSQL_*` values in `.env`.
* **Permissions after file restore:** ensure `wp-content` belongs to `www-data` (`33:33`).
* **Nginx still using old cert:** reload after issuance/renewal.

## 11) Optional enhancements (later)

* Auto-reload Nginx after cert renewal (small watcher sidecar)
* Remote Borg repository (SSH): set `BORG_REPO=ssh://user@host:port/~/repo` and ensure SSH keys/known\_hosts; add `openssh-client` to backup image
* Extra exclusions (cache folders) or include additional app folders in the Borg snapshot

---

If you want, I can tailor a **remote Borg** setup (with SSH keys and known\_hosts) or add the **automatic Nginx reload** sidecar.

