# Diagnosing a red mandatory CI job on a peer's PR

`gh pr checks` gives PASS/FAIL/PENDING and nothing else. This is the route from
"a mandatory job is red" to a correction message the peer can act on in one turn.

## 1. Find the failing run and job

```bash
gh run list -R <owner>/<upstream> --branch <branch> --limit 3 --json databaseId,conclusion
gh run view <run-id> -R <owner>/<upstream> --json jobs \
  --jq '.jobs[] | select(.conclusion=="failure") | .name + " " + (.databaseId|tostring)'
```

The job id printed there is what you need for step 2 — do not stop at the job
name.

## 2. Read the assertion, WITHOUT waiting for the run to finish

`gh run view <run-id> --log-failed` returns nothing while the run is still
`in_progress`, and the sibling jobs you are waiting on can add another 20
minutes. The failing job's log is already downloadable:

```bash
curl -sL -H "Authorization: token $(gh auth token)" \
  "https://api.github.com/repos/<owner>/<upstream>/actions/jobs/<jobId>/logs" \
  | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -nE "FAILED|Failed asserting|Tests:|at tests/" | head -30
```

`gh api` on that same endpoint silently writes a 0-byte file (it does not follow
the redirect to the archive) — use `curl -sL`. Once the whole run completes,
`gh run view <run-id> --log-failed` works and is the shorter path; use whichever
is available rather than sitting on the first.

Strip ANSI or the output is unreadable. Pull three things: the failing test's
full name, the literal expected-vs-actual text, and the source line it failed on.

Do not propose `gh run rerun` as a remedy: on a repo you can only read it fails
with `Must have admin rights to Repository`, so it is never available to the
orchestrator.

## 3. Triage by blast radius across the WHOLE batch first

Before blaming any single peer's diff, ask how many PRs fail the same way. Get
`gh pr checks <n> -R <upstream>` for every open PR in the batch, then read the
failing test name across them:

- **Fails in ONE PR** → that peer's change. Diagnose and correct it.
- **Identical assertion fails in SEVERAL unrelated PRs, and none of their diffs
  touch the failing test or file** → it is a pre-existing flake on the base
  branch, not anybody's regression. `gh api repos/<owner>/<upstream>/pulls/<n>/files --paginate --jq '.[].filename'`
  settles the "none of them touched it" half in one call.

For a base-branch flake, dispatch ONE test-only fix and tell every other peer
explicitly which failure to ignore, naming the test and the symptom so they do
each try to "fix" their own PR. In that message require:

- RED against the current tree, proven — a flake you could not reproduce is not
  yet pinned. Say so and stop rather than shipping a fix that only passed
  locally.
- No change to the production code the flake exercised. If the test asserted on
  something the code gets right (an escaping helper, an observer, an exporter),
  the defect is the assertion, and saying "do not touch the code" in the message
  is what keeps the diff one line.
- A NEW branch and a NEW PR for this fix, off the base branch — not a second
  commit on the peer's existing issue branch, which would stack it.

Common mechanism behind such flakes: a test reads a row by POSITION (a fixed
cell address, `assertSame` on "row 2") while the query's ordering is not a
contract (a `latest(<second-precision timestamp>)` over two rows written in the
same second, one of them written by a model observer rather than the test). It
passes on one machine's insertion order and fails on the runner's. The repair is
to key the assertion to the row's identity, not its position.

## 4. A scope-tightening fix can turn a pre-existing test RED

When a fix closes a disclosure (a bare `whereIn` in place of an org-wide query,
a `?->` in place of a null-dereference), the tests that pin the OLD leaking
behaviour start failing — a fixture scoped outside the caller's own subtree now
resolves to nothing where it used to return a row.

That failure is the fix working. Tell the peer to move the FIXTURE into the
caller's scope so the test's original intent survives, not to weaken the
assertion, and require the reason recorded in the PR body so a later reader does
not assume the test was edited for convenience. Give the exact fixture change,
including which column the fixture was missing.

**Line ownership does not freeze forever.** A prompt may say "that file belongs
to another peer" to prevent parallel-edit conflicts — once that peer's own work
is landed and its PR is open, the file is no longer being edited and the peer
holding the PR may fix the fallout. Say that explicitly in the correction, or
the peer will report the block and leave the job red.

## 5. Name the root cause in the correction

The recurring shape, and it is usually a TEST defect rather than a flaky run:

The new test asserts on runner-specific OUTPUT — a summary word like "passed", a
pass COUNT, a duration, a coverage percentage, a row position — while CI's PHP
version, environment or insertion order makes the marker land somewhere else.

Worked example of the mechanism: `assertMatchesRegularExpression('/Tests?:.*passed/is')`
fails because an unrelated unit test emits a deprecation on the CI PHP version and
Pest prints `Tests: 1 deprecated` instead of a pass count. Locally the same
assertion passes, which is exactly why it reached CI.

The repair, in order of preference:

1. Re-key the assertion to the IDENTITY of the thing under test — its own test
   name, its own marker output, its own row's id — not a summary line and not a
   fixed position.
2. Assert the NEGATIVE of the old broken shape: that the string the pre-fix code
   produced is ABSENT. This is what proves the fix did something.
3. Only then assert a positive, and prefer a positive about the mechanism over one
   about a global summary.

## 6. Require RED against the pre-fix shape

Ask the peer to show the new test failing against the old code shape and passing
against the fixed one. A test that passes both ways pins nothing, however green
CI looks. Where the fix is a wrapper or a script that can be temporarily reverted,
that RED is cheap to demonstrate and is the whole proof.

## 7. Do not stop at the mandatory jobs

The user's gate may name a subset of jobs as required while others run anyway. Say
plainly which are green and that the remainder are still running rather than
calling a PR complete on the required subset alone.
