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

## Rules

- Read the top ~10 findings plus every finding that touches an executable
  entry point; skim-count the rest. Report the split ("N in docs/tests, M in
  runtime code") to the user — that is the decision-relevant fact.
- Present the override as the user's decision, with a recommendation only if
  your triage found nothing in the runtime code. The install stays blocked
  until they answer.
- A verdict is a verdict: never restate `CAUTION`/`BLOCKED` as "safe" or
  "verified" after overriding it.
