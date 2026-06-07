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

This pattern is ideal for complex, multi-step, or long commands where inline bash heredocs become fragile with quoting, escaping, and variable interpolation issues.

## Git Operations

The repo is at `github.com/nexuslbs/hermes`.

**Commit workflow:**
```bash
toolbox bash -c '
  cd /opt/hermes-repo && \
  git add <files> && \
  git commit -m "message"'
```

**Push workflow** (requires GitHub App token — pipe via stdin to avoid env issues):
```bash
source /opt/data/credentials/auto/gh-auth.sh
echo "$GITHUB_TOKEN" | toolbox bash -c '
  read TOKEN
  cd /opt/hermes-repo && \
  ORIGIN_URL=$(git remote get-url origin) && \
  git remote set-url origin "https://x-access-token:${TOKEN}@github.com/nexuslbs/hermes.git" && \
  git push origin main && \
  git remote set-url origin "$ORIGIN_URL"'
```

**Git identity:**
- `user.name = Hermes Agent`
- `user.email = hermes@nexuslbs.io`

Set per-repo via `git config user.name/user.email`. There is NO global git config. NEVER use `hermes@nousresearch.com` — that email is verified under a different GitHub user and causes incorrect attribution.

## Gitignore Convention

The root `.gitignore` must be minimal. Avoid redundant entries — e.g., `/tmp/` already covers everything under `/tmp/`, so `/tmp/data/restore/` is unnecessary.

## Backup & Restore Scripts

- `scripts/hermes-backup.sh` — daily backup to S3 (B2 bucket). Runs via cron at 5AM UTC.
- `scripts/hermes-restore.sh` — restore from S3. Uses `/tmp/hermes-restore-*.log` for logging (outside rclone exclude paths).

Both scripts share the same exclude list (`.cache/`, `.npm/`, `lsp/`, `logs/`, `sessions/`, etc.) and use `rclone sync --delete-excluded` to keep S3 clean.

## Credentials

- Manual credentials: `credentials/` directory
- Auto-generated tokens: `credentials/auto/`
- Vault creds: `credentials/vault.env`
- Vault URL: `http://hermes-vault:8200` (file backend, `services/` compose file)
- Temp creds: `/tmp/data/credentials/` — copy to `credentials/` for persistence, clean up temp after

**Never embed secret values in chat responses.** Show masked/shortened values (last 4 chars) unless explicitly told otherwise.

## Subagent / ACP Pattern

- Provider: opencode-go
- Model: deepseek-v4-flash
- Sub-agents have NO memory of the parent conversation — pass all context explicitly via `delegate_task(context=...)`
- Sub-agent summaries are self-reported and may be wrong — verify external side effects

## External Repos

- Fork under `nexuslbs` org first before making any changes
- Never write/PR directly to original upstream repos
- Exception: `nexuslbs/*` repos and B2 bucket are safe — no approval needed

## Container Management

- **Start:** `docker compose up -d` in `/opt/hermes-repo/services/`
- **Stop (shorthand):** stop all containers **except** `hermes`, `hermes-toolbox`, `hermes-tunnel`
- Hermes services: `hermes-loki`, `hermes-prometheus`, `hermes-grafana`, `hermes-vector`, `hermes-vault`, `hermes-files`, `hermes-cadvisor`

## When in Doubt

1. Check this file for operational guidance.
2. Check `user-conventions` skill for user preferences.
3. Check relevant skill for the task domain.
4. If genuinely stuck, ask the user — but try the above first.
