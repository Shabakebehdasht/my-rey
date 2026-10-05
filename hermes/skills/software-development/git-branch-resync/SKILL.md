---
name: git-branch-resync
description: "Use when a branch must match an upstream ref exactly."
version: 1.0.0
author: curator
license: MIT
metadata:
  hermes:
    tags: [git, branch, reset, force-push, sync, verification]
    category: software-development
---

# Git Branch Resync

Making a branch match an upstream ref EXACTLY — same commits, no extra files, no
leftover local edits — and pushing that state to the right remote.

General everyday git pitfalls (nested `.git`, staging, identity) live in
`git-workflow`. This skill covers only the make-it-identical-and-push workflow.

## When to Use

- "Make my branch exactly the same as upstream beta."
- "Reset the local branch to upstream and delete any extra files."
- "Force-push / mirror this content onto another branch on my fork."
- Any request ending in "I want the fork's branch to be identical to upstream."

## Standing Rules

- Read the topology, never assume it: `git remote -v`, `git branch --show-current`.
  Never hardcode a fork URL or a server-specific branch name.
- Match state by SHA + empty diff. "Looks the same" is not a match.
- Verify on the REMOTE, never from the local side's exit code.
- Scope every write to the refs the user named. Sibling branches stay untouched.

## Procedure

1. **Read the topology**

   ```bash
   git remote -v && git branch --show-current
   git status -sb && git stash list && git worktree list
   ```

2. **Fetch the upstream branch as an explicit ref, without checking it out.**
   Projects often forbid switching branches, and you rarely need to.

   ```bash
   git fetch <upstream-url> <branch>:refs/remotes/canonical/<branch>
   ```

3. **Compare identity, not appearance**

   ```bash
   git rev-list --left-right --count HEAD...canonical/<branch>   # "0 0" == already identical
   git diff --stat canonical/<branch> HEAD                       # empty == no content drift
   git rev-parse HEAD canonical/<branch>                         # both SHAs on one line
   ```

4. **If the counts are `0 0` and the diff is empty: SKIP the reset entirely.**
   A resync request is frequently already satisfied by a recent merge or
   fast-forward. Deleting files or hard-resetting a branch that already matches
   only destroys work.

5. **If diverged: tag a safety net BEFORE anything destructive, then reset.**

   ```bash
   git tag -f pre-reset-$(date +%Y%m%d-%H%M)
   git reset --hard canonical/<branch>
   ```

   Tag first even when you believe a fast-forward will suffice — it costs one line.

6. **Clear the working tree back to the tracked state**

   ```bash
   git status --porcelain -uall          # inspect untracked, non-ignored
   git clean -nd                         # dry-run preview only
   git checkout -- <path>                # discard churn from a build tool
   ```

7. **Push the current branch to its configured remote**

   ```bash
   git push <remote> <branch>:<branch>             # fast-forward when allowed
   git push --force-with-lease <remote> <b>:<b>    # rewrite an existing remote branch
   ```

8. **Mirror the same content onto ANOTHER branch name without a local checkout.**
   Push the fetched ref straight through:

   ```bash
   git push <remote> canonical/<branch>:refs/heads/<other-name>
   ```

9. **Verify on both remotes**

   ```bash
   git ls-remote --heads <remote>
   git ls-remote <upstream-url> refs/heads/<branch>
   ```

   The claim "my fork's branch is identical to upstream beta" requires the SHA from
   `ls-remote` on BOTH sides to be equal. Report those SHAs.

## Pitfalls

### "Delete every extra file" means untracked, non-ignored — never `git clean -x`

`-x` also deletes IGNORED files, which in a Laravel/Node repo is the working
environment itself: `.env`, `composer.lock`, `bootstrap/cache/*`, `node_modules/`,
tool databases. Count them before you touch anything so you can say you kept them:

```bash
git status --porcelain --ignored -uall | grep -c '^!!'
```

A large ignored count is expected and is NOT "extra files".

### A dirty tracked file from a build tool is not an extra file

`package-lock.json` / `composer.lock` churn after a local build is local noise.
Restore it (`git checkout -- package-lock.json`) — never commit it as part of a resync.

### `-f` on a branch that does not exist yet is a no-op, not a risk

Check first, so you can report accurately whether force was even needed:

```bash
git ls-remote --heads <remote> | grep <name>
```

Output empty → plain push creates it. Output present → the user meant a rewrite,
and `--force-with-lease` is safer than `-f` because it refuses if the remote moved
since your last fetch.

### A successful push message is not verification

`git push` exiting 0 says the local side updated the remote ref. It does not say the
remote content equals upstream, nor that no other branch moved. Only `ls-remote` on
both sides proves that.

### Never switch the checkout just to compare branches

Fetch a ref and read through it (`git show <ref>:<path>`, `git grep <pattern> <ref>`).
Checking out a branch to diff it perturbs the session's working state and can be
forbidden outright.

See `references/push-and-force-decisions.md` for the situation → command table.

## Verification

Before reporting success, all of these must hold with output you actually saw:

- `git diff --stat canonical/<branch> HEAD` → empty, and both `git rev-parse` SHAs equal
- `git status --porcelain -uall | wc -l` → `0`
- `git ls-remote --heads <remote>` shows the target branch at the expected SHA
- `git ls-remote <upstream-url> refs/heads/<branch>` shows the same SHA
- No branch other than the named ones changed in the `ls-remote` listing