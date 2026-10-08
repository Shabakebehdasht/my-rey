# Triaging a blocked plugin security scan

The scanner flags *text matches*, not executed behavior, so most findings on
mature multi-harness repos are documentation and tests. Triage before asking
the user to override.

## Almost always false positives

| Pattern | Why it's benign |
|---|---|
| `rm -rf` inside `.opencode/INSTALL.md`, `docs/README.*.md` | Uninstall instructions for *other* harnesses' install dirs |
| `os.environ[...]` / `env \| grep` in `tests/`, `docs/` plans, eval specs | Test assertions and design docs reading their own fixture vars |
| Placeholder tokens (`abab…`, `testtoken-…`) in `tests/` fixtures | Fake credentials in test files, never wired to a network |
| `git clone`, `pip/npm install` in `docs/`, `scripts/`, test harnesses | Dev/CI bootstrap of the repo itself |
| `path.resolve(__dirname, '../../…')` in per-harness extension shims | Normal path math; traversal only matters if it reaches user config to *write* |
| Mentions of `CLAUDE.md` / `AGENTS.md` persistence in release notes | Changelog prose |

## Where real risk lives

- Executable entry points: `index.js`, `hooks/`, `scripts/`, anything named by
  `provides_hooks` in `.hermes-plugin/plugin.yaml` — these run inside the
  gateway (`pre_llm_call` hooks see every prompt).
- Install-time side effects: commands the installer runs, postinstall scripts,
  network fetches beyond the clone.
- Writes outside the plugin directory: config edits (`~/.bashrc`,
  `trustedFolders.json`), credential-file access, telemetry endpoints.

## Reading the runtime code without installing

A `CAUTION` verdict does not require installing to review: clone shallow into
scratch and read the entry points first, so the summary you give the user is
based on code rather than on finding text.

```
git clone --depth 1 https://github.com/<owner>/<repo> ~/.hermes/cache/scratch/<name>
```

Then, inside the clone:

- `cat .hermes-plugin/plugin.yaml` → `version`, `provides_hooks` (what executes).
- `cat .hermes-plugin/__init__.py` → the whole Hermes-side runtime. For a
  skills+bootstrap plugin this is typically the entire attack surface: a
  `register(ctx)` that calls `ctx.register_skill(...)` per skill plus one hook
  returning fixed text. Read it in full; it is usually under ~100 lines.
- `python3 -c "import json;d=json.load(open('package.json'));print(d.get('dependencies'),d.get('scripts'))"`
  → `None None` means there is no install-time code to be malicious.
- Grep the runtime files only (not `docs/`) for network and env access:
  `grep -rniE 'https?://|fetch\(|curl |wget |axios|requests\.|node:http|os\.environ|getenv' index.js hooks/ .hermes-plugin/`
  A single URL inside a comment is not exfiltration.
- Cross-check per-harness shims against `provides_hooks`: a repo can ship
  `index.js`, `hooks/session-start` and `scripts/*.sh` that belong to OpenCode,
  Codex or CI. They never execute under Hermes unless the manifest names them,
  so say explicitly that they are out of scope rather than counting them as risk.
- `find . -maxdepth 2 -type f -perm -u+x` → executables actually present; name
  which harness owns each.

Report the split as counts plus the one runtime-file verdict: "N findings in
docs/tests, M in runtime; the M consist of X which only does Y." That is the
fact the user needs to decide on `--force`.

## Rules

- Read the top ~10 findings plus every finding that touches an executable
  entry point; skim-count the rest. Report the split ("N in docs/tests, M in
  runtime code") to the user — that is the decision-relevant fact.
- Bulk severity lines can run to hundreds and blow up the context: capture the
  install to a scratch file and grep it for the verdict line plus severity and
  path columns instead of tailing the whole output.
- Expect `HIGH` findings that are pure documentation and test prose on mature
  repos; do not let the count push you toward recommending an override on its
  own. Recommend only when the runtime code path is clean.
- Present the override as the user's decision, with a recommendation only if
  your triage found nothing in the runtime code. The install stays blocked
  until they answer. Ask with `clarify()` offering yes/no choices.
- A verdict is a verdict: after installing with `--force`, still report the
  scan as `CAUTION` and that the override was the user's call — never restate
  it as "safe" or "verified". Say which check is only cosmetic (e.g. a
  manifest warning that fires while the manifest exists) and why, rather than
  leaving the user unsure whether the install is whole.
