#!/bin/bash
set -euo pipefail

COMPOSE_DIR="/home/tim/paperless"
LOG_FILE="$COMPOSE_DIR/update.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

cd "$COMPOSE_DIR"

# ── pull latest config from git ───────────────────────────────────────────────
log "Checking for config updates..."
git pull --ff-only origin main >> "$LOG_FILE" 2>&1 || log "WARN: git pull failed, continuing with local config"

# ── check paperless-ngx version ───────────────────────────────────────────────
CURRENT=$(grep 'paperless-ngx:' docker-compose.yml | head -1 | sed 's/.*paperless-ngx://')

LATEST=$(curl -sf "https://api.github.com/repos/paperless-ngx/paperless-ngx/releases/latest" \
  | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')

if [ -z "$LATEST" ]; then
  log "ERROR: could not fetch latest version from GitHub"
  exit 1
fi

log "Current: ${CURRENT:-unknown}  Latest: ${LATEST}"

if [ "${CURRENT:-}" != "$LATEST" ]; then
  log "New version available — updating docker-compose.yml to ${LATEST}..."
  sed -i "s|paperless-ngx:[^ ]*|paperless-ngx:${LATEST}|g" docker-compose.yml
  git add docker-compose.yml
  git commit -m "chore: bump paperless-ngx to ${LATEST}" >> "$LOG_FILE" 2>&1
  git push origin main >> "$LOG_FILE" 2>&1 || log "WARN: git push failed"
fi

# ── pull images and restart if anything changed ───────────────────────────────
BEFORE=$(docker compose images -q 2>/dev/null | sort | md5sum)
docker compose pull >> "$LOG_FILE" 2>&1
AFTER=$(docker compose images -q 2>/dev/null | sort | md5sum)

if [ "$BEFORE" != "$AFTER" ] || [ "${CURRENT:-}" != "$LATEST" ]; then
  log "Changes detected — restarting containers..."
  docker compose up -d >> "$LOG_FILE" 2>&1
  log "Update complete."
else
  log "Already up to date."
fi
