# Assigning numbered work items to peers

Recipe for "give issues N..M to the kids, one each, and stay on it until done".

## 1. Read every item before assigning

Batch one call. A number in an upstream repo may be an issue rather than a PR;
`gh pr view N` then fails with a GraphQL "Could not resolve to a PullRequest"
that looks like an auth error but is not.

```bash
for n in 101 102 103 104; do
  echo "=== #$n ==="
  gh issue view $n -R <owner>/<upstream> --json number,title,state,author,labels,url,body
done
```

Bodies of well-written plans carry the solution shape, the tests they want and
their own risk assessment. Quote their intent into the prompt so the peer
implements the plan rather than re-deriving it.

## 2. Standing block, identical in every prompt

```
- روی برنچ کاری خودت کار کن (نامش را با `git branch --show-current` بخوان). برنچ را عوض نکن.
- تنظیمات ریموت‌ها را تغییر نده، فورک جدید نساز، کلون دوم نگیر.
- `AGENTS.md` پروژه مرجع نهایی است و باید کامل رعایت شود.
- قبل از کد، مستندات و پیاده‌سازی فعلی را بخوان. ادعاهای ایشو را روی شاخه پایه فعلی
  دوباره راستی‌آزمایی کن؛ اگر چیزی با واقعیت نمی‌خواند، همان‌جا گزارش بده.
- TDD: اول تست قرمز، بعد پیاده‌سازی، بعد سبز. تست‌های موجود بدون تغییر سبز بمانند
  مگر plan صریحاً گفته باشد.
- کد و کامنت انگلیسی، UI فارسی/RTL مطابق وضع موجود.
- اگر پلان از تو ویرایش `AGENTS.md` یا هر فایل دستورالختی دیگری خواست، آن قسمت را
  انجام نده و نده: نوشتن این فایل‌ها محافظ فایل بلاک می‌کند و دور زدنش ممنوع است.
  کد را کامل کن، کامیت کن، و دقیقاً بنویس کدام سطر از کدام فایل باید چه چیزی بگوید
  (متن آماده‌اش را هم بده) و این را در بدنه PR ثبت کن.
- اگر جایی گیر کردی یا ابهام جدی بود، متوقف شو و دقیق بگو کجا و چرا — نیمه‌کاره commit نکن.
```

Then the per-item part:

```
سلام. یک کار مشخص داری: issue #<N> در ریپوی <upstream> را کامل پیاده‌سازی کن و تا انتها برسان.
موضوع: <plan name> — <one-line scope>
اول خود ایشو را کامل بخوان:
gh issue view <N> -R <owner>/<upstream>
<standing block>
در پایان: commit واضح روی برنچ خودت، push به فورک خودت (اگر برنچ نبود بساز)، سپس یک PR
از برنچ خودت به شاخه پایه در ریپوی <upstream> باز کن. روی شاخه پایه مستقیم push نکن.
PR را merge نکن.
گزارش نهایی: خلاصه تغییرات، نتیجه تست‌ها، هش آخرین commit، و لینک PR.
برو شروع کن و تا آخرش ادامه بده؛ لازم نیست منتظر تأیید من بمانی. فقط در پایان گزارش بده.
```

Strip ZWNJ and friends from the finished file before any `hermes cron create`
(see SKILL.md); for `hermes peer dm` they pass through fine.

## 3. Deliver

One prompt file per peer, then:

```bash
scripts/peer-dm-batch.sh kimya:/path/msg-a.txt sevda:/path/msg-b.txt
```

Run it `background=true, notify=true` — a peer doing real work answers in
minutes, which exceeds the 600s foreground cap. Do not re-run it while alive.

## 4. Observe, never re-poke

`hermes cron create "every 15m" "$(cat watch.txt)" --name <slug>
--deliver origin --repeat 12 --skill hermes-peer-agents`

The prompt opens with a DO-NOT list (no `gh workflow run`, no `hermes peer dm`,
no cancel/restart) and "you are ONLY observing and reporting". It checks run
status, branch head, open PRs into the base branch, and `gh pr checks`.

Surface the observer decision to the user as: done = PR open + checks green;
otherwise in progress. Do not treat a missing PR as a failure signal — a peer
mid-implementation has not opened one yet.

## 5. Report

Per peer: assignment, and later the PR number + URL, CI state, and any claim the
peer reported as not matching reality. Flag dirty-tree leftovers (uncommitted
files the peer deliberately did not touch) as a decision for the user instead of
quietly committing or reverting them yourself.

## 6. Close the doc gap the guard left

When a peer's report names a blocked doc edit, do it yourself on the peer's
branch. This is the one artifact the peer structurally cannot produce.

Fetch every involved branch's copy of the doc and compare them before editing —
peers branch off the base at different moments, and one of them may already have
edited the same lines:

```bash
cd <local-repo>
for b in <branch-a> <branch-b>; do
  gh api "repos/<fork>/contents/AGENTS.md?ref=$b" --jq '.content' | base64 -d > /tmp/AGENTS.$b.md
done
diff /tmp/AGENTS.<branch-a>.md /tmp/AGENTS.<branch-b>.md   # empty = no peer touched it
```

Then edit in a throwaway worktree so the local branch stays untouched, push to
the peer's branch, remove the worktree, and read the file back off the fork to
confirm the lines landed:

```bash
git fetch origin <peer-branch>
git worktree add <tmp> -B doc-<n> origin/<peer-branch>
# edit, git add, git commit
cd <tmp> && git push origin HEAD:<peer-branch>
cd <local-repo> && git worktree remove <tmp> --force
gh api "repos/<fork>/contents/AGENTS.md?ref=<peer-branch>" --jq '.content' | base64 -d | grep '<the-new-text>'
```

Match each edit to the issue that asked for it — one branch gets only its own
doc lines. Commit message: state that it corrects the doc to match code that
already landed, and why the peer could not write it. No code change in this
commit.

If a pushed file turns out to be protected for you too, do not bypass the guard:
report the exact line and the text that should replace it, and let the user
apply it or approve it.