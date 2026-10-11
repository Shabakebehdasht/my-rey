# Laravel Testing Pitfalls — Decision Table

## Resource Transformer Assertions

| Scenario | Wrong | Correct |
|---|---|---|
| Check `whenLoaded` not loaded | `expect($array['unit'])->toBeNull()` | `expect($array['unit'])->not->toBeInstanceOf(Unit::class)` or `array_key_exists` check |
| Validate ISO 8601 dates | `DateTimeImmutable::createFromFormat(ATOM, $str)` | `strtotime($str)` — flexible, handles `.000000Z` suffix |
| Assert factory nullable field | `'icon' => null` on NOT NULL column | Use column default: `'icon' => 'o-bell'` |
| Generate optional JSON data | `fake()->passthrough()` | `fake()->words(3)` — passthrough requires a value argument |

## PHPStan Patterns for Laravel/Livewire

| Scenario | Wrong | Correct |
|---|---|---|
| Access auth ID in blade component | `auth()->id()` | `Auth::id()` with `use Illuminate\Support\Facades\Auth;` |
| HasFactory on model | `use HasFactory;` alone | `/** @use HasFactory<\Database\Factories\XFactory> */` above `use HasFactory;` |
| JsonResource magic property | `$this->field` in `toArray()` | `@property-read` annotations + `$model = $this->resource;` with `@var Model $model` |
| After fixing PHPStan errors | Run `composer phpstan` once | Regenerate baseline: `vendor/bin/phpstan analyse --generate-baseline`, then verify |

## Factory Creation Checklist

1. Check the migration for NOT NULL columns — factory must not pass null.
2. Check if model has `HasFactory` trait — add it if missing.
3. UUID models: manual `Str::uuid()` in `boot()` + `HasFactory` is fine;
   do NOT add `HasUuids` trait (conflicts with boot logic).
4. After seeding explicit IDs in tests, resync Postgres sequence:
   `SELECT setval('table_id_seq', (SELECT MAX(id) FROM table))`.

## Scope & Fixture Traps

| Scenario | Wrong | Correct |
|---|---|---|
| Resolve an auth-scoped id list in `beforeEach` | create + attach a user, then read the scope | `actingAs($user)` first — a create/attach helper does **not** log in, and an `auth()`-based scope resolver returns `[]` |
| Trust a scope you just built | use it directly | `expect($scope)->not->toBeEmpty()` first — an empty scope makes every "excludes X" assertion pass for the wrong reason |
| "Unit with zero personnel" fixture | attach the user's backing person to the unit under test | the user factory creates its backing `Person` on the **first existing** unit — create the empty unit *after* the user, or assert on a unit created later |
| Query-count budget | guess a number | measure once, then set a bound with slack, and skip `BEGIN`/`COMMIT`/`ROLLBACK`/`SAVEPOINT` when counting |
| Two query-count measurements in one test method | call the query-count helper twice and compare | shared `assertNoNPlusOne`/`assertQueryCount` helpers register a `DB::listen` listener **globally and never unregister it**, so the second measurement starts from the first one's total. Prove "same count at 5 rows and at 20 rows" with separate test methods (or subtests), or reset the counter between measurements |
| Poison row for a 500 / regression test | seed it into whatever unit/model a shared helper returns first | a row outside the viewer's reachable scope is filtered out, so the page renders and the test goes green **without ever exercising the bug**. Put it in the viewer's OWN unit. When the helper does `$overrides['fk'] ?? $default`, that also folds "explicitly absent" into "not supplied" — switch to `array_key_exists()` and add a dedicated constructor path for the absent case |
| Asserting a word a shared layout already renders | `assertSee('System')` | the help modal / navbar renders the word on every page, so the assertion passes no matter what the feature under test does — a test that can only pass. Scope it to the element's own markup (`assertSee('<span class="...">System</span>', escape: false)`), then **revert the fix and confirm it goes red**; only then does it count as evidence |
| Reproducing a null/soft-delete rendering bug | assert against a hand-built model in isolation | a real row reached through the real component and the real scope proves the whole chain. Use a throwaway probe test that writes `get_class()` / substr_count of the rendered HTML to STDERR when you need to *discover* which class a framework call receives or where a string actually comes from — then delete it before committing |

## Fixture Traps for Graphs & Walks

A test over a hierarchy/relationship walk passes for the wrong reason when the
fixture does not contain the very thing it asserts.

| Scenario | Wrong | Correct |
|---|---|---|
| Prove a walk terminates / a depth guard truncates | seed only the relationship rows | seed the matching **parent rows** too — a final `whereIn` against missing parents silently filters the answer down, so the assertion passes while the walk misbehaves |
| Prove a cycle is deduped, not truncated | assert only "the call returns" | assert the cycle's own id is **present exactly once** — a bare termination check also passes for a depth cap that silently drops the intended member |
| A test that only fails by hanging | run the suite and eyeball the diff | `timeout 60 <cmd>; echo $?` — `124` = killed while hanging, i.e. RED |
| Assert a bound ("the guard truncates the walk") | invent a number | build a chain deeper than the guard with real ids, state the reachable total, assert the returned count is strictly below it, and offset ids clear of the shared fixture rows |

## E2E Test Structure

```
tests/e2e/<feature>/<feature>.spec.ts
```

Imports from `../shared/fixtures`:
- `login(page, nCode?, password?)` — fills login form, waits for redirect
- `waitForLivewire(page)` — **NOT a working gate; see below**
- `waitForToast(page, text?)` — waits for toast notification

### `waitForLivewire` is an inert gate — do not rely on it

The common `waitForLivewire(page)` helper polls for a `.wire-loading` element.
**No element ever gets that class.** `wire:loading` is a *directive* that toggles
`style.display` on its own element (`toggleBooleanStateDirective` in
`vendor/livewire/livewire/dist/livewire.esm.js`); the only occurrence of the
string `wire-loading` in the bundle is a source-path comment. So the helper's
first clause — "no `.wire-loading` element exists" — is always true and it
resolves instantly.

Everything asserted after it may therefore read a half-morphed DOM. Verify the
helper is real before trusting any suite that calls it:
`grep -o '.\{80\}wire-loading.\{80\}' vendor/livewire/livewire/dist/livewire.esm.js`
— empty output means the selector is dead.

**Prefer a positive wait on the thing you actually expect to change:**
`await expect(locator).toHaveCount(n)`, `expect.poll(() => locator.count())`, or
`waitForSelector(selector, { state: 'visible' })`. When you must wait on the
request itself, wait on an element that actually carries `wire:loading` /
`wire:target`, e.g. `page.locator('[wire\\:loading]').first().waitFor({ state: 'hidden' })`
— and note that resolves only for directives the template really renders.

Pattern:
1. `test.beforeEach` — login + navigate to page
2. Test: page loads (assert header, key elements visible)
3. Test: CRUD operations via Livewire modals
4. Use `page.locator('input[wire\\:model="field"]')` for Livewire inputs
5. Use `page.getByRole('button', { name: '...' })` for buttons
6. After any action that triggers an update, wait on a **positive** signal for
   the change (count, text, visibility) — not on `waitForLivewire`.
7. Prefer `expect.poll(() => locator.count(), { timeout })` over fixed sleeps.

### Assertions on seeded data

- **Never assume a filter narrows the result set.** A tree/search UI that
  *expands* its matches shows MORE nodes after filtering than the default view.
  Assert semantics instead of direction: the highlight class is present, a deep
  node that was previously hidden is now visible, clearing the term removes the
  highlights.
- **Query the seeded database for facts before choosing an assertion.** The
  suite migrates and seeds fresh every run, so tree depth, names and match
  counts are reproducible — a count-based guess is what fails:
  `psql -h 127.0.0.1 -U <user> -d <e2e_db> -tAc "SELECT count(*) FROM units WHERE name LIKE '%x%'"`
- **Match component-rendered attributes by prefix.** Wrappers rewrite what you
  passes them: a clearable input appends a trailing space to `placeholder`, so
  `input[placeholder="..."]` matches nothing while the page looks fine — use
  `input[placeholder^="..."]`.

### Runner lifecycle

- A `set -e` runner that swaps `.env` (or any config file) **skips its restore
  step when a test fails** — restore the backup, remove temp state and kill the
  dev server yourself after every run, pass or fail.
- Never `pkill -f` a pattern that appears in your own command line: the shell
  matches itself and SIGTERMs the job you are still running. Bracket one
  character — `pkill -f "port=800[1]"` matches the server but not the command
  that mentions it.

## Testing a Repeated Defect Across Many Files

When a defect class repeats across N sites (a missing gate, a missing index, a
missing `authorize()`), the tests that protect the fix have to repeat across N
sites too — and the N-1th one you skip is the Nth regression.

### Extend the sweep before writing a parallel suite

A codebase that fixed one instance of a repeating defect often ends with a
**source-scanning test** holding a hardcoded map of the files already fixed.

```php
$source = [
    'resources/views/livewire/roles/index.blade.php' => 'manage_roles',
    'resources/views/livewire/permissions/index.blade.php' => 'manage_roles',
];
foreach ($source as $file => $permission) {
    preg_match_all("/authorize\('([^']+)'\)/", file_get_contents(base_path($file)), $m);
    // assert every found name equals $permission
}
```

**Grep for the sweep's assertion shape before authoring anything new.** A
duplicate suite rots independently and the executor does not know the other one
exists. Extending the map is strictly better: it inherits the existing
explanation, the already-fixed files as precedent, and the exact `preg` shape the
author tuned.

Two sweeps usually coexist and both are worth extending:

| Sweep shape | Asserts | Add a file when |
|---|---|---|
| every `authorize('X')` in the file names one permission | a mistyped permission | any file gains an `authorize()` call |
| every `catch` of the exception type re-throws | the clause contains `throw $e;` | the file wraps a mutator in `try/catch` |

The second has a trap: it asserts an **exact count** (`assertSame(1, ...)`), so
only add files that genuinely have exactly one such catch. A file whose mutator
returns early on every guard and has no `try` at all will fail the assertion.
Check the full method body before adding a file — not a truncated window of it.

### Structural assertions still need behavioural ones

A source scan proves the **code** is shaped correctly. It passes happily on a
call placed *after* the write, or inside a branch that never runs. Pair it with a
behavioural test that mounts the component, revokes the permission, and asserts
**both** the exception and the untouched row:

```php
test('createX is refused after the permission is revoked', function () {
    ['user' => $user] = $this->createUserWithUnit(['the_permission']);
    $this->actingAs($user);

    $component = Livewire::test('x.index')->assertStatus(200);

    $user->revokePermissionTo('the_permission');
    app(PermissionRegistrar::class)->forgetCachedPermissions();

    $component->set('name', 'Escalated')->call('createX')->assertForbidden();

    $this->assertDatabaseMissing('xs', ['name' => 'Escalated']);
});
```

Three details make it real:

1. **Mount while the permission is still held**, then revoke — a fresh mount 403s
   on the route gate and proves nothing about the mutator.
2. **Seed the fixture between mount and revoke**, on the same actor and unit the
   tab was opened with. Otherwise the assertion passes for the wrong reason (the
   row sits somewhere the actor could never have reached).
3. **Assert the row too.** A mutator that failed *validation* also leaves no row;
   `assertForbidden()` plus `assertDatabaseMissing()` together prove the refusal
   came from authorization.

Always add a **positive** control — a user who still holds the permission can
call the mutator. Fail-closed permission names (unknown name → `false`, not an
exception) turn a typo into a green suite over a locked-out app, and only a
positive test catches it.

### Fixtures for components that load data in `mount()`

A behavioural test on a component whose `mount()` queries lookup tables cannot
mount without them. Copy the `setUp()` from an existing test of the same
component rather than guessing, or every test in the new file fails at mount for
a reason unrelated to the gate under test:

```php
protected function setUp(): void
{
    parent::setUp();
    $this->seed(PermissionSeeder::class);
    $this->seedLookupTables();
}
```