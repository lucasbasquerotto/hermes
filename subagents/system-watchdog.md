# System Watchdog

A subagent that monitors system health, backup status, container states, and sends alerts when thresholds are breached.

## When to use

- Checking disk usage and alerting when above a threshold
- Verifying backup/restore integrity after a cycle
- Monitoring container health across all services
- Checking S3 backup sync freshness
- Running periodic health checks (cron-driven)

## Tools

| Tool | Purpose |
|------|---------|
| `terminal` | Run df, docker ps, sqlite3 PRAGMA, rclone check |
| `cronjob` | Schedule recurring health checks |
| `send_message` | Send alerts/notifications to Telegram |

## Recommended models

| Priority | Model | Provider | Why |
|----------|-------|----------|-----|
| Primary | deepseek-v4-flash | opencode-go | Cheap, fast — most watchdog output is deterministic data collection |

## Seed config

```yaml
# Cron-driven watchdog (no_agent mode is ideal for most checks)
goal: "Check system health every 6 hours and alert if anything is wrong"
context: |
  Thresholds:
    Disk: < 85% used
    State DB: PRAGMA integrity_check must return "ok"
    Containers: all expected services must be "Up"
    Backup: last backup must be < 28 hours old
toolsets: [terminal, cronjob, send_message]
model:
  provider: opencode-go
  model: deepseek-v4-flash
```

## Notes

- For simple threshold checks, use `no_agent: true` in cron with a bash/Python script
- Only involve the LLM when data needs interpretation or a notification needs drafting
- Common checks: disk, container states, state.db integrity, backup freshness, vault seal status
