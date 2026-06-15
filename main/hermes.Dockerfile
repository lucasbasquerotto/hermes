FROM nousresearch/hermes-agent:v2026.5.29.2

USER root

# Install Docker CLI, Compose, and sqlite3 from Debian repos
RUN apt-get update && apt-get install -y --no-install-recommends \
        docker.io \
        docker-compose \
        sqlite3 \
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

# Install rclone for backup/restore S3 syncs
RUN curl -L https://downloads.rclone.org/rclone-current-linux-amd64.zip -o /tmp/rclone.zip \
    && apt-get update && apt-get install -y --no-install-recommends unzip \
    && rm -rf /var/lib/apt/lists/* \
    && unzip -j /tmp/rclone.zip "*/rclone" -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/rclone \
    && rm /tmp/rclone.zip

# Install hindsight-client for persistent memory support (Hindsight)
# Pinned to match the version in lazy_deps.py (memory.hindsight).
# Force-reinstall transitive deps to work around potential stale/corrupt
# copies of urllib3, yarl, aiohttp, aiohttp-retry in the base image.
RUN uv pip install --python /opt/hermes/.venv/bin/python \
    --reinstall-package urllib3 \
    --reinstall-package yarl \
    --reinstall-package aiohttp \
    --reinstall-package aiohttp-retry \
    'hindsight-client==0.6.1' \
    'websockets>=15'

# Install fastembed for local CPU embedding (Qdrant wiki search, no external API)
RUN uv pip install --python /opt/hermes/.venv/bin/python fastembed

# Install Himalaya CLI for on-demand email reading (login flows)
ARG HIMALAYA_VERSION=1.2.0
RUN curl -sSL "https://github.com/pimalaya/himalaya/releases/download/v${HIMALAYA_VERSION}/himalaya.x86_64-linux.tgz" \
    | tar -xz -C /usr/local/bin/ himalaya \
    && chmod +x /usr/local/bin/himalaya

# When HERMES_ALLOW_ROOT_GATEWAY=1, skip s6-setuidgid so the gateway
# runs as root and preserves supplementary groups (e.g. docker GID)
# from group_add. Replaces the original main-wrapper.sh.
COPY main/main-wrapper.sh /opt/hermes/docker/main-wrapper.sh
RUN chmod +x /opt/hermes/docker/main-wrapper.sh

# Install toolbox wrapper script
COPY main/toolbox-wrapper.sh /usr/local/bin/toolbox
RUN chmod +x /usr/local/bin/toolbox

# Install normalize script — fixes /opt ownership to hermes:hermes
# on every container start (runs from main-wrapper.sh init)
COPY main/normalize.sh /usr/local/bin/normalize
RUN chmod +x /usr/local/bin/normalize
