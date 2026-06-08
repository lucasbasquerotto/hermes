FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Networking & transfer
    curl wget dnsutils iputils-ping netcat-openbsd traceroute iperf3 \
    # Editors
    vim nano \
    # Data processing
    jq python3 python3-pip \
    # System & monitoring
    htop tmux tree rsync \
    # Compression
    unzip zip xz-utils \
    # Build & dev
    git make gcc build-essential ca-certificates openssh-client gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI and Docker Compose plugin
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get install -y docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Install yq (YAML processor)
RUN ARCH=$(dpkg --print-architecture) && case "$ARCH" in amd64) YQ_ARCH=amd64 ;; arm64) YQ_ARCH=arm64 ;; *) echo "Unsupported arch: $ARCH"; exit 1 ;; esac && wget -q https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${YQ_ARCH} -O /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

CMD ["sleep", "infinity"]
