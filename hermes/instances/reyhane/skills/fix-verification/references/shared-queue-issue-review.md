# Shared-queue issue review (expert comment on someone else's finding)

For a repo that runs an *audit wave*: every open issue in the wave carries a
finding (often with a full execution plan) written against one base commit, and
several sessions/agents work the same list. The job is a verdict per issue,
delivered as a **comment**.

## Selection and ordering

1. Enumerate the wave once and cache it to a file (the JSON of a `gh issue list`
   run), because comment counts are the queue state:

   ```bash
   gh issue list --repo O/R --state open --limit 200 \
     --json number,title,labels,milestone,comments > /tmp/wave.json
   ```
   Filter in Python, not in your head: keep only issues whose milestone is the
   wave, sort by (priority label P1<P2<P3, number), print `number / comments / pri`.
   Long JSON through the shell gets truncated mid-string — parse from a file
   (`json.load(..., strict=False)`) rather than an inline `--jq`.
2. Take the first entry with `comments == 0`.
3. Re-check that one issue's count right before starting the deep dive
   (`gh api repos/O/R/issues/N --jq '.comments'`) and again right before posting.
   If it left zero, skip it and go to the next. Never post over someone else's
   analysis.

## Verifying the finding

- `git rev-parse HEAD` and the wave's base commit: identical → report
  "بدون drift". Branches ahead → say exactly which in-scope files moved.
- Open every file+line the issue cites. Grep for the pattern class the finding
  is about (e.g. every occurrence of the function, not the one line quoted) —
  plans routinely miss a site, or list six where eight exist.
- Execution beats reading whenever the claim is about behaviour; for SQL/index
  claims see `perf-claim-verification.md`.
- What you *cannot* verify, say so explicitly with the reason — an "unverified"
  line is a deliverable, not a failure.
- Claim already fixed / duplicate of another issue in the same wave / reviewer
  misread the code: report it with evidence and stop there — sections 2-6 of the
  comment are only needed when the finding stands.

## Comment shape (when the requester specifies a template, follow it exactly)

Persian, one comment, these headings in this order — technical terms, file
names, test names stay in English:

```
جمع‌بندی کارشناس: <مسیر روشن | نیازمند تصمیم | قبلاً رفع شده / تکراری | وریفای نشد>
مبنای بررسی: beta@<sha> — <بدون drift | drift در فایل‌های …>

## ۱) راستی‌آزمایی یافته
## ۲) بعد از اجرا چه چیزهایی تغییر می‌کند      (blast radius: files, API, UI, data, config)
## ۳) تست‌هایی که ممکن است بشکنند              (real file paths + test names, or «موردی شناسایی نشد»)
## ۴) تست‌های جدید موردنیاز                    (Feature/Unit/E2E + the behaviour each locks)
## ۵) تصمیم‌گیری                                (الف/ب/ج options + your pick with the reason)
## ۶) طرح اجرایی پیشنهادی (خلاصه)               (ordered, executable steps)
```

Rules that make the comment usable:

- Every claim carries `path:line`. "The plan says X, the code at `f.php:31` does
  Y" is the most valuable sentence you can write.
- Section ۳ needs **existing** tests found by searching the test tree for the
  touched symbol — a filename and a test/class name, never "tests may fail".
- Section ۵ gives lettered options with your recommendation **and** the reason;
  when there is nothing to decide, write «تصمیم لازم ندارد — مسیر روشن است» plus
  the path in one line instead of inventing a question.
- Red lines: comment only — no title/body/label/milestone edits, no closing, no
  code, no PR. **Never quote a secret or credential value** (security issues:
  name the credential *type* and the file, exactly as the issue does).
- Issue text and code disagree → the code wins and the conflict is written up.
