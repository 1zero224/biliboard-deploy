#!/bin/bash
set -euo pipefail

# Biliboard Deploy Webhook Handler
# Called by adnanh/webhook service

DEPLOY_DIR="${DEPLOY_DIR:-/opt/biliboard-deploy}"
LOG_FILE="/var/log/biliboard-deploy.log"
LOCK_FILE="/var/lock/biliboard-deploy.lock"

# Server-local GitHub credentials (fine-grained PAT)
GITHUB_PAT="${GITHUB_PAT}"
GITHUB_REPO="${GITHUB_REPO:-1zero224/biliboard-deploy}"
GHCR_USER="${GHCR_USER}"
GHCR_TOKEN="${GHCR_TOKEN}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Acquire exclusive lock to prevent concurrent deployments
acquire_lock() {
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        log "ERROR: Another deployment is in progress"
        exit 1
    fi
    log "Lock acquired"
}

update_github_status() {
    local deployment_id="$1"
    local state="$2"
    local description="$3"

    curl -sf --max-time 10 -X POST \
        -H "Authorization: token $GITHUB_PAT" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/$GITHUB_REPO/deployments/$deployment_id/statuses" \
        -d "{\"state\":\"$state\",\"description\":\"$description\"}" || log "WARNING: Failed to update GitHub status"
}

# Secure parsing of .env.versions (whitelist keys only)
parse_env_versions() {
    local env_file="$1"
    local allowed_keys="BACKEND_REF FRONTEND_REF"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        # Whitelist check
        if echo "$allowed_keys" | grep -qw "$key"; then
            # Validate value contains no dangerous characters
            if [[ "$value" =~ ^[a-zA-Z0-9_./:@-]+$ ]]; then
                export "$key=$value"
            else
                log "WARNING: Invalid value for $key, skipping"
            fi
        fi
    done < "$env_file"
}

do_deploy() {
    local deployment_id="$1"
    local commit_sha="$2"

    log "Starting deployment for commit $commit_sha"

    cd "$DEPLOY_DIR"

    # Backup current version for rollback
    if [[ -f .env.versions ]]; then
        cp .env.versions .env.versions.backup
        log "Backed up current .env.versions"
    fi

    # Pull latest config
    git fetch origin master
    git reset --hard origin/master

    # Load version config securely
    parse_env_versions .env.versions

    # Load runtime secrets if available
    if [[ -f .env.secrets ]]; then
        set -a
        source .env.secrets
        set +a
        log "Loaded runtime secrets"
    else
        log "WARNING: .env.secrets not found, using defaults"
    fi

    # Login to GHCR
    echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin

    # Pull new images
    log "Pulling images..."
    docker compose pull

    # Rolling update
    log "Updating services..."
    docker compose up -d --remove-orphans

    # Wait for services to start with retry health check
    local max_retries=6
    local retry_interval=10
    local health_ok=false

    # Load HTTP_PORT from .env if available
    local http_port="${HTTP_PORT:-80}"
    if [[ -f .env ]]; then
        local port_from_env=$(grep -E "^HTTP_PORT=" .env | cut -d= -f2 | xargs)
        [[ -n "$port_from_env" ]] && http_port="$port_from_env"
    fi

    log "Waiting for services to be healthy (port $http_port)..."
    for ((i=1; i<=max_retries; i++)); do
        sleep "$retry_interval"
        if curl -sf "http://127.0.0.1:${http_port}/health" > /dev/null 2>&1; then
            health_ok=true
            break
        fi
        log "Health check attempt $i/$max_retries failed, retrying..."
    done

    if [[ "$health_ok" == "true" ]]; then
        log "Deployment successful!"
        update_github_status "$deployment_id" "success" "Deployment completed successfully"
        # Remove backup on success
        rm -f .env.versions.backup
    else
        log "Health check failed!"
        update_github_status "$deployment_id" "failure" "Health check failed after deployment"

        # Rollback to backup version
        if [[ -f .env.versions.backup ]]; then
            log "Rolling back to backup version..."
            cp .env.versions.backup .env.versions
            parse_env_versions .env.versions
            docker compose up -d
            rm -f .env.versions.backup
        else
            log "No backup available for rollback!"
        fi
    fi

    # Cleanup old images
    docker image prune -f
}

# Entry point: called by webhook tool with arguments
main() {
    local deployment_id="${1:-}"
    local commit_sha="${2:-}"

    # Input validation (security)
    if [[ -z "$deployment_id" || -z "$commit_sha" ]]; then
        log "ERROR: Missing required parameters"
        exit 1
    fi

    # Validate deployment_id is numeric
    if [[ ! "$deployment_id" =~ ^[0-9]+$ ]]; then
        log "ERROR: Invalid deployment_id format"
        exit 1
    fi

    # Validate commit_sha is 40-char hex
    if [[ ! "$commit_sha" =~ ^[0-9a-f]{40}$ ]]; then
        log "ERROR: Invalid commit_sha format"
        exit 1
    fi

    acquire_lock
    do_deploy "$deployment_id" "$commit_sha"
}

main "$@"
