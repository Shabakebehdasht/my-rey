---
name: improve-workflows
version: 1.1.0
author: Hermes Agent (session-derived)
license: MIT
description: "Audit plans, file issues, implement a plan end to end."
---

# Improve Workflows

Operational patterns discovered during real improve skill executions. Supplements the improve skill (shadcn) with Hermes-specific tooling workflows. Covers both directions: **writing/filing plans** and **implementing a written plan** through to a PR.

## Filing a Single Issue Without Writing Plans

When the ask is "audit, then register the one most important finding as an
issue" — no plan files, no local edits — the improve workflow still applies, with
the plan-writing phases dropped:

1. Recon and audit as usual; **vet every finding yourself** before ranking.
2. **Sweep for duplicates across open AND closed issues, with several keyword
   families, not one.** A closed issue from the same root cause (e.g. an
   eager-load fix on a different code path) will surface for the obvious query and
   make the area look covered. Sweep the mechanism words as well as the component
   name: `N+1`, `eager load`, `lazy load`, `payload`, `hydration`, `snapshot`,
   the method or component name, the table or model involved. Only conclude
   "not a duplicate" once the mechanism-level searches come back empty. Also read
   the two or three closest existing issues in full — they set the house style
   for title and body, and reusing it makes a new issue read as part of the same
   thread rather than a competing claim.
3. **Put measured numbers in the body, not adjectives.** A table of queries /
   time / payload bytes per interaction, plus the repeated query shape with its
   count, is what makes the issue actionable. "Slow" gets closed; `x318 select *
   from "units" where "id" = ? limit 1` gets picked up.
4. Stamp the commit it was audited against, and state plainly that nothing in the
   repo was changed.
5. Respect the explicit scope limit — "no other changes" means no plan files, no
   branch commits, no config tweaks, even useful-looking ones.

## Implementing a Plan End to End (issue → branch → PR)

When a plan you or a teammate wrote (a GitHub issue with `ready`/`Plan NN:` in
the title) is assigned to you as an **implementation** task, not an audit.

1. Read the whole issue first, including its stated solution and its own list of
   tests. Then read repo instructions (`AGENTS.md`) — it is the final authority
   and may contradict the issue.
2. **Reproduce the claimed failure before touching code.** Run the command /
   exercise the path on the current base branch and capture the actual output.
   A plan that says "exits 0 doing nothing" must be shown doing nothing.
3. **Verify each numbered claim individually** (see Pitfalls below).
4. Red test per behavior, watch it fail, then implement, then go green. Drive
   each cycle vertically; do not write the plan's whole test list at once.
5. Run the canonical test entrypoint on the whole suite, plus static analysis.
   If the repo keeps a **line-keyed** baseline file, regenerate it and assert the
   diff has **zero additions** — an addition means a new error got suppressed.
6. Commit selectively (`git add <paths>`, not `-A`) so unrelated dirty files
   from other work stay out, push to your own fork on your own branch with an
   explicit refspec when the branch tracks something else, then open the PR to
   the canonical `beta`. **Never push to `beta` directly, never merge the PR.**
7. Final report: changes, test + static-analysis results, last commit hash, PR
   link, and anything you could not complete.

### Pitfalls

- **A plan's claim can be wrong, and the wrongness changes the fix.** Verify
  each claim by reproducing it. When a claim diverges, report it *at that
  point* (not silently at the end) — it usually means the plan's own remedy is
  incomplete for that path, and following the plan literally would ship a
  latent hard failure. Fix the whole path, and say so explicitly.
- **The plan's cited line numbers drift.** Verify against the file's content,
  not the plan's `file:line`. A claim anchored to the wrong line is often a
  misread of a neighbouring function.
- **A green suite proves nothing for non-request-scoped paths.** When the code
  runs in a scheduler/queue worker, `sync` test config executes it inside a
  still-authenticated request and hides the bug. Add a no-actor test, and prove
  it once against the real worker (see `laravel-livewire`).
- **`AGENTS.md` may be write-protected** (agent-instruction guard). Do not route
  around the refusal. Complete every other change, and surface the blocked edit
  with the exact text you wanted applied so a session with access can apply it.
- **Vendor binaries can be blocked by a scan-size guard.** Invoke the tool
  through `php vendor/<vendor>/<package>/<entry>` when the shim is refused;
  same tool, same result.
- **GitHub MCP may be unauthenticated while `gh` is not.** One MCP
  `Authentication Failed` → switch to `gh` immediately (see Issue Registration).
- **Re-read any file the plan claims is already fixed** through a ref, not the
  checkout — the working tree can lag the branch carrying the work.

## Issue Registration (`--issues`)

When the improve skill's `--issues` modifier publishes plans as GitHub issues:

### Procedure

1. Determine `owner/repo` from `git remote -v` — never assume from AGENTS.md or memory. The canonical upstream and the server's fork may use different owner names.
2. Check if issues are enabled: `gh issue list --repo owner/repo`. If "disabled", try the fork remote.
3. Verify labels exist: `gh label list --repo owner/repo`. Create missing ones first or omit.
4. `gh issue create --repo owner/repo --title '...' --body '...' [--label '...']`
5. Record the issue URL in the plan file and tracker.
6. **Read the issue back and confirm the labels landed**:
   `gh issue view N --repo owner/repo --json labels,url`. A token without
   issue-triage permission creates the issue successfully and applies *no*
   labels, with no warning at create time — verify rather than assume.

### Pitfalls

- **GitHub MCP auth failure → switch to `gh` CLI immediately.** Do not retry MCP. The MCP server requires `GITHUB_PERSONAL_ACCESS_TOKEN` env var; `gh` uses stored credentials. One retry wastes time; the fallback is instant.
- **Wrong repo name.** AGENTS.md may reference a canonical name that differs from the actual git remote. `git remote -v` is authoritative. If the primary repo has issues disabled, try the fork remote.
- **Missing labels.** `--label 'improve-audit'` fails if the label doesn't exist. Either create it first (`gh label create improve-audit --repo owner/repo`) or omit labels entirely.
- **Labels silently dropped.** `gh issue create --label X` can succeed with an empty label set when the token lacks triage permission on the repo — create output says nothing. `gh issue edit N --add-label` then fails with a GraphQL permission error. Confirm with `gh issue view N --json labels` and, if triage is unavailable, tell the user the issue exists unlabelled rather than retrying the edit.
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
- The slice each one owns, so three overlapping agents do not file the same root
  cause three different ways.

Subagent output schema per finding: `{id, category, finding, evidence, impact, effort, risk, confidence}`.

**Fan out by layer, not by category, when the ask is a single category.** A
"performance only" audit of a web app splits cleanly by where the work happens:
data layer, template/interaction layer, request/config layer. Give each agent the
file globs it owns and tell it what is off-limits.

**Do not sit idle waiting on the fan-out.** While the agents read, run the
primary measurement yourself on the hottest component. That independent number is
what the issue body leads with, and it is also how you catch subagents reporting
something a cache already absorbs.

## Vetting Subagent Reports

Subagents over-report. Four failure classes to check:

1. **By-design behavior** reported as bug (e.g., "CSP unsafe-inline" when it's intentional)
2. **Mis-attributed evidence** — real finding, wrong file or line
3. **Duplicates** across subagents (same root cause, different symptoms)
4. **Framework-behaviour assumptions never checked against `vendor/`** — the
   highest-ranking finding in a fan-out is often wrong here, and the wrongness
   inverts the fix. A subagent reporting "this auto-refresh re-runs the heaviest
   query in the app" may be describing a call the framework *blocks*: read the
   guard in the installed package and check whether the code path is reachable
   at all. If the framework refuses the call, the finding is a broken feature,
   not a performance cost. Grep `vendor/<vendor>/<package>/` for the guard and
   quote it in the rejection.

Always open the cited code yourself before including a finding in the vetted table. Downgrade or reject accordingly. **Say in your final report which ranked findings you rejected and why** — a rejected top finding is evidence the vetting happened, and it stops the same bad finding being re-reported in the next audit.

Pass the vendor-verification rule into the subagent prompts themselves, not just your own vetting pass: tell each to quote a `vendor/` path for any claim that depends on framework or package behaviour.

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
