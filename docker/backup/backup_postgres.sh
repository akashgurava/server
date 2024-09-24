#!/bin/bash

LOG_DIR="/backup-data/postgres/log"
BACKUP_DIR="/backup-data/postgres/data"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p $LOG_DIR
mkdir -p $BACKUP_DIR

echo "Starting PostgreSQL backup at $(date)"

echo "Attempting to connect to PostgreSQL..."

PGPASSWORD=$POSTGRES_PASSWORD pg_dumpall -c  -h $POSTGRES_HOST -U $POSTGRES_USERNAME | brotli --best > $BACKUP_DIR/dump_`date +%Y-%m-%d"_"%H_%M_%S`.sql.br



# if PGPASSWORD=$POSTGRES_PASSWORD pg_dump -h postgres -U $POSTGRES_USER $POSTGRES_DB > "$BACKUP_FILE" 2>> /var/log/backup.log; then
#     echo "PostgreSQL backup completed successfully" >> /var/log/backup.log 2>&1
#     echo "OK" > /backup_status
# else
#     echo "PostgreSQL backup failed" >> /var/log/backup.log 2>&1
#     echo "Exit code: $?" >> /var/log/backup.log 2>&1
#     echo "FAIL" > /backup_status
# fi

# echo "Backup process completed at $(date)" >> /var/log/backup.log 2>&1