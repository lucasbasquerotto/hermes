#!/bin/bash
# code-server startup wrapper — ensures extensions are present on every start
set -e

for EXT in vscode-icons-team.vscode-icons; do
  echo "[startup] Ensuring extension: $EXT"
  /app/code-server/bin/code-server --install-extension "$EXT"     --extensions-dir /config/extensions 2>&1 |     grep -v "DeprecationWarning\|url.parse\|already installed"
done

exec /init
