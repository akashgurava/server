#!/bin/bash

echo "Starting Prometheus backup at $(date)"

BACKUP_DIR="/backup-data/prometheus-data/backup_$(date +%Y%m%d_%H%M%S)"

if promtool tsdb snapshot -o "$BACKUP_DIR" /prometheus; then
    echo "Prometheus backup completed successfully"
    echo "OK" > /backup_status
else
    echo "Prometheus backup failed"
    echo "FAIL" > /backup_status
    exit 1
fi

echo "Backup completed at $(date)"
