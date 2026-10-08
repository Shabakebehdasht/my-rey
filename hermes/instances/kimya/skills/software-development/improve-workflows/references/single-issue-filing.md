# Filing a single audit finding as a GitHub issue

Use when the deliverable is ONE issue from an audit, with no plan files and no local edits.

## Shape of a good audit issue

Follow the improve skill's issue style: the reader is a maintainer deciding whether to act.

1. **Problem statement, in the project's language.** Say what is broken for a real user, not
   which lines are ugly. Lead with the aggregate number (how many sites, in how many files) —
   that is what makes it rankable against other issues.
2. **Evidence.** Every claim carries `file:line`. Counts come from a reproducible command, not
   an impression. Group by shape (a census listing) rather than dumping 78 line numbers.
3. **Why it matters.** Tie to work already invested elsewhere in the repo, so the maintainer sees
   why this is not cosmetic. Name the concrete consequence (destructive actions unreachable,
   error messages unannounced) rather than restating the category label.
4. **Suggested direction, not implementation.** Numbered, prioritised, each with a why.
5. **Non-duplication section.** See the sweep recipe below. This section is mandatory.
6. **Audit footer.** Commit hash audited, plus the explicit statement that nothing was changed.

## Duplicate sweep

Two passes, both required.

**Pass 1 — bulk classification.** Pull every issue and PR with title+body, then classify hits:

```bash
gh issue list --repo OWNER/REPO --state all --limit 200 --json number,title,body,state > /tmp/iss.json
python3 - <<'EOF'
import json
d = json.load(open('/tmp/iss.json'))
kws = ['aria','a11y','accessib','keyboard','wcag','screen reader', 'دسترس‌پذیر']
for i in d:
    txt = (i['title'] + ' ' + (i.get('body') or '')).lower()
    hits = [k for k in kws if k in txt]
    if hits:
        print(i['number'], i['state'], '|', i['title'][:60], '|', hits)
EOF
```

*Pitfall:* bare `i['state']` aborts the sweep with a KeyError when GitHub omits the field for
some items. Use `i.get('state')` or let the exception pass and re-run with the field selected.

Expect a majority of hits to be incidental. Read the hit and state in the issue body which
category each fell into and why it does not count. "Keyword search found nothing" is not proof;
a classified sweep is.

**Pass 2 — server-side search**, which also covers PRs and merged history:

```bash
gh api search/issues -q 'repo:OWNER/REPO+aria+OR+repo:OWNER/REPO+keyboard' --jq '.items[] | "\(.number) \(.title)"'
```

Use `\.number` not `\(.number)` inside `--jq` or the shell eats the paren.

## Rendering components for evidence

When a finding depends on what a Blade/UI component emits, render it rather than reading the
component source and inferring:

```bash
php artisan tinker --execute='
$h = \Illuminate\Support\Facades\Blade::render("<x-button icon=\"o-trash\" />");
$p = strpos($h, "<button"); $e = strpos($h, ">", $p);
echo preg_replace("/\s+/", " ", substr($h, $p, $e - $p + 1)), PHP_EOL;'
```

Pitfalls:

- Render the variants that matter (bare / with a name attribute / with a tooltip) side by side —
  that is how you prove both the defect and the fix path in one step.
- `tinker --execute` echoes the PHP source before output. Match on your own sentinel strings
  (tag regexes, output labels), not on the first N lines.
- The heredoc-free single-quoted form is safest; nested quotes in the Blade snippet will break
  the shell before PHP ever parses them.

## Do not touch the working tree

An issue-only request means zero local writes. Confirm at the end with
`git status --porcelain` against the state you recorded at the start, and if a file shows as
modified check whether it was already dirty before you began — say so in the report rather than
claiming a clean tree or taking credit for an unrelated change.

## Report back

State the issue URL, the one-sentence topic, the evidence highlights as counts, the
non-duplication result, and the closing confirmation that nothing local changed. Do not paste the
whole issue body into chat.
