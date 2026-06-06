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
    git make gcc build-essential ca-certificates openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install yq (YAML processor)
RUN wget -q https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

CMD ["sleep", "infinity"]
