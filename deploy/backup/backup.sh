#!/bin/sh
# Biliboard Database Backup Script
# Runs inside the backup container

set -e

BACKUP_DIR="/backups"
DB_PATH="/app/data/prod.db"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/biliboard_${TIMESTAMP}.db"

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

# Wait for database file to exist
if [ ! -f "${DB_PATH}" ]; then
    echo "[$(date)] Database not found at ${DB_PATH}, skipping backup"
    exit 0
fi

# Create backup using SQLite online backup API (safe for running database)
echo "[$(date)] Starting backup..."
sqlite3 "${DB_PATH}" ".backup '${BACKUP_FILE}'"

# Compress backup
gzip "${BACKUP_FILE}"
BACKUP_FILE="${BACKUP_FILE}.gz"

# Calculate backup size
BACKUP_SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
echo "[$(date)] Backup created: ${BACKUP_FILE} (${BACKUP_SIZE})"

# Clean up old backups
echo "[$(date)] Cleaning backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "biliboard_*.db.gz" -type f -mtime +${RETENTION_DAYS} -delete

# List current backups
echo "[$(date)] Current backups:"
ls -lh "${BACKUP_DIR}"/biliboard_*.db.gz 2>/dev/null || echo "  (none)"

echo "[$(date)] Backup completed successfully"
