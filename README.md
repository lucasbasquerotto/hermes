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
   S3_BUCKET=your-s3-bucket-name  # Set this to your actual S3-compatible bucket
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



## Environment Configuration - `/opt/data/`

The `opt-data-example/` directory in this repo shows the structure of files expected under `/opt/data/` at runtime. Copy this directory as a starting point and fill in your values:

```bash
cp -r opt-data-example /opt/data
```

### `opt-data-example/.env`

This is the main configuration file loaded by Hermes and the startup scripts. Some variables can be set before first run; others must be generated after the environment is already running.

| Variable | When to set | Description |
|----------|------------|-------------|
| `TELEGRAM_BOT_TOKEN` | Before setup | Bot token from @BotFather. Required for Telegram connectivity. |
| `TELEGRAM_ALLOWED_USERS` | Before setup | Comma-separated Telegram user IDs allowed to interact. |
| `TELEGRAM_HOME_CHANNEL` | Before setup | Telegram channel/chat ID for default message delivery. |
| `OPENCODE_GO_API_KEY` | Optional* | API key for the opencode-go provider (DeepSeek models). At least one provider must be configured. |
| `GITHUB_APP_ID` | Before setup | GitHub App ID (numeric). Required for Hermes to authenticate with GitHub. |
| `GITHUB_INSTALLATION_ID` | Before setup | GitHub App installation ID. Generated when installing the app in your org. |
| `GOOGLE_API_KEY` | Optional* | Google API key for provider backends. At least one provider must be configured. |
| `S3_BUCKET` | Before setup | S3 bucket name for backup (Backblaze B2, AWS S3, MinIO). |
| `S3_ENDPOINT` | Before setup | S3 endpoint URL. |
| `S3_REGION` | Before setup | S3 region. |
| `S3_ACCESS_KEY` | Before setup | S3 access key ID. |
| `S3_SECRET_KEY` | Before setup | S3 secret access key. |
| `HERMES_DASHBOARD` | Before setup | Set to 1 to enable the web dashboard on port 9119. |
| `HINDSIGHT_API_URL` | Before setup | URL for the local Hindsight memory service. Default: http://hermes-hindsight:8888. |
| `HINDSIGHT_API_LLM_PROVIDER` | Before setup | LLM provider for Hindsight embeddings (e.g. gemini, openai). |
| `HINDSIGHT_API_LLM_MODEL` | Before setup | Model name for Hindsight embeddings (e.g. gemini-2.5-flash). |
| `HINDSIGHT_API_LLM_BASE_URL` | Optional | Custom base URL for the Hindsight LLM provider. Leave empty for default. |
| `HINDSIGHT_API_LLM_API_KEY` | Before setup | API key for the Hindsight LLM provider. |

\* **At least one provider must be active.** You can configure providers and models interactively after Hermes is running:

```bash
cd /opt/hermes-repo && docker compose exec hermes hermes model
```

This command lets you choose a provider and model, and enter the required API key directly. The keys in `.env` are an alternative way to provide credentials that are picked up automatically at startup.

### `opt-data-example/credentials/services.env`

Grafana-specific environment variables for the monitoring stack.

| Variable | When to set | Description |
|----------|------------|-------------|
| `GF_SERVER_DOMAIN` | Before setup | Public domain for Grafana (e.g. hermes-grafana.mydomain.com). |
| `GF_SERVER_ROOT_URL` | Before setup | Full URL for Grafana (e.g. https://hermes-grafana.mydomain.com). |

### `opt-data-example/credentials/.env`

HashiCorp Vault credentials, merged into the shared credentials file. **Must be generated after Vault is already initialized and running** — the values do not exist beforehand.

Vault is used as a convenient way to pass development secrets to projects that Hermes runs in `workspace/`. For example, when asking Hermes to fork a repo, run tests, or improve code, the project may need API keys or database credentials. These are stored in Vault and accessed at runtime (e.g. via `https://hermes-vault.mydomain.com`).

This file also holds other manual secrets (e.g. Twilio, Hostinger). Add the vault variables alongside them:

```env
# Vault secrets (manual reference only — NOT consumed by containers)
VAULT_ROOT_TOKEN=
VAULT_SINGLE_KEY=
```

**Security note:** Be mindful of which secrets you store in this environment. Any secret here is accessible to Hermes, and a misconfiguration or AI hallucination could expose it. Prefer dev-only secrets with limited blast radius. Avoid including secrets that are costly or dangerous (production credentials, cloud provider admin keys, etc.) in this project entirely.

### `opt-data-example/credentials/tunnel.env`

Cloudflare Tunnel configuration for exposing services via Cloudflare Zero Trust.

| Variable | When to set | Description |
|----------|------------|-------------|
| `TUNNEL_TOKEN` | Before setup | Cloudflare Tunnel token. Only needed if using Cloudflare Tunnel. |

The Cloudflare Tunnel service is **optional**. It is not required if your instance has a fixed public IP and you can manage DNS directly. Use it when:

- Running on a **local machine** (home, office) that needs to be accessible from the internet via a specific domain
- Running on a **hosted server** where you want to avoid managing SSL/TLS certificates manually - Cloudflare handles that automatically

If you do not need either scenario, leave this file empty or skip the tunnel container.

### `opt-data-example/credentials/nexuslbs-app.2026-06-04.private-key.pem`

GitHub App private key (PEM file). Required for Hermes to authenticate as a GitHub App and manage repositories.

**Important:**
- The GitHub App **must be organization-scoped/restricted** to your GitHub organization (not user-wide). This ensures the app can only access repos within your org.
- Generate from: **GitHub Settings - Developer Settings - GitHub Apps - your app - Generate a private key**.
- The filename includes the date it was generated and your org name (e.g. `your-app.2026-06-04.private-key.pem`). The actual file name may differ from the example — use whatever you named it.
- The example file (`nexuslbs-app.2026-06-04.private-key.pem`) is intentionally empty - place the actual PEM in `/opt/data/credentials/`.
- **Never commit the actual PEM file** to the repository.

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

---

---

## Operations Guide

*This section provides operational context used by the Hermes agent when working in this repo. The agent considers the entire README as reference, but this section covers the day-to-day patterns specific to this deployment.*

### Filesystem Mounts

| Path | Hermes container | Notes |
|------|-----------------|-------|
| `/opt/hermes-repo/` | **rw** | Repo root — write directly |
| `/opt/data/` | **rw** | Persistent config, scripts, state |
| `/opt/workspace/` | **rw** | Workspace projects |
| `/tmp/data/` | **rw** | Shared scratch space |

All mounts are **read-write**. Use `write_file`/`patch` directly — no `toolbox` needed for file operations. If ownership is ever wrong, run `normalize` (fast action) to fix it.

### Repo Layout

- `workspace/` folder in the target machine contains the workspace repo from `$WORKSPACE_REPO` (defined in `.env`).
- At the root of `workspace/`, expect mostly `.gitignore` and `.md` files plus one directory per project.
- Each project directory is named after the repository and typically contains `docker-compose.yml`, an optional `base.env`, and an optional `build/` directory for Docker build artifacts.
- The actual cloned repository lives under `workspace/<project>/repo/`.
- A `workspace/<project>/.env` file may also exist with credentials derived from `base.env`.

### /opt/data/ Ownership

Everything under `/opt/data/` must be owned by the hermes user (UID 10000). If something is root-owned, run the `normalize` fast action or manually:

```bash
sudo chown -R hermes:hermes /opt
```

### Git Operations

Repos:
- `github.com/nexuslbs/hermes` → `/opt/hermes-repo/`
- `github.com/nexuslbs/hermes-workspace` → `/opt/workspace/`
- `github.com/nexuslbs/playground` → `/opt/workspace/playground/repo`

**Remote URL:** `origin` uses the clean HTTPS URL (no embedded auth). All pushes use an inline token URL via the push script.

**Push script (minimal GitHub API calls):**

```bash
# Hermes repo
/opt/hermes/.venv/bin/python3 /opt/data/gh-push.py /opt/hermes-repo https://github.com/nexuslbs/hermes.git

# Workspace repo
/opt/hermes/.venv/bin/python3 /opt/data/gh-push.py /opt/workspace https://github.com/nexuslbs/hermes-workspace.git
```

The script generates a GH App token (1 API call), pushes (1 API call), fetches tracking ref (1 API call). Total: ~2-3 calls.

**Identity:** Sourced from `/opt/data/credentials/.env` — `GIT_NAME=Hermes`, `GIT_EMAIL=hermes@nexuslbs.org`. Set per-repo via `git config`. NEVER use `hermes@nousresearch.com` — that email is verified under a different GitHub user (Rafa-Ross) causing incorrect attribution.

### Gitignore Convention

The root `.gitignore` must be minimal. Avoid redundant entries — e.g., `/tmp/` already covers everything under `/tmp/`, so `/tmp/data/restore/` is unnecessary.

### Backup & Restore

- `scripts/hermes-backup-generic.sh <dest>` — generic backup to S3 under `bucket/<dest>/`. Handles sqlite snapshots, grafana/vault/hindsight dumps, then rclone syncs `/opt/data/` to S3. Used by both backup and checkpoint.
- `scripts/hermes-restore-generic.sh <src>` — generic restore from S3 under `bucket/<src>/`. Syncs down, then restores state.db, grafana, vault, and hindsight.
- `scripts/hermes-backup.sh` — daily backup wrapper, calls `hermes-backup-generic.sh data`. Runs via cron at 5AM UTC.
- `scripts/hermes-restore.sh` — restore from `data/` prefix, calls `hermes-restore-generic.sh data`.

All scripts share the same exclude list (`.cache/`, `.npm/`, `home/.local/**`, `lsp/`, `logs/`, `sessions/`, etc.) and use `rclone sync --delete-excluded` to keep S3 clean.

**Checkpoint:** `scripts/hermes-backup-generic.sh checkpoint/$(date +%Y%m%d)` creates a full snapshot under a date-stamped prefix. Expensive (full data duplication) — only run on explicit request.

### Credentials

- Manual credentials: `credentials/` directory
- Auto-generated tokens: `credentials/auto/` — use `gh-app-token.py` for GH App tokens
- Vault creds: `credentials/.env`
- Vault URL: `http://hermes-vault:8200` (file backend, `services/` compose file)
- Hostinger email: `credentials/.env` — `HOSTINGER_APP_PASSWORD` for IMAP/SMTP auth
- Himalaya config reads from `credentials/.env` via `grep|cut|tr`, never embedded

**Golden rule — never embed secrets in commands, configs, or chat:**
- Source credentials from files via `grep | cut | tr` — never pass as CLI args or variables
- If referencing a credential in chat, show at most the last 4 chars — preferably none
- Tool output goes to Telegram, so any credential visible in output leaks to the chat

### Container Management

- **Start:** `docker compose up -d` in `/opt/hermes-repo/services/`
- **Stop (shorthand):** stop all containers **except** `hermes`, `hermes-toolbox`, `hermes-tunnel`, `hermes-hindsight`
- Hermes services: `hermes-loki`, `hermes-prometheus`, `hermes-grafana`, `hermes-vector`, `hermes-vault`, `hermes-files`, `hermes-cadvisor`

**Never restart your own container directly** — it kills the agent mid-session. Always restart from outside:
- **Restart hermes:** `toolbox docker restart hermes`
- **Restart toolbox:** `docker restart hermes-toolbox`

### Subagent / ACP Pattern

- Provider: opencode-go
- Model: deepseek-v4-flash
- Sub-agents have NO memory of the parent conversation — pass all context explicitly via `delegate_task(context=...)`
- Sub-agent summaries are self-reported and may be wrong — verify external side effects

### External Repos

Non-`nexuslbs` repos must be forked under the `nexuslbs` org first — never write or PR to the original upstream directly.

### When in Doubt

1. Check this README for operational guidance.
2. Check `user-conventions` skill for user preferences.
3. Load relevant skill for the task domain (`skill_view`).
4. If genuinely stuck, ask the user — but try the above first.

