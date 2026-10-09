---
name: pint-precommit-blank-line-breaks-phpstan-baseline
description: "Pint hook shifts Livewire blade lines, breaking baseline."
---

# Pint pre-commit can silently break the PHPStan baseline

Applies to h-dashboard (`/home/runner/h-dashboard`), Livewire 4 single-file
components under `resources/views/livewire/**/*.blade.php`.

**Symptom.** CI's `PHPStan Static Analysis` job fails on a PR whose only change was
inside a single-file Livewire Blade component. The report contains no real code
error — only dozens of:

```
Ignored error pattern #^Method Livewire\Component@anonymous/resources/views/.../foo.blade\.php\:9\:\:getSelectedActions\(\) ...$#
was not matched in reported errors.   (ignore.unmatched — non-ignorable)
```

Locally `composer phpstan` says `[OK] No errors`, because the local tree is the
one that moved the line and the commit regenerated the baseline — or the local
run predates the hook.

**Cause.** `phpstan-baseline.neon` keys Livewire component entries by the line of
`return new class extends Component`. The versioned `pre-commit` hook runs
`vendor/bin/pint`, and Pint's `single_line_after_imports` fixer inserts one blank
line after the `use` block — moving `return new class` from line 9 to line 10.
Every baseline entry for that file is now stale and PHPStan reports each as
unmatched (the `ignore.unmatched` errors are non-ignorable, so the gate fails).

The `.blade.php` extension is why this is easy to miss: Pint does not lint blade
files itself, but the hook's Pint pass still applies the import-block fixer
because the file is parsed as PHP.

**Fix.** Restore the line to `:9` (delete the added blank line) rather than
regenerating the baseline. Regenerating accepts `:10` and churns ~48 entries for
a formatting-only change, then breaks again the moment anyone runs Pint. Verify
with `vendor/bin/phpstan analyse --no-progress` on the exact tree you pushed.

**Prevention.** When a PR touches a single-file Livewire component, check whether
the diff also adds or removes lines *above* the anonymous class — especially
`use` statements. A pure `use`-line change shifts the baseline. Note this is the
same failure family as the existing "phpstan-baseline is line-keyed" note in
`AGENTS.md`; this skill is the blade-specific version with the CI symptom.

Diagnose which line the class sits on now versus before:

```bash
git show HEAD:<blade file> | head -12 | cat -n | tail -6
git show HEAD~1:<blade file> | head -12 | cat -n | tail -6
```

A `#883`-style fix that only removes a blank line is a small, self-contained
follow-up commit on the same head branch — never a force-push (blocked on
unattended runs), and never a regenerated baseline.

## Running Pint yourself creates the very breakage this skill warns about

The pre-commit hook is not the only way to hit this. `vendor/bin/pint --dirty`
reformats **every** dirty file, including Livewire blade components you never
opened, and its `single_line_after_imports` fixer inserts the blank line that
shifts `return new class extends Component` from `:9` to `:10`. Two failure
modes follow, and both land in someone else's PR:

1. **Unrelated files enter your diff.** The shifted blade files are yours in the
   index but unrelated to the issue, so a scoped PR silently ships them. After
   any formatter run, check the staged list for files you did not open:
   `git diff --cached --name-only`. Restore them from the base and keep them out.

2. **The local gate goes green while the committed baseline is stale.** Local
   PHPStan reads the tree *you* just reformatted and reports no errors, because
   the commit also moved the line the baseline keys on. Only CI — which checks
   out the pushed tree — sees the mismatch.

**Prefer running the formatter with an explicit path list** so it cannot touch
unrelated components:

```bash
vendor/bin/pint --dirty <your paths>
vendor/bin/pint --test        # verify the WHOLE repo is still clean
```

## Catch the spill BEFORE the commit, not after the PR

Timing is what makes this expensive. Discovering stray files after the PR is
open cannot be undone by rewriting history: force-push is blocked on unattended
runs, so the only remedy is a forward commit that reverts the spill — extra noise
in a review, on a branch the maintainer is already reading. Check immediately
after every formatter run, while the fix is still a staged change you can
discard:

```bash
vendor/bin/pint --dirty <your paths>
git status --short                       # anything you did NOT open?
git diff --name-only                     # unstaged spill
git diff --cached --name-only            # staged spill
git checkout <base-ref> -- <stray paths> # restore, keep them out
```

The same discipline covers files that were already dirty before you started —
lockfiles and env-adjacent files change during `composer`/`npm` runs and are
routinely left modified in the working tree. Never `git add -A` / `git add .`
on a branch cut from a shared base; stage explicit paths so an inherited dirty
file cannot ride along into a scoped PR.

Final confirmation, after the commit exists, uses a **three-dot** diff against
the base — `git diff --name-only <base>...HEAD` — because a two-dot diff also
reports base-side changes that the PR will not actually carry:

```bash
git diff --name-only <base>...HEAD        # what the PR really changes
git log --oneline <base>..HEAD             # commits the PR really carries
```

Read both before reporting a PR as scoped. Commits inherited from a branch you
cut from can appear in `git log` while contributing no file changes — that is
harmless ancestry, not scope creep — but stray *files* in the three-dot diff are
real and must be removed before the maintainer reviews.

## Keep parity when you must edit the baseline by hand

Regenerating the whole baseline to absorb one intentional change also rewrites
every unrelated drifted entry — the churn defeats the point of a scoped PR.
Instead, update only the entries whose `path:` points at the file you edited,
and copy the replacement lines byte-for-byte out of a freshly generated
baseline. Two traps:

- **NEON stores regexes with doubled backslashes**, so a hand-typed
  replacement string is easy to get subtly wrong. Match on the message with
  every backslash stripped (or a plain-ASCII substring) rather than comparing
  full escaped literals from PHP.
- **Changing a call's receiver shape invalidates its baselined message**, even
  when the count is unchanged: `Model::scope()` is a *static* message
  (`staticMethod.notFound`) but `Model::query()->scope()` is a builder-message
  (`method.notFound`). Add or drop a `where()` first and the entry must be
  converted, not just re-counted.

Verify with `vendor/bin/phpstan analyse --no-progress` on the exact tree you
pushed, and confirm the diff is only the intended entries.

## A stale autoloader produces fake "pre-existing" PHPStan failures

Before reporting a gate failure as pre-existing, rule out the autoloader.
A deleted class can linger in Composer's optimized classmap, so PHPStan keeps
analysing a file the repository no longer contains and emits its stale entries as
`ignore.unmatched` errors. The signature: every error names a file that is
**absent from the checkout** (`git ls-files <path>` returns nothing), and the
count disappears after regenerating the classmap.

```bash
composer dump-autoload
vendor/bin/phpstan analyse --no-progress
php artisan test            # a test asserting a class must NOT exist also fails
```

This is an environment fix, not a repository change — commit nothing for it.
Two things it protects you from:

- **Do not attribute it to your diff.** Reporting "48 pre-existing errors on the
  base branch" from a contaminated tree invents a defect upstream does not have,
  and sends a reviewer hunting a phantom.
- **Do not report it as a broken tool.** The gate is fine; the local classmap is
  stale. Run the fix and move on.

Confirm the base branch is genuinely red by testing a **clean tree** — stash your
work, regenerate, re-run — before using that phrase in a PR body. If you cannot
isolate it, describe the symptom rather than claiming a verdict you did not
establish.