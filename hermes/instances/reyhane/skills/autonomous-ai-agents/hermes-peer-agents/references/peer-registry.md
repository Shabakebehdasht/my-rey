# Peer registry

Mapping from peer name (as registered with `hermes peer`) to the GitHub repo
and workflow file that wakes it. A peer is reachable only while its workflow
run is alive.

**All peer workflows live in ONE repo: `Shabakebehdasht/my-rey`** (default
branch `reyhane` — the ONLY branch in the repo; never assume `beta`). The
per-peer repos `my-kim`, `my-sev`, `my-son`, `my-kyl` do NOT exist (HTTP 404)
— every `-R Shabakebehdasht/my-kim` style command fails. Use `-R
Shabakebehdasht/my-rey` for all four. `my-rey` also holds `reyhane.yml` and
`rebecca.yml`; `reyhane` is this orchestrator machine's own workflow, so an
`in_progress` `reyhane` run is normal and is not a peer conflict.

**Every peer workflow already carries a single-run server guard:**

```yaml
concurrency:
  group: ${{ github.workflow }}
  cancel-in-progress: false
```

`cancel-in-progress: false` is the load-bearing part: it makes GitHub QUEUE a
second dispatch instead of running it, so even a blind
`gh workflow run` cannot power a machine on twice. Do not "clean this up" or
flip it to `true` — `true` would CANCEL the live machine instead.

**Verified by live probe, then confirmed with the user** (throwaway workflow
under the same repo, since deleted; its three runs were cancelled afterwards):

| dispatch | state of the group | GitHub's behavior |
|---|---|---|
| B while A `in_progress` | one running | B becomes **`pending`** (queued), A untouched |
| C while A running, B pending | one running + one pending | **B is cancelled, C becomes `pending`** |

So `cancel-in-progress: false` means "at most one RUNNING, at most one
PENDING": the second dispatch waits rather than running, but a THIRD dispatch
cancels the pending one and replaces it. The machine is never double-booted —
the invariant that matters — but a wake request can be dropped, so after
queueing, re-read the peer's runs to confirm which request is the surviving
`pending` one. `github.workflow` in the group name is the workflow's `name:`
(`kimya`, `rebecca`, …), so the five peers never share a group with each
other.

Do not re-run the probe by hand; use `scripts/peer-wake.sh`, whose verification
step already reports the run id that actually landed.

Caveat: these files are RemoteHermes-managed ("template v1, regenerated on
Update; manual edits are overwritten"). After any RemoteHermes Update, re-check
that the `concurrency:` block is still present and re-add it if not.

| Peer | Repo | Workflow |
|---|---|---|
| kimya | `Shabakebehdasht/my-rey` | `kimya.yml` |
| sevda | `Shabakebehdasht/my-rey` | `sevda.yml` |
| sonia | `Shabakebehdasht/my-rey` | `sonia.yml` |
| kylie | `Shabakebehdasht/my-rey` | `kylie.yml` |
| rebecca | `Shabakebehdasht/my-rey` | `rebecca.yml` |

**`rebecca.yml` also has a `schedule:` cron (`0 */6 * * *`)** — the only peer
workflow that re-triggers itself. So a `rebecca` run can appear without you
dispatching it; that is normal, not a double dispatch.

Batch wake — always through the script, never a bare `gh workflow run`:

```bash
scripts/peer-wake.sh              # all five; skips any that is already up
scripts/peer-wake.sh kimya sevda  # or a subset
gh run list -R Shabakebehdasht/my-rey --limit 10 --json databaseId,name,status,url
```

## Adding a peer

```bash
hermes peer add <name> --url http://<name>:8642 --key <API_SERVER_KEY>
```

The key is stored as a credential in `~/.hermes/.env`; never paste it into
chat or into a job prompt.

The key is per-peer only by name — every instance writes the SAME value it was
given (`HERMES_API_KEY` from the `HERMES_CUSTOM_API_KEY` secret), so all peer
keys in `~/.hermes/.env` are identical and the local `HERMES_PEER_<NAME>_KEY`
must equal `HERMES_API_KEY`. Read the existing one out of `.env` and pass it;
never ask the user for a key and never print it.

`config.yaml` (`bot_peers:`) is **agent-write-protected**: the patch tool
refuses writes to it. Add a peer with the `hermes peer add` CLI, which is the
supported path.

## Message templates

Memory cleanup request (dedupe + drop stale/incorrect entries, keep only
durable facts, do not store completed work or transient state, return a short
summary of what was removed or corrected):

```
سلام. لطفاً حافظه داخلی‌ات (memory و user profile) را مرتب کن: موارد تکراری و منسوخ را حذف کن، اطلاعات نادرست یا قدیمی را اصلاح یا پاک کن، و فقط واقعیت‌های پایدار و درست را نگه دار. کارهای انجام‌شده و وضعیت موقت را در حافظه ذخیره نکن (آن‌ها تاریخچه‌ی جلسه هستند، نه حافظه). در پایان خلاصه‌ای کوتاه از اینکه چه چیزی حذف یا اصلاح شد برگردان.
```

Strip ZWNJ (U+200C) from any Persian message before it goes into a
`hermes cron create` prompt — see the Pitfalls section of SKILL.md.
