#!/bin/bash
# Biliboard Backup Management Script
# Usage: ./backup-manager.sh [command]

set -e

COMPOSE_DIR="${COMPOSE_DIR:-/home/deploy/_work/biliboard-deploy/biliboard-deploy}"
COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-biliboard}"

get_backup_container() {
    docker ps -q -f "label=com.biliboard.service=backup" | head -1
}

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
    echo "Environment:"
    echo "  COMPOSE_DIR  Path to docker-compose directory (default: ${COMPOSE_DIR})"
    echo ""
}

backup_now() {
    local container
    container=$(get_backup_container)
    if [ -z "$container" ]; then
        echo "Error: Backup container not found"
        exit 1
    fi
    echo "Running backup now..."
    docker exec "$container" /scripts/backup.sh
}

list_backups() {
    local container
    container=$(get_backup_container)
    if [ -z "$container" ]; then
        echo "Error: Backup container not found"
        exit 1
    fi
    echo "Available backups:"
    docker exec "$container" ls -lh /backups/ 2>/dev/null || echo "No backups found"
}

restore_backup() {
    local container
    container=$(get_backup_container)
    if [ -z "$container" ]; then
        echo "Error: Backup container not found"
        exit 1
    fi

    echo "Available backups:"
    docker exec "$container" ls -1 /backups/biliboard_*.db.gz 2>/dev/null | nl
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

    # Load environment variables
    cd "${COMPOSE_DIR}"
    export $(grep -v '^#' .env.versions | xargs)

    echo "Stopping backend service..."
    docker compose stop backend

    echo "Creating pre-restore backup..."
    docker exec "$container" cp /app/data/prod.db /backups/pre_restore_$(date +%Y%m%d_%H%M%S).db 2>/dev/null || true

    echo "Restoring from ${BACKUP_FILE}..."
    docker exec "$container" sh -c "gunzip -c /backups/${BACKUP_FILE} > /tmp/restore.db && cp /tmp/restore.db /app/data/prod.db"

    echo "Starting backend service..."
    docker compose start backend

    echo "Restore completed!"
}

download_backup() {
    local container
    container=$(get_backup_container)
    if [ -z "$container" ]; then
        echo "Error: Backup container not found"
        exit 1
    fi

    echo "Available backups:"
    docker exec "$container" ls -1 /backups/biliboard_*.db.gz 2>/dev/null | nl
    echo ""
    read -p "Enter backup filename to download: " BACKUP_FILE

    if [ -z "$BACKUP_FILE" ]; then
        echo "No backup selected."
        exit 1
    fi

    LOCAL_PATH="./backups/${BACKUP_FILE}"
    mkdir -p ./backups
    docker cp "$container:/backups/${BACKUP_FILE}" "${LOCAL_PATH}"
    echo "Downloaded to: ${LOCAL_PATH}"
}

show_status() {
    local container
    container=$(get_backup_container)

    cd "${COMPOSE_DIR}"
    export $(grep -v '^#' .env.versions | xargs) 2>/dev/null || true

    echo "Backup Service Status:"
    docker compose ps backup 2>/dev/null || docker ps --filter "label=com.biliboard.service=backup" --format "table {{.Names}}\t{{.Status}}"
    echo ""
    echo "Next scheduled backups (crontab):"
    if [ -n "$container" ]; then
        docker exec "$container" crontab -l 2>/dev/null || echo "Unable to read crontab"
    else
        echo "Backup container not running"
    fi
}

show_logs() {
    cd "${COMPOSE_DIR}"
    export $(grep -v '^#' .env.versions | xargs) 2>/dev/null || true

    local container
    container=$(get_backup_container)
    docker compose logs --tail=50 backup 2>/dev/null || {
        if [ -n "$container" ]; then
            docker logs --tail=50 "$container"
        else
            echo "Backup container not found"
        fi
    }
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
