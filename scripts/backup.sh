#!/bin/sh
# Biliboard Database Backup Script

set -e

BACKUP_DIR="/backups"
DATA_DIR="/app/data"
DB_FILE="prod.db"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="biliboard_${TIMESTAMP}.db.gz"

echo "[$(date)] Starting backup..."

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

# Create backup using SQLite online backup API
if [ -f "${DATA_DIR}/${DB_FILE}" ]; then
    sqlite3 "${DATA_DIR}/${DB_FILE}" ".backup '/tmp/backup.db'"
    gzip -c /tmp/backup.db > "${BACKUP_DIR}/${BACKUP_FILE}"
    rm -f /tmp/backup.db
    echo "[$(date)] Backup created: ${BACKUP_FILE}"
else
    echo "[$(date)] ERROR: Database file not found: ${DATA_DIR}/${DB_FILE}"
    exit 1
fi

# Cleanup old backups
echo "[$(date)] Cleaning up backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "biliboard_*.db.gz" -type f -mtime +${RETENTION_DAYS} -delete

# Show current backups
echo "[$(date)] Current backups:"
ls -lh "${BACKUP_DIR}"/biliboard_*.db.gz 2>/dev/null || echo "No backups found"

echo "[$(date)] Backup completed."
