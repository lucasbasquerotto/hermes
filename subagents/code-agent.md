# Code Agent

A subagent that implements features, fixes bugs, and manages PRs across repos.

## When to use

- Forking an external repo under the <your-org> org, making changes, and opening a PR
- Implementing a feature described in an issue or plan
- Running code review gates (lint, security scan, type check) before committing
- Multi-step git workflows (branch → commit → push → PR)

## Tools

| Tool | Purpose |
|------|---------|
| `terminal` | Clone, build, test, run git/gh commands |
| `file` | Read/write source files, inspect project structure |
| `web` | Look up API docs, crate references, error solutions |
| `skills` | Load project-specific skills (e.g. `sql-forge-development`) |
| `search` | Search codebase for patterns and references |

## Recommended models

| Priority | Model | Provider | Why |
|----------|-------|----------|-----|
| Primary | deepseek-v4-flash | opencode-go | Good balance of speed and code quality |
| Fallback | claude-sonnet-4 | openrouter | Better at complex logic, PR descriptions |

## Seed config

```yaml
goal: "Implement <feature> from <issue/plan>"
context: |
  Repo: <org/repo>
  Changes needed: <summary>
  Branch: <name>
toolsets: [terminal, file, web, skills, search]
model:
  provider: opencode-go
  model: deepseek-v4-flash
```

## Notes

- External repos must be forked under <your-org> first — never PR to upstream directly
- After completion, verify the PR link exists before reporting success
