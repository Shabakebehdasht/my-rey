# Peer registry

Mapping from peer name (as registered with `hermes peer`) to the GitHub repo
and workflow file that wakes it. A peer is reachable only while its workflow
run is alive.

| Peer | Repo | Workflow |
|---|---|---|
| kimya | `Shabakebehdasht/my-kim` | `kimya.yml` |
| sevda | `Shabakebehdasht/my-sev` | `sevda.yml` |
| sonia | `Shabakebehdasht/my-son` | `sonia.yml` |
| kylie | `Shabakebehdasht/my-kyl` | `kylie.yml` |

Batch wake (one call for all four):

```bash
gh workflow run kimya.yml -R Shabakebehdasht/my-kim
gh workflow run sevda.yml -R Shabakebehdasht/my-sev
gh workflow run sonia.yml -R Shabakebehdasht/my-son
gh workflow run kylie.yml -R Shabakebehdasht/my-kyl
```

## Adding a peer

```bash
hermes peer add <name> --url http://<name>:8642 --key <API_SERVER_KEY>
```

The key is stored as a credential in `~/.hermes/.env`; never paste it into
chat or into a job prompt.

## Message templates

Memory cleanup request (dedupe + drop stale/incorrect entries, keep only
durable facts, do not store completed work or transient state, return a short
summary of what was removed or corrected):

```
سلام. لطفاً حافظه داخلی‌ات (memory و user profile) را مرتب کن: موارد تکراری و منسوخ را حذف کن، اطلاعات نادرست یا قدیمی را اصلاح یا پاک کن، و فقط واقعیت‌های پایدار و درست را نگه دار. کارهای انجام‌شده و وضعیت موقت را در حافظه ذخیره نکن (آن‌ها تاریخچه‌ی جلسه هستند، نه حافظه). در پایان خلاصه‌ای کوتاه از اینکه چه چیزی حذف یا اصلاح شد برگردان.
```

Strip ZWNJ (U+200C) from any Persian message before it goes into a
`hermes cron create` prompt — see the Pitfalls section of SKILL.md.
