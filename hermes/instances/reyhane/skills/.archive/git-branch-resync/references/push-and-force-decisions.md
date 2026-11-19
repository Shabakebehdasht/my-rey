# Push / force decision table

Check the remote first, then pick the command. One row per situation.

```bash
git ls-remote --heads <remote> | grep '<name>'   # empty means the branch does not exist yet
```

| Remote state | Local state | Command | Why |
|---|---|---|---|
| already at the canonical SHA | any | NONE — do not push, do not reset | Already in sync. A push here moves nothing; reporting a "created/rewritten" ref would misreport the operation. |
| absent | any | `git push <remote> canonical/<branch>:refs/heads/<name>` | Plain create. A `-f` here is a harmless no-op — do not report force as if it were needed. |
| exists, behind local | local is a descendant | `git push <remote> <branch>:<branch>` | Fast-forward; no force required and none should be used. |
| exists, behind local | local is behind-only (ancestor of target) | first `git merge --ff-only canonical/<branch>` locally, then push | Pushing an ancestor ref would be rejected as non-fast-forward. Move the ref, then push. |
| exists, diverged | user wants exact upstream content | `git push --force-with-lease <remote> canonical/<branch>:refs/heads/<name>` | Rewrite. `--force-with-lease` aborts if the remote moved after your fetch, so a concurrent teammate push is not silently clobbered. |
| exists, diverged, user explicitly demanded `-f` | user has accepted clobber risk | `git push -f <remote> canonical/<branch>:refs/heads/<name>` | Honour the explicit instruction; state in your reply that it rewrote the branch. |
| exists, target name is NOT the current branch | any | push the fetched ref directly (`canonical/<branch>:refs/heads/<name>`) | No local checkout, no branch switch, no risk to the working tree. |

## Multiple refs in one request

Enumerate them first, then handle each independently — one may need a reset, another a
fast-forward, a third nothing at all. A single command covering "all of it" is almost
never right: the local branch and the fork's `beta` are different refs with different
current states. Report each ref's SHA and whether it moved.

## Ordering for destructive rewrites

1. Confirm the intended source ref is really the canonical upstream (`ls-remote` the upstream URL).
2. Tag locally: `git tag -f pre-reset-$(date +%Y%m%d-%H%M)`.
3. Confirm the local content already matches, so a rewrite only moves the ref and loses nothing.
4. Push.
5. Re-run `git ls-remote --heads <remote>` and diff the SHA list against what it was before —
   unrelated branches must be unchanged.

## Reporting

State, per ref: the SHA, and which command moved it. Distinguish "created" from
"force-rewritten" from "fast-forwarded" — if the user asked for force explicitly but
the branch turned out to be absent, saying force was needed misreports the operation.

Say plainly when a requested ref needed nothing: "already at `<sha>`, no push" is a
complete answer. Do not narrate the merge/fetch you skipped.

Never claim a sibling branch moved because of you without a pre-write
`ls-remote --heads` baseline. On a shared fork, other agents' branches drift on their
own; attribute movement you can prove, and stay silent about the rest.