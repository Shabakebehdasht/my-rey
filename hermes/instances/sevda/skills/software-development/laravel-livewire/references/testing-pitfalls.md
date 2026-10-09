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
| Guard the scope in the query | `->when($ids, fn ($q) => $q->whereIn(...))` | unconditional `->whereIn('col', $ids)` — `when()` drops the predicate for an empty `$ids` and leaks the whole table |
| "Unit with zero personnel" fixture | attach the user's backing person to the unit under test | the user factory creates its backing `Person` on the **first existing** unit — create the empty unit *after* the user, or assert on a unit created later |
| Model reached through a person's scope | invent a `u_id`/`person_id` column on the child | link by `n_code` and resolve `persons.u_id` — hardware/hardware-audits scope through the person's unit, so pass the creator's `n_code`, and verify the column exists in the migration before trusting a factory override |
| Permission-gated endpoint fixture | pass an unrelated permission | the route's `role_or_permission` gate answers 403 before the controller runs, so the test proves nothing; grant exactly the gate's permission AND the matching Sanctum token ability |
| Query-count budget | guess a number | measure once, then set a bound with slack, and skip `BEGIN`/`COMMIT`/`ROLLBACK`/`SAVEPOINT` when counting |

## Livewire Effects & Success-Path Assertions

| Scenario | Wrong | Correct |
|---|---|---|
| Assert a toast/flash message | `assertSee('…')` | read `effects['xjs']` → `json_decode` the inner `toast({…})` → compare (text is `\uXXXX`-escaped) |
| Reuse an existing toast helper | `assertSee` on rendered HTML | extend the suite's helper; don't add a second one |
| Helper that "passes" by returning | `: void` + bare `return` | return the matched value so the caller asserts; a void helper makes the test *risky* (0 assertions) |
| Suite reports N risky tests | treat as noise | they are the tests asserting nothing; fix each, then re-check the count |
| Message string built from a possibly-array value | `"…{$results['errors']}"` | `count($results['errors'] ?? [])` — interpolation raises `Array to string conversion` |
| A `catch (\Exception)` sits after that message | assume it's defensive | it is swallowing the interpolation `ErrorException`; every later statement (reset + dispatch) is unreachable |
| Rows written but UI says "failed" | suspect the DB | it's false reporting — writes commit before the message is built; don't describe it as lost writes |
| Regression test for a swallowed success path | only `assertDatabaseHas` | assert success message **and** reset state **and** `assertDispatched('<event>')` — the write passes on old code too |
| Fixture for a bug that only fires on success | an errored fixture | a zero-error fixture; an errored one exercises the same catch legitimately |
| Prove the new test actually bites | trust it went red once | stash the implementation and re-run — confirm it fails at the intended assertion |
| Prove a leak reproduces before fixing | assume the issue is right | drive the unfixed path in a throwaway probe and print the real artifacts (rows created, files on disk, error bag); quote that output in the PR. Delete the probe file before committing |
| Owner/unit-scope leak test | assert only that a row renders | build a **pair** fixture (one row the viewer owns + one a colleague owns in the SAME unit) and assert the COUNT. With only the viewer row a leak is invisible; with only the colleague row the correct answer and the leak look identical |
| A pre-existing test pins the buggy behavior | treat its failure as a regression | that assertion was pinning the defect. Update its fixture to the correct contract and say so in the PR — do not silently "fix" it |
| RED is an error, not a failure | accept any red | a missing import / empty assertion also reads red. Confirm the failure message names the real defect before implementing |
| Scope-aware fixture (org tree, nested units) | create rows as siblings of the user's unit | create them as **children of** the actor's unit, or they fall outside the scope and the assertion passes for the wrong reason |

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

### Runner lifecycle

- A `set -e` runner that swaps `.env` (or any config file) **skips its restore
  step when a test fails** — restore the backup, remove temp state and kill the
  dev server yourself after every run, pass or fail.
- Never `pkill -f` a pattern that appears in your own command line: the shell
  matches itself and SIGTERMs the job you are still running. Bracket one
  character — `pkill -f "port=800[1]"` matches the server but not the command
  that mentions it.