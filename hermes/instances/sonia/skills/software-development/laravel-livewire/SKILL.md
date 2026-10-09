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

## Authorization on Livewire Mutators

`mount()` is **not** an authorization boundary. Livewire re-runs route
middleware on `/livewire/update` only for classes registered via
`Livewire::addPersistentMiddleware()`; anything else on the route is dropped.
So a page gated by `role_or_permission:*` (or any custom middleware) whose
component checks the permission **only in `mount()`** is unguarded for the
whole life of an open tab: a session whose permission is revoked mid-session
keeps writing. Every public mutator needs its own `authorize()`.

1. **`authorize()` goes in every mutator, as the first statement.** Read/write
   methods, and the form-opening methods (`edit()`, `openFormForCreate()`) —
   they fill public, client-settable component state, which is a read leak
   before any write. Copy the shape from a component in the project that
   already does it rather than inventing one.
2. **Use the permission the page's own `mount()` / route gate uses.** Gating a
   mutator with a *different* permission than the page is a silent trap: the
   route gate answers for one capability while the component guards another.
   Pin the mapping with a test that reads each component's source and asserts
   every `authorize('…')` call names the page's permission.
3. **Place the check BEFORE the write, and beware a trailing `mount()`.** A
   mutator that ends by calling `$this->mount()` to refresh its stats will
   re-authorize *after* its write — the request 403s while the org-wide update
   has already committed. Same for a method that dispatches a job before the
   guard: the job is already queued when the exception fires. Assert on the
   side effects (no row written, no job pushed), not only the status code.
4. **An exception assertion alone is not enough.** A mutator that throws a
   *validation* error also writes nothing, so "no exception and no row" can
   pass on the wrong behaviour. Assert the 403 **and** the unchanged data.
5. **A catch-all `catch (\Exception $e)` in front of a toast converts a 403
   into a 200.** This is why mount-only authorization bugs stay invisible. Catch
   `AuthorizationException` specifically and re-throw it so the 403 stays
   distinguishable from a domain failure like a foreign-key violation.
6. **Revoking a permission in a test needs a cache flush.** `revokePermissionTo()`
   plus `PermissionRegistrar::forgetCachedPermissions()`, otherwise the gate
   answers from a warm cache and the test cannot observe the revoke.
7. **Keep route-middleware persistence a separate decision.** Adding
   `addPersistentMiddleware(SomeGate::class)` re-runs that gate on every
   `/livewire/update` in the whole app, including components that rely on the
   route gate alone. Do not bundle it into a component-authorization fix; it is
   a different blast radius and belongs in its own change.
8. **Livewire's test harness already exempts `AuthorizationException`,** so
   `assertForbidden()` works without extra setup. `RequestBroker` calls
   `withoutExceptionHandling([HttpException, AuthorizationException, ModelNotFoundException])`
   — do not write a bespoke `expectException` around these, and do not assume
   the exemption applies to exceptions you throw yourself from a catch block
   (it applies to the class, so a re-thrown one is exempt too).

## File Cleanup Tied to an FK Cascade

When a parent row's `ON DELETE CASCADE` removes child rows, the cascade runs in
the **database, after Eloquent's model events**. Two consequences that decide
the whole fix:

- A hook on the **child** model never fires on that path at all — the child's
  rows are gone without Eloquent knowing.
- The parent's `deleted` event is already too late to read the child's columns.

Collect the paths in the parent's `deleting` hook (before the delete statement
runs), and delete the child rows explicitly there so the file and its row
disappear together rather than relying on the cascade. Read the paths with one
query and delete them in a single **array-form** call
(`Storage::disk($disk)->delete($paths)`); the local driver ignores missing
files when the disk sets `throw => false`, so a hand-deleted file still lets
the row go.

Ship a matching dry-run-first recovery command for the files the old path
already orphaned — it must delete **files only**: a row whose file is already
gone is a separate problem, and removing that row would hide it rather than
report it. Fixture traps for this shape (a migration whose PHP text disagrees
with the live schema, session-mutating helpers) are in
`references/testing-pitfalls.md`.

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
- **A JS `$wire.mount()` / `$wire.hydrate()` cannot re-run anything.** Livewire 4
  refuses direct calls to lifecycle hooks: `SupportLifecycleHooks` matches the
  method name against a protected list (`mount`, `boot`, `booted`, `exception`,
  `hydrate*`, `dehydrate*`, `updating*`, `updated*`, `rendering`, `rendered`,
  `scriptSrc`, plus trait-suffixed variants) and throws
  `DirectlyCallingLifecycleHooksNotAllowedException`. So an auto-refresh
  `setInterval(() => $wire.mount())` is a **broken feature**, not a recurring
  query cost — and any audit finding that ranks it as the heaviest recurring
  load is wrong. Call it via a public non-lifecycle method (`$refresh`, or a
  dedicated `refreshData()`) instead. Confirm by reading the vendor guard before
  believing either story.
- **Probing APIs that do not exist on the test harness.** `Livewire\Testing\Testable`
  has no `lastState` / `lastResponse`; use `->html()` and parse the snapshot, or
  `->instance()` for direct calls. `QueryExecuted` has no `getTrace()`; use
  `debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS, N)` and drop the
  `Dispatcher`/`Connection`/`Query\Builder` frames to name the caller.
- **`wire:snapshot` HTML-escaped in the rendered output.** `json_decode` on the
  raw attribute returns null; `html_entity_decode($m[1], ENT_QUOTES)` first.
- **A window/range constructor that keeps only its LENGTH discards the range.**
  The shape `between($from,$to)` → `$days = diff + 1` → `new self($days)` then
  rebuilding `[$from, $to]` from `now()` inside `window()` charts the wrong axis
  forever, and a LEFT JOIN over that wrong axis **silently drops** rows that were
  inside the range the user picked. The symptom is a summary total that disagrees
  with the chart summing it, with no error raised anywhere. Whenever a factory-style
  method takes two bounds, store both — `?Carbon $from` / `?Carbon $to` — and have
  the derived accessor return them unchanged; keep the single-argument
  `lastDays($n)` path deriving from `now()` so `?days=` callers stay untouched.
- **Carbon 3's `diffInDays()` is SIGNED.** `2026-06-30 → 2026-01-01` returns `-180`,
  so a `max(1, $days)` clamp on the *count* silently turns an inverted range into a
  single-day window instead of erroring or normalising. Normalise the bounds first
  (`if ($from->gt($to)) swap`), then compute.
- **`now()` is `CarbonInterface`, not `Carbon`.** Storing it in a constructor
  property typed `?Carbon` passes at runtime but fails PHPStan
  (`argument.type: CarbonInterface given`). Narrow with
  `Carbon::instance(now())` — the documented Carbon ≥ 3 conversion — instead of
  widening the property type or adding a cast.
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

## Measuring Livewire Cost Before Claiming a Perf Finding

Never file or fix a Livewire perf finding from reading code alone — quantify it.
A page that looks heavy can be cached, and one that looks light can ship a
300 KB snapshot on every keystroke. Full probe recipe and output format:
`references/perf-probing.md`.

1. **Query count per interaction.** Register one `DB::listen` collector, then
   measure deltas with an array offset (`$before = count($log)` +
   `array_slice($log, $before)`) — listeners accumulate across `Livewire::test()`
   calls in one process, so per-test counters drift if you bind inside the loop.
2. **Snapshot bytes per public property.** Render with `->html()`, regex
   `wire:snapshot="([^"]*)"`, `html_entity_decode(...)`, `json_decode`, and
   `strlen(json_encode($v))` for each entry of the **top-level `data` key**
   (`memo.data` does not exist). That table is the evidence for "this prop is
   the problem".
3. **Isolate the method, not just the page.** `$c->instance()->someMethod()` runs
   one method in isolation and attributes every query to it — the difference
   between "the page is slow" and "this method is called twice per interaction".
4. **Per-relation attribution.** Filter the log by a table name and print the
   repeated shapes with counts; `x318 select * from "units" where "id" = ?` is an
   eager-load miss stated as a fact.
5. **Check what triggers the method client-side.** `wire:model.live` on a filter
   select plus a JS `$wire.method()` inside `$watch` means one user click costs
   one full method execution, and the render still runs.
6. **Grep for the inline/`$wire` duplicate.** A chart or report method called
   both as `@php $data = $this->payload(); @endphp` in the markup (to fill stat
   tiles) and again as `await $wire.payload()` in the `<script>` block runs
   **twice per page view** even with zero user interaction. Find it with:
   `grep -n '@php \$[a-z]* = \$this->\|@php \$this->\|\$wire\.\<method\>()'`.
7. **Measure the proposed fix shape before filing, not just the problem.** Run
   the corrected query (`->with([...])`, batched `whereIn`) in the same probe and
   report both numbers — "1273 queries now, 5 with eager loading" makes the issue
   unarguable and sets the executor's target.
8. **Verify every framework-level claim against `vendor/`.** A finding that
   depends on framework behaviour (a blocked lifecycle call, a chunk-reading
   interface, a cache namespace) is only valid against the installed version.
   Grep the vendor path and quote it; if the vendor says otherwise, drop the
   finding rather than hedge it.

Two finding classes this surfaces that reading code misses:

- **A public property holding a whole reference table.** A full org tree
  assigned to a public array is re-serialized into `wire:snapshot` and re-POSTed
  by the browser on **every** update — the payload is proportional to the table,
  not to the page. Fix shape: `#[Computed]`, a protected/lazy-loaded property, or
  a search endpoint scoped to the modal that needs it.
- **Lazy relations inside a report/chart payload.** A method that `->get()`s rows
  and then reads `$row->relation?->name` per row issues one query per relation
  per row, and every filter change re-runs it. Fix shape: `with([...])` the
  relations, or resolve them from the small lookup tables already in memory.

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

## Migrations: driver guards, naming, and capping a window

Copy the **existing** trgm/index migration in the project rather than writing one
from memory — the established shape is the pgsql guard, the extension enable inside
it, `IF NOT EXISTS` on every create, and `DROP INDEX IF EXISTS` in `down()`:

```php
public function up(): void
{
    if (DB::getDriverName() !== 'pgsql') {
        return;               // same early return in down()
    }
    DB::statement('CREATE EXTENSION IF NOT EXISTS pg_trgm');
    DB::statement('CREATE INDEX IF NOT EXISTS foo_trgm_idx ON foo USING GIN (bar gin_trgm_ops)');
}
```

Keep the `IF NOT EXISTS` even when a standalone extension-enabling migration exists:
it is what lets a fresh database that ran only this migration succeed. `CREATE INDEX`
(plain, not `CONCURRENTLY`) matches the repo precedent; `CONCURRENTLY` cannot run
inside a transaction, which `migrate` wraps each migration in.

**Which columns deserve a trigram index** is a judgement call worth stating in the
PR rather than indexing everything:

- A column already covered by a **B-tree for exact/prefix lookups** does not need
  one for leading-wildcard `LIKE` unless users genuinely search it by fragment.
  Every index on a fast-growing table is write amplification — that cost is real
  and belongs in the argument.
- Indexing only what a search path actually queries: two surfaces searching the same
  table over *different* column sets means one index may never be used. Note the
  asymmetry in the PR so the migration is not read as "all search is indexed", and
  add a test that pins the deliberate omission so nobody adds it back quietly.

**Unclamped user-supplied windows are a DoS on your own browser.** A date picker
taking free-text dates has no `ReportDays`-style validator behind it, so a 40-year
range builds 14610 rows — one chart point each. Clamp in the service that builds the
window (one place, all callers) and keep the user-visible end bound; a cap that
silently returns a different range than requested is still a divergence, so anchor it
to the bound the user picked and assert that.

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

## Jobs and Scheduled Commands Run Without an Actor

A queue worker and the scheduler have **no authenticated user and no session**.
Any scope resolver built on `auth()->user()` / `session(...)` therefore returns
`[]` there — and every consumer that treats an empty scope as "nothing to do"
becomes a **silent no-op that still reports success**. Fail-closed, so no data
leak, but the work never happens and a success toast fires for it.

1. **Separate request-scoped scope from actor-independent scope explicitly.**
   Keep `accessibleUnitIds()` for UI/controllers/policies/imports and add a
   second, explicitly non-request-scoped method (e.g. `allUnitIds()`) that jobs
   and commands call. Never reuse the request-scoped one as a job fallback.
2. **An empty scope in a job/command means org-wide, not "the clicker's units".**
   Deriving retention/generation scope from whoever triggered it lets two users
   with different scopes prune or generate for two different slices of the same
   table. Keep an explicit parameter for a scoped run; empty = org-wide.
3. **Test every job with NO authenticated user.** `phpunit.xml` forcing
   `QUEUE_CONNECTION=sync` means a component test calling a job runs it inside
   the still-authenticated request, so the whole suite can be green while the
   real worker deletes nothing. Assert the precondition
   (`assertNull(auth()->user())`) so the test cannot quietly become
   authenticated later.
4. **Log before an early return.** `return 0;` placed above the `Log::info()`
   makes "genuinely nothing to do" indistinguishable from "ran and did
   nothing" — the exact ambiguity that hid the original bug.
5. **Do not call `handle()` on a resolved Command.** A `Command` resolved from
   the container has no console input bound, so `$this->option('x')` inside
   `handle()` throws `Call to a member function getOption() on null`. Use
   `Artisan::call('cmd:signature', [...])`, which binds input and returns the
   exit code. This turns a "fix the scope only" change into a hard 500 on a
   worker, so check for it whenever a job touches a command with options.
6. **Prove it on the real worker once, not just the sync harness.** Dispatch to
   the app's real queue connection and run
   `queue:work <conn> --stop-when-empty`, then assert on DB rows + the log
   line. Use throwaway probe rows/files (prefix them so cleanup is one
   `WHERE`-prefixed DELETE) and delete them plus the probe afterwards.

## Testing Patterns

See `references/testing-pitfalls.md` for the full decision table on
assertion patterns, factory creation, scope/fixture traps, non-actor job
testing, and E2E test structure.