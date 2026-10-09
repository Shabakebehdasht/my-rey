# Assigning numbered work items to peers

Recipe for "give issues N..M to the kids, one each, and stay on it until done".

## 1. Triage the backlog before assigning anything

The peers clone the repo at boot, but the base branch keeps moving while
they boot and while you write prompts. **Every item's claim must be checked
against the current tip of the base branch, not against the checkout you have
locally** — an item whose fix was merged while peers were booting is now
duplicate work, and the user's standing expectation is that merged work is not
redone.

```bash
git fetch https://github.com/<owner>/<upstream>.git <base>:refs/remotes/canonical/<base>
git rev-list --left-right --count origin/<base>...canonical/<base>   # behind <tab> ahead
gh pr list -R <owner>/<upstream> --base <base> --state merged --limit 30 \
  --json number,title,mergedAt,headRefName
```

Read that merged-PR list against the backlog and drop items it already
covers. Then fast-forward the fork's base branch so a later push cannot
rewrite history:

```bash
git merge-base --is-ancestor origin/<base> canonical/<base> \
  && git push origin canonical/<base>:<base> \
  || echo "diverged - do NOT push, resolve first"
```

Only fast-forward when the ancestor test passes; a non-zero divergence means
the fork has commits the upstream lacks, and pushing over them destroys work.

Then re-verify the surviving items against the fetched ref, never the working
tree:

```bash
git grep -n '<symbol>' canonical/<base> -- app resources
git show canonical/<base>:path/to/file
```

An item whose symptom is already gone, or partly gone, still goes to a peer —
with the prompt telling it to implement only the remainder and to record in
the PR body which part was already fixed. Do not silently drop a partial.

### "Closes #N" in a merged PR does not mean the issue is finished

An issue can be cited by a merged PR and still be open with the actual symptom
intact, because that PR fixed a neighbouring site or only half the case. The
merged-PR list is a *candidate* filter, not a verdict. For each intersecting
item, read what the merged PR actually changed and compare it against the file
and line the issue names:

```bash
gh pr view <merged-pr> -R <owner>/<upstream> --json files \
  --jq '.files[] | "\(.additions)+ \(.path)"'
git show canonical/<base>:<path-named-by-the-issue>     # is the symptom still there?
```

- **Symptom still present on the base ref** → the remainder is real work. Assign
  it, and open the prompt with what already landed and what is left, so the peer
  neither re-implements the finished half nor re-derives the same diagnosis.
- **Symptom gone, issue merely not yet closed** → VERIFY-ONLY assignment: the
  peer confirms the fix exists on the base ref and opens no PR. An implement
  prompt here gets the same fix re-applied as duplicate work.

This distinction is the difference between dropping real work and dropping none.

## 2. Detect file overlap between assigned items

Two peers editing the same file in parallel produce conflicting PRs that block
each other. **Intersect only the paths each item will EDIT, not every path it
names.** An item cites files as evidence far more often than as targets — a
route file listed to prove a gate exists, a model listed to show a column is
not fillable — so raw mention intersection reports conflicts that do not exist
and mangles the split into a worse one.

Take paths from the action/plan section of each item, then compare:

```bash
# per item, restricted to its action/plan section (not the whole body)
grep -oE '\b(app|tests|database|resources|routes|config|bootstrap|\.github)/[A-Za-z0-9_/-]+\.(php|js|yml|json)\b' <action-section>
```

Shared *evidence* paths are fine; shared *edit* paths are not. Then either move
an item to a peer that owns none of its files, or when two items unavoidably
share a hot file, split it by LINE ownership: name in BOTH prompts exactly
which layer each peer owns (e.g. "you own the value-binder/escaping layer of
this export, the other peer owns its date columns"), and give every prompt the
standing escape:

*if finishing the item requires editing a file that belongs to another peer's
item, stop and say which file and which line instead of editing it.*

## 3. Read every item before assigning

Batch one call. A number in an upstream repo may be an issue rather than a PR;
`gh pr view N` then fails with a GraphQL "Could not resolve to a PullRequest"
that reads like an auth error but is not.

**List the backlog compactly first.** A bulk issue lister that returns full
bodies for every labelled item spills to disk and floods context before triage
starts. Scan titles with `gh issue list --label <label> --state open --json
number,title,labels`, then fetch bodies and comments for the survivors only.

```bash
for n in 101 102 103 104; do
  echo "=== #$n ==="
  gh issue view $n -R <owner>/<upstream> --json number,title,state,author,labels,url,body
  gh api repos/<owner>/<upstream>/issues/$n/comments --paginate --jq '.[].body'
done
```

**Rank the comment text above the body.** A review comment carries the corrected
plan; a later gate/approval comment carries the decisions that are now CLOSED.
Three consequences for the prompt you write:

- Where the body offers "fix A or B" and a later comment chose one, send the
  DECIDED option and state the rejected one is explicitly out of scope. A peer
  given both stops to ask a question that is already answered.
- Carry the comment's "not part of this issue" exclusions verbatim (out-of-scope
  suggestions, refuted claims, rejected alternatives). This is what stops a peer
  helpfully implementing a rejected suggestion and widening the diff.
- Corrections by the reviewer beat the body's root-cause narrative; when the two
  conflict, the comment wins and the prompt says so.

Bodies of well-written plans carry the solution shape, the tests they want and
their own risk assessment. Quote their intent into the prompt so the peer
implements the plan rather than re-deriving it. Quote each item's own
non-obvious precondition (a file whose real name contains an emoji, a pattern
already documented elsewhere in the repo) so the peer does not mis-locate the
code.

Also carry the triage forward into the prompt as an explicit step: fetch the
canonical base ref, merge it, and re-verify before writing code. Give the peer
the exact base-ref sha the prompt's claims were verified against, and tell it to
re-verify against that ref rather than its own working tree.

**Composing the prompt files.** Plan text is full of literal braces — object
literals in the code the peer must write — so never build prompts with
f-strings or `.format()`; one brace aborts the whole batch build. Use plain
string concatenation of a shared-block constant plus per-item paragraphs. Then
grep the written files before firing: one hit for a sentinel line of the shared
block per file, and the issue-number list per file matching the assignment with
nothing shared and nothing dropped. A batch where the shared block silently
failed to concatenate writes plausible-looking files and strips the branch and
PR rules from every peer at once.

## 4. Standing block, identical in every prompt

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
از برنچ خودت به شاخهٔ `beta` در ریپوی **<upstream>** باز کن:

    gh pr create -R <owner>/<upstream> --base beta --head <your-branch> \
      --title "<title>" --body "Closes #<N>\n\n<body>"

قواعد حیاتی این خط:
- `-R <owner>/<upstream>` **الزامی** است. بدون آن، `gh pr create` برنچ را در همان ریپویی
  باز می‌کند که remote `origin` به آن اشاره می‌کند، یعنی **فورک خودِ peer** — و PR در
  آپ‌استریم دیده نمی‌شود، پس مدیر پروژه هرگز آن را نمی‌بیند. این اشتباه کار و تست را
  بی‌نقص نگه می‌دارد و فقط مقصد را خراب می‌کند، پس از خود گزارش peer هم معلوم نمی‌شود.
- یک برنچ و یک PR برای هر ایشو. اگر هر دو ایشو در یک برنچ رفت، PR بعدی کامیت ایشوی قبلی
  را هم حمل می‌کند و با مرج، ایشوی قبلی هم بی‌صدا مرج می‌شود. هر برنچ را از روی شاخهٔ
  پایه بساز، نه از روی برنچ ایشوی قبلی.
- PR را merge نکن، لیبل نزن، ایشو را نبند.
گزارش نهایی: خلاصه تغییرات، نتیجه تست‌ها، هش آخرین commit، و لینک PR.
برو شروع کن و تا آخرش ادامه بده؛ لازم نیست منتظر تأیید من بمانی. فقط در پایان گزارش بده.
```

Strip ZWNJ and friends from the finished file before any `hermes cron create`
(see SKILL.md); for `hermes peer dm` they pass through fine.

## 5. Deliver

One prompt file per peer, then:

```bash
scripts/peer-dm-batch.sh kimya:/path/msg-a.txt sevda:/path/msg-b.txt
```

Run it `background=true, notify=true` — a peer doing real work answers in
minutes, which exceeds the 600s foreground cap. Do not re-run it while alive.

Before firing the batch, verify the prompts match the split you decided: the
issue numbers named in each file must equal that peer's assignment, with no
number appearing in two files. A prompt that names an item you reassigned is
the cheapest possible bug to fix and the most expensive to discover later.

## 6. Observe, never re-poke

`hermes cron create "every 15m" "$(cat watch.txt)" --name <slug>
--deliver origin --repeat 12 --skill hermes-peer-agents`

The prompt opens with a DO-NOT list (no `gh workflow run`, no `hermes peer dm`,
no cancel/restart) and "you are ONLY observing and reporting". It checks run
status, branch head, open PRs into the base branch, and `gh pr checks`.

**Write the observer prompt in plain ASCII.** Persian prose trips the same
invisible-Unicode validation that rejects ZWNJ, through the CLI and through
`cronjob_manage` alike, so English instructions that ASK for a report in the
user's language are more reliable than a Persian prompt — no strip-retry loop,
and the job is reproducible from the file. Per-issue assignment makes the
observer able to name which peer owes which PR, and stating the mandatory CI
job names lets it quote the exact failing job instead of "CI red".

**Record each peer's branch sha at assignment time and put that baseline in
the observer prompt.** "Work landed" is then a fact read off the sha, not a
claim from the peer's own DM reply — a peer can report success and leave the
branch untouched, so the baseline is the control that makes the report
trustworthy.

Surface the observer decision to the user as: done = PR open + checks green;
otherwise in progress. Do not treat a missing PR as a failure signal — a peer
mid-implementation has not opened one yet.

## 7. Report

Per peer: assignment, and later the PR number + URL, CI state, and any claim the
peer reported as not matching reality. Flag dirty-tree leftovers (uncommitted
files the peer deliberately did not touch) as a decision for the user instead of
quietly committing or reverting them yourself.

## 8. Close the doc gap the guard left

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