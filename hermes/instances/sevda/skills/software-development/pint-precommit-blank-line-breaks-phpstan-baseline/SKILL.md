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