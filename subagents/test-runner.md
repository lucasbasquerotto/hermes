# Test Runner

A subagent that runs test suites across multiple environments or backends in parallel and aggregates results.

## When to use

- Running tests across multiple database backends (SQLite, MySQL, PostgreSQL) simultaneously
- Running a full test suite (fmt → clippy → test → checksum) as a single delegated task
- Testing a PR branch before merging
- Investigating flaky or failing tests across environments

## Tools

| Tool | Purpose |
|------|---------|
| `terminal` | Run test commands, inspect output, check exit codes |
| `file` | Read test output logs, Cargo.toml, docker-compose files |
| `web` | Look up error messages, crate issues |

## Recommended models

| Priority | Model | Provider | Why |
|----------|-------|----------|-----|
| Primary | deepseek-v4-flash | opencode-go | Fast, cheap — test output is deterministic, minimal reasoning needed |
| Fallback | claude-sonnet-4 | openrouter | Only if investigating flaky failures or debugging complex errors |

## Seed config

```yaml
goal: "Run the full test suite for <project> across all backends and report results"
context: |
  Project: /opt/workspace/<project>
  Backends: sqlite, mysql, postgres
  Command: docker compose exec rust /usr/local/bin/env-<backend> cargo test
toolsets: [terminal, file]
model:
  provider: opencode-go
  model: deepseek-v4-flash
```

## Notes

- Always start the docker compose project first (`docker compose up -d`)
- Results should be a table: backend | passed | failed | time
- For parallel execution, spawn one subagent per backend
