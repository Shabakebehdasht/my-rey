---
name: fix-verification
description: "Use when verifying issue claims or which issues are fixed."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [issues, triage, verification, ci, gh, git]
    category: software-development
    related_skills: [git-workflow]
---

# Fix Verification — issue claims vs. current code

Answer "which open issues are fixed?" with a three-bucket verdict backed by
code and CI — never by titles or the mere existence of a merged PR. The issue
body's acceptance checklist is the rubric; grade every line against it. Do NOT
close anything yourself unless asked — hand the user the buckets and let them
close.

The same evidence discipline answers the sibling question: **is this issue's
finding still true on the current ref?** (audit-wave findings, `plan-in-issue`
bodies that carry a full execution plan). The deliverable there is a verdict —
confirmed / already fixed / duplicate / unverifiable — with file+line evidence,
not a fix.

## When to Use

- Asked which open issues are fixed / ready to close.
- Auditing a backlog before a release or after a burst of merged PRs.
- Confirming a single issue's fix actually shipped (same steps, one issue).
- Reviewing a reported finding against the current tree and reporting an expert
  verdict — `references/shared-queue-issue-review.md` when a whole issue list is
  in play and other agents are working it too.
- NOT for reviewing open PR code (use the `github` skill's code-review flow),
  and never for closing issues off keyword matches alone.

## Procedure

1. **Find the repo that hosts the issues.** Run `gh issue list` from inside the
   checkout first. If it errors with `repository has disabled issues`, you are
   on a fork — issues live on the canonical upstream; re-run every `gh` call
   with `--repo <canonical-owner/repo>`. Derive the canonical from remotes and
   project docs, never assume `origin` hosts issues.

2. **Batch-read every open issue's body** — titles are not evidence:

   ```bash
   gh issue list --repo O/R --state open --limit 100 --json number,title
   for n in <numbers>; do
     gh issue view $n --repo O/R --json title,body --template '{{.title}}{{.body}}'
   done
   ```

3. **Fetch the integration branch (the one PRs merge into) as an explicit ref**
   before reading any file — the working branch typically lags it:

   ```bash
   git fetch https://github.com/O/R.git <branch>:refs/remotes/upstream-canonical/<branch>
   git rev-list --left-right --count HEAD...upstream-canonical/<branch>  # behind X, ahead Y
   ```
   Non-zero lag means every grep of the checkout is a verdict on stale code.
   Never switch branches to inspect (technique in the `git-workflow` skill).

4. **Grade each acceptance item against that ref's tree**, not the working tree:

   ```bash
   git show upstream-canonical/<branch>:path/to/file | grep ...
   git grep -n 'pattern' upstream-canonical/<branch> -- routes app database
   ```

5. **Corroborate with PR/CI evidence:** `gh pr list --repo O/R --state merged`
   maps fixes → PRs; `gh pr checks <pr>` per fix PR. A merged PR whose checks
   FAILED was usually unblocked by a follow-up PR — trace to the PR that left CI
   green before calling it fixed. `gh run list --repo O/R --limit 10` shows the
   repo's latest overall state.

6. **Prove absences via the API** — settings and files never in git don't show
   up in a checkout: `gh api repos/O/R/contents/<path>` and
   `gh api repos/O/R/branches/<b>/protection` returning 404 is the evidence.

7. **Report in three buckets:**
   - **Fixed** — evidence per item: file/test path + green CI (name the PR).
   - **Fixed with gaps** — enumerate each unmet or deviating acceptance line.
   - **Not fixed** — what is missing and where you looked.
   Also report in-flight work (`gh pr list --state open`): an open PR means
   "not fixed" may just be "not merged yet".

8. **Verify by executing when the claim is about behaviour, not text.** A query
   plan, an ordering rule, a route's middleware list — run it. Reading code says
   what the line *looks* like; only execution settles whether the index is
   picked, the job is reserved twice, or the guard actually fires. SQL/index
   claims: `references/perf-claim-verification.md`. Keep every live probe
   read-only or wrapped so it cannot persist.

## Shared queues (several agents on one issue list)

On an audit wave the work protocol is part of correctness, not etiquette:

- **Claim by commenting, nothing else.** Only issues with **zero** comments are
  free; a comment means another agent has it or has finished it. Re-read the
  count right before the deep dive *and* immediately before posting — it moves
  under you. If it moved, skip to the next issue and drop your draft.
- **Never post a second analysis on the same issue**, even when yours is deeper.
- **Order:** priority label first (P1 → P2 → P3), lowest issue number inside a
  priority. One issue at a time — do not open the next before the current one's
  comment is posted.
- **Only comment.** Do not touch title/body/labels/milestone, do not close, do
  not push code or open a PR unless the requester asked.
- Progress lives in the comments, so no separate status report is needed: a
  session that dies mid-list is resumed by the next one under the same
  zero-comment rule.
- Expect to lose races — batch the verification reads into as few calls as
  possible and write the comment as soon as the evidence is in.

The comment skeleton, verdict vocabulary, and evidence rules:
`references/shared-queue-issue-review.md`.

## Pitfalls

- Fixes often carry no `#N` in commit messages. Keyword-search PR titles AND
  grep the tree for the acceptance artifacts — test files, migration filenames,
  routes. A test named after the behavior is the strongest single signal.
- Merged ≠ acceptance-complete: implementations can deliberately deviate from
  the issue's written spec. Diff shipped code against each acceptance line and
  report deviations as gaps instead of counting the PR as done.
- An acceptance item about a repo setting (branch protection, required checks,
  templates) is invisible to git — skip the API check and you will wrongly
  report it done.
- Batch shell work in medium calls: one oversized execution that times out
  destroys every command's output in it, not just the slow one.
- **The body's own "Current state" excerpts are not evidence.** Plan-in-issue
  bodies are written from memory and drift: a quoted `config` block can show a
  setting the file no longer has, and quoted line numbers can be off by one.
  Re-read every cited file+line; on a disagreement the **code wins** and the
  disagreement is itself a finding worth reporting.
- **A plan can be dead on arrival.** Check its own STOP conditions first — a
  column that is already nullable, a `retry_after` that moved, a middleware the
  plan assumes is registered but never was. When one is already true, report
  that with evidence instead of recommending the execution.
- **A dead index arm is invisible to a one-line grep.** When a fix claims "this
  query will use index X", verify the whole predicate, not the changed line.
- Names of tests you must update are part of the evidence: grep the test tree
  for the symbol the change touches and cite file + test name, never "tests may
  break".

## Verification

- Every bucket entry cites a concrete artifact: file path, test name, PR number,
  or API response.
- The gap list maps 1:1 to the issue's own acceptance checklist.
- No issue was closed or commented on unless the user asked.
