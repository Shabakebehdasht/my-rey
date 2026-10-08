---
name: improve-workflows
version: 1.0.0
author: Hermes Agent (session-derived)
license: MIT
description: "Audit plan-writing and issue registration workflows."
---

# Improve Workflows

Operational patterns discovered during real improve skill executions. Supplements the improve skill (shadcn) with Hermes-specific tooling workflows.

## Issue Registration (`--issues`)

When the improve skill's `--issues` modifier publishes plans as GitHub issues:

### Procedure

1. Determine `owner/repo` from `git remote -v` — never assume from AGENTS.md or memory. The canonical upstream and the server's fork may use different owner names.
2. Check if issues are enabled: `gh issue list --repo owner/repo`. If "disabled", try the fork remote.
3. Verify labels exist: `gh label list --repo owner/repo`. Create missing ones first or omit.
4. Create: `gh issue create --repo owner/repo --title '...' --body '...' [--label '...']`
5. Record the issue URL in the plan file and tracker.

### Pitfalls

- **GitHub MCP auth failure → switch to `gh` CLI immediately.** Do not retry MCP. The MCP server requires `GITHUB_PERSONAL_ACCESS_TOKEN` env var; `gh` uses stored credentials. One retry wastes time; the fallback is instant.
- **Wrong repo name.** AGENTS.md may reference a canonical name that differs from the actual git remote. `git remote -v` is authoritative. If the primary repo has issues disabled, try the fork remote.
- **Missing labels.** `--label 'improve-audit'` fails if the label doesn't exist. Either create it first (`gh label create improve-audit --repo owner/repo`) or omit labels entirely.
- **Bulk issue registration (10+ plans).** Use `cronjob_manage` with `schedule: 'every 5m'` and `repeat: N` instead of creating all issues in one turn. Track progress in `plans/tracker.json` (JSON array with `done: boolean`, `plan_file`, `issue_url` fields per finding). Set `deliver` to the user's home channel for status updates.

## Subagent Audit Pattern

For the `standard` effort level (default), fan out with 4 parallel subagents:

1. **Correctness & Security** — input validation, auth/authz, SQL injection, XSS, race conditions
2. **Performance & Architecture** — N+1 queries, unbounded recursion, cache misuse, God classes
3. **Test Coverage & Quality** — untested critical paths, wrong annotations, DRY violations
4. **Tech Debt & DX** — baseline bloat, dead code, CI gaps, documentation

Each subagent prompt must include:
- Recon facts (languages, frameworks, key directories)
- Domain-specific risk hints from recon
- Decided tradeoffs from intent docs
- "Return findings only — no fixes, no file dumps"
- Hard Rules 4 and 6 from the improve skill (verbatim)

Subagent output schema per finding: `{id, category, finding, evidence, impact, effort, risk, confidence}`.

## Vetting Subagent Reports

Subagents over-report. Three failure classes to check:

1. **By-design behavior** reported as bug (e.g., "CSP unsafe-inline" when it's intentional)
2. **Mis-attributed evidence** — real finding, wrong file or line
3. **Duplicates** across subagents (same root cause, different symptoms)

Always open the cited code yourself before including a finding in the vetted table. Downgrade or reject accordingly.

## Plans Directory Structure

```
plans/
  tracker.json              ← queue for automated processing
  README.md                 ← index: priority order, dependency graph, status
  001-<slug>.md
  002-<slug>.md
```

Each plan file stamps the commit hash it was written against (`git rev-parse --short HEAD`).

The `tracker.json` schema:
```json
{
  "last_created": 0,
  "findings": [
    {
      "num": 1,
      "id": "SEC-001",
      "slug": "short-slug",
      "title": "Plan title",
      "category": "security",
      "effort": "M",
      "impact": "high",
      "done": false,
      "plan_file": "plans/001-short-slug.md",
      "issue_url": "https://github.com/.../issues/N"
    }
  ]
}
```
