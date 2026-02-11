#!/bin/bash

####################################
# MongoDB Production Backup Script
# Works for ALL databases
####################################

# ===== MONGO CONNECTION =====
MONGO_HOST="localhost"
MONGO_PORT="27017"
MONGO_USER="backupuser"
MONGO_PASS="StrongPassword"
AUTH_DB="admin"

# ===== BACKUP CONFIG =====
BACKUP_BASE_DIR="/data/mongo-backups"
DATE=$(date +"%Y-%m-%d_%H-%M-%S")
RETENTION_DAYS=7
LOG_FILE="/var/log/mongodb_backup.log"

BACKUP_DIR="$BACKUP_BASE_DIR/$DATE"
ARCHIVE_FILE="$BACKUP_BASE_DIR/mongo_all_$DATE.tar.gz"

# ===== PREP =====
mkdir -p "$BACKUP_DIR"

echo "[$(date)] MongoDB backup started" >> "$LOG_FILE"

# ===== BACKUP ALL DATABASES =====
mongodump \
  --host "$MONGO_HOST" \
  --port "$MONGO_PORT" \
  --username "$MONGO_USER" \
  --password "$MONGO_PASS" \
  --authenticationDatabase "$AUTH_DB" \
  --out "$BACKUP_DIR"

if [ $? -ne 0 ]; then
  echo "[$(date)] ❌ MongoDB backup FAILED" >> "$LOG_FILE"
  exit 1
fi

# ===== COMPRESS =====
tar -czf "$ARCHIVE_FILE" -C "$BACKUP_BASE_DIR" "$DATE"
rm -rf "$BACKUP_DIR"

echo "[$(date)] ✅ Backup successful: $ARCHIVE_FILE" >> "$LOG_FILE"

# ===== RETENTION =====
find "$BACKUP_BASE_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
echo "[$(date)] Old backups deleted (> $RETENTION_DAYS days)" >> "$LOG_FILE"

echo "[$(date)] Backup job completed" >> "$LOG_FILE"

