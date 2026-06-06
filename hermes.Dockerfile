FROM nousresearch/hermes-agent:v2026.5.29.2

USER root

# Install Docker CLI and Compose from Debian repos
RUN apt-get update && apt-get install -y --no-install-recommends \
        docker.io \
        docker-compose-v2 \
    && rm -rf /var/lib/apt/lists/*

# Preserve supplementary groups (e.g. docker GID from group_add)
# when s6 drops privileges to the hermes user
RUN sed -i 's/s6-setuidgid hermes/s6-setuidgid -D hermes/g' \
        /opt/hermes/docker/s6-rc.d/main-hermes/run \
        /opt/hermes/docker/s6-rc.d/dashboard/run \
        /opt/hermes/docker/main-wrapper.sh
