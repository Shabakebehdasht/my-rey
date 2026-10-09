# GitHub Issue to Pull Request

Turn a GitHub issue into a tested, verified PR. This skill owns the end-to-end discipline — premise validation, duplicate sweeps, class-level fixes, and honest CI reporting; the sibling GitHub and development skills own their own mechanics.

## When to Use

- "Fix issue #123 and open a PR."
- "Implement this GitHub feature request."
- "Take this bug from issue to green CI."

Don't use for: reviewing an existing PR, or answering a code question with no requested change.

## Procedure

### 1. Read the live issue — body AND full thread

Use `terminal` to run `gh issue view <N> --comments`. The body is a snapshot from filing time; the newest comments carry the live state: partial fixes already merged, new root-cause analyses, maintainer decisions, or questions directed at you that change the task. Also read repository instructions (`AGENTS.md`, contribution docs) with `read_file`. Done when the currently requested behavior, non-goals, and any unanswered thread questions are known.

### 2. Sweep for existing and duplicate work

Before writing anything, run `gh pr list --search "#<N>" --state all` plus at least two keyword/synonym variants of the symptom (`gh pr list --search "<subsystem> <symptom>" --state open`). Popular issues attract multiple independent fixes; building a duplicate wastes the work and the credit. Also check whether a recent commit already fixed it: `git log --oneline -20 -- <relevant files>`. Done when you know every open PR and recent commit touching this issue, or that none exist.

**The issue body is a snapshot, and it is often wrong about scope.** Treat each
concrete claim as a hypothesis to re-verify against the code you will actually
change, not as a spec to transcribe. Build a claim table before coding:

| Claim from the issue | Still true on current code? | Already fixed / partially fixed? |
|---|---|---|

Two directions matter:

- **Already fixed upstream?** Sync to the canonical base *first* (see the
  note below), then re-verify. Report in the PR body which claims were stale and
  implement only what remains — do not redo fixed work.
- **Contradicted by the code or by a maintainer comment?** The issue thread wins
  over its own body. Many repos post a "ready for execution" banner saying the raw
  text is discovery history and that an **expert-review comment plus a maintainer
  confirmation are authoritative** — those comments routinely *reduce or overturn*
  the proposed scope. Follow them, and say in the PR body where you deviated and
  why. A maintainer who closed a decision is the decision.

### 2b. Multiple issues in one request → one branch and one PR each

When the user asks for N issues in N separate PRs, branch each from the **same
canonical base**, not from your working branch, so no PR contains another PR's
diff:

```bash
git checkout -b fix/<slug>-a <canonical-base>
# …commit only that issue's files…
git push -u origin fix/<slug>-a

git checkout -b fix/<slug>-b <canonical-base>   # sibling, not a child of a
# …commit only that issue's files…
git push -u origin fix/<slug>-b
```

Staging discipline is what actually enforces this: `git add <explicit paths>`,
never `git add -A`. Stray untracked files from the other issue sit in the working
tree and will silently join whichever commit you make next. Park unrelated
modifications with `git stash push -- <path>` and pop them on the original branch
at the end. Return to the user's original branch when finished.

### 2c. Instruction files are not yours to edit

Project instruction files (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, anything
under `docs/`/`references/` that reads as hand-maintained policy) are frequently
**write-protected**, and a plan that asks for a doc update will fail on them.

**Do not attempt to bypass the protection.** Finish the code, then put the doc
change in the PR body as *exact ready-to-paste text*: which file, which line, the
full replacement snippet. This is a normal deliverable, not a compromise — a
maintainer pastes it in one step, and the intent is not lost.

State plainly in the PR body that the doc edit was skipped and why, so the next
reader knows it is outstanding rather than forgotten.

### 3. Validate the premise against current code — and against design intent

Reproduce the bug or demonstrate the missing behavior on the current default branch with a failing test or fixture, using `search_files` and `read_file` to trace the reported path. Then check the second question: is the "bug" actually deliberate design? Run `git log -p -S "<symbol>"` on the code the issue wants changed and read the original commit's intent — a missing link or restriction is often the feature. Challenge stale or flawed issue prose instead of implementing it blindly. Done when the root cause or feature gap is demonstrated in current code AND the change doesn't fight an intentional design.

### 4. Define acceptance and risk

List acceptance criteria, interfaces, migrations/state changes, compatibility, security/privacy, rollout, and rollback. Map every criterion to a test or explicit verification. Done when review has a finite contract.

### 5. Implement the smallest complete change — and fix the class

Work on an isolated branch or worktree, loading `systematic-debugging` or `test-driven-development` when the bug class calls for them. Add regression tests first, then implement. When the fix is in hand, `search_files` for the same bug shape at sibling call sites and fix the whole class in this PR — an incomplete fix that leaves known siblings broken is worse than none. Every changed line must trace to the issue; no drive-by cleanup. Done when targeted tests pass, the original failure no longer reproduces, and sibling sites are fixed or explicitly ruled out.

### 6. Prove the regression test bites (sabotage run)

Temporarily restore the old behavior of the exact function under test, run the new test, and confirm it FAILS; then restore the fix and confirm it passes. A regression test that passes with and without the fix proves nothing. Done when the test demonstrably fails on pre-fix code.

### 7. Run repository quality gates, then open the PR immediately

Run the formatter, lint, typecheck, and the repo's canonical test entrypoint on affected areas; use `requesting-code-review` on the diff. Then push and open the PR right away — the PR is what dispatches CI, and CI latency is the long pole; do not sit on finished work. Load `github-pr-workflow` for PR mechanics: conventional branch/commit, body linking the issue with problem, approach, tests, risk, and exclusions. Read the PR back and verify head SHA, base, title, and files. Done when the PR exists with the intended diff and CI is running.

### 8. Shepherd CI honestly and close the loop

Inspect live checks and failure logs via `gh pr checks` / `gh run view --log-failed`. Distinguish failures introduced by your diff from pre-existing baseline or infrastructure failures — reproduce on the default branch when unsure, and rerun once only for genuine infra flakes. Never say "green," "merged," or "released" without live evidence of that exact state. When the PR lands, comment on the issue with the PR link and a one-line explanation so the reporter gets a traceable resolution. Done when CI state, remaining blockers, and the issue thread all reflect reality.

## Pitfalls

- Coding before reading issue comments, sweeping for duplicate PRs, or reading current code.
- "Fixing" behavior that the original commit shows is intentional design.
- Fixing a symptom at one call site while sibling sites keep the same bug.
- Shipping a regression test that also passes without the fix.
- Opening a PR with unrun tests or unrelated formatting churn.
- Claiming the issue is delivered because a PR exists.

## Verification

- [ ] Full issue thread read; newest comment state reflected in the plan.
- [ ] Duplicate-PR sweep run with issue number + 2 keyword variants.
- [ ] Premise reproduced on current code; design intent checked via git history.
- [ ] Regression test proven to fail without the fix.
- [ ] Sibling call sites fixed or explicitly ruled out.
- [ ] Every changed line traces to the issue.
- [ ] CI state reported from live evidence only; issue commented with the PR link.
