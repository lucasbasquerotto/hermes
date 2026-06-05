#!/bin/bash
# Hermes Agent — first-boot startup script
# Runs inside the Vagrant VM, invoked by the Vagrantfile provisioner.
set -euo pipefail

HERMES_HOME="/opt/data"
REPO_DIR="/opt/hermes-repo"
LOG="$HERMES_HOME/cron/output/startup_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$HERMES_HOME/cron/output"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hermes startup script — begin" | tee -a "$LOG"

# ── 1. Create /opt/data if missing ──────────────────────────────────
mkdir -p "$HERMES_HOME"

# ── 2. Source .env for secrets ──────────────────────────────────────
if [ -f "$HERMES_HOME/.env" ]; then
  set -a
  source "$HERMES_HOME/.env"
  set +a
fi

# ── 3. Attempt S3 restore (if credentials are configured) ────────────
if [ -n "${S3_ACCESS_KEY:-}" ] && [ -n "${S3_SECRET_KEY:-}" ] && \
   [ -n "${S3_ENDPOINT:-}" ] && [ -n "${S3_BUCKET:-}" ]; then

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] S3 credentials found — attempting restore..." | tee -a "$LOG"

  # Download rclone if missing
  RCLONE=$(command -v rclone || echo "/usr/local/bin/rclone")
  if ! command -v rclone &>/dev/null && [ ! -f "$RCLONE" ]; then
    python3 -c "
import urllib.request, zipfile, os, stat, shutil
url = 'https://downloads.rclone.org/rclone-current-linux-amd64.zip'
urllib.request.urlretrieve(url, '/tmp/rclone.zip')
with zipfile.ZipFile('/tmp/rclone.zip', 'r') as zf:
    for name in zf.namelist():
        if name.endswith('/rclone'):
            zf.extract(name, '/tmp')
            shutil.copy2('/tmp/' + name, '/usr/local/bin/rclone')
            os.chmod('/usr/local/bin/rclone', 0o755)
            break
" 2>&1 | tee -a "$LOG"
  fi

  # Build S3 rclone config on the fly
  cat > /tmp/rclone-hermes-restore.conf << EOF
[hermes-s3]
type = s3
provider = Other
access_key_id = ${S3_ACCESS_KEY}
secret_access_key = ${S3_SECRET_KEY}
endpoint = ${S3_ENDPOINT}
region = ${S3_REGION:-us-east-1}
EOF

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Downloading data from S3 (bucket: ${S3_BUCKET})..." | tee -a "$LOG"
  $RCLONE --config /tmp/rclone-hermes-restore.conf sync "hermes-s3:${S3_BUCKET}/data" "$HERMES_HOME" \
    --exclude ".cache/**" \
    --exclude "cache/**" \
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
    --exclude "state.db-wal" \
    --exclude "state.db-shm" \
    --log-level INFO 2>&1 | tee -a "$LOG"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] S3 restore done." | tee -a "$LOG"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] No S3 credentials found — skipping restore." | tee -a "$LOG"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] To restore from backup, set the following in $HERMES_HOME/.env:" | tee -a "$LOG"
  echo "  S3_ACCESS_KEY=<your_key>" | tee -a "$LOG"
  echo "  S3_SECRET_KEY=<your_secret>" | tee -a "$LOG"
  echo "  S3_ENDPOINT=<s3_endpoint_url>" | tee -a "$LOG"
  echo "  S3_REGION=<region>" | tee -a "$LOG"
  echo "  S3_BUCKET=<bucket_name>" | tee -a "$LOG"
fi

# ── 4. Ensure HERMES_DASHBOARD=1 is set ─────────────────────────────
if ! grep -q "^HERMES_DASHBOARD=" "$HERMES_HOME/.env" 2>/dev/null; then
  echo "HERMES_DASHBOARD=1" >> "$HERMES_HOME/.env"
fi

# ── 5. Start Docker containers via compose ───────────────────────────
if command -v docker &>/dev/null && [ -f "$REPO_DIR/docker-compose.yml" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Hermes container..." | tee -a "$LOG"
  cd "$REPO_DIR"
  docker compose up -d 2>&1 | tee -a "$LOG"

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for Hermes to start..." | tee -a "$LOG"
  for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:8642/health > /dev/null 2>&1; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hermes is ready!" | tee -a "$LOG"
      break
    fi
    sleep 2
  done
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Docker or compose file not found — start containers manually." | tee -a "$LOG"
fi

# ── 6. Configure cron from existing jobs ─────────────────────────────
if [ -f "$HERMES_HOME/cron/jobs.json" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cron jobs found — the scheduler will pick them up automatically." | tee -a "$LOG"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hermes startup script — complete" | tee -a "$LOG"
