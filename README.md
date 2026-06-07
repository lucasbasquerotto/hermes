# Hermes Agent — Isolated Vagrant + Docker Deployment

Deploy [Hermes Agent](https://hermes-agent.nousresearch.com) in an isolated VM using Vagrant, with Docker socket access and optional data restore from S3-compatible storage (Backblaze B2, AWS S3, MinIO, etc.).

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
- 8 GB RAM + 2 vCPUs available for the VM

## Quick Start

```bash
git clone https://github.com/nexuslbs/hermes.git
cd hermes
vagrant up
```

> **Hyper-V users:** run `vagrant up --provider hyperv` instead.

On first boot, the VM will:

1. Install Docker Engine + Compose
2. Clone this repo to `/opt/hermes-repo`
3. Run [`scripts/startup.sh`](scripts/startup.sh) which:
   - Attempts an S3 restore if credentials are present (see below)
   - Starts the Hermes container via `docker compose up -d`
   - Restores cron jobs from the existing `cron/jobs.json`

## Restoring from S3 Backup

The startup script will restore your Hermes data (skills, config, state DB, .env, credentials) from any S3-compatible storage if the credentials are present in `/opt/data/.env`.

The flow is: `vagrant up` provisions the VM and starts Hermes **raw** (fresh, no restore). Then you add the `.env` file manually, and re-run the provisioner — this time the startup script finds the credentials and pulls your data from S3.

### Step-by-step

1. **Start the VM.** Vagrant runs the provisioners immediately, so Hermes starts raw (no restored data yet):

   > **Hyper-V users:** `vagrant up --provider hyperv`

   ```bash
   vagrant up
   ```

2. **SSH into the VM** and create the credentials file:

   ```bash
   vagrant ssh
   sudo mkdir -p /opt/data
   sudo nano /opt/data/.env
   ```

   > You can use any text editor (nano, vim, vi, etc.). Paste the following variables:

   ```env
   S3_ACCESS_KEY=your_s3_access_key
   S3_SECRET_KEY=your_s3_secret_key
   S3_ENDPOINT=https://s3.us-east-005.backblazeb2.com
   S3_REGION=us-east-005
   S3_BUCKET=hermes-nexuslbs
   HERMES_DASHBOARD=1
   ```

   Save and exit, then return to your host shell:

   ```bash
   exit
   ```

3. **Re-run provisioning.** The startup script now finds `.env` with valid S3 credentials and restores your data:

   ```bash
   vagrant provision
   ```

Alternative: skip S3 restore entirely and configure Hermes from scratch after it starts.

### Supported S3 Providers

| Provider | Example Endpoint | Notes |
|----------|-----------------|-------|
| Backblaze B2 | `https://s3.<region>.backblazeb2.com` | Region: `us-east-005` (default for this repo), `us-west-001`, etc. |
| AWS S3 | `https://s3.<region>.amazonaws.com` | e.g. `us-east-1`, `eu-west-1` |
| MinIO | `http://<host>:9000` | Any value (e.g. `us-east-1`) |
| GCP Cloud Storage | Use S3-compatible interop endpoint | — |

For **Backblaze B2**, generate S3-compatible credentials:
1. Go to B2 Dashboard → **App Keys**
2. **Add a New Application Key** (do NOT use the Master Key — create a dedicated one)
3. Save and copy the generated key ID and secret — all non-master keys work with the S3 API automatically
4. **Recommended bucket type:** Private & Encrypted (not Public)



## Environment Configuration — `/opt/data/`

The `opt-data-example/` directory in this repo shows the structure of files expected under `/opt/data/` at runtime. Copy this directory as a starting point and fill in your values:

```bash
cp -r opt-data-example /opt/data
```

### `opt-data-example/.env`

This is the main configuration file loaded by Hermes and the startup scripts.

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_BOT_TOKEN` | Depends | Bot token from @BotFather. Required for Telegram connectivity. |
| `TELEGRAM_ALLOWED_USERS` | Depends | Comma-separated Telegram user IDs allowed to interact. |
| `TELEGRAM_HOME_CHANNEL` | Depends | Telegram channel/chat ID for default delivery. |
| `OPENCODE_GO_API_KEY` | Yes | API key for opencode-go provider (DeepSeek models). |
| `GITHUB_APP_ID` | Yes | GitHub App ID (numeric). Required for GitHub auth. |
| `GITHUB_INSTALLATION_ID` | Yes | GitHub App installation ID. Generated when installing the app. |
| `GOOGLE_API_KEY` | No | Google API key for provider backends. |
| `S3_BUCKET` | No | S3 bucket name for backup (Backblaze B2, AWS S3, MinIO). |
| `S3_ENDPOINT` | No | S3 endpoint URL. |
| `S3_REGION` | No | S3 region. |
| `S3_ACCESS_KEY` | No | S3 access key ID. |
| `S3_SECRET_KEY` | No | S3 secret access key. |
| `HERMES_DASHBOARD` | No | Set to 1 to enable web dashboard on port 9119. |

### `opt-data-example/credentials/services.env`

Grafana-specific environment variables.

| Variable | Required | Description |
|----------|----------|-------------|
| `GF_SERVER_DOMAIN` | Yes | Public domain for Grafana (e.g. hermes-grafana.mydomain.com). |
| `GF_SERVER_ROOT_URL` | Yes | Full URL for Grafana (e.g. https://hermes-grafana.mydomain.com). |

### `opt-data-example/credentials/tunnel.env`

Cloudflare Tunnel token for exposing services.

| Variable | Required | Description |
|----------|----------|-------------|
| `TUNNEL_TOKEN` | No | Cloudflare Tunnel token. Only needed for Cloudflare Tunnel. |

### `opt-data-example/credentials/vault.env`

HashiCorp Vault credentials. **Set up after Vault is initialized and running.** Vault starts in dev mode by default (no auth required). For production, configure Vault manually and add these values.

| Variable | Required | Description |
|----------|----------|-------------|
| `VAULT_ROOT_TOKEN` | Yes (prod) | Vault root token. Generated by `vault operator init`. |
| `VAULT_SINGLE_KEY` | Yes (prod) | Vault unseal key. Generated during Vault initialization. |

### `opt-data-example/credentials/my-github-app.2026-06-04.private-key.pem`

GitHub App private key (PEM file). Required for Hermes to authenticate as a GitHub App and manage repositories.

**Important:**
- The GitHub App **must be organization-scoped/restricted** to your GitHub organization (not user-wide). This ensures the app can only access repos within your org.
- Generate from: GitHub Settings -> Developer Settings -> GitHub Apps -> your app -> Generate a private key.
- The example file is intentionally empty -- place the actual PEM in `/opt/data/credentials/`.

## Ports

| Port | Service | Access |
|---|---|---|
| 8642 | Gateway API | `http://127.0.0.1:8642` |
| 9119 | Dashboard | `http://127.0.0.1:9119` (requires `HERMES_DASHBOARD=1`) |

Both are only exposed to `127.0.0.1` on the host.

## Customization

| Variable | Default | Where to change |
|---|---|---|
| VM memory | 8192 MB | `Vagrantfile` |
| VM CPUs | 2 | `Vagrantfile` |
| Hermes container memory | 4 GB | `docker-compose.yml` |
| Hermes container CPUs | 2.0 | `docker-compose.yml` |

## Security Notes

- The VM has **no synced folders** — the host filesystem is inaccessible
- Docker socket is mounted → Hermes can run Docker commands inside the VM
- Gateway and dashboard ports are forwarded only to `127.0.0.1` on the host
- SSH agent forwarding is disabled
- S3 credentials are stored in `/opt/data/.env` (inside the VM, backed up to S3)

## Verification

Repository last tested: 2026-06-06. Push pipeline working.