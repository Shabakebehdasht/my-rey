---
name: fix-verification
description: "Use when checking which open issues are already fixed."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [issues, triage, verification, ci, gh, git]
    category: software-development
    related_skills: [git-workflow]
---

# Fix Verification — pre-close issue audit

Answer "which open issues are fixed?" with a three-bucket verdict backed by
code and CI — never by titles or the mere existence of a merged PR. The issue
body's acceptance checklist is the rubric; grade every line against it. Do NOT
close anything yourself unless asked — hand the user the buckets and let them
close.

## When to Use

- Asked which open issues are fixed / ready to close.
- Auditing a backlog before a release or after a burst of merged PRs.
- Confirming a single issue's fix actually shipped (same steps, one issue).
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

## Verification

- Every bucket entry cites a concrete artifact: file path, test name, PR number,
  or API response.
- The gap list maps 1:1 to the issue's own acceptance checklist.
- No issue was closed or commented on unless the user asked.
