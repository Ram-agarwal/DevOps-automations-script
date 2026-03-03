#!/bin/bash

# ==============================
# Docker Safe Cleanup Script
# Author: Ram DevOps
# ==============================

LOG_FILE="/var/log/docker-cleanup.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "=========================================" >> $LOG_FILE
echo "Docker Cleanup Started at $DATE" >> $LOG_FILE
echo "=========================================" >> $LOG_FILE

# Check if Docker is running
if ! systemctl is-active --quiet docker; then
    echo "Docker service is not running. Exiting..." | tee -a $LOG_FILE
    exit 1
fi

echo "Removing stopped containers..." | tee -a $LOG_FILE
docker container prune -f >> $LOG_FILE 2>&1

echo "Removing dangling images only..." | tee -a $LOG_FILE
docker image prune -f >> $LOG_FILE 2>&1

echo "Removing unused volumes..." | tee -a $LOG_FILE
docker volume prune -f >> $LOG_FILE 2>&1

echo "Docker Cleanup Completed Successfully at $(date '+%Y-%m-%d %H:%M:%S')" | tee -a $LOG_FILE
echo "" >> $LOG_FILE
