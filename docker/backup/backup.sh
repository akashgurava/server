#!/bin/bash

BACKUP_DIR="/backup-data"
POSTGRES_BACKUP_DIR="$BACKUP_DIR/postgres"
PROMETHEUS_BACKUP_DIR="$BACKUP_DIR/prometheus"
INTERVAL_SECONDS=3600  # 1 hour

mkdir -p $POSTGRES_BACKUP_DIR
mkdir -p $PROMETHEUS_BACKUP_DIR

while true; do
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    
    echo "Starting backup at $TIMESTAMP"
    
    # PostgreSQL backup
    echo "Backing up PostgreSQL databases..."
    PGPASSWORD=$POSTGRES_PASSWORD pg_dumpall -c  -h $POSTGRES_HOST -U $POSTGRES_USERNAME | brotli --best > $POSTGRES_BACKUP_DIR/${TIMESTAMP}.sql.br

    # Prometheus backup
    echo "Backing up Prometheus data..."
    PROMETHEUS_BACKUP_FILE="$PROMETHEUS_BACKUP_DIR/prometheus_${TIMESTAMP}"
    if promtool tsdb snapshot -o "$PROMETHEUS_BACKUP_FILE" /prometheus; then
        echo "Prometheus backup completed successfully"
    else
        echo "Prometheus backup failed"
    fi
    
    echo "Backup completed at $(date)"
    echo "Waiting for next backup cycle..."
    sleep $INTERVAL_SECONDS
done
