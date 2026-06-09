#!/bin/bash
# Hermes Agent restore script - delegates to generic restore with "data" as src
set -euo pipefail
cd "$(dirname "$0")"
bash hermes-restore-generic.sh "data"
