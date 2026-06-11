#!/bin/sh
# normalize — fix ownership of /opt to hermes:hermes
# Called during container initialization to ensure all files under /opt
# are owned by the hermes user, regardless of how they were created
# (e.g., by root during image build or by bind-mount preservation).
echo "$(date +%T) Normalizing permissions..."
sudo chown -R hermes:hermes /opt/data
sudo chown -R hermes:hermes /opt/hermes-repo
sudo chown -R hermes:hermes /opt/workspace
echo "$(date +%T) Permissions normalized..."
