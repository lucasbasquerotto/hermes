#!/bin/bash
# Hermes Agent backup script - delegates to generic backup with "data" as dest
set -euo pipefail
cd "$(dirname "$0")"
bash hermes-backup-generic.sh "data"
