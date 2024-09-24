printenv | grep -v "POSTGRES_HOST" >> /etc/environment
printenv | grep -v "POSTGRES_USERNAME" >> /etc/environment
printenv | grep -v "POSTGRES_PASSWORD" >> /etc/environment

cron -f