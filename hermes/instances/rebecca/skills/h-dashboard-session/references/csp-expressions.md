# CSP-safe Alpine / Livewire expressions (h-dashboard)

This app runs the **CSP-safe builds**: `config/livewire.php` ships
`'csp_safe' => env('LIVEWIRE_CSP_SAFE', true)`, so the page loads
`vendor/livewire/livewire/dist/livewire.csp.js` (Alpine's CSP build + Livewire's
CSP expression parser). Two classes of code are **silently inert** under it.

Rules first, then the probes that prove a given form is dead before you rewrite it.

## Rule 1 — one statement per `wire:` action expression

`vendor/livewire/livewire/dist/livewire.csp.js` (~4651-4657):

```js
const expr = this.parseExpression();
this.match("PUNCTUATION", ";");
if (!this.isAtEnd()) throw new Error(`Unexpected token: ${this.current().value}`);
```

Exactly one expression, one optional trailing `;`, then EOF. A second statement
throws, and because Livewire rewrites bare identifiers to `$wire.<ident>` first
(`contextualizeExpression`, ~9345-9375) the thrown token is literally `$wire`:

```
Livewire Expression Error: CSP Parser Error: Unexpected token: $wire
Expression: "$dispatch('help-open', { section: 'dashboard' }); $set('showHelpModal', true)"
```

Consequences to remember:

- **The whole handler dies**, not just the second statement — no `$dispatch`, no
  `$set`, no server round trip. The button looks clickable and does nothing.
- A single statement is fine, including `$set(...)` and `$dispatch(...)` with an
  object-literal argument.
- Split, don't combine:
  ```blade
  wire:click="$set('showHelpModal', true)"
  x-on:click="$dispatch('help-open', { section: '{{ $section }}' })"
  ```
  Two independent single-statement directives both fire on the same click
  (verified live: Alpine state updated *and* Livewire property committed).

## Rule 2 — `x-data` must be a REGISTERED NAME, never a call

`x-data="initTrafficChart('1','2','Title', 7200)"`, object literals, method
shorthand and arrow functions all evaluate to an **empty data object**:

```
Object.keys(Alpine.$data(el))  ->  []
Alpine.$data(el).start        ->  undefined
```

`x-init="start($el)"` then never runs either. There is **no console error** —
the only symptom is a component that never does anything (charts stay blank, no
`fetch`, no error text, no loading spinner).

Correct shape — logic in plain JS, config in `data-*`:

```js
// resources/js/*.js, registered on 'alpine:init' (see resources/js/bootstrap.js)
Alpine.data('trafficChart', () => ({
  outItemId: '', duration: 3600, error: null, chart: null,
  init() {
    const ds = this.$el.dataset;
    this.outItemId = ds.outItemId || '';
    this.start(this.$el);
  },
  start(el) { /* … */ },
}));
```

```blade
<div x-data="trafficChart" data-out-item-id="…" data-in-item-id="…" data-duration="7200">
```

## Rule 3 — `$wire.prop = value` inside a directive expression is a silent no-op

Assignments to `$wire` members evaluated through the CSP parser do nothing (no
throw, no request). State writes that must bypass the parser live as **plain JS
listeners inside the factory** (`wireSet(this.$wire, name, false)` on a real
`click` handler), which is why the MaryUI `maryModal` factory looks the way it
does.

## Verified working / not working (measured, not assumed)

| Form | Result |
|---|---|
| `wire:click="$set('p', true)"` | works — request sent, property committed |
| `wire:click="$dispatch('e',{a:1}); $set('p', true)"` | **inert**, parser error at `$wire` |
| `x-on:click="$dispatch('e', { section: 'x' })"` | works (single statement, object literal ok) |
| `x-data="someFactory('a', 2)"` + `x-init="method($el)"` | **empty data object**, nothing runs |
| `x-data="maryModal"` + `:class="open ? 'a' : ''"` + `:open="open"` + `x-bind:inert="!open"` | works |
| `@click="$wire.set('m', false); $wire.cancel()"` | unverified — Alpine's own CSP parser is a different grammar from Livewire's; do not assume it inherits Rule 1 |

## Probes — decide a form empirically before rewriting a template

1. **State probe** (any page, no code change):
   ```js
   const el = document.querySelector('[x-data]');
   Object.keys(Alpine.$data(el))          // [] => x-data never evaluated
   typeof Alpine.$data(el).someMethod     // undefined => factory did not load
   ```
2. **Expression probe** (tests a directive shape without touching the repo):
   ```js
   const btn = document.createElement('button');
   btn.setAttribute('x-on:click', "$dispatch('help-open', { section: 'probe' })");
   btn.setAttribute('wire:click', "$set('showHelpModal', true)");
   document.querySelector('[x-data="helpModal"]').appendChild(btn);
   Alpine.initTree(btn);      // binds both directives like a real render
   btn.click();
   ```
   Check `_x_attributeCleanups` to confirm both directives bound, then read both
   sides: `Alpine.$data(wrapper).helpSection` and `$wire.showHelpModal`.
3. **Console capture**: the warn is `console.warn` **and** Livewire POSTs it to
   Laravel Boost's `/_boost/browser-logs`; hook `window.fetch` to read the
   payload, or read the app log. Register the hook **after** the navigation — a
   page load wipes `window` state.

## Migration checklist for any component touched

```bash
grep -rn 'x-data="[^"]*('            resources/views   # call form -> dead
grep -rn 'x-init="'                  resources/views   # only valid with a real factory
grep -rn 'wire:click="[^"]*;[^"]*"' resources/views   # multi-statement -> inert
```

A regression guard worth adding: a Pest test asserting **zero** occurrences of
`wire:click="…;…"` under `resources/views/**/*.blade.php`. Scope it to
`wire:click` only — `@click` is Alpine's parser, whose limits are not the same.
