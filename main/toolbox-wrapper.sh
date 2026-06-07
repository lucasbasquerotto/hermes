#!/bin/bash
# Shortcut to run commands inside the hermes-toolbox container
cd /opt/hermes-repo/ && docker compose exec hermes-toolbox "$@"
