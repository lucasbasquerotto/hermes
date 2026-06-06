#!/bin/bash
# Provision Grafana dashboards from grafana.com via API
# Called during startup — no large JSON files in the repo
set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"

dashboards=(
  "14282:Cadvisor exporter"    # needs DS_PROMETHEUS → Prometheus fix
  "1860:Node Exporter Full"    # works as-is
)

for entry in "${dashboards[@]}"; do
  id="${entry%%:*}"
  name="${entry##*:}"

  echo "→ Downloading dashboard $id ($name)..."

  json=$(curl -fsSL "https://grafana.com/api/dashboards/$id/revisions/latest/download")

  if [ "$id" = "14282" ]; then
    echo "  Fixing DS_PROMETHEUS → Prometheus for dashboard $id..."
    json="${json//\$\{DS_PROMETHEUS\}/Prometheus}"
  fi

  # Wrap in Grafana import payload
  payload=$(cat <<PAYLOAD
{
  "dashboard": $json,
  "overwrite": true,
  "inputs": []
}
PAYLOAD
  )

  echo "  Importing into Grafana..."
  code=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$payload" \
    "$GRAFANA_URL/api/dashboards/import"

  if [ "$code" = "200" ]; then
    echo "  ✓ Dashboard '$name' imported"
  else
    echo "  ⚠ Dashboard '$name' returned HTTP $code (may already exist)"
  fi
done

echo "✓ Dashboard provisioning complete"
