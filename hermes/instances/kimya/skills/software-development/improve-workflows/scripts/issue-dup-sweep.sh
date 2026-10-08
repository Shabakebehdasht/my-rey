#!/usr/bin/env bash
# Duplicate sweep before filing a single audit issue.
# Usage: ./issue-dup-sweep.sh OWNER/REPO 'aria|keyboard|wcag'  'second|term|set'
#
# Prints every issue/PR whose title or body matches any keyword, for manual
# classification. Matching is substring-based and WILL produce false positives
# (e.g. "accessib" inside "accessible units"), so classify each hit before
# concluding the topic is not a duplicate.
set -euo pipefail

REPO="${1:?usage: issue-dup-sweep.sh OWNER/REPO KEYWORDS [MORE_KEYWORDS]}"
shift
KEYWORDS=("$@")

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "repo: $REPO"
echo "keywords: ${KEYWORDS[*]}"
echo

gh issue list --repo "$REPO" --state all --limit 300 \
  --json number,title,body,state > "$TMP"

python3 - "$TMP" "${KEYWORDS[@]}" <<'PY'
import json, sys

path, *kws = sys.argv[1:]
data = json.load(open(path))
if isinstance(kws, str):
    kws = [kws]
kws = [k.lower() for k in kws]

print(f"scanned {len(data)} items")
hits = 0
for item in data:
    text = (item.get('title') or '' + ' ' + (item.get('body') or '')).lower()
    matched = [k for k in kws if k in text]
    if matched:
        hits += 1
        # .get everywhere: GitHub omits fields on some search results
        print(f"  {item.get('number')} [{item.get('state')}] "
              f"{item.get('title', '')[:70]} -> {matched}")
print(f"\n{hits} keyword hits — classify each before declaring non-duplication.")
PY

echo
echo "PRs and merged history (server-side search):"
gh api search/issues -q "repo:$REPO+$(printf '%s+' "${KEYWORDS[@]}")" \
  --jq '.items[] | "  \(.number) \(.state) \(.title)"' || true
