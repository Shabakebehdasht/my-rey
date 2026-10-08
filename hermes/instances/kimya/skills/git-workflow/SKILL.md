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

### Verifying a fix without weakening the assertion

A test written against a behaviour that may or may not manifest (an exception
path, a harness that swallows an error) can pass while asserting nothing. Two
rules:

- **Every branch of a fixture asserts its own precondition.** If a test depends on
  the caller having an empty access scope, assert `accessibleUnitIds() === []`
  inside the fixture first. Otherwise a fixture that silently stops being the
  case you think it is passes vacuously.
- **Prove which branch runs before trusting a conditional assertion.** Write the
  test, then temporarily `fwrite(STDERR, "PATH=X")` into each branch and run it.
  Laravel/Livewire commonly swallow exceptions the base exception would have
  thrown, so the branch you *expect* may be dead code. Delete the probe afterwards.

Corollary: if you find the exception branch is unreachable, collapse both branches
into one unconditional assertion. Duplicated asserts in a dead branch are noise,
and they read as if the case is covered when it is not.

### Never run two test suites against the same test database

`h_dashboard_test` is shared. Running `composer test` in the background and a
focused `php artisan test <file>` at the same time produces Postgres
`SQLSTATE[40P01]: Deadlock detected` on `drop table ... cascade` — it looks like a
real failure in your change, and it is not. Sequence them: finish (or kill) the
suite before running anything else, and do not edit test files while a suite is
running. If a suite dies on a deadlock, suspect this before suspecting your diff.

### Missing git identity on fresh clones

New clones may lack both global and per-repo `user.name`/`user.email`.
Commits fail with `empty ident name`.

**Fix — set per-repo config before first commit:**

```bash
git config user.email "user@users.noreply.github.com"
git config user.name "username"
```

Detect from `gh auth status` or set manually.

## Verification

- `git status` shows no unexpected submodule entries.
- `git diff --cached --stat` shows actual file additions, not just mode changes.
- Commit and push succeed without warnings about embedded repos.
