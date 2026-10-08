# Quantifying Livewire / Eloquent Cost

Read-only measurement recipes for perf work on a Livewire 4 + Laravel project.
Nothing here writes to the app; every probe runs from a scratch script.

## The measurement harness

Bootstrap once, log in as a user that has the page's permission, put a scope in
the session (many pages derive their scope from `session('current_unit_id')`),
then drive `Livewire::test()`.

```php
$user = \App\Models\User::find(1);
\Illuminate\Support\Facades\Auth::login($user);
session()->put('current_unit_id', 1);

$log = [];
\Illuminate\Support\Facades\DB::listen(function ($q) use (&$log) {
    $log[] = preg_replace('/\s+/', ' ', $q->sql);
});
```

Run it with `php artisan tinker /abs/path/to/probe.php`. `tinker` prints Blade
compile noise (`mkdir(): File exists`, `DEPRECATED`) — filter it, and add
`tr -d '\0'` because backtraces carry binary-safe escapes that make grep treat
the output as a binary file and silently drop matches.

## Probe 1 — per-component cost table

Bind the listener ONCE before the loop; inside the loop use an offset so each
row is a clean delta.

```php
foreach ($components as $name) {
    $before = count($log);
    $t0 = microtime(true);
    $html = \Livewire\Livewire::test($name)->html();
    $ms = (microtime(true) - $t0) * 1000;

    $chunk = array_slice($log, $before);
    $agg = [];
    foreach ($chunk as $s) { $agg[substr($s, 0, 70)] = ($agg[substr($s, 0, 70)] ?? 0) + 1; }
    arsort($agg);

    $snap = 0;
    if (preg_match('/wire:snapshot="([^"]*)"/', $html, $m)) {
        $snap = strlen(html_entity_decode($m[1], ENT_QUOTES));
    }
    printf("%-20s q=%-4d %6.0fms snap=%-9s html=%-9s\n", $name, count($chunk), $ms, number_format($snap), number_format(strlen($html)));
}
```

Report this as the finding's evidence table: component, queries, time, snapshot
bytes, HTML bytes. A snapshot far larger than the page's own data (10s or 100s of
KB where everything else is under 2 KB) means a public property is holding a
reference table.

## Probe 2 — snapshot prop breakdown

Decoded snapshot shape is `{data, memo, checksum}` — the properties live under
the **top-level `data`**, not `memo.data`.

```php
$snap = json_decode(html_entity_decode($m[1], ENT_QUOTES), true);
foreach (($snap['data'] ?? []) as $k => $v) {
    printf("  %-24s %s bytes\n", $k, number_format(strlen(json_encode($v))));
}
```

Each row is one public property. Sort descending; the offender is visible
without interpretation. Confirm the round-trip consequence by sizing the POST
the browser sends: the update body is the same snapshot plus the diff, so
`snapshot + updates` bytes ≈ bytes per keystroke.

## Probe 3 — attribute queries to one method

```php
$before = count($log);
$c->instance()->chartPayload();     // or whichever method
$chunk = array_slice($log, $before);
```

Print the repeated shapes with counts. N eager-load misses show up as
`x<rowcount> select * from "<lookup table>" where "id" = ? limit 1` — one shape
repeated once per row per relation. That is the finding, stated numerically.

## Probe 4 — per-relation lazy-load attribution

When the repeated shape is not enough to name the caller, take a backtrace and
strip the framework plumbing frames:

```php
\Illuminate\Support\Facades\DB::listen(function ($q) use (&$log) {
    $sql = preg_replace('/\s+/', ' ', $q->sql);
    if (! str_contains($sql, 'from "units"')) { return; }
    $bt = debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS, 200);
    $frames = [];
    foreach ($bt as $f) {
        $fn = ($f['class'] ?? '').($f['type'] ?? '').($f['function'] ?? '');
        if ($fn !== '' && ! str_contains($fn, 'Dispatcher')
            && ! str_contains($fn, 'listen')
            && ! str_contains($fn, 'Connection->')
            && ! str_contains($fn, 'Query\Builder')) {
            $frames[] = $fn.(isset($f['file']) ? ' ['.basename($f['file']).':'.($f['line'] ?? '?').']' : '');
        }
        if (count($frames) >= 12) { break; }
    }
    $log[] = implode("\n    < ", $frames);
});
// dedupe identical frame stacks, prefix with the occurrence count
```

This is what distinguishes a lazy relation on a model (`MutateAttributeMarkedAttribute`
→ the accessor) from an accessor that misses a loaded relation entirely — two
different fixes.

## Probe 4b — inline + `$wire` duplicate execution

A payload method invoked once in the markup and once from JS runs twice per page
view, before any user interaction:

```
grep -n '@php .*\$this->\|@php \$this->\|\$wire\.\<method\>()' resources/views/livewire/<comp>.blade.php
```

Measure each half separately — the inline call lands in the `Livewire::test()`
construct/mount delta, the `$wire` call needs its own `->call('<method>')`:

```php
$b = count($log); $c->html();                       echo 'render: '.(count($log)-$b)."\n";
$b = count($log); $c->call('chartPayload');          echo '$wire:  '.(count($log)-$b)."\n";
$b = count($log); $c->set('filter', '1');           echo 'change: '.(count($log)-$b)."\n";
```

Three lines: render cost, method-via-`$wire` cost, one filter change. When the
method is the N+1, `render + $wire` ≈ 2× the single-execution number — that
doubling is the headline number in the issue.

## Probe 4c — measure the fix, not only the fault

Run the corrected shape in the same probe so the issue carries its own target:

```php
$ids = app(AccessService::class)->accessibleUnitIds();

// current
$b = count($log);
Model::whereIn('u_id', $ids)->orderBy('n_code')->get()->map(fn ($p) => [
    $p->unit?->name, $p->tahsil?->name, $p->semat?->name, $p->estekhdam?->name,
]);
echo 'now:   '.(count($log) - $b)." queries\n";

// with the relations eager-loaded
$b = count($log);
Model::with(['unit', 'tahsil', 'semat', 'estekhdam'])
    ->whereIn('u_id', $ids)->orderBy('n_code')->get()->map(fn ($p) => [
        $p->unit?->name, $p->tahsil?->name, $p->semat?->name, $p->estekhdam?->name,
]);
echo 'fixed: '.(count($log) - $b)." queries\n";
```

Keep every other line identical so the delta is attributable to the one change.
Same trick for snapshot weight: drop one public prop in a scratch harness and
re-measure `wire:snapshot` bytes.

## Probe 5 — client-side trigger count

Grep the component for what fires the method:

```
grep -rn "wire:model.live" resources/views/livewire/<comp>   # each = one round trip
grep -rn '\$wire\.<method>()' resources/views/livewire/<comp> # inside $watch = another full run
```

Multiply per-interaction cost by trigger count. `wire:model.live` on N filter
selects plus a `$watch` that calls the method means one click = 2 executions, and
the `wire:model.live` request re-renders the whole component as well.

## Reading the numbers honestly

- Absolute query counts from a dev database understate the problem; the
  **repeated-shape** (`x318`) and the **snapshot bytes** are size-independent
  and are what to put in the issue.
- Report per interaction, not per page load: "one debounced keystroke" and
  "one filter change" are the units a user feels.
- A cached page will read fast while still shipping a large snapshot — always
  report snapshot and HTML bytes next to query count and time, never time alone.
- Do not present a shape that a `Cache::remember` in the current code already
  absorbs as a live cost. Check for a cache on the path before writing the
  finding.
- **Repeated shapes are the evidence, not the absolute count.** A dev database
  understates the total, but `x318 select * from "units" where "id" = ?` is
  size-independent: quote it, plus the one-line fix delta from Probe 4c.
- **Vet every finding that depends on framework behaviour against `vendor/`.**
  Grep the installed version for the guard or interface and quote it. Findings
  that assume a newer/older framework API, or that misread a guard as a code
  path, must be dropped or corrected in place — never hedged.
- **Say which scope the number came from.** Row counts, snapshot bytes, and
  table sizes change; a reader needs the seed state to judge them, so state the
  scope (e.g. "834 units, 318 persons") in the issue.