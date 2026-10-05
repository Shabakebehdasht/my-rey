# Push / force decision table

Check the remote first, then pick the command. One row per situation.

```bash
git ls-remote --heads <remote> | grep '<name>'   # empty means the branch does not exist yet
```

| Remote state | Local state | Command | Why |
|---|---|---|---|
| absent | any | `git push <remote> canonical/<branch>:refs/heads/<name>` | Plain create. A `-f` here is a harmless no-op — do not report force as if it were needed. |
| exists, behind local | local is a descendant | `git push <remote> <branch>:<branch>` | Fast-forward; no force required and none should be used. |
| exists, diverged | user wants exact upstream content | `git push --force-with-lease <remote> canonical/<branch>:refs/heads/<name>` | Rewrite. `--force-with-lease` aborts if the remote moved after your fetch, so a concurrent teammate push is not silently clobbered. |
| exists, diverged, user explicitly demanded `-f` | user has accepted clobber risk | `git push -f <remote> canonical/<branch>:refs/heads/<name>` | Honour the explicit instruction; state in your reply that it rewrote the branch. |
| exists, target name is NOT the current branch | any | push the fetched ref directly (`canonical/<branch>:refs/heads/<name>`) | No local checkout, no branch switch, no risk to the working tree. |

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