# CI Troubleshooting Quick Reference

Common CI failure patterns and how to diagnose them from the logs.

## Reading CI Logs

```bash
# With gh (completed runs only)
gh run view <RUN_ID> --log-failed

# Per-job logs via API — works even while sibling jobs are still running.
# `gh run view --log` refuses for the whole run until every job finishes;
# the per-job endpoint has no such gate. `--allow-escape-sequences` is
# required — CI logs contain ANSI escapes and the call errors without it.
# Find <JOB_ID> in the job URL printed by `gh pr checks <N>`.
# GH_REPO is required: `gh api` here takes no -R flag.
# GH_REPO={owner}/{repo} gh api --allow-escape-sequences \
#   "repos/{owner}/{repo}/actions/jobs/<JOB_ID>/logs" > /tmp/job-log.txt
# GH_REPO={owner}/{repo} gh api "repos/{owner}/{repo}/actions/runs/<RUN_ID>/jobs" \
#   --jq '.jobs[] | {name, status, conclusion}'

# With curl — download and extract
curl -sL -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/$GH_OWNER/$GH_REPO/actions/runs/<RUN_ID>/logs \
  -o ~/.hermes/cache/scratch/ci-logs.zip && unzip -o ~/.hermes/cache/scratch/ci-logs.zip -d ~/.hermes/cache/scratch/ci-logs
```

## Common Failure Patterns

### Test Failures

**Signatures in logs:**
```
FAILED tests/test_foo.py::test_bar - AssertionError
E       assert 42 == 43
ERROR tests/test_foo.py - ModuleNotFoundError
```

**Diagnosis:**
1. Find the test file and line number from the traceback
2. Use `read_file` to read the failing test
3. Check if it's a logic error in the code or a stale test assertion
4. Look for `ModuleNotFoundError` — usually a missing dependency in CI

**Common fixes:**
- Update assertion to match new expected behavior
- Add missing dependency to requirements.txt / pyproject.toml
- Fix flaky test (add retry, mock external service, fix race condition)

---

### Lint / Formatting Failures

**Signatures in logs:**
```
src/auth.py:45:1: E302 expected 2 blank lines, got 1
src/models.py:12:80: E501 line too long (95 > 88 characters)
error: would reformat src/utils.py
```

**Diagnosis:**
1. Read the specific file:line numbers mentioned
2. Check which linter is complaining (flake8, ruff, black, isort, mypy)

**Common fixes:**
- Run the formatter locally: `black .`, `isort .`, `ruff check --fix .`
- Fix the specific style violation by editing the file
- If using `patch`, make sure to match existing indentation style

---

### Type Check Failures (mypy / pyright)

**Signatures in logs:**
```
src/api.py:23: error: Argument 1 to "process" has incompatible type "str"; expected "int"
src/models.py:45: error: Missing return statement
```

**Diagnosis:**
1. Read the file at the mentioned line
2. Check the function signature and what's being passed

**Common fixes:**
- Add type cast or conversion
- Fix the function signature
- Add `# type: ignore` comment as last resort (with explanation)

---

### Build / Compilation Failures

**Signatures in logs:**
```
ModuleNotFoundError: No module named 'some_package'
ERROR: Could not find a version that satisfies the requirement foo==1.2.3
npm ERR! Could not resolve dependency
```

**Diagnosis:**
1. Check requirements.txt / package.json for the missing or incompatible dependency
2. Compare local vs CI Python/Node version

**Common fixes:**
- Add missing dependency to requirements file
- Pin compatible version
- Update lockfile (`pip freeze`, `npm install`)

---

### Permission / Auth Failures

**Signatures in logs:**
```
fatal: could not read Username for 'https://github.com': No such device or address
Error: Resource not accessible by integration
403 Forbidden
```

**Diagnosis:**
1. Check if the workflow needs special permissions (token scopes)
2. Check if secrets are configured (missing `GITHUB_TOKEN` or custom secrets)

**Common fixes:**
- Add `permissions:` block to workflow YAML
- Verify secrets exist: `gh secret list` or check repo settings
- For fork PRs: some secrets aren't available by design

---

### Timeout Failures

**Signatures in logs:**
```
Error: The operation was canceled.
The job running on runner ... has exceeded the maximum execution time
```

**Diagnosis:**
1. Check which step timed out
2. Look for infinite loops, hung processes, or slow network calls

**Common fixes:**
- Add timeout to the specific step: `timeout-minutes: 10`
- Fix the underlying performance issue
- Split into parallel jobs

---

### Docker / Container Failures

**Signatures in logs:**
```
docker: Error response from daemon
failed to solve: ... not found
COPY failed: file not found in build context
```

**Diagnosis:**
1. Check Dockerfile for the failing step
2. Verify the referenced files exist in the repo

**Common fixes:**
- Fix path in COPY/ADD command
- Update base image tag
- Add missing file to `.dockerignore` exclusion or remove from it

---

## Designing a New CI Job That Cannot Lie

When adding a job that wires a previously-unrun suite into CI:

- **Prove execution, not greenness.** Tee the runner's reporter stream to a
  log file and assert on the executed-test count plus the summary line in a
  follow-up step. A job that goes green with zero tests executed is the
  failure mode — the count assertion turns it into a hard failure.
- **Count with the runtime lister, not static grep.** Loop- or
  data-generated tests are invisible to a `test(` grep; the authoritative
  count is the framework's own `--list` output on a checkout that can load
  fixtures (stub run-state/env if listing requires it).
- **Ship untested-in-CI suites as non-blocking first.** A suite that never
  ran in CI carries latent failures; start with `continue-on-error: true`,
  document the exact promotion criteria (consecutive green runs plus named
  prerequisite fixes), and keep the collateral fixes in separate PRs so the
  ramp measures the app, not the wiring.
- **Fail fast on load-bearing preconditions.** Assert mandatory env/config
  (locale, isolated database name, required state files) in their own steps
  before the long run, not after a 20-minute failure.
- **Do not re-provision what the service definition already provides.** A
  `services.postgres` block with `POSTGRES_DB` creates that database at
  container startup — a manual `CREATE DATABASE` step fails as "already
  exists". Verify with a connection check (`SELECT 1` against the expected
  name) instead of creating.
- **Sanitize surgically, never by whole-line blanking.** When a generated
  env/config file carries unreplaced placeholders, strip only the bad
  fragment — blanking the entire line also destroys correctly-copied real
  values (e.g. an emptied DB password surfaces later as an auth failure far
  from the cause). Follow with a guard step that fails on any leftover
  placeholder pattern.
- **A reporting job must tolerate its producer's exit code.** An
  informational job that parses an artifact stays green with `|| true` on
  the producing step — `continue-on-error` alone still renders the job red
  and reads as a failure. The parsing step then states explicitly what it
  computed (covered/valid counts, or "no data") so a hollow green is
  impossible.

## Auto-Fix Decision Tree

```
CI Failed
├── Test failure
│   ├── Assertion mismatch → update test or fix logic
│   └── Import/module error → add dependency
├── Lint failure → run formatter, fix style
├── Type error → fix types
├── Build failure
│   ├── Missing dep → add to requirements
│   └── Version conflict → update pins
├── Permission error → update workflow permissions (needs user)
└── Timeout → investigate perf (may need user input)
```

## Re-running After Fix

```bash
git add <fixed_files> && git commit -m "fix: resolve CI failure" && git push

# Then monitor
gh pr checks --watch 2>/dev/null || \
  echo "Poll with: curl -s -H 'Authorization: token ...' https://api.github.com/repos/.../commits/$(git rev-parse HEAD)/status"
```
