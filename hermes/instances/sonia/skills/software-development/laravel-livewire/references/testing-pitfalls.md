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
| Editing a single-file Livewire component that has baseline entries | add the `use …;` import you need at the top of the Blade view | Reference the class **fully-qualified** inline instead — the baseline is keyed to the anonymous-class line number (`…roles/index.blade.php:9::$sortBy`), so one added `use` line shifts `return new class extends Component` from `:9` to `:10` and every entry for that file reports as unmatched |
| CI fails with `Ignored error pattern … was not matched` and no real error | regenerate the baseline (48+ churned entries) | The baseline is line-keyed, so a cosmetic line shift is the cause. Restore the line rather than accepting the churn — regenerating to `:10` re-breaks the moment anyone runs the formatter. Assert the fix with `pint --test` plus `phpstan`, both green |
| Adding a scope to an existing model lookup (`Model::find($x)` → `Model::whereIn('id', $ids)->find($x)`) | writing the static chain | `Call to an undefined static method` — the forwarders aren't declared without larastan, so the old `find()` carried a baseline entry and the new chain would need one. Past `whereIn()` the receiver also types as `Query\Builder`, so `find()` degrades to `stdClass` and breaks assignment to a `?Model` property. One form fixes both: `Model::query()->where(fn ($q) => $q->whereIn('id', $ids))->find($x)` |
| Reading a regenerated baseline diff to check for new suppressions | trusting the `git diff` | `--generate-baseline` reorders unrelated entries, so the diff shows `+` lines for suppressions you never added. Parse both revisions' `(message, identifier, count, path)` tuples and compare as multisets; only entries for code you actually touched may appear |

## Jobs, Queues & Scheduled Commands

These paths have no actor, which breaks any `auth()`/`session()`-based scope.

| Scenario | Wrong | Correct |
|---|---|---|
| Job falls back to a request-scoped scope | `accessibleUnitIds()` as the empty-case fallback | an explicitly non-request-scoped resolver (`allUnitIds()`); empty scope = org-wide |
| Job "ran" but deleted nothing | `return 0;` above the `Log::info()` | log first, then return — keep "nothing to do" distinguishable from "did nothing" |
| A job invokes a command with options | `app(Command::class)->handle()` | `Artisan::call('cmd:name', [...])` — a resolved Command has no console input, so `option()` throws `Call to a member function getOption() on null` |
| Proving a job works | a component test (`QUEUE_CONNECTION=sync` runs it in-request) | dispatch to the real queue connection, `queue:work <conn> --stop-when-empty`, then assert DB rows **and** the log line |
| Making the no-actor condition explicit | assume the test is unauthenticated | `Session::flush()` / `Auth::logout()` **and** assert the precondition `assertNull(auth()->user())` |
| Existing scoped-run coverage | delete it as redundant | keep it — an explicit `$unitIds`/`--unit` path is a separate behaviour from the org-wide default |

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
| Call a session-mutating fixture helper twice in one test | assume the second fixture is independent | A shared helper that sets `current_unit_id` (or any session key) on the **second** call moves the first actor's own rows out of their scope — the request then 403s and the test is proving the API gate, not the behaviour it was written for. Use one actor/one unit, or re-establish the session before the request under test |
| Assert a mutator is refused, checking only the response code | `->assertForbidden()` alone | Also assert the side effects did not happen — no row written, no job pushed. A mutator that threw a *validation* error writes nothing too, so a status-only test can pass on the wrong behaviour |
| Trust a scope you just built | use it directly | `expect($scope)->not->toBeEmpty()` first — an empty scope makes every "excludes X" assertion pass for the wrong reason |
| "Unit with zero personnel" fixture | attach the user's backing person to the unit under test | the user factory creates its backing `Person` on the **first existing** unit — create the empty unit *after* the user, or assert on a unit created later |
| Fixture inserting a child row fails on a column you believe is nullable | re-read the migration to check | Query `information_schema.columns` for `is_nullable` — the migration's PHP source does not always match the live schema (e.g. an `unsignedBigInteger()` column that is `NOT NULL` in the database). Let the schema decide the fixture |
| Livewire mutator must return 403 | write a bespoke `expectException` around the call | `assertForbidden()` works directly — Livewire's `RequestBroker` already calls `withoutExceptionHandling([HttpException, AuthorizationException, ModelNotFoundException])`, and a re-thrown `AuthorizationException` from a catch block is exempt too |
| A regression test for a bug fixed upstream passes on day one | ship it as proof the guard works | Temporarily re-introduce the defect, watch the test fail for the predicted reason, then restore — see `test-driven-development`, "Establish RED when the fix already landed upstream" |
| Query-count budget | guess a number | measure once, then set a bound with slack, and skip `BEGIN`/`COMMIT`/`ROLLBACK`/`SAVEPOINT` when counting |
| Asserting a whole organization must NOT be listed | assert only that a known foreign row is absent | Assert the paginator's `total()` is `0` too, and pin that the fixture's scope really is empty (`assertSame([], $service->scope())`) first — an assertion that passes because the fixture never had a scope proves nothing |
| A negative scope test whose fixture uses a bare factory row | `Unit::factory()->create()` and assert the foreign row is hidden | Set every eligibility flag the query filters on **explicitly**. Factories routinely omit boolean columns and the migration default decides: a row created without the flag is excluded by the *eligibility* predicate, not the scope one, so the negative assertion goes green against unfixed code. Read the migration's `->default()` before trusting a bare factory row |
| A leak/scope test file with only negative assertions | assert the foreign row is absent | Add the positive direction — a row **inside** the actor's scope must still resolve and render. Every negative assertion also passes against code that resolves nothing at all, so without it the suite cannot tell a closed leak from a broken component |
| A guard change is visible only in the markup, not in state | assert the component property is null | Assert on `->html()` too. A Blade guard that tests the id rather than the resolved model leaves a fallback chip («فیلتر: نامشخص») rendered for a row the actor cannot see — the property is null, so a property-only assertion passes and the dead UI ships |
| Fixture user needs an empty organizational scope | `User::create(['n_code' => …, 'password' => …])` | `users.n_code` is FK-bound to `persons`, so a raw insert violates the constraint. Use the factory (which attaches the backing person), null out its `u_id`, and clear the session unit key — a factory user otherwise always resolves a scope through `person.u_id` |
| Fixture row meant to be visible to a scoped actor | creating it standalone, and asserting the positive case works | A recursive-scope resolver's CTE returns the anchor ids **unconditionally** and adds children under `is_active = true`, so a row with no `parent_id` is a tree root in nobody's scope and the positive assertion fails for reasons unrelated to the code under test. Give it `parent_id` = the actor's own unit |
| An existing test breaks after you scope a query | relaxing or skipping the assertion | Diagnose the fixture first: a test that passed because the query was unscoped was pinning the leak. Move the fixture row into scope (`parent_id` = the actor's unit) and keep the assertion verbatim. A silently weakened assertion is invisible to the next reviewer and reintroduces the bug silently |
| `wire:click="select(id)"` guard uses `in_array($id, $ids, true)` | strict compare on the raw parameter | Unquoted attributes deliver strings while typed props deliver ints, so strict mode rejects a legitimate id and fails closed on the path meant to succeed. Cast first: `in_array((int) $id, $ids, true)`, and document the dual shape in the param docblock |

## Proving a Database Index Exists (Postgres)

A search test that only asserts the endpoint answers proves **nothing** about the
index — the query returns the same rows with or without it, so such a test cannot
catch a dropped index. Assert on the **plan** or on the **catalog**.

```php
// The plan is the assertion. enable_seqscan = off is REQUIRED.
DB::statement('SET LOCAL enable_seqscan = off');
$plan = implode("\n", array_column(
    DB::select("EXPLAIN SELECT id FROM tickets WHERE subject LIKE ?", ['%term%']),
    'QUERY PLAN'
));
$this->assertStringContainsString('Bitmap Index Scan', $plan);
```

| Scenario | Wrong | Correct |
|---|---|---|
| Proving a trigram/LIKE index works | assert the search returns rows | `EXPLAIN` + assert `Bitmap Index Scan` |
| Making the plan observable in a test | run the query as-is | `SET LOCAL enable_seqscan = off` — on a small table the planner picks a seq scan *regardless of existing indexes*, so the test would measure the fixture, not the index |
| Asserting an index exists | assume the conventional name | query `pg_indexes.indexdef` for `USING gin` / the opclass — generated names often embed the column (`<table>_<column>_unique`) and do not match the migration's variable name |
| Rolling back one migration in a test | `migrate:rollback --step=1` | `migrate:rollback --path=database/migrations/<that-file>.php` — `--step=1` rolls back whichever is last and silently shifts whenever a migration is appended |
| Asserting an index was deliberately *not* created | assert on the index NAME | assert on `indexdef` **contents** — the B-tree you are relying on may itself be named after that column |

`enable_seqscan = off` also means a *false* positive is possible in the other
direction — Postgres can pick an unusable index and pay for it. For a GIN
trigram index the plan line is unambiguous, so this is safe; for a B-tree a
`Bitmap Index Scan` is the right signal and a `Seq Scan` under the flag genuinely
means no usable index.

## E2E Test Structure

```
tests/e2e/<feature>/<feature>.spec.ts
```

Imports from `../shared/fixtures`:
- `login(page, nCode?, password?)` — fills login form, waits for redirect
- `waitForLivewire(page)` — waits for `.wire-loading` to disappear
- `waitForToast(page, text?)` — waits for toast notification

Pattern:
1. `test.beforeEach` — login + navigate to page
2. Test: page loads (assert header, key elements visible)
3. Test: CRUD operations via Livewire modals
4. Use `page.locator('input[wire\\:model="field"]')` for Livewire inputs
5. Use `page.getByRole('button', { name: '...' })` for buttons
6. Always `waitForLivewire(page)` after actions that trigger updates
7. Prefer `expect.poll(() => locator.count(), { timeout })` over fixed sleeps for
   anything a `wire:click` changes — `waitForLivewire` only helps when the
   template actually renders `.wire-loading`.

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
  pass them: a clearable input appends a trailing space to `placeholder`, so
  `input[placeholder="..."]` matches nothing while the page looks fine — use
  `input[placeholder^="..."]`.
- **A `wire:ignore` readonly input cannot be typed into.** Date pickers inside
  `wire:ignore` are driven by their JS widget, not by `fill()`. Find the event the
  page's own listener binds to (e.g. a picker dispatching `jdp:change` into
  `$wire.set('prop', …)`) and dispatch exactly that from `locator.evaluate()`, or
  the test writes a value nothing reads and then asserts on stale state:

  ```ts
  await page.locator('#some_date_input').evaluate((el, v) => {
    (el as HTMLInputElement).value = v;
    el.dispatchEvent(new CustomEvent('jdp:change', { detail: { value: v }, bubbles: true }));
  }, '1403/10/01');
  ```

  Cast to `HTMLInputElement` — `evaluate` types the element as `SVGElement | HTMLElement`,
  so `.value` is a TS error without it.
- **Assert the rendered axis/payload, not just that the chart container rendered.**
  `expect(chart).toBeVisible()` passes on wrong data; read the data out of the chart
  instance (`Highcharts.charts.find(c => c.renderTo.id === 'trendChart').xAxis[0].categories`)
  and compare it to what was requested.
- **A test file that only ever asserts visibility is not covering the fix.** When
  the bug being fixed is in what the chart *shows*, extend the existing suite rather
  than adding a new file, so the assertion lives next to the fixtures that set it up.

### Runner lifecycle

- A `set -e` runner that swaps `.env` (or any config file) **skips its restore
  step when a test fails** — restore the backup, remove temp state and kill the
  dev server yourself after every run, pass or fail.
- Never `pkill -f` a pattern that appears in your own command line: the shell
  matches itself and SIGTERMs the job you are still running. Bracket one
  character — `pkill -f "port=800[1]"` matches the server but not the command
  that mentions it.