---
name: hermes-peer-agents
description: "Wake and message remote Hermes peer agents."
version: 1.2.0
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
- For a batch, use `scripts/peer-dm-batch.sh peer:file ...` instead of hand
  looping: it retries, prints the peer's reply, and does not abort on one
  offline peer.

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

## Assigning work items to peers

When the user hands over a list of numbered work items (issues, plans, tickets)
and says "give each one to one of the kids and stay on it until it's done":

1. Read the items BEFORE assigning, batched in one call, so the split matches
   real scope. A number in an upstream repo may be an issue, not a PR:
   `gh pr view N` fails with a GraphQL "Could not resolve to a PullRequest"
   that reads like an auth error. Fall back to
   `gh issue view N --json number,title,state,author,labels,url,body`.
2. Give every prompt the same standing block — own working branch (read it with
   `git branch --show-current`, never switch), no remote edits, no new fork, no
   second clone, the project's `AGENTS.md` is authoritative, re-verify the
   issue's claims against current `beta` before changing anything and report any
   claim that does not hold, tests written before the fix, no merging of the PR.
   Then the per-item part: the number, the exact read command, and the end
   state (commit, push to own fork, open PR into `beta`, report sha + PR link).
3. One prompt file per peer, then `scripts/peer-dm-batch.sh` for delivery. Pass
   `peer:prompt-file` pairs; the script retries and does not abort the batch on
   one offline peer.
4. The DM loop outlives the 600s foreground cap, because a peer doing real work
   answers in minutes: run it `background=true, notify=true` and let it own the
   DMs. Never re-run it while it is alive — that is a second DM of the same
   task, and on a task that says "work until it's done" it starts duplicate
   work on the same branch.
5. Track progress with a read-only observer job, never with more DMs. "Stay on
   it" means the user gets progress reports, not that peers get re-poked.

See `references/work-assignment.md` for the prompt skeleton and the observer
job recipe.

## Pitfalls

### An observer job must be observation-only

A scheduled progress-checker runs in a fresh session that cannot see that the
peers are already awake and mid-task. If its prompt contains `gh workflow run`
or `hermes peer dm` — even as an "if stuck, nudge them" clause — it will
re-dispatch wakes and re-DM work in progress. Open the prompt with an explicit
DO-NOT list (`gh workflow run`, `hermes peer dm`, cancel/restart runs) and the
single sentence "you are ONLY observing and reporting". Report asleep or
unfinished as an observation instead of fixing it.

Useful observation surface, one line per peer: latest run status via
`gh run list -R <owner>/<repo> --json status,conclusion,createdAt --limit 1`,
branch head via `gh api repos/<fork>/commits/<branch> --jq '.sha + " " +
.commit.message'`, and PRs + CI via `gh pr list -R <upstream> --state open
--json number,headRefName,url,isDraft` then `gh pr checks <n> -R <upstream>`.

Give the observer job a bounded `--repeat N` so it stops on its own, and attach
`--skill hermes-peer-agents` so the fresh session has the standing rules.
Report the job id to the user.

### A peer is blocked from editing AGENTS.md — finish the doc yourself

Peers run behind a file-mutation guard that refuses writes to protected
agent-instruction files (`AGENTS.md`, `SOUL.md`): the write is rejected because
approving it needs an interactive user and a workflow run has none. A peer that
follows the rules reports the block and moves on — never tell it to bypass the
guard.

Put this in the standing block up front so the peer's commit is complete even
when the plan wants a doc change: implement the code, commit it, record the
exact doc gap in the PR body, report it. Then the orchestrator does the doc
commit **on the peer's branch**, without disturbing its own working tree:

```bash
cd <local-repo>
git fetch origin <peer-branch>
git worktree add <tmp> -B doc-<n> origin/<peer-branch>
# edit the file inside <tmp>, commit there, then:
cd <tmp> && git push origin HEAD:<peer-branch>
git -C <local-repo> worktree remove <tmp> --force
```

Push to the peer's branch, never to the base branch. Fetch each involved
branch's copy of the doc and diff them against **each other and** the base
first: if two branches differ, a peer already edited it and you must build on
that version, not on the base one you have locally. Verify the push landed by
reading the file back off the fork — `gh api repos/<fork>/contents/<path>?ref=<branch>
--jq .content | base64 -d` — since your local copy tracks the base branch, not
the fork.

Expect a late doc push to cancel the peer's in-flight CI and queue fresh runs.
`gh pr checks` reporting "no checks reported on the '<branch>' branch" right
after is the normal consequence, not a regression; check
`gh run list -R <upstream>` for the new run's status and say so in the report.

`references/work-assignment.md` has the prompt wording and the full recipe.

### A peer that accepted the DM but never acted — take the item yourself

Delivery success is not progress. A peer can report `DELIVERED` (exit 0) and
then never touch the repo: branch head unchanged, no PR, no commit. Detect it
by checking the branch head against the state at assignment time, not by
trusting the DM result.

Distinguish two failure modes before deciding what to do, with two cheap
probes and one control:

```bash
curl -s -m 5 -o /dev/null -w "http=%{http_code} time=%{time_total}\n" http://<peer>:8642/health
time timeout 45 hermes peer dm <healthy-peer> "ping"
time timeout 45 hermes peer dm <silent-peer> "status?"
```

A sub-second API response plus a DM that hangs to timeout means the machine
and its API server are fine and the peer's **own agent loop is wedged**
mid-turn. That is not an offline peer, and re-dispatching the workflow does
not fix it — one run per machine means the machine is already claimed, and a
second run collides with it. Do not cancel the run: its shutdown step syncs
the peer's state back to the repo, and cancelling loses that.

Report it as a wedged agent, not a down peer, then **do the item yourself** —
that is what "stay on it until it's done" means when a peer cannot finish. Say
plainly which peer dropped and that you are taking it over. Re-pinging a
wedged agent burns the turn and returns nothing.

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
Write the prompt to a file first so it is a one-line fix on retry. Stripping
that Unicode with an inline interpreter inside the same compound command that
runs `hermes cron create` trips the command security scanner and blocks the
whole call: do the strip as its own simple step, write the clean text to a
file, then create the job from `"$(cat file)"`.

### `hermes cron create` prompts that embed shell/agent commands

`$(cat file)` inside the create call is expected and reads fine, but a prompt
containing further backticks or `$(...)` that the job would itself execute gets
both a security-scan approval prompt and a validation failure on some shells.
Keep job prompts as plain instructions ("run these commands"), never as literal
command substitution that must expand at job time.

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
