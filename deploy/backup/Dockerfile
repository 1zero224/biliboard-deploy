FROM alpine:3.19

RUN apk add --no-cache sqlite tzdata

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

# Default: run backup every 6 hours
ENV BACKUP_SCHEDULE="0 */6 * * *"
ENV BACKUP_RETENTION_DAYS=7
ENV TZ=Asia/Shanghai

CMD echo "Backup schedule: ${BACKUP_SCHEDULE}" && \
    echo "${BACKUP_SCHEDULE} /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" | crontab - && \
    crond -f -l 2
