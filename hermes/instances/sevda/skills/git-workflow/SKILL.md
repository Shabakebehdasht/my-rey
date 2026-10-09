---
name: git-workflow
description: "Git pitfalls: nested repos, staging, identity."
version: 1.0.0
author: Sydney
license: MIT
metadata:
  hermes:
    tags: [git, workflow, pitfalls, staging, nested-repos, commit]
    category: software-development
---

# Git Workflow

Pitfalls and procedures for everyday git operations that fall outside standard
`gh` CLI workflows (for gh-specific flows see the `github` skill).

## Standing Rules

- Always check `git status` and `git remote -v` before staging or pushing.
- Configure per-repo identity before first commit if global config is absent.
- Never assume a branch name — read it from `git branch --show-current`.

## Pitfalls

### Nested `.git` directories when copying content

When `cp -r` (or similar) a directory that contains its own `.git` into another repo,
`git add` detects the nested `.git` and stages only a submodule reference (mode 160000),
not the actual files. Clones of the outer repo will not contain the copied content.

**Fix — remove nested `.git` before staging:**

```bash
cp -r /source/dir target/inside/repo
rm -rf target/inside/repo/.git
git add target/inside/repo/
```

If already staged as submodule:

```bash
git rm -r --cached target/inside/repo/
rm -rf target/inside/repo/.git
git add target/inside/repo/
git commit -m "Add dir contents (fix nested repo)"
```

### Unintended file changes in feature commits

When committing feature work, run `git diff --stat` before staging to catch
unintended modifications to config/meta files (e.g. `AGENTS.md`, `.hermes.md`)
that were modified by tooling or agents during the session but are not part of
the feature.

**Prevention:** `git add -p` or selective `git add <paths>` instead of
`git add -A`. Review `git diff --staged --stat` before committing.

**Fix — restore from upstream before amend:**

```bash
git show upstream/beta:AGENTS.md > AGENTS.md
git add AGENTS.md
git commit --amend --no-edit
```

### Reading files from a branch the checkout does not have

When a task requires judging the current state of code (issue audits, fix
verification, comparing branches), the working tree often LAGS the branch that
carries the work. Grepping the checkout then yields a confident verdict on
stale code. Do not `git checkout` the other branch just to read it — projects
may forbid switching branches, and it disturbs session state.

**Fix — fetch the branch as an explicit remote-tracking ref and read through it:**

```bash
git fetch <remote> <branch>:refs/remotes/<remote>/<branch>   # e.g. beta
git rev-list --left-right --count HEAD...<remote>/<branch>   # behind X, ahead Y
git show <ref>:path/to/file            # one file
git grep -n 'pattern' <ref> -- path/   # search the branch's tree
git diff --stat HEAD <ref> -- path     # what changed vs checkout
```

Run these as small batches with explicit timeouts — one oversized shell call
dying takes every command's output down with it.

### Compare against canonical upstream without adding a remote

Session init may require diffing the working branch against the canonical repo while
forbidding remote changes. Fetch it into a namespaced remote-tracking ref instead of
creating an `upstream` remote:

```bash
git fetch https://github.com/<org>/<repo>/ beta:refs/remotes/official/beta
git rev-list --left-right --count HEAD...official/beta   # ahead<TAB>behind
```

This never writes to `.git/config`, so the remote layout stays exactly as provisioned.

### Preserve unrelated uncommitted edits across a fast-forward merge

A merge can refuse or conflict when the working tree has uncommitted changes. Stash only
the unrelated paths, merge, then pop:

```bash
git stash push -m "wip before sync" -- path/to/file
git merge official/beta --no-edit
git stash pop
```

Always verify the pop restores the same modification list you started with; if the
target file was also touched by the merge, resolve before continuing.

### Missing git identity on fresh clones

New clones may lack both global and per-repo `user.name`/`user.email`.
Commits fail with `empty ident name`.

**Fix — set per-repo config before first commit:**

```bash
git config user.email "user@users.noreply.github.com"
git config user.name "username"
```

Detect from `gh auth status` or set manually.

## Multiple PRs from one working branch

GitHub permits only ONE open PR per (head, base) pair, so a task asking for N
separate PRs out of a single working branch cannot open the second one against
that branch. The obvious workaround is worse than the limitation: branching the
second PR off the working-branch tip makes it carry the FIRST issue's commits,
so the "one PR per issue" split is silently gone.

**Rule: every additional PR gets its own head branch cut from the BASE commit,
containing only that change.** Verify containment from the remote, never from
memory of what you committed:

```bash
gh pr view <N> -R <org>/<repo> --json files -q '.files[].path'
```

Build each side branch in a worktree — it leaves the working branch and its
index/stash untouched, which matters when branch-switching is forbidden:

```bash
git worktree add ../<repo>-<n> -b fix/<n>-<slug> <base-commit>
cd ../<repo>-<n>
git cherry-pick <commit-for-this-issue>
git diff --stat <base-commit>          # must list ONLY this issue's files
```

After all PRs are open, drop the worktrees (`git worktree remove --force <path>`).

**An open PR whose head is wrong:** close it and reopen on the correct branch.
`gh pr edit` has no `--head` flag, and `gh api -X PATCH .../pulls/N -f head=...`
returns HTTP 200 while **silently keeping the old ref** — always re-read
`.head.ref` (or `.files`) afterwards to confirm the change landed.

**Move/create a branch ref without force-deleting:** `git branch -f <name> <commit>`
works where `git branch -D` may be gated.

### Run formatters before staging, then audit what the formatter touched

A `--dirty` / pre-commit formatter pass rewrites every file *it* considers
dirty, not just yours, and those edits ride straight into your commit. After
any formatter run, audit the staged set for files you never opened:

```bash
git add <only your paths>          # never `git add -A`
git diff --cached --name-only      # must list ONLY this change's files
git diff --name-only <base>..HEAD  # and again after commit
```

If a formatter changed an unrelated file, restore it from the base and keep it
out of the commit. Reverting it as a **forward commit** is preferable to
rewriting history when a force push is unavailable or blocked.

### Verify PR contents from the remote, and read the file list with an API

Never trust a PR's own commit count as a scope signal — a branch cut from a
working branch carries that branch's commits as ancestry while the diff stays
correct. Read the file list from the API, which reflects the merge-base diff:

```bash
gh pr view <N> -R <org>/<repo> --json files -q '.files[].path'   # may be cached
gh api repos/<org>/<repo>/pulls/<N>/files --jq '.[].filename'     # authoritative
```

Extra commits in the PR are harmless **iff** the file list is exactly your
scope; confirm with a three-dot diff against the base:

```bash
git diff --name-only <base>...origin/<head-branch>
```

### A stale pre-existing gate failure may be an environment artifact

Before blaming a baseline/config file or filing it as a pre-existing repo
defect, clear the local caches and re-run. A classmap left over from a file
another branch deleted makes the removed class still load, which surfaces as
dozens of confusing analyser errors. `composer dump-autoload` fixes it with no
repo change. Re-verify the gate on the pristine base tree too, so you can state
plainly whether the failure is yours.

Critically: **if you reported the failure in a PR body and later disproved your
own explanation, correct the PR body.** Do not leave an explanation you have
since disproven sitting under a reviewer's nose — edit it with `gh pr edit`.

### Forward-fix a PR you cannot force-push

When a push would need `--force-with-lease` — often blocked on unattended
runners — or the guidance forbids rewriting a published branch, add a small
self-contained follow-up commit on the same head branch instead. Remote file
lists and diff views update on their own.

### A worktree needs its own runtime wiring

A fresh worktree has no `.env`, `vendor/`, or `node_modules`. Symlink the
dependency directories instead of reinstalling:

```bash
ln -s /path/to/main/vendor vendor
ln -s /path/to/main/node_modules node_modules
```

For the env, prefer exporting the few variables the test run actually needs
over copying `.env` — and export the drivers explicitly, because the main
checkout's cached config otherwise leaks in and produces failures that look
like real test failures:

```bash
APP_ENV=testing CACHE_STORE=array SESSION_DRIVER=array QUEUE_CONNECTION=sync \\
DB_CONNECTION=pgsql DB_HOST=127.0.0.1 DB_DATABASE=... DB_USERNAME=... \\
DB_PASSWORD=... php artisan test
```

## Verification

- `git status` shows no unexpected submodule entries.
- `git diff --cached --stat` shows actual file additions, not just mode changes.
- Commit and push succeed without warnings about embedded repos.
