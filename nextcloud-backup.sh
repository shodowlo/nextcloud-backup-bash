#!/bin/bash

NEXTCLOUD_USER="root"
NEXTCLOUD_IP="..."
NEXTCLOUD_DATA_DIR="/var/www/nextcloud/data"
DEST_DIR="/home"
DATE=$(date +"%Y-%m-%d")
TMP_DIR="$DEST_DIR/nextcloud_temp_$DATE"
ARCHIVE="$DEST_DIR/nextcloud_backup_$DATE.tar.gz"

USERS=("user1" "user2") 

PUSHOVER_USER_KEY="..."
PUSHOVER_APP_TOKEN="..."

# begining
mkdir -p "$TMP_DIR"

START_TIME=$(date +%s)

send_pushover() {
    local MESSAGE="$1"
    local PRIORITY="$2"

    if [ "$PRIORITY" -eq 2 ]; then
        curl -s \
            --form-string "token=$PUSHOVER_APP_TOKEN" \
            --form-string "user=$PUSHOVER_USER_KEY" \
            --form-string "message=$MESSAGE" \
            --form-string "priority=2" \
            --form-string "expire=86400" \
            --form-string "retry=3600" \
            https://api.pushover.net/1/messages.json
    else
        curl -s \
            --form-string "token=$PUSHOVER_APP_TOKEN" \
            --form-string "user=$PUSHOVER_USER_KEY" \
            --form-string "message=$MESSAGE" \
            --form-string "priority=$PRIORITY" \
            https://api.pushover.net/1/messages.json
    fi
}

for USER in "${USERS[@]}"; do
    USER_DIR="$NEXTCLOUD_DATA_DIR/$USER/files"
    TMP_USER_DIR="$TMP_DIR/$USER"

    echo "[+] Downloading $USER..."

    rsync -az --exclude '*.tmp' --exclude 'cache/' "$NEXTCLOUD_USER@$NEXTCLOUD_IP:$USER_DIR" "$TMP_USER_DIR"
    RSYNC_EXIT=$?

    if [ $RSYNC_EXIT -ne 0 ]; then
        echo "[ERROR] Download errors for $USER"
        send_pushover "Nextcloud error for $USER. Partial backup archived." 2
    fi

    ZERO_FILES=$(find "$TMP_USER_DIR" -type f -size 0 -print)
    if [ -n "$ZERO_FILES" ]; then
        echo "[ERROR] 0-byte files detected for $USER:"
        echo "$ZERO_FILES"
        send_pushover "0-byte files for $USER in Nextcloud backup" 2
    else
        echo "[OK] No empty files for $USER."
    fi
done

echo "[+] Compressing all users into one archive..."
if ! tar -czf "$ARCHIVE" -C "$DEST_DIR" "$(basename "$TMP_DIR")"; then
    echo "[ERRROR] Global compression error"
    send_pushover "Nextcloud backup compression error. Check disk space!" 2
fi

TOTAL_SIZE_MB=$(stat -c%s "$ARCHIVE")
TOTAL_SIZE_MB=$((TOTAL_SIZE_MB / 1024 / 1024))

rm -rf "$TMP_DIR"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "[+] Deleting archives older than 3 days..."
find "$DEST_DIR" -maxdepth 1 -daystart -name "nextcloud_backup_*.tar.gz" -mtime +2 -exec rm -f {} \;

send_pushover "Nextcloud backup: $ELAPSED s, ${TOTAL_SIZE_MB} MB." 0

echo "[OK] Backup completed: $ARCHIVE"