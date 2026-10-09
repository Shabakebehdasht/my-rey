---
name: implementing-github-issues
description: "Land a triaged GitHub issue as a scoped PR."
version: 1.0.0
author: Hermes Agent (session-derived)
license: MIT
metadata:
  hermes:
    tags: [github, pull-request, issue, triage, scope-discipline]
    category: software-development
---

# Implementing a Triaged Issue as a PR

## When to Use

Use when the ask is "implement issue N" / "execute the handover for the `ready`
issues" — i.e. a GitHub issue that has already been triaged by a reviewer and is
handed over for implementation. Not for filing issues, not for auditing.

## Authority Order (read before writing code)

An issue body written by an audit tool is **discovery history**, not a spec. Work
from the most authoritative source that exists, in this order:

1. **Expert/review comment** on the issue — holds the execution map and the
   decisions. It routinely *overrides* the body (corrected counts, rejected
   suggestions, narrowed scope).
2. **Gate/approval comment** ("verified on `beta`", lists what was re-checked on
   the current branch tip and what was dropped as out of scope).
3. **Raw issue body** — only for the problem statement.

Fetch every comment before planning:

```bash
gh issue view N --repo owner/repo --json number,title,state,labels,url,body
gh api repos/owner/repo/issues/N/comments \
  --jq '.[] | "=== \(.user.login) @ \(.created_at) ===\n\(.body)"'
```

Save the comment dump to scratch and read it whole. Comments are appended newest
last, so the gate comment (usually last) reflects the current decision.

**Eligibility.** Only issues carrying the handover label are in scope. Check
`labels` in the JSON above and stop if the label is missing — an unlabelled issue
is not handed over.

## Pre-flight before editing anything

1. `git fetch upstream beta` and read `git log --oneline -3 upstream/beta`. The
   gate comment verified against a specific commit; the branch may have moved.
2. **Confirm every cited `file:line` still points at the code the comment
   describes.** A reviewer comment that cites lines from a stale tip is the most
   likely source of a wrong edit.
3. **Find the in-repo precedent** for the fix and match it. An approved fix
   almost always mirrors an existing pattern somewhere in the codebase; locating
   it is faster and safer than inventing a shape.
4. Read the framework's own source in `vendor/` for any claim about what it does
   at runtime. Do not infer framework behaviour from memory.

## Scope Discipline

The PR contains **only** the code and tests for this issue.

Never let these in:

- dependency/lockfile churn (`package-lock.json`, `composer.lock`) that was
  already dirty in the working tree before you started — check `git status` on
  arrival and leave pre-existing modifications uncommitted
- working notes, plans, scratch files, personal logs
- refactors or drive-by cleanups that the comment did not ask for
- **edits to `AGENTS.md` or any other instruction/reference file, ever.** These
  are protected: writing them blocks the file and bypassing that is forbidden.
  Finish the code instead, then record in the PR body the exact file, the exact
  line, what that line should say, and the ready-to-paste replacement text. The
  reviewer applies it.

Verify before pushing: `git diff upstream/beta...HEAD --stat` must list only
intended files, and `git status --porcelain` must show nothing staged that you
did not mean to commit.

## One PR per issue, when several issues share a file

Do not stack unrelated issues into one PR. When the ask is "one PR per issue"
and two issues legitimately touch the same file (a shared bootstrap/config
file), split them so each PR stands alone:

1. **Back up every touched file** before splitting (`cp` into a scratch dir) —
   a later `git checkout <base> -- <path>` discards work you have not committed.
2. **Branch each issue off the synced base ref, not off your working branch:**
   `git checkout -b <branch> <base>`. A branch created from your working
   branch inherits the previous issue's changes.
3. **Restore only this issue's files/hunks.** For a shared file, apply just
   this issue's hunk to the branch's pristine copy; strip the other issue's
   files with `git checkout <base> -- <paths>`.
4. **Commit scoped by pathspec, not `git add`:** `git commit -F - -- <paths>`.
   `git add <deleted-file>` fails with a pathspec error when the deletion is
   already staged, which silently leaves the commit uncreated.
5. **Never stash per-path to separate work.** `git stash push -- <paths>`
   errors with a pathspec error on an already-staged deletion and can still
   create a partial stash, leaving files in an ambiguous state.
6. Prove isolation per branch before pushing:
   `git diff --stat <base>..<branch>` lists only that issue's files.

## Tests run serially, always

The Pest suite uses ONE test database. Never run a suite in the background
while running tests in the foreground — the two interleave on the same
database and produce a large block of failures that look real and are pure
contamination. If a contaminated run happens, discard it and re-run alone;
never report those numbers. Report the clean run only.

When a test failure count is implausibly large, suspect concurrency or
mid-run edits before debugging the code.

## Verify the claim table, not just the code

Re-derive the numbers the authority comment asserts against the real data, and
replay the new algorithm against the live rows. A fix that handles the case in
the report but not the case in the data is the failure mode this catches. When
a fix's expected output is already documented somewhere (probed counts,
per-start results), match it — a mismatch means the implementation differs
from the reviewed design, not that the design was wrong.

## Verify

- Run the tests the plan names, plus the existing related suite in that area.
- The project's mandatory gates must be green: the test/coverage run, the code
  style fixer, and the static analyser. Read the project agent instructions for
  the exact command of each.
- A performance fix needs a guard test that fails without it — a measured query
  count or an equivalent bound, not a smoke assertion.
- When the fix removes a framework anti-pattern, add a test asserting the
  absence (e.g. the payload method runs once per view, not twice).

## Stop Conditions

Do not guess. When the plan is ambiguous, contradicts the code on the branch tip,
or needs a product decision that is not closed in the comments:

1. Post a comment on the issue stating exactly what is unclear, what you read,
   and which options need a decision.
2. Stop. Do not implement a partial guess.

Acceptable scope narrowing is only what a comment already decided. "Out of scope
until a separate decision" is a closed decision — honour it and do not bundle
the extra work.

## Do Not

- Label issues, close issues, or merge PRs. Merge belongs to the project
  maintainer.
- Push to the shared base branch directly.
- Re-open or re-litigate a scope decision the gate comment already closed.

## PR Body

Include the closing keyword for the exact issue implemented (`Closes #N`), a
short statement of what changed and why, the measured before/after for any
performance claim, and the test commands run with their result. Reference the
authority comment rather than restating the audit history.

## Reporting Progress

Report status in the user's language, in labelled sections, no filler. State
what is done, what remains, and any open question. Stop reporting as soon as the
work is complete.
