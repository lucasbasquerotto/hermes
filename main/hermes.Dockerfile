FROM nousresearch/hermes-agent:v2026.5.29.2

USER root

# Install Docker CLI and Compose from Debian repos
RUN apt-get update && apt-get install -y --no-install-recommends \
        docker.io \
        docker-compose \
    && rm -rf /var/lib/apt/lists/*

# Create docker group with GID 999 (matching host) and add hermes user
# so docker.sock access works through group_add in docker-compose.yml
RUN groupadd -g 999 dockerhost && usermod -aG 999 hermes

# When HERMES_ALLOW_ROOT_GATEWAY=1, skip s6-setuidgid so the gateway
# runs as root and preserves supplementary groups (e.g. docker GID)
# from group_add. Replaces the original main-wrapper.sh.
COPY main/main-wrapper.sh /opt/hermes/docker/main-wrapper.sh
RUN chmod +x /opt/hermes/docker/main-wrapper.sh
