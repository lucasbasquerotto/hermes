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

# ── 2. Attempt B2 restore (optional, user provides key) ──────────────
if [ -f "$HERMES_HOME/.env" ] && grep -q "^BACKBLAZE_APPLICATION_KEY=" "$HERMES_HOME/.env" 2>/dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] B2 credentials found — attempting restore..." | tee -a "$LOG"

  # Source credentials
  source "$HERMES_HOME/.env"

  # Check if rclone exists (if not, download it)
  RCLONE=$(command -v rclone || true)
  if [ -z "$RCLONE" ]; then
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
    RCLONE="/usr/local/bin/rclone"
  fi

  # Build rclone config from env
  cat > /tmp/rclone-b2.conf << EOF
[nexuslbs-b2]
type = b2
account = ${BACKBLAZE_KEY_ID}
key = ${BACKBLAZE_APPLICATION_KEY}
EOF

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Downloading data from B2..." | tee -a "$LOG"
  $RCLONE --config /tmp/rclone-b2.conf sync "nexuslbs-b2:hermes-nexuslbs/data" "$HERMES_HOME" \
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

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] B2 restore done." | tee -a "$LOG"
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] No B2 credentials found — skipping restore." | tee -a "$LOG"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] To restore from backup, set BACKBLAZE_KEY_ID and BACKBLAZE_APPLICATION_KEY in $HERMES_HOME/.env" | tee -a "$LOG"
fi

# ── 3. Ensure .env has HERMES_DASHBOARD=1 ─────────────────────────────
if ! grep -q "^HERMES_DASHBOARD=" "$HERMES_HOME/.env" 2>/dev/null; then
  echo "HERMES_DASHBOARD=1" >> "$HERMES_HOME/.env"
fi

# ── 4. Start Docker containers via compose ───────────────────────────
if command -v docker &>/dev/null && [ -f "$REPO_DIR/docker-compose.yml" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Hermes container..." | tee -a "$LOG"
  cd "$REPO_DIR"
  docker compose up -d 2>&1 | tee -a "$LOG"

  # Wait for Hermes to be ready
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

# ── 5. Configure cron from existing jobs ─────────────────────────────
if [ -f "$HERMES_HOME/cron/jobs.json" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cron jobs found — the scheduler will pick them up automatically." | tee -a "$LOG"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hermes startup script — complete" | tee -a "$LOG"
