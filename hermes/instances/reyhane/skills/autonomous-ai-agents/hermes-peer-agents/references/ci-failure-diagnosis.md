# Diagnosing a red mandatory CI job on a peer's PR

`gh pr checks` gives PASS/FAIL/PENDING and nothing else. This is the route from
"a mandatory job is red" to a correction message the peer can act on in one turn.

## 1. Find the failing run and job

```bash
gh pr view <n> -R <owner>/<upstream> --json files --jq '.[].messageHeadline'  # optional
gh run list -R <owner>/<upstream> --branch <branch> --limit 3 --json databaseId,conclusion
gh run view <run-id> -R <owner>/<upstream> --json jobs \
  --jq '.jobs[] | select(.conclusion=="failure") | .name'
```

`--log-failed` is empty while the run is still in progress — wait for
`status=completed`, or you will conclude "no failure" from a run that has not
reported yet.

## 2. Read the assertion

```bash
gh run view <run-id> -R <owner>/<upstream> --log-failed | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -iE 'FAILED|Tests:|Failed asserting|at tests/|Error' | head -25
```

Strip ANSI or the output is unreadable. Pull three things: the failing test's
full name, the literal expected-vs-actual text, and the source line it failed on.

## 3. Name the root cause in the correction

The recurring shape, and it is a TEST defect rather than a flaky run:

The new test asserts on runner-specific OUTPUT — a summary word like "passed", a
pass COUNT, a duration, a coverage percentage — while CI's PHP version or
environment makes some OTHER test skip or deprecate, so the marker never appears.

Worked example of the mechanism: `assertMatchesRegularExpression('/Tests?:.*passed/is')`
fails because an unrelated unit test emits a deprecation on the CI PHP version and
Pest prints `Tests: 1 deprecated` instead of a pass count. Locally the same
assertion passes, which is exactly why it reached CI.

The repair, in order of preference:

1. Re-key the assertion to the IDENTITY of the thing under test — its own test
   name, its own marker output — not a summary line.
2. Assert the NEGATIVE of the old broken shape: that the string the pre-fix code
   produced is ABSENT. This is what proves the fix did something.
3. Only then assert a positive, and prefer a positive about the mechanism over one
   about a global summary.

## 4. Require RED against the pre-fix shape

Ask the peer to show the new test failing against the old code shape and passing
against the fixed one. A test that passes both ways pins nothing, however green
CI looks. Where the fix is a wrapper or a script that can be temporarily reverted,
that RED is cheap to demonstrate and is the whole proof.

## 5. Do not stop at the mandatory jobs

The user's gate may name a subset of jobs as required while others run anyway. Say
plainly which are green and that the remainder are still running rather than
calling a PR complete on the required subset alone.