# Verifying peer work landed in the upstream repo

A peer works in its own fork and opens a PR into the upstream base branch.
Almost every "the peer says it is done, but the upstream repo disagrees"
failure is one of the three shapes below. Check each with the upstream repo
named explicitly.

## Rule 0: never resolve a PR by bare number

PR numbers are per-repo. A fork's numbering starts at 1, so a peer's "#10"
is very often not upstream's "#10" — and `gh pr view 10 -R <upstream>` may
return a completely unrelated PR that happens to share the number. Always pass
`--repo`. When a peer reports a PR number, treat it as meaningless until you
have located that number in the repo you actually expect.

## Shape 1: the PR is in the fork, not upstream

The peer's work is complete and correct — real commits, real tests, real green
CI — but the PR was opened against its own fork, which the project manager
does not read.

```bash
gh pr list -R <owner>/<upstream> --state open --head <branch> --json number,state   # empty
gh pr list -R <owner>/<fork>     --state all --head <branch> --json number,state   # found it
```

Ask the peer to open it upstream with `-R <owner>/<upstream> --base <base>`
and to close the fork's copy. Never open it yourself: the prompt told the peer
not to touch the upstream repo's PRs beyond its own, and the peer's PR body
carries its test evidence and scope notes.

## Shape 2: the branch is stacked on another issue's branch

The peer branched each item off its previous item's branch, so every PR also
carries the earlier items' commits.

```bash
git fetch origin --prune
git log --oneline canonical/<base>..origin/<branch>    # subjects name other issues
```

More than one issue's commit on a branch means merging it lands all of them.
Fix per branch, in a throwaway worktree, one commit cherry-picked onto the base
so the result is independent of how it was built:

```bash
git worktree add <tmp> -B sep-<issue> canonical/<base>
git -C <tmp> cherry-pick <commit-for-this-issue>
git -C <tmp> push --force-with-lease origin HEAD:<branch>
git -C <local-repo> worktree remove <tmp> --force
```

Before cherry-picking, confirm the commits are separable: `git show --stat
<commit>` per commit and check for a shared file. The common overlap is a lint
baseline, where each issue removes its own distinct entries — those cherry-pick
clean. If two commits genuinely edit the same lines, that is a conflict to
raise, not to resolve blind.

`--force-with-lease` refuses when the peer pushed since your fetch, so a wedged
or still-working peer's commits are never destroyed.

Force-push needs user approval. Ask with the exact commands in hand, say which
PRs are mixed and what each single commit belongs to, and say what breaks if
left alone (the later merge silently lands the earlier issues, and the
already-open sibling PR for that earlier issue becomes a no-op).

An approval prompt that times out or lapses is NOT consent. Report the blocked
push with the exact commands and what it would change, then wait — never re-issue
the destructive push on your own initiative.

## Shape 3: the correction was overtaken by a merge

While a correction was queued, the project manager merged the very PRs it was
about. The base branch now holds the union, so the separation is moot and
correcting it would only rewrite history for nothing.

Re-check before building or requesting approval for any destructive fix:

```bash
gh pr list -R <owner>/<upstream> --state all --limit 12 \
  --json number,state,headRefName,mergedAt,closedAt
```

Several PRs with merged-at timestamps seconds apart is the signature. Fetch
the base ref and read the result off it:

```bash
git fetch https://github.com/<owner>/<upstream>.git <base>:refs/remotes/canonical/<base>
git diff --stat <old-base> canonical/<base>       # what actually landed
git show canonical/<base>:<path>                  # read content off the merged ref
```

## Shape 4: a guard that was DELETED is the fix, not the bug

Not a "shape" of missing work — the inverse trap, and it makes triage wrong.

Code that fails closed often does it by REMOVING a defensive guard:

```php
// before — the bug
if (! empty($accessibleIds)) { $query->whereIn('id', $accessibleIds); }

// after — the fix
$query->whereIn('id', $accessibleIds);   // [] now compiles to 0 = 1 on purpose
```

Read the bare line as a leak and you will re-assign work that is already done.
Judge the BEHAVIOUR, not the shape:

```bash
git show <the-fix-commit> -- <path-the-issue-names>
```

Two consequences for triage:

- A "Closes #N" merged PR plus an unguarded-looking line on the base ref can
  mean the issue is COMPLETE. Verify, then make the assignment verify-only or
  skip it — do not dispatch an implement prompt.
- When a peer contradicts the triage and its reasoning points at the guard having
  been removed, the peer is probably right. Re-read the commit before defending
  the original read, and correct the assignment openly.

A test-only PR that pins the already-correct behaviour is the correct deliverable
for a closed item; accept it rather than asking for production changes.

## Proving a specific commit landed after someone else merged

Reachability, not content grepping against your own checkout:

```bash
git fetch origin <pr-branch> && git branch -r --contains <sha>
```

Empty output means the commit is not on any branch. Also note that your local
checkout can be many commits behind the base branch, so `git show
canonical/<base>:FILE | grep -c '<expected text>'` returning 0 is a FALSE
NEGATIVE whenever your `canonical/<base>` ref predates the merge — refetch
first, and prefer `git diff <old-base>..<new-base> -- FILE` which shows the
change itself rather than a snapshot you may be holding stale.