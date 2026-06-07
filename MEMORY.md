# Hermes Agent — Repo Memory

This file documents operational patterns the agent must follow when working in this repo. Read this if a command fails, something unexpected happens, or you're unsure how to proceed.

## Filesystem Mounts

| Path | In hermes container | In toolbox container |
|------|-------------------|-------------------|
| `/opt/hermes-repo/` | **ro** (read-only) | **rw** (read-write) |
| `/opt/data/` | **rw** | Not mounted |
| `/tmp/data/` | **rw** (after `chown 10000:10000`) | **rw** |

**Rule:** Always use `docker exec hermes-toolbox` for any file writes, git operations, or directory changes under `/opt/hermes-repo/`.

## Creating / Editing Files in the Repo

1. Write to a temp path or use heredoc on the host, then:
   ```
   docker cp /opt/data/myfile hermes-toolbox:/opt/hermes-repo/path/to/target
   ```
   Or pipe directly:
   ```
   docker exec hermes-toolbox bash -c 'cat > /opt/hermes-repo/path/to/file' << 'EOF'
   content
   EOF
   ```

2. The toolbox runs as **root** (UID 0). The hermes container runs as UID **10000**. After creating files via toolbox, they may need `chown` if the hermes container needs to read them from a shared volume.

## /tmp/data/ Shared Volume

`/tmp/data/` is a root-owned directory shared between hermes and toolbox containers. To make it writable by the hermes user:

```
docker exec hermes-toolbox chown 10000:10000 /tmp/data/
```

Use this for passing files between containers (e.g., creating a script in toolbox, reading result in hermes).

## Git Operations

The repo is at `github.com/nexuslbs/hermes`.

**Commit workflow:**
```
docker exec hermes-toolbox bash -c '
  cd /opt/hermes-repo && \
  git add <files> && \
  git commit -m "message"'
```

**Push workflow** (requires GitHub App token):
```
source /opt/data/credentials/auto/gh-auth.sh
docker exec -e GITHUB_TOKEN=*** hermes-toolbox bash -c '
  cd /opt/hermes-repo && \
  ORIGIN_URL=$(git remote get-url origin) && \
  git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/nexuslbs/hermes.git" && \
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
