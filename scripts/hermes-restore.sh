#!/bin/bash
# Hermes Agent restore script - S3-compatible (Backblaze, AWS, Minio, etc.)
# Single source of truth: lives in /opt/hermes-repo/scripts/hermes-restore.sh
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-/opt/data}"
REPO_DIR="${REPO_DIR:-/opt/hermes-repo}"
RCLONE="${RCLONE:-/opt/data/bin/rclone}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="/tmp/hermes-restore-${TIMESTAMP}.log"

mkdir -p "$HERMES_HOME/cron/output"

if [ -f "$HERMES_HOME/.env" ]; then
  set -a
  source "$HERMES_HOME/.env"
  set +a
fi

if [ -z "${S3_ACCESS_KEY:-}" ] || [ -z "${S3_SECRET_KEY:-}" ] || \
   [ -z "${S3_ENDPOINT:-}" ] || [ -z "${S3_BUCKET:-}" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] S3 credentials not configured - skipping restore." | tee -a "$LOG"
  echo "Set S3_ACCESS_KEY, S3_SECRET_KEY, S3_ENDPOINT, S3_REGION, S3_BUCKET in $HERMES_HOME/.env" | tee -a "$LOG"
  exit 0
fi

if ! command -v "$RCLONE" &>/dev/null && [ ! -f "$RCLONE" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: rclone not found at $RCLONE. Install it in the container image (see hermes.Dockerfile)." | tee -a "$LOG"
  exit 1
fi

S3_CONF="/tmp/rclone-hermes-restore.conf"
cat > "$S3_CONF" << EOF
[hermes-s3]
type = s3
provider = Other
access_key_id = ${S3_ACCESS_KEY}
secret_access_key = ${S3_SECRET_KEY}
endpoint = ${S3_ENDPOINT}
region = ${S3_REGION:-us-east-005}
EOF

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Downloading data from S3 (bucket: ${S3_BUCKET})..." | tee -a "$LOG"

$RCLONE --config "$S3_CONF" sync "hermes-s3:${S3_BUCKET}/data" "$HERMES_HOME" \
  --delete-excluded \
  --exclude ".cache/**" \
  --exclude "cache/**" \
  --exclude ".npm/**" \
  --exclude "home/.npm/**" \
  --exclude ".npm/_npx/**" \
  --exclude "audio_cache/**" \
  --exclude "image_cache/**" \
  --exclude "logs/**" \
  --exclude "cron/output/**" \
  --exclude "sandboxes/**" \
  --exclude "sessions/**" \
  --exclude ".local/share/tirith/**" \
  --exclude ".skills_prompt_snapshot.json" \
  --exclude "models_dev_cache.json" \
  --exclude "ollama_cloud_models_cache.json" \
  --exclude "/state.db" \
  --exclude "state.db-wal" \
  --exclude "state.db-shm" \
  --exclude "lsp/**" \
  --log-level INFO 2>&1 | tee -a "$LOG"

echo "[$(date +'%Y-%m-%d %H:%M:%S')] S3 sync complete." | tee -a "$LOG"

if [ -f "$HERMES_HOME/backup/state.db" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Restoring consistent state.db from backup..." | tee -a "$LOG"
  mv "$HERMES_HOME/backup/state.db" "$HERMES_HOME/state.db"
  chown 10000:10000 "$HERMES_HOME/state.db"
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] state.db restored." | tee -a "$LOG"
fi

if [ -f "$HERMES_HOME/backup/grafana/grafana.db" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Restoring grafana database..." | tee -a "$LOG"
  docker stop hermes-grafana >> "$LOG" 2>&1 || true
  docker cp "$HERMES_HOME/backup/grafana/grafana.db" hermes-grafana:/var/lib/grafana/grafana.db >> "$LOG" 2>&1
  docker run --rm -v grafana:/var/lib/grafana alpine chown 472:0 /var/lib/grafana/grafana.db >> "$LOG" 2>&1 || true
  docker run --rm -v grafana:/var/lib/grafana alpine chmod 640 /var/lib/grafana/grafana.db >> "$LOG" 2>&1 || true
  docker start hermes-grafana >> "$LOG" 2>&1
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Grafana database restored." | tee -a "$LOG"
fi

if [ -d "$HERMES_HOME/backup/vault" ] && [ "$(ls -A $HERMES_HOME/backup/vault 2>/dev/null)" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Restoring vault data..." | tee -a "$LOG"
  docker stop hermes-vault >> "$LOG" 2>&1 || true
  docker run --rm --volumes-from hermes-vault hermes-repo-toolbox bash -c "rm -rf /vault/data/*"
  docker cp "$HERMES_HOME/backup/vault/." hermes-vault:/vault/data/ >> "$LOG" 2>&1
  docker start hermes-vault >> "$LOG" 2>&1
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Vault data restored." | tee -a "$LOG"
fi

# Hindsight restore — stop container, start PG from bundled binaries, restore via psql, restart
if [ -f "$HERMES_HOME/backup/hindsight/dump.sql" ]; then
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Restoring hindsight database..." | tee -a "$LOG"

  docker stop hermes-hindsight >> "$LOG" 2>&1 || true

  TMP_CONTAINER="hermes-hindsight-restore"

  # Start a temporary container with the hindsight data volume
  docker rm -f "$TMP_CONTAINER" >> "$LOG" 2>&1 || true
  docker run --rm -d --name "$TMP_CONTAINER" \
    -v hindsight:/home/hindsight/.pg0 \
    --entrypoint bash \
    ghcr.io/vectorize-io/hindsight:latest \
    -c 'sleep 9999' >> "$LOG" 2>&1

  # Copy the dump file in
  docker cp "$HERMES_HOME/backup/hindsight/dump.sql" "$TMP_CONTAINER:/tmp/dump.sql" >> "$LOG" 2>&1

  # Start embedded PG, restore, stop PG
  docker exec "$TMP_CONTAINER" bash -c '
    PASS=$(python3 -c "import json; print(json.load(open(\"/home/hindsight/.pg0/instances/hindsight/instance.json\"))[\"password\"])")
    export PGPASSWORD=***    export LD_LIBRARY_PATH=/home/hindsight/.pg0/installation/18.1.0/lib

    PGDATA=/home/hindsight/.pg0/instances/hindsight/data
    PGBIN=/home/hindsight/.pg0/installation/18.1.0/bin

    echo "Starting PostgreSQL..."
    "$PGBIN/pg_ctl" -D "$PGDATA" -l /tmp/pg.log start
    sleep 2

    if ! "$PGBIN/pg_isready" -h /tmp -q 2>/dev/null; then
      echo "ERROR: PostgreSQL failed to start."
      cat /tmp/pg.log
      exit 1
    fi

    echo "Restoring from dump..."
    "$PGBIN/psql" -h /tmp -U hindsight -d hindsight -f /tmp/dump.sql

    echo "Stopping PostgreSQL..."
    "$PGBIN/pg_ctl" -D "$PGDATA" stop
  ' >> "$LOG" 2>&1

  docker rm -f "$TMP_CONTAINER" >> "$LOG" 2>&1

  # Remove the dump so it is not re-applied on next restore
  rm -f "$HERMES_HOME/backup/hindsight/dump.sql"

  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Hindsight database restored." | tee -a "$LOG"
else
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] No hindsight backup found - skipping." | tee -a "$LOG"
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Restore complete!" | tee -a "$LOG"
rm -f "$S3_CONF"
