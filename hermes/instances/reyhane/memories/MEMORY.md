For h-dashboard PRs: user says 'pr' → create PR from current branch to upstream/beta (asgarimehdi/h-dashboard). All changes commit+push to current branch.
§
Every new session: default cwd is /home/runner/h-dashboard, and always use CodeGraph (`codegraph sync` first; codegraph_explore for code Q&A) + superpowers skills + read-the-damn-docs (web_search official docs) before acting; shadcn/improve for h-dashboard audits only on request.
§
Boost MCP occasionally dies on first stdio call ("lost its stdio subprocess") — just call it again. CLI fallback always works: php scripts/boost_tool.php <tool> '<json>'.
§
MaryUI x-select defaults to optionValue='id'/optionLabel='name'. Options keyed 'value'/'label' need explicit option-value="value" option-label="label" or every <option> renders empty (blank control). Pass :options="$this->myOptions()" from a component method — a bare $myOptions is undefined in the Blade view.
§
e2e/env rules: scripts/e2e-test.sh not concurrency-safe (never two runs; .env.dev.bak may already be swapped — after a run verify `grep DB_DATABASE .env` == h_dashboard). Lost bak: cp .env.e2e .env, APP_URL=http://127.0.0.1:8000, DB_DATABASE=h_dashboard; kill orphan `kill $(pgrep -f 'artisan serve --port=800[1]')`, never pkill -f 'artisan serve' (kills shared :8000). .env is gitignored: rebuild from .env-example-github + secrets in .env.e2e, drop `secrets.` lines, verify `php artisan about --only=environment`; parse_ini_file fails (unquoted parens) — regex scan or config().
§
homeassistant is permanently deny-listed in ~/.hermes/config.yaml (plugins.disabled) — never re-enable or `hermes plugins install` it; it was never installed here.
§
Peer wake-up single-instance rule (kylie/sonia/kimya/sevda): only ONE run per machine may be in_progress. Always `gh run list -R Shabakebehdasht/<repo> --json databaseId,status,conclusion` before dispatching; if a run is in_progress, do NOT start another — cancel the newer duplicate instead. Concurrent runs clash (both sync hermes state and claim the tailscale hostname).
§
h-dashboard: default branch = main, PRs merge into beta, so "Closes #N" does not auto-close the issue (only default-branch merges close them).