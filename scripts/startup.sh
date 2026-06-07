#!/bin/bash
# Hermes Agent — first-boot startup script
# Runs inside the Vagrant VM, invoked by the Vagrantfile provisioner.
# Single source of truth for backup/restore: scripts/hermes-backup.sh and scripts/hermes-restore.sh
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

# ── 3. Attempt S3 restore (delegated to repo script) ────────────────
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running restore from S3 backup..." | tee -a "$LOG"
bash "$REPO_DIR/scripts/hermes-restore.sh" 2>&1 | tee -a "$LOG" || true

# Restore may delete cron/output/ (rclone --delete-excluded removes excluded dirs)
mkdir -p "$HERMES_HOME/cron/output"

# ── 4. Ensure HERMES_DASHBOARD=1 is set ─────────────────────────────
if ! grep -q "^HERMES_DASHBOARD=" "$HERMES_HOME/.env" 2>/dev/null; then
  echo "HERMES_DASHBOARD=1" >> "$HERMES_HOME/.env"
fi

# ── 5. Start Docker containers via compose ───────────────────────────
if command -v docker &>/dev/null && [ -f "$REPO_DIR/docker-compose.yml" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting Hermes container..." | tee -a "$LOG"
  cd "$REPO_DIR"
  docker compose up -d 2>&1 | tee -a "$LOG"

  # Also start monitoring services (Grafana, Prometheus, cAdvisor, Loki)
  if [ -d "$REPO_DIR/services" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting monitoring services..." | tee -a "$LOG"
    cd "$REPO_DIR/services"
    docker compose up -d 2>&1 | tee -a "$LOG"
    cd "$REPO_DIR"
  fi

  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for Hermes to start..." | tee -a "$LOG"
  for i in $(seq 1 30); do
    if curl -sf http://127.0.0.1:8642/health > /dev/null 2>&1; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hermes is ready!" | tee -a "$LOG"
      break
    fi
    sleep 2
  done

  # ── 6. Restore Grafana database from backup (if exists) ──────────────
  if [ -f "$HERMES_HOME/backup/grafana/grafana.db" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Grafana db backup found — restoring..." | tee -a "$LOG"
    docker stop hermes-grafana 2>&1 | tee -a "$LOG"
    docker cp "$HERMES_HOME/backup/grafana/grafana.db" hermes-toolbox:/tmp/data/grafana/grafana.db 2>&1 | tee -a "$LOG"
    docker exec hermes-toolbox chown 472:0 /tmp/data/grafana/grafana.db 2>&1 | tee -a "$LOG"
    docker start hermes-grafana 2>&1 | tee -a "$LOG"
    cd "$REPO_DIR/services"
    docker compose exec -T grafana cp /tmp/data/grafana/grafana.db /var/lib/grafana/grafana.db 2>&1 | tee -a "$LOG"
    cd "$REPO_DIR"
    docker restart hermes-grafana 2>&1 | tee -a "$LOG"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Grafana db restore done." | tee -a "$LOG"
  fi

  # ── 7. Provision Grafana dashboards ─────────────────────────────────
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Provisioning Grafana dashboards..." | tee -a "$LOG"
  GRAFANA_URL="http://localhost:3000"   bash "$REPO_DIR/scripts/provision-grafana-dashboards.sh" 2>&1 | tee -a "$LOG" || true
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Docker or compose file not found — start containers manually." | tee -a "$LOG"
fi

# ── 8. Configure cron from existing jobs ─────────────────────────────
if [ -f "$HERMES_HOME/cron/jobs.json" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cron jobs found — the scheduler will pick them up automatically." | tee -a "$LOG"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Fixing /opt/data ownership..."
chown -R 10000:10000 "$HERMES_HOME"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Hermes startup script — complete" | tee -a "$LOG"
