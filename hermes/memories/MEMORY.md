For h-dashboard PRs: user says 'pr' → create PR from current branch to upstream/beta (asgarimehdi/h-dashboard). All changes commit+push to current branch.
§
Every new session: default cwd is /home/runner/h-dashboard, and always use CodeGraph (`codegraph sync` first; codegraph_explore for code Q&A) + superpowers skills + read-the-damn-docs (web_search official docs) before acting; shadcn/improve for h-dashboard audits only on request.
§
Boost MCP occasionally dies on first stdio call ("lost its stdio subprocess") — just call it again. CLI fallback always works: php scripts/boost_tool.php <tool> '<json>'.
§
h-dashboard branch reyhaneh tracks origin/beta (branch.reyhaneh.merge=refs/heads/beta), so `git status` shows 'reyhaneh...origin/beta'; always use explicit refspecs HEAD:refs/heads/reyhaneh.
§
MaryUI x-select defaults to optionValue='id'/optionLabel='name'. Options keyed 'value'/'label' need explicit option-value="value" option-label="label" or every <option> renders empty (blank control). Pass :options="$this->myOptions()" from a component method — a bare $myOptions is undefined in the Blade view.
§
.env is gitignored; rebuild from `.env-example-github` + secrets in `.env.e2e`, override APP_URL=http://127.0.0.1:8000 and DB_DATABASE=h_dashboard, drop `secrets.` lines, verify `php artisan about --only=environment`. parse_ini_file('.env') fails (unquoted parens) — regex scan or config() instead.
§
Map perf fixed (adc561f): bottleneck was main-thread rendering, not server (longtask /map pan 620→52ms). Fix: circleMarker+lazy popup, icon cache, id-Map/memo depth, canvas lines, dead Livewire loadStats removed.
OSM stack (Iran tiles/Nominatim/OSRM) is a separate public repo Shabakebehdasht/iran-osm-stack, running here in /home/runner/osm-stack. Ports 8080/8088/5000 all on 0.0.0.0 by user's choice (h-dashboard calls the last two from browser JS, so 127.0.0.1 breaks them). Nominatim still needs a rate-limit proxy (policy: max 1 req/s + User-Agent).
§
skill_manage create rejects descriptions >60 chars (index shows 57+'...'); put long trigger phrases in metadata.triggers + a 'When to use' body section instead.