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

This pattern is ideal for complex, multi-step, or long commands where inline bash heredocs become fragile with quoting, escaping, and variable interpolation issues.

## Git Operations
The repo is at `github.com/nexuslbs/hermes`.

**Commit & push:**
```bash
/opt/hermes/.venv/bin/python3 /opt/data/gh-final-push.py "fix: describe what changed"
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

### `stats`
Query the host node-exporter via `host.docker.internal:9100` (resolves via `extra_hosts` in toolbox) and return CPU idle % and memory used/total:
```bash
toolbox curl -s http://host.docker.internal:9100/metrics | python3 -c "
import sys, re
data = sys.stdin.read()
idle = sum(float(m) for m in re.findall(r'node_cpu_seconds_total\{[^}]*mode="idle"[^}]*\}\s+([\d.e+\-]+)', data))
all_ = sum(float(m) for m in re.findall(r'node_cpu_seconds_total\{[^}]*\}\s+([\d.e+\-]+)', data))
print(f'CPU Idle: {idle/all_*100:.1f}%' if all_ else 'CPU Idle: N/A')
t = float(re.search(r'node_memory_MemTotal_bytes\s+([\d.e+\-]+)', data).group(1))
a = float(re.search(r'node_memory_MemAvailable_bytes\s+([\d.e+\-]+)', data).group(1))
print(f'Memory: {(t-a)/1e9:.0f} / {t/1e9:.0f} GB ({(t-a)/t*100:.0f}% used)')
"
```

Expected format:
```
CPU Idle: 83.0%
Memory: 2 / 8 GB (23% used)
```

### `ps`
Show a detailed formatted overview using the template below.

<details>
<summary>📊 ps template</summary>

```
📊 Current Stats

Sessions
Active (Telegram DM)
• ID: ...
• Started: 15:56 UTC
• Messages: ongoing
• Tokens: last prompt: 45K

Archived (ghost)
• ID: ...
• Started: 04:09 UTC
• Messages: 0
• Tokens: 23K in / 1.5K out

Active Session Details
- Display: ...
- Last prompt tokens: 45,215
- Estimated cost: ~$0.000006
- Last updated: 20:40 UTC

State DB
- sessions: 1 archived (0 msgs)
- messages: 0
- integrity: ✅ ok

Memory
- agent memories: 7 entries (~2.1 KB)
- user profile: 5 entries (~1.4 KB)

Skills
- total: 96 SKILL.md files across 24 categories

Backup (just ran)
- S3 bucket (B2): 1,917 objects — 173 MiB
- Snapshot state.db: 144 KB
- Last backup log: 37.5s, 3 files transferred, 100%

Disk
- Used: 34 GB / 62 GB (58%)

Services (all healthy)
cadvisor
• Status: ✅ Up (healthy)

files
• Status: ✅ Up

grafana
• Status: ✅ Up

loki
• Status: ✅ Up

prometheus
• Status: ✅ Up

vault
• Status: ✅ Up

vector
• Status: ✅ Up
```
</details>

### `links`
Return 4 bare inline-code URLs (one-tap copyable on Telegram), no labels:

```
`https://hermes-dashboard.mydomain.com`
`https://hermes-grafana.mydomain.com`
`https://hermes-vault.mydomain.com`
`https://hermes-files.mydomain.com`
```

The actual domain is resolved from `GF_SERVER_ROOT_URL` in `/opt/data/credentials/services.env`.

### `logs` / `logs <service>`
Tail the last 50 lines of a service container. Without arguments, shows the `hermes` container:

```bash
# Default: hermes container
docker logs hermes --tail 50 --follow

# Specific service: logs <service>
docker logs hermes-<service> --tail 50
```

### `gitlog`
Show the last 10 commits in the hermes-repo:

```bash
toolbox bash -c 'cd /opt/hermes-repo && git log --oneline -10'
```

### `commit`
Stage all changes, commit with a descriptive message, and push:
```bash
/opt/hermes/.venv/bin/python3 /opt/data/gh-final-push.py "fix: describe what changed"
```


### `backup`
Trigger an ad-hoc backup immediately (run directly, not via toolbox — `/opt/data/` is read-only there):

```bash
bash /opt/hermes-repo/scripts/hermes-backup.sh
```

### `restore`
Restore data from S3 (run directly, not via toolbox — `/opt/data/` is read-only there):

```bash
bash /opt/hermes-repo/scripts/hermes-restore.sh
```

### `session`
Show current session details and token usage:

```bash
python3 << 'PYEOF'
import json, datetime, sqlite3
from pathlib import Path

sfile = Path('/opt/data/sessions/sessions.json')
if sfile.exists():
    with open(sfile) as f:
        data = json.load(f)
    s = list(data.values())[0]
    created = datetime.datetime.fromisoformat(s['created_at'])
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    delta = now - created
    hours = delta.total_seconds() / 3600

    print('📊 Current Session')
    print(f"ID: {s['session_id']}")
    print(f"Created: {s['created_at'][:19]} UTC ({hours:.1f}h ago)")
    print(f"Platform: {s['origin']['platform']} ({s['origin']['chat_type']})")
    ctx = s.get('last_prompt_tokens', '?')
    if isinstance(ctx, int):
        print(f"Context: {ctx:,} / 1,000,000")
    else:
        print(f"Context: {ctx} / 1,000,000")
    print()

db = '/opt/data/state.db'
if Path(db).exists():
    conn = sqlite3.connect(db)
    c = conn.cursor()
    c.execute('SELECT COUNT(*), COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0) FROM sessions')
    count, inp, out = c.fetchone()
    print(f"📦 Archived Sessions")
    print(f"Sessions: {count}")
    print(f"Total tokens: {inp:,} in / {out:,} out")
    conn.close()
PYEOF
```

Expected format:
```
📊 Current Session
ID: 20260607_155613_8521135c
Created: 2026-06-07 15:56:13 UTC (8.0h ago)
Platform: telegram (dm)
Context: 134,467 / 1,000,000

📦 Archived Sessions
Sessions: 1
Total tokens: 23,336 in / 1,499 out
```



### `env`
Show key configuration at a glance:

```bash
# Gathers from state.db, services.env, and .env
echo "Provider: $(grep -m1 'provider:' /opt/hermes-repo/config.yaml 2>/dev/null || echo 'opencode-go')"
echo "Model: $(sqlite3 /opt/data/state.db 'SELECT model FROM sessions ORDER BY started_at DESC LIMIT 1;' 2>/dev/null || echo 'deepseek-v4-flash')"
grep GF_SERVER_ROOT_URL /opt/data/credentials/services.env
df -h /opt/data | tail -1 | awk '{printf "Disk: %s / %s (%s)\n", $3, $2, $5}'
```

Expected format:
```
Provider: opencode-go
Model: deepseek-v4-flash
GF_SERVER_ROOT_URL=https://hermes-grafana.mydomain.com
Disk: 34G / 62G (58%)
```
## When in Doubt

1. Check this file for operational guidance.
2. Check `user-conventions` skill for user preferences.
3. Load relevant skill for the task domain (`skill_view`).
4. If genuinely stuck, ask the user — but try the above first.

