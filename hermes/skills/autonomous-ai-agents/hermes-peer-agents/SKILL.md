---
name: hermes-peer-agents
description: "Wake and message remote Hermes peer agents."
version: 1.1.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [hermes, peers, multi-agent, gh-workflows, cron, orchestration]
    category: autonomous-ai-agents
---

# Hermes Peer Agents

## When to Use

The user names a peer agent (Kimya, Sevda, Sonia, Kylie, or anything in
`hermes peer list`) and asks to wake it, start it, message it, or send it
something once it is up. Also use when the user hands over a specific
`my-*` GitHub Actions workflow to run for an agent.

Peer inventory (peer → repo → workflow file) lives in
`references/peer-registry.md` — read it, do not guess the repo or the
`.yml` filename. It also holds ready-to-send message templates.

## Standing rules

- **One run per machine, ever.** A peer repo is a whole machine: its run
  claims the tailscale hostname and syncs `hermes/` state back to the repo at
  shutdown. Two concurrent runs on one repo collide. Before ANY dispatch
  (including inside a scheduled job) check run state, and if a run is already
  `in_progress`, do NOT dispatch — the peer is already awake.
- **A deferred job must never re-dispatch a wake.** When the wake already
  happened in this conversation, the scheduled job's prompt is DM-only. Give
  the job the message text and the peer names, never `gh workflow run`.
  Scheduling "after N minutes, then tell them X" is a message, not a second
  wake.
- A peer's API server only answers while its workflow run is alive. Order is
  always: wake first, then DM. A DM to a sleeping peer is a delivery error.
- Preflight once per batch, in one call: `gh auth status` and
  `hermes peer list`. Auth failure or an unregistered peer is fixed before
  dispatching anything.
- Fire every wake dispatch in ONE terminal call (loop over pairs). A single
  call returns every run URL; splitting them costs a round trip per peer and
  lets a mid-batch failure hide earlier successes.
- Never report a wake as done without the printed run URL — that URL is the
  only evidence the dispatch landed.
- One offline peer must never abort the batch. Continue to the next peer and
  report the failure.
- Never sleep or poll inside a foreground turn waiting for a peer to boot.
  See "Deferred work" below.

## Waking peers

```bash
scripts/peer-run-state.sh                            # conflicts first
gh workflow run <workflow>.yml -R <owner>/<repo>      # prints the run URL
```

The workflow file `on:` block is `workflow_dispatch:` ONLY — nothing else
re-triggers these runs, so a run you did not dispatch still needs explaining
(check `event` and `actor` with `gh api .../actions/runs/<id>`).

## Messaging peers

```bash
hermes peer dm <peer> "<message>"     # prints the peer's reply
```

- Exit code 0 = delivered; non-zero = not delivered. Read the reply, it is
  usually the payload the user wants back.
- A peer that was just woken may still be booting. Retry up to 3 times with
  ~20s gaps inside the same call; after that, report `hermes peer list` state
  and move on.
- Long or multi-paragraph message text (especially non-Latin): keep it in a
  scratch file and pass `"$(cat file)"` so quoting survives and the text can
  be edited without re-typing the whole command.

## Deferred work

When the user says "after N minutes, when they're up, tell them X": do NOT
block the turn and do NOT hand-compute a timestamp. Schedule a one-shot job.

```bash
hermes cron create "in 10m" "$(cat /path/prompt.md)" \
  --name <slug> --deliver origin --repeat 1
hermes cron list        # verify: job id + next-run timestamp
```

The job runs in a FRESH session with no chat context, so its prompt must be
self-contained: the peer names, the exact message text, the retry policy, and
the instruction to report per-peer success/failure and quote the replies
briefly. Tell it not to stop the batch on one failure.

## Pitfalls

### A double dispatch already happened — recover, don't re-dispatch

If two runs show `in_progress` on one repo, cancel the NEWER run and keep the
older one running (the older already holds the hostname and is further along):

```bash
gh run cancel <newer-run-id> -R <owner>/<repo>
```

`gh run cancel` is asynchronous — the run still reports `in_progress` for a
few seconds. Re-list after ~15s to confirm it flipped to
`completed cancelled`, and report the surviving run id per peer. Then say
plainly what caused the duplicate (an over-broad job prompt) so the next
session does not repeat it.

A run concluding `cancelled` is NOT evidence the peer is up: cancelled runs
are the normal state of the previous machine's shutdown step. Only
`in_progress` counts as awake.

### Persian text is rejected by `hermes cron create`

Prompt validation blocks invisible Unicode, and Persian typing naturally emits
ZWNJ (U+200C) inside words like `حافظه‌ی` / `می‌کند`. Strip U+200C, U+200E,
U+200F, U+200B, U+2060, U+FEFF (replace ZWNJ with a plain space) before
creating the job; the surface meaning is unchanged and the prompt is accepted.
Write the prompt to a file first so this is a one-line fix on retry.

### `cronjob_manage` through the deferred-tool layer

`tool_call` needs `calls` as an array of `{name, arguments}` objects; a
malformed nesting surfaces as `'...' is not a known tool name`. Do not
burn turns re-shaping it — `hermes cron create` is the same scheduler, runs
from the terminal, and is always available. Use it directly.

## Verification

- `scripts/peer-run-state.sh` exits clean: at most one `in_progress` run per
  repo. Run it before reporting any wake batch as good.
- `hermes cron list` shows the job `[active]` with a next-run timestamp for
  every deferred job created this session.
- Every wake reported to the user carries its run URL.
- Report the job id to the user so the schedule can be inspected or cancelled.
- When the user says "stop cron", run `hermes cron list` and report what it
  actually shows. A fired one-shot job removes itself, so an empty list means
  the job already completed — say that instead of hunting for it.
