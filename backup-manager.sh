#!/bin/bash
# Biliboard Backup Management Script
# Usage: ./backup-manager.sh [command]

set -e

BACKUP_CONTAINER="biliboard-backup"
BACKUP_VOLUME="biliboard_backup-data"

show_help() {
    echo "Biliboard Backup Manager"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  now         Run backup immediately"
    echo "  list        List all backups"
    echo "  restore     Restore from a backup (interactive)"
    echo "  download    Download backup to local machine"
    echo "  status      Show backup service status"
    echo "  logs        Show backup logs"
    echo ""
}

backup_now() {
    echo "Running backup now..."
    docker exec ${BACKUP_CONTAINER} /usr/local/bin/backup.sh
}

list_backups() {
    echo "Available backups:"
    docker exec ${BACKUP_CONTAINER} ls -lh /backups/ 2>/dev/null || echo "No backups found"
}

restore_backup() {
    echo "Available backups:"
    docker exec ${BACKUP_CONTAINER} ls -1 /backups/biliboard_*.db.gz 2>/dev/null | nl
    echo ""
    read -p "Enter backup filename to restore (e.g., biliboard_20240101_120000.db.gz): " BACKUP_FILE

    if [ -z "$BACKUP_FILE" ]; then
        echo "No backup selected. Aborting."
        exit 1
    fi

    echo ""
    echo "⚠️  WARNING: This will REPLACE the current database!"
    echo "    The current database will be backed up first."
    read -p "Are you sure? (yes/no): " CONFIRM

    if [ "$CONFIRM" != "yes" ]; then
        echo "Restore cancelled."
        exit 0
    fi

    echo "Stopping backend service..."
    docker compose stop backend

    echo "Creating pre-restore backup..."
    docker exec ${BACKUP_CONTAINER} cp /app/data/prod.db /backups/pre_restore_$(date +%Y%m%d_%H%M%S).db 2>/dev/null || true

    echo "Restoring from ${BACKUP_FILE}..."
    docker exec ${BACKUP_CONTAINER} sh -c "gunzip -c /backups/${BACKUP_FILE} > /tmp/restore.db && cp /tmp/restore.db /app/data/prod.db"

    echo "Starting backend service..."
    docker compose start backend

    echo "Restore completed!"
}

download_backup() {
    echo "Available backups:"
    docker exec ${BACKUP_CONTAINER} ls -1 /backups/biliboard_*.db.gz 2>/dev/null | nl
    echo ""
    read -p "Enter backup filename to download: " BACKUP_FILE

    if [ -z "$BACKUP_FILE" ]; then
        echo "No backup selected."
        exit 1
    fi

    LOCAL_PATH="./backups/${BACKUP_FILE}"
    mkdir -p ./backups
    docker cp ${BACKUP_CONTAINER}:/backups/${BACKUP_FILE} ${LOCAL_PATH}
    echo "Downloaded to: ${LOCAL_PATH}"
}

show_status() {
    echo "Backup Service Status:"
    docker compose ps backup
    echo ""
    echo "Next scheduled backups (crontab):"
    docker exec ${BACKUP_CONTAINER} crontab -l 2>/dev/null || echo "Unable to read crontab"
}

show_logs() {
    docker compose logs --tail=50 backup
}

case "${1:-help}" in
    now)
        backup_now
        ;;
    list)
        list_backups
        ;;
    restore)
        restore_backup
        ;;
    download)
        download_backup
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    *)
        show_help
        ;;
esac
