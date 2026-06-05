# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # ── Base Box ─────────────────────────────────────────────────────────
  config.vm.box = "ubuntu/jammy64"
  config.vm.box_version = "20250528.0.0"

  # ── No Host File Sharing (security) ─────────────────────────────────
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # ── VM Resources ────────────────────────────────────────────────────
  config.vm.provider "virtualbox" do |vb|
    vb.memory = "4096"
    vb.cpus   = 2
    vb.name   = "hermes-agent"
  end

  config.vm.provider "hyperv" do |hv|
    hv.memory = "4096"
    hv.cpus   = 2
    hv.vmname = "hermes-agent"
    hv.enable_enhanced_session_mode = false
  end

  # ── Network ─────────────────────────────────────────────────────────
  # Private network for static IP (reachable from host)
  config.vm.network "private_network", type: "dhcp"

  # Expose gateway & dashboard ports to host
  config.vm.network "forwarded_port", guest: 8642, host: 8642, host_ip: "127.0.0.1"
  config.vm.network "forwarded_port", guest: 9119, host: 9119, host_ip: "127.0.0.1"

  # ── SSH ─────────────────────────────────────────────────────────────
  config.ssh.forward_agent = false
  config.ssh.insert_key = true

  # ── Install Docker Engine + Compose ─────────────────────────────────
  config.vm.provision "shell", name: "install-docker", privileged: true, inline: <<-SHELL
    set -euxo pipefail

    # Install prerequisites
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl

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

  # ── Clone Repo + Run Startup ───────────────────────────────────────
  config.vm.provision "shell", name: "setup-hermes", privileged: true, inline: <<-SHELL
    set -euxo pipefail

    # Install git
    apt-get install -y -qq git

    # Clone this repo (first boot — bootstrap itself)
    if [ ! -d /opt/hermes-repo ]; then
      git clone https://github.com/nexuslbs/hermes.git /opt/hermes-repo
    fi

    # Run the startup script
    bash /opt/hermes-repo/scripts/startup.sh
  SHELL
end
