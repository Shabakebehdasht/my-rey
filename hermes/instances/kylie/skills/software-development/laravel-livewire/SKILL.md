---
name: laravel-livewire
description: "Laravel 13 + Livewire 4 conventions, pitfalls, testing."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [laravel, livewire, php, pest, testing]
    category: software-development
---

# Laravel 13 + Livewire 4 Development

## When to Use

Use this skill when writing PHP/Laravel code, Livewire components, Pest tests,
API Resource transformers, or E2E tests for a Laravel 13 + Livewire 4 project.

Standing conventions and pitfalls for Laravel/Livewire projects. Applies to
PHP code changes, test writing, and API resource transformers.

## Always-On Rules

1. **Run Pint before commit.** `vendor/bin/pint --dirty` is enforced in CI.
2. **Clear config+route cache before running tests.** Stale `routes-v7.php`
   causes Livewire endpoint-hash mismatch — tests silently return 404 on
   `->set()`/`->call()`.
3. **Use `assertDatabaseHas` with all relevant fields.** Don't just assert on
   `title` — include `user_id`, `unit_id`, or any field the code was supposed
   to set. Partial assertions miss bugs.
4. **Test Resource transformers directly.** Don't rely solely on controller
   tests to cover API response shape — instantiate the Resource class and
   call `toArray(new Request())` to assert exact field contracts.
5. **E2E tests go in `tests/e2e/<feature>/`** with `.spec.ts` extension.
   Import from `../shared/fixtures` for `login`, `waitForLivewire`, etc.
6. **Regenerate PHPStan baseline after fixing errors.** When you fix errors
   that exist in `phpstan-baseline.neon`, the old entries become unmatched
   and PHPStan reports new errors. Run `vendor/bin/phpstan analyse
   --generate-baseline` after every fix round, then verify with
   `composer phpstan`.

## Pitfalls

- **`whenLoaded` returns `MissingValue`, not `null`.** When calling
  `toArray()` directly on a JsonResource (not through `toResponse()`),
  `whenLoaded('relation')` returns a `MissingValue` object. Tests must
  check `instanceof` or use `array_key_exists` — `assertNull()` fails.
- **Factory defaults ≠ nullable columns.** A migration with
  `->default('o-bell')` on a NOT NULL column means the factory must NOT
  pass `null` for that field. Use the default value, not `null`.
- **Faker `passthrough()` requires an argument.** Use
  `fake()->optional(0.6)->words(3)` or another generator for optional
  JSON fields — `passthrough()` needs a value parameter.
- **Carbon `toISOString()` ≠ ATOM format.** `toISOString()` returns
  `.000000Z` suffix; ATOM uses timezone offset. Use `strtotime()` for
  flexible ISO 8601 validation in tests.
- **UUID primary key models + HasFactory.** Models with manual UUID
  generation in `boot()` (via `Str::uuid()`) work with `HasFactory`.
  Don't add `HasUuids` trait — it would conflict with the manual boot
  logic.
- **PHPStan `auth()->id()` vs `Auth::id()` in Livewire blade components.**
  PHPStan types `auth()` as `Illuminate\Contracts\Auth\Factory` which
  lacks `id()`. In anonymous-class Livewire blade components (single-file
  components with `return new class extends Component`), add
  `use Illuminate\Support\Facades\Auth;` and call `Auth::id()` instead.
  `auth()->user()` works fine (returns User|null), but `auth()->id()`
  does not.
- **PHPStan generic type for HasFactory.** PHPStan level 6+ requires the
  generic type annotation on `use HasFactory`. Write
  `/** @use HasFactory<\Database\Factories\YourFactory> */` immediately
  above the `use HasFactory;` statement. Without it, PHPStan reports
  `missingType.generics`.
- **PHPStan `@property-read` on JsonResource.** When a Resource class
  accesses `$this->some_field` (magic proxied from the underlying model),
  PHPStan reports `property.notFound`. Fix: add `@property-read` PHPDoc
  annotations for every accessed field, then access via
  `$model = $this->resource;` with a `@var Model $model` cast. Match
  the pattern used by other Resources in the project (see
  `NotificationResource.php` for the reference implementation).
- **PHPStan without larastan degrades an Eloquent chain to `Query\Builder`
  after `whereIn()`.** `Eloquent\Builder` declares `@mixin Query\Builder`, so
  the first call PHPStan resolves through the mixin types the receiver as
  `Query\Builder` and any later Eloquent-only call fails with
  `Call to an undefined method Illuminate\Database\Query\Builder::with()/withCount()`.
  **Fix (verified — clears the error with zero baseline entries): end every
  chain on a call that `Eloquent\Builder` defines itself.** Put eager loads
  first, then move the scope filters into a trailing closure —
  `->where(function ($q) use ($ids) { $q->whereIn(...); })` — or filter by key
  with `whereKey($ids)` instead of `whereIn('id', $ids)`. `where()` and
  `whereKey()` are declared on the Eloquent builder with `@return $this`, so the
  body returns an Eloquent builder and `return.type` disappears; callers already
  honour the declared `@return Builder<Model>`. Do NOT reach for an inline
  `@var`/`assert()` to override the inferred type — PHPStan rejects that
  explicitly. Only a chain that must end on a mixin-only call
  (`orderBy()`/`limit()` before `get()`) still reports; that residual goes into
  the regenerated baseline (Always-On rule 6). The root fix is larastan, which
  this project does not run.
- **`updateOrCreate` overwrites ownership on edit.** When using
  `Model::updateOrCreate(['id' => $editingId], [...])` and one field
  (e.g. `user_id`, `created_by`) should only be set on create — not on
  update — do NOT include it in the attributes array. The update path
  would overwrite the original value. Instead, omit the field from
  `updateOrCreate`, then conditionally set it after:
  ```php
  $model = Model::updateOrCreate(['id' => $editingId], [...]);
  if (! $editingId) {
      $model->update(['user_id' => Auth::id()]);
  }
  ```

## Extracting a Reusable Nested Component

When one single-file Livewire component holds two responsibilities, split it
into a child component and a thin parent page:

1. Move the mechanics **verbatim** into `resources/views/livewire/<ns>/<name>.blade.php`.
   The child owns state and methods; the parent keeps access checks, detail
   panels and page chrome (header, theme selector).
2. Child → parent: `$this->dispatch('event', id: $id)` in the child,
   `#[On('event')] public function handler(int $id)` on the parent. Dispatched
   **named** arguments must match the listener's parameter names.
3. Per-node render hooks: pass a Blade view name plus a data array down as
   props and `@include($view, ['unit' => $unit, 'data' => $data])` in the node
   partial. Never let the child query page-specific data per node — that is the
   N+1 trap the extraction exists to remove.
4. Retarget mechanics tests to the child; keep auth/panel/render tests on the
   parent.

Test contract after the split:
- Parent `assertSee()` **does** include child-rendered HTML (children render
  inline), so page-level render assertions keep working.
- Parent `->get('prop')` / `->call('method')` do **not** reach the child — assert
  child state with `Livewire::test('child', $props)` and drive the parent through
  the event: `Livewire::test('parent')->dispatch('event', id: ...)`.
- Cover both halves of the wiring: `->assertDispatched(...)` on the child proves
  it fires, `->dispatch(...)` on the parent proves the listener runs. Asserting
  only the parent's handler by direct `->call()` passes even when the event is
  never dispatched.
- Batch level-wise loads (`whereIn('parent_id', $ids)`) rather than one query
  per node, and pin the result with a measured query-count assertion so the N+1
  cannot come back.

## Merge Conflicts in Auto-Generated Files

When a PR has merge conflicts with `upstream/beta` in auto-generated files
(like `phpstan-baseline.neon`), do NOT manually merge the conflict markers.
These files are machine-generated — manual merge produces invalid output.

**Procedure:**
1. `git fetch upstream beta && git merge upstream/beta`
2. For the conflicted auto-generated file: `git checkout --theirs <file>`
   (take upstream's version as starting point)
3. `git add <file>`
4. Regenerate from scratch: `vendor/bin/phpstan analyse --no-progress --generate-baseline`
5. Verify: `composer phpstan`
6. `git add <file> && git commit --no-edit`
7. `git push origin <branch>`

**Never** edit phpstan-baseline.neon by hand to resolve conflicts.
The regenerate step produces the correct baseline for the current code state.

## Testing Patterns

See `references/testing-pitfalls.md` for the full decision table on
assertion patterns, factory creation, scope/fixture traps, and E2E test
structure.