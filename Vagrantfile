# -*- mode: ruby -*-
# vi: set ft=ruby :*

require 'yaml'

config_file = File.exist?(File.join(__dir__, 'config.yml')) ? YAML.load_file(File.join(__dir__, 'config.yml')) : {}

VM_MEMORY = config_file.dig('vm', 'memory') || 4096
VM_CPUS   = config_file.dig('vm', 'cpus')   || 2
VM_DISK   = config_file.dig('vm', 'disk')   || "50GB"

Vagrant.configure("2") do |config|
  # ── Base Box ─────────────────────────────────────────────────────────
  config.vm.box = "generic/ubuntu2204"

  # ── No Host File Sharing (security) ─────────────────────────────────
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # ── VM Resources ────────────────────────────────────────────────────
  config.vm.provider "virtualbox" do |vb|
    vb.memory = VM_MEMORY.to_s
    vb.maxmemory = VM_MEMORY.to_s
    vb.cpus   = VM_CPUS
    vb.name   = "hermes-agent"
  end

  config.vm.provider "hyperv" do |hv|
    hv.memory = VM_MEMORY.to_s
    hv.maxmemory = VM_MEMORY.to_s
    hv.cpus   = VM_CPUS
    hv.vmname = "hermes-agent"
    hv.enable_enhanced_session_mode = false
  end

  # ── Network ─────────────────────────────────────────────────────────
  # Private network for DHCP IP (VirtualBox only — Hyper-V uses its default switch)
  config.vm.provider "virtualbox" do |_vb, override|
    override.vm.network "private_network", type: "dhcp"
  end

  # ── SSH ─────────────────────────────────────────────────────────────
  config.ssh.forward_agent = false
  config.ssh.insert_key = true

  # ── Fix Hermes Data Folder ──────────────────────────────────────────
  config.vm.provision "shell", name: "fix-hermes-folder", privileged: true, inline: <<-SHELL
    echo "Setting up /opt/data for the Hermes container..."

    # 1. Create the hermes group with GID 10000 if it does not exist
    if ! getent group hermes > /dev/null 2>&1; then
      echo "Creating hermes group (GID 10000)..."
      groupadd -g 10000 hermes
    fi

    # 2. Add the vagrant user to the hermes group
    echo "Adding vagrant user to the hermes group..."
    usermod -aG hermes vagrant

    # 3. Create the data directory and fix ownership/permissions
    mkdir -p /opt/data
    chown -R 10000:10000 /opt/data
    chmod -R 755 /opt/data

    echo "Hermes environment setup completed successfully!"
  SHELL

  # ── Install Docker Engine + Compose ─────────────────────────────────
  config.vm.provision "shell", name: "install-docker", privileged: true, inline: <<-SHELL
    set -euxo pipefail

    # Install prerequisites
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl git

    # Add Docker's official GPG key and repository
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine, CLI, containerd, and Compose plugin
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add vagrant user to docker group (so non-sudo docker works)
    usermod -aG docker vagrant

    # Enable and start Docker
    systemctl enable docker
    systemctl start docker

    # Verify installation
    docker --version
    docker compose version
  SHELL

  # ── Disable Buildx Default Attestations ────────────────────────────────────────────
  config.vm.provision "shell", name: "disable-buildx-attestations", privileged: true, inline: <<-SHELL
    # Prevent buildx from adding provenance/sbom attestations by default
    # (avoids multi-platform errors and speeds up builds)

    # For vagrant user (non-sudo shell)
    echo "export BUILDX_NO_DEFAULT_ATTESTATIONS=1" >> /home/vagrant/.bashrc

    # System-wide (available to all users, including sudo)
    grep -q "^BUILDX_NO_DEFAULT_ATTESTATIONS=" /etc/environment 2>/dev/null \
      || echo "BUILDX_NO_DEFAULT_ATTESTATIONS=1" >> /etc/environment

    # Preserve through sudo (env_keep)
    grep -q "BUILDX_NO_DEFAULT_ATTESTATIONS" /etc/sudoers 2>/dev/null \
      || echo "Defaults env_keep += \"BUILDX_NO_DEFAULT_ATTESTATIONS\"" >> /etc/sudoers
  SHELL

  # ── Install Node Exporter (host metrics for Prometheus) ──────────────
  config.vm.provision "shell", name: "install-node-exporter", privileged: true, inline: <<-SHELL
    set -euxo pipefail

    VERSION="1.8.2"
    ARCH="linux-amd64"
    FILENAME="node_exporter-${VERSION}.${ARCH}"
    URL="https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/${FILENAME}.tar.gz"

    if [ ! -f /usr/local/bin/node_exporter ]; then
      cd /tmp
      curl -fsSL "$URL" -o node_exporter.tar.gz
      tar xzf node_exporter.tar.gz
      cp "${FILENAME}/node_exporter" /usr/local/bin/node_exporter
      rm -rf "${FILENAME}" node_exporter.tar.gz
    fi

    # Create node_exporter user
    id -u node_exporter &>/dev/null || useradd -rs /bin/false node_exporter

    # Systemd unit
    cat > /etc/systemd/system/node_exporter.service << 'UNIT'
[Unit]
Description=Prometheus Node Exporter
After=network.target

[Service]
Type=simple
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter \
  --web.listen-address=:9100 \
  --path.rootfs=/ \
  --collector.systemd \
  --collector.processes
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

    systemctl daemon-reload
    systemctl enable --now node_exporter
  SHELL

  # ── Clone Repo + Run Startup ───────────────────────────────────────
  config.vm.provision "shell", name: "setup-hermes", privileged: true, inline: <<-SHELL
    set -euxo pipefail

    # Add a brief pause for network stability (Docker restart can briefly
    # disrupt systemd-resolved, causing transient DNS failures)
    sleep 2

    # Clone this repo (first boot — bootstrap itself)
    if [ ! -d /opt/hermes-repo ]; then
      git clone https://github.com/nexuslbs/hermes.git /opt/hermes-repo
    fi

    # Run the startup script
    bash /opt/hermes-repo/scripts/startup.sh
  SHELL
end
