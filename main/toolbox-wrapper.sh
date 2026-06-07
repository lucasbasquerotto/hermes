#!/bin/bash
# Shortcut to run commands inside the hermes-toolbox container
# Compose service name is "toolbox" (container_name: hermes-toolbox)
cd /opt/hermes-repo/ && docker compose exec toolbox "$@"
