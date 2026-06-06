FROM nousresearch/hermes-agent:v2026.5.29.2

USER root

# Install Docker CLI and Docker Compose plugin
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl \
    && install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
    && chmod a+r /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        docker-ce-cli \
        docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Preserve supplementary groups (e.g. docker GID from group_add)
# when s6 drops privileges to the hermes user
RUN sed -i 's/s6-setuidgid hermes/s6-setuidgid -D hermes/g' \
        /opt/hermes/docker/s6-rc.d/main-hermes/run \
        /opt/hermes/docker/s6-rc.d/dashboard/run \
        /opt/hermes/docker/main-wrapper.sh
