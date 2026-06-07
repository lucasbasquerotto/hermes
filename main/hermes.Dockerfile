FROM nousresearch/hermes-agent:v2026.5.29.2

USER root

# Install Docker CLI and Compose from Debian repos
RUN apt-get update && apt-get install -y --no-install-recommends \
        docker.io \
        docker-compose \
    && rm -rf /var/lib/apt/lists/*

# Install sudo, create docker group GID 999 (matching host),
# add hermes to root + docker groups, grant passwordless sudo
RUN apt-get update && apt-get install -y --no-install-recommends sudo \
    && rm -rf /var/lib/apt/lists/* \
    && groupdel docker 2>/dev/null || true \
    && groupadd -g 999 docker \
    && usermod -aG docker,root hermes \
    && echo "hermes ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/hermes \
    && chmod 440 /etc/sudoers.d/hermes

# When HERMES_ALLOW_ROOT_GATEWAY=1, skip s6-setuidgid so the gateway
# runs as root and preserves supplementary groups (e.g. docker GID)
# from group_add. Replaces the original main-wrapper.sh.
COPY main/main-wrapper.sh /opt/hermes/docker/main-wrapper.sh
RUN chmod +x /opt/hermes/docker/main-wrapper.sh

# Install toolbox wrapper script
COPY main/toolbox-wrapper.sh /usr/local/bin/toolbox
RUN chmod +x /usr/local/bin/toolbox
