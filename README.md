# Hermes Agent — Isolated Vagrant + Docker Deployment

Deploy [Hermes Agent](https://hermes-agent.nousresearch.com) in an isolated VM using Vagrant, with Docker socket access and optional data restore from Backblaze B2.

## Architecture

```
Host Machine (Windows / macOS / Linux)
  └── Vagrant VM (Ubuntu 22.04)
        ├── Docker Engine
        │     └── Hermes Agent container (nousresearch/hermes-agent)
        │           ├── /opt/data          → persistent storage
        │           └── /var/run/docker.sock  → Docker access
        └── /opt/hermes-repo               → this repo cloned at first boot
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
   - Attempts a B2 restore if credentials are available (see below)
   - Starts the Hermes container via `docker compose up -d`
   - Restores cron jobs from the existing `cron/jobs.json`

## Restoring from Backblaze B2

The startup script will restore your Hermes data (skills, config, state DB) from Backblaze B2 if the credentials are present in `/opt/data/.env`.

### Step-by-step

1. **Start the VM** (it will provision but skip the restore):

   ```bash
   vagrant up
   ```

2. **SSH into the VM** and create the credentials file:

   ```bash
   vagrant ssh
   sudo mkdir -p /opt/data
   sudo tee /opt/data/.env << 'EOF'
   BACKBLAZE_KEY_ID=your_key_id
   BACKBLAZE_APPLICATION_KEY=your_app_key
   HERMES_DASHBOARD=1
   EOF
   exit
   ```

3. **Re-run provisioning** to trigger the restore and start Hermes:

   ```bash
   vagrant provision
   ```

Alternative: skip B2 restore entirely and configure Hermes from scratch after it starts.

## Ports

| Port | Service | Access |
|---|---|---|
| 8642 | Gateway API | `http://127.0.0.1:8642` |
| 9119 | Dashboard | `http://127.0.0.1:9119` (requires `HERMES_DASHBOARD=1`) |

Both are only exposed to `127.0.0.1` on the host.

## Customization

| Variable | Default | Where to change |
|---|---|---|
| VM memory | 4096 MB | `Vagrantfile` |
| VM CPUs | 2 | `Vagrantfile` |
| Hermes container memory | 4 GB | `docker-compose.yml` |
| Hermes container CPUs | 2.0 | `docker-compose.yml` |

## Security Notes

- The VM has **no synced folders** — the host filesystem is inaccessible
- Docker socket is mounted → Hermes can run Docker commands inside the VM
- Gateway and dashboard ports are forwarded only to `127.0.0.1` on the host
- SSH agent forwarding is disabled
