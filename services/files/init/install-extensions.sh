#!/bin/bash
# Auto-install extensions on every container start
# This ensures extensions are present even on fresh volumes / new machines
set -e

EXTENSIONS="vscode-icons-team.vscode-icons"

for EXT in $(echo "$EXTENSIONS" | tr ',' ' '); do
  EXT_DIR="/config/.local/share/code-server/extensions/${EXT}*"
  if ! ls $EXT_DIR 1>/dev/null 2>&1; then
    echo "Installing extension: $EXT"
    /app/code-server/bin/code-server --install-extension "$EXT"
  else
    echo "Extension already installed: $EXT"
  fi
done
