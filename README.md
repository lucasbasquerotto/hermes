# Hermes Agent — Isolated Vagrant + Docker Deployment

Deploy [Hermes Agent](https://hermes-agent.nousresearch.com) in an isolated VM using Vagrant, with Docker socket access and optional data restore from Backblaze B2.

## Architecture

```
Host Machine
  └── Vagrant VM (Ubuntu 22.04)
        ├── Docker Engine
        │     └── Hermes Agent container (nousresearch/hermes-agent)
        │           ├── /opt/data      → persistent storage
        │           └── /var/run/docker.sock  → Docker access
        └── /opt/hermes-repo           → this repo cloned at first boot
```

**No synced folders** — the VM is fully isolated from the host filesystem by default.

## Requirements

- [Vagrant](https://www.vagrantup.com/downloads) (supports VirtualBox or Hyper-V)
- [VirtualBox](https://www.virtualbox.org/) or Hyper-V enabled on Windows
- 4 GB RAM + 2 vCPUs available for the VM

## Quick Start

```bash
git clone https://github.com/nexuslbs/hermes.git
cd hermes
vagrant up
```

On first boot, the VM will:

1. Install Docker Engine + Compose
2. Clone this repo to `/opt/hermes-repo`
3. Run [`scripts/startup.sh`](scripts/startup.sh) which:
   - Attempts a B2 restore if `.env` contains `BACKBLAZE_KEY_ID` / `BACKBLAZE_APPLICATION_KEY`
   - Starts the Hermes container via `docker compose up -d`
   - Restores cron jobs from the existing `cron/jobs.json`

## Restoring from Backblaze B2

Before `vagrant up`, create `/opt/data/.env` on the **host** with your B2 credentials (the Vagrantfile does not sync this — you must create it inside the VM after boot, or inject it via a separate provisioner):

```bash
vagrant ssh
sudo mkdir -p /opt/data
sudo tee /opt/data/.env << 'EOF'
BACKBLAZE_KEY_ID=your_key_id
BACKBLAZE_APPLICATION_KEY=your_app_key
HERMES_DASHBOARD=1
EOF
exit
vagrant provision
```

Or run the startup manually after placing the `.env`:

```bash
vagrant ssh
sudo bash /opt/hermes-repo/scripts/startup.sh
```

## Customization

| Variable | Default | Description |
|---|---|---|
| VM memory | 4096 MB | Edit in `Vagrantfile` |
| VM CPUs | 2 | Edit in `Vagrantfile` |
| Hermes container memory | 4 GB | Edit in `docker-compose.yml` |
| Hermes container CPUs | 2.0 | Edit in `docker-compose.yml` |

## Security Notes

- The VM has **no synced folders** — the host filesystem is inaccessible
- Docker socket is mounted → Hermes can run Docker commands inside the VM
- Gateway and dashboard ports are forwarded only to `127.0.0.1` on the host
- SSH agent forwarding is disabled
