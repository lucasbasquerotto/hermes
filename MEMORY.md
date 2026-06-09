# Hermes Agent — Repo Memory

This file documents operational patterns the agent must follow when working in this repo. Read this if a command fails, something unexpected happens, or you're unsure how to proceed.

**Note for memory management:** The agent's main memory (MEMORY.md in /opt/data/memories/) has a **permanent first entry** directing to this file. That entry must never be removed during memory trimming or compaction — it is the primary fallback for operational guidance.

## Filesystem Mounts

| Path | In hermes container | In toolbox container |
|------|-------------------|-------------------|
| `/opt/hermes-repo/` | **ro** (read-only) | **rw** (read-write) |
| `/opt/data/` | **rw** | **ro** |
| `/tmp/data/` | **rw** | **rw** |
| `/opt/workspace/` | **ro** (read-only) | **rw** (read-write) |

**Rule:** Always use `toolbox` (wrapper for `docker compose exec toolbox`) for any file writes, git operations, or directory changes under `/opt/hermes-repo/` or `/opt/workspace/`. Run directly (without toolbox) for writes under `/opt/data/`.

## Repo-Specific Notes

- Check [README.md](README.md) for repo-specific information first before making assumptions about behavior or setup.
- The `workspace/` folder in the target machine contains the workspace repo from `$WORKSPACE_REPO`. Defined in `.env` (`WORKSPACE_REPO`).
- At the root of `workspace/`, expect mostly `.gitignore` and `.md` files plus one directory per organization project.
- Each project directory is named after the repository and typically contains `docker-compose.yml`, an optional `base.env`, and an optional `build/` directory for Docker build artifacts such as Dockerfiles.
- The actual cloned repository lives under `workspace/<project>/repo/`.
- A `workspace/<project>/.env` file may also exist with credentials derived from `base.env`.
- `<project>` name must not start with `hermes` to avoid collisions when running it.

## /opt/data/ Ownership

Everything under `/opt/data/` must be owned by the hermes user (UID 10000).
If something is root-owned, fix with:
```bash
docker run --rm -v /opt/data:/opt/data alpine chown -R 10000:10000 /opt/data/<path>
```

## Creating / Editing Files in the Repo or Workspace

Use `toolbox <command>` for any file operations under `/opt/hermes-repo/` or `/opt/workspace/`. Examples:

```bash
# Write a file
toolbox bash -c 'cat > /opt/hermes-repo/path/to/file' << 'EOF'
content
EOF

# Quick inline write
toolbox bash -c 'echo "content" > /opt/hermes-repo/path/to/file'

# Copy files
toolbox cp /opt/data/source /opt/hermes-repo/path/to/dest
```

For **complex scripts** that would be fragile in an inline heredoc (quoting, escaping, interpolation issues), use the `/tmp/data/scripts/` pattern:

```bash
# 1. Write the script to /tmp/data/scripts/ (hermes has /opt/data/ access)
# 2. Make it executable
toolbox chmod +x /tmp/data/scripts/my-script.sh
# 3. Run it — toolbox has rw access to repo & workspace
toolbox /tmp/data/scripts/my-script.sh
```

The toolbox runs as **root** (UID 0). The hermes container runs as UID **10000**. After creating files via toolbox, they may need `chown` if the hermes container needs to read them from a shared volume.

### ⚠️ The `patch` Tool Limitation

The `patch` tool (Hermes built-in find-and-replace, `mode='replace'`) runs inside the **hermes container** — where `/opt/hermes-repo/` and `/opt/workspace/` are **read-only**. Using `patch` on files in those paths produces:

```
Read-only file system
```

This error has occurred repeatedly. **Always use `terminal()` → `toolbox`** (via bash heredoc or the `/tmp/data/scripts/` pattern) to edit files in the repo or workspace. The `patch` tool works correctly for files under `/opt/data/` — the only path that is read-write in the hermes container.

## /tmp/data/ — Inter-Container Bridge

`/tmp/data/` is shared **read-write** between both the `hermes` and `toolbox` containers — the only path both can access. Use it as an intermediary for file transfer between containers.

**Permission notes:**
- Toolbox runs as **root** (UID 0), hermes runs as **10000**
- Files written by toolbox (root) in `/tmp/data/` are unwritable by hermes (uid 10000)
- Files written by hermes (10000) in `/tmp/data/` are unwritable by toolbox (root)

**Fixing permissions:**
```bash
toolbox chown -R 10000:10000 /tmp/data/
```

**Smart script pattern** (avoids heredoc quoting issues):
```bash
# 1. Write script to /tmp/data/scripts/ (hermes container can write here)
toolbox bash -c 'mkdir -p /tmp/data/scripts'
# 2. Make executable and run
toolbox chmod +x /tmp/data/scripts/my-script.sh
toolbox /tmp/data/scripts/my-script.sh
```

This pattern is ideal for complex, multi-step, or long commands where inline bash heredocs become fragile with quoting, escaping, and interpolation issues.

## Git Operations

The repos are at:
- `github.com/nexuslbs/hermes` → `/opt/hermes-repo/`
- `github.com/nexuslbs/hermes-workspace` → `/opt/workspace/`

### Remote URL

`origin` remote uses the clean HTTPS URL (no embedded auth — avoids wasted API calls on accidental pushes).

All pushes use an inline token URL — never push to `origin` directly.

### Push script (minimal GitHub API calls)

```bash
# Hermes repo
/opt/hermes/.venv/bin/python3 /opt/data/gh-push.py /opt/hermes-repo https://github.com/nexuslbs/hermes.git

# Workspace repo
/opt/hermes/.venv/bin/python3 /opt/data/gh-push.py /opt/workspace https://github.com/nexuslbs/hermes-workspace.git
```

The script:
1. Generates a GH App installation token (1 API call)
2. Pushes with inline token URL (1 API call)
3. Fetches tracking ref so `git status` stays accurate (1 API call)

Total: ~2-3 GitHub API calls — no wasted requests.

### Identity

- `user.name = $GIT_USER` (default: `Hermes Agent`)
- `user.email = $GIT_USER_EMAIL` (default: `hermes@nexuslbs.io`)
Set per-repo via `git config user.name/user.email`. There is NO global git config. NEVER use `hermes@nousresearch.com` — that email is verified under a different GitHub user and causes incorrect attribution.

## Gitignore Convention

The root `.gitignore` must be minimal. Avoid redundant entries — e.g., `/tmp/` already covers everything under `/tmp/`, so `/tmp/data/restore/` is unnecessary.

## Backup & Restore Scripts

- `scripts/hermes-backup-generic.sh <dest>` — generic backup to S3 under `bucket/<dest>/`. Handles sqlite snapshots, grafana/vault/hindsight dumps, then rclone syncs `/opt/data/` to S3. Used by both backup and checkpoint.
- `scripts/hermes-restore-generic.sh <src>` — generic restore from S3 under `bucket/<src>/`. Syncs down, then restores state.db, grafana, vault, and hindsight.
- `scripts/hermes-backup.sh` — daily backup wrapper, calls `hermes-backup-generic.sh data`. Runs via cron at 5AM UTC.
- `scripts/hermes-restore.sh` — restore from `data/` prefix, calls `hermes-restore-generic.sh data`.

All scripts share the same exclude list (`.cache/`, `.npm/`, `home/.local/**`, `lsp/`, `logs/`, `sessions/`, etc.) and use `rclone sync --delete-excluded` to keep S3 clean.

**Checkpoint:** `scripts/hermes-backup-generic.sh checkpoint/$(date +%Y%m%d)` creates a full snapshot under a date-stamped prefix. This is an expensive operation (full data duplication) — only run on explicit request.

## Credentials

- Manual credentials: `credentials/` directory
- Auto-generated tokens: `credentials/auto/` — use `gh-app-token.py` for GH App tokens
- Vault creds: `credentials/vault.env`
- Vault URL: `http://hermes-vault:8200` (file backend, `services/` compose file)
- Hostinger email: `credentials/.env` — `HOSTINGER_APP_PASSWORD` for IMAP/SMTP auth
- Himalaya config reads from `credentials/.env` via `grep|cut|tr`, never embedded

**Golden rule — never embed secrets in commands, configs, or chat:**
- Source credentials from files via `grep | cut | tr` — never pass as CLI args or variables
- If referencing a credential in chat, show at most the last 4 chars — preferably none
- Tool output goes to Telegram, so any credential visible in output leaks to the chat

## Subagent / ACP Pattern

- Provider: opencode-go
- Model: deepseek-v4-flash
- Sub-agents have NO memory of the parent conversation — pass all context explicitly via `delegate_task(context=...)`
- Sub-agent summaries are self-reported and may be wrong — verify external side effects

## External Repos

Non-`nexuslbs` repos must be forked under the `nexuslbs` org first — never write or PR to the original upstream directly.

## Container Management

- **Start:** `docker compose up -d` in `/opt/hermes-repo/services/`
- **Stop (shorthand):** stop all containers **except** `hermes`, `hermes-toolbox`, `hermes-tunnel`, `hermes-hindsight`
- Hermes services: `hermes-loki`, `hermes-prometheus`, `hermes-grafana`, `hermes-vector`, `hermes-vault`, `hermes-files`, `hermes-cadvisor`

## Fast Actions — Quick Command Reference

These are shorthand commands the agent uses when the user says these keywords:

### `start`
```bash
cd /opt/hermes-repo/services && docker compose up -d
```

### `stop`
Stop all containers **except** `hermes`, `hermes-toolbox`, `hermes-tunnel`, `hermes-hindsight`:
```bash
docker ps --format '{{.Names}}' | grep -v -E '^(hermes(-toolbox|-tunnel|-hindsight)?)$' | xargs -r docker stop
```

### `restart`
Restart the hermes container (runs from toolbox — outside, avoids self-destruction):
```bash
toolbox docker restart hermes
```

### `build`
Rebuild and start the hermes container:
```bash
toolbox bash -c 'docker compose up -d --build hermes'
```

### `stats`
Query the host node-exporter via `host.docker.internal:9100` and return CPU idle % and memory used/total:
```bash
toolbox curl -s http://host.docker.internal:9100/metrics | python3 -c "
import sys, re
data = sys.stdin.read()
idle = sum(float(m) for m in re.findall(r'node_cpu_seconds_total\{[^}]*mode=\"idle\"[^}]*\}\s+([\d.e+\-]+)', data))
all_ = sum(float(m) for m in re.findall(r'node_cpu_seconds_total\{[^}]*\}\s+([\d.e+\-]+)', data))
print(f'CPU Idle: {idle/all_*100:.1f}%' if all_ else 'CPU Idle: N/A')
t = float(re.search(r'node_memory_MemTotal_bytes\s+([\d.e+\-]+)', data).group(1))
a = float(re.search(r'node_memory_MemAvailable_bytes\s+([\d.e+\-]+)', data).group(1))
print(f'Memory: {(t-a)/1e9:.0f} / {t/1e9:.0f} GB ({(t-a)/t*100:.0f}% used)')
"
```

### `ps`
Show docker containers with formatted status.

### `links`
Return 4 bare inline-code URLs (one-tap copyable on Telegram), no labels.

The actual domain is resolved from `GF_SERVER_ROOT_URL` in `/opt/data/credentials/services.env`.

### `logs` / `logs <service>`
Tail the last 50 lines of a service container. Without arguments, shows the `hermes` container.

### `gitlog`
Show the last 10 commits in the hermes-repo:
```bash
toolbox bash -c 'cd /opt/hermes-repo && git log --oneline -10'
```

### `commit`
Check both repos (hermes-repo and workspace) for unpushed commits. If found, push each with `gh-push.py`:
```bash
# Hermes repo
/opt/hermes/.venv/bin/python3 /opt/data/gh-push.py /opt/hermes-repo https://github.com/nexuslbs/hermes.git
# Workspace repo
/opt/hermes/.venv/bin/python3 /opt/data/gh-push.py /opt/workspace https://github.com/nexuslbs/hermes-workspace.git
```

If uncommitted changes exist, stage and commit first with:
```bash
toolbox bash -c 'cd /opt/hermes-repo && git add -A && git -c user.name=\"Hermes Agent\" -c user.email=hermes@nexuslbs.io commit -m \"feat: description\"'
```

### `backup`
```bash
bash /opt/hermes-repo/scripts/hermes-backup.sh
```

### `restore`
```bash
bash /opt/hermes-repo/scripts/hermes-restore.sh
```

### `restore checkpoint <YYYYMMDD>`
```bash
bash /opt/hermes-repo/scripts/hermes-restore-generic.sh "checkpoint/<YYYYMMDD>"
```

### `checkpoint`
```bash
bash /opt/hermes-repo/scripts/hermes-backup-generic.sh "checkpoint/$(date +%Y%m%d)"
```

### `session`
Show current session details and token usage from state.db.

### `env`
Show key configuration at a glance (provider, model, disk, services URL).

### `wiki`
Review the current session and update the Obsidian wiki (`/opt/data/wiki/`) with information worth persisting since the last update.

## When in Doubt

1. Check this file for operational guidance.
2. Check `user-conventions` skill for user preferences.
3. Load relevant skill for the task domain (`skill_view`).
4. If genuinely stuck, ask the user — but try the above first.

## Container Restarts (Cross-Container Pattern)

Never restart your own container directly — it kills the agent mid-session. Always restart from **outside**:

- **Restart hermes:** `toolbox docker restart hermes`
- **Restart toolbox:** `docker restart hermes-toolbox`
