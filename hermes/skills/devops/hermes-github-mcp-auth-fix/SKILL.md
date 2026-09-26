---
name: hermes-github-mcp-auth-fix
description: Fix GitHub MCP "Authentication Failed" in Hermes.
license: MIT
author: Hermes Agent
version: 1.0.0
metadata:
  hermes:
    tags: [github, mcp, auth, troubleshooting, git]
    related_skills: [github, hermes-agent]
---

# Fix Hermes GitHub MCP "Authentication Failed"

## When to Use

- Any `mcp__github__*` tool returns `MCPError: Authentication Failed` or
  `Requires authentication`.
- `gh auth status` succeeds but GitHub MCP calls fail.
- After adding a GitHub token to the Hermes env file, the MCP still fails
  (it will not recover without a gateway restart — go straight to the `gh`
  fallback below).

## Symptom

Any `mcp__github__*` tool returns:

```
MCPError: Authentication Failed: Requires authentication
```

## Cause

The `github` server entry in the Hermes config passes the token through an
`--env` argument that references a shell-style variable placeholder. That
placeholder resolves from the Hermes env file, which may define the token under
a *different* name than the one the config references. When the referenced name
is absent, the server starts with an empty token and every call fails auth —
even though `gh` on the same box works fine.

Diagnose which name actually exists (check the Hermes env file, not the shell —
the shell may have it exported and hide the real gap):

```bash
gh auth status          # is the CLI authenticated at all?
grep -oE '^[A-Z_]+=' ~/.hermes/.env | tr -d '='
```

If the CLI is authenticated but the MCP is not, the env file is the problem.

## Fix

Add an alias line to the Hermes env file, copying the value of the key that
*is* present. Keep both — other tooling may read either name.

**Do not hand-edit `config.yaml`.** Its own guidance is explicit: a stray indent
can corrupt the live gateway, and `hermes config set` cannot express a nested
list argument. Fixing the env file resolves the placeholder without touching
the config.

## The MCP will not recover in the current session

The server process captured the (empty) token at startup. Editing the env file
does not re-inject it — a gateway restart is required.

## Fallback: use `gh` now, do not block on the restart

`gh` is already authenticated with the `repo` scope, so cross-fork pull
requests work:

```bash
gh pr create --repo <upstream-owner>/<repo> \
  --base <upstream-branch> --head <fork-owner>:<branch> \
  --title "..." --body-file /tmp/pr-body.md
```

Prefer this over declaring the task blocked. Verify afterwards with
`gh pr view <n> --json state,baseRefName,headRefName,mergeable,url` and confirm
the head repo owner is the fork, not the upstream.

## Why this matters

Treating a failing tool as "unavailable" and reporting a blocker loses the work.
The auth failure is an environment gap with a two-line fix plus a working CLI
fallback. Diagnose before reporting.
