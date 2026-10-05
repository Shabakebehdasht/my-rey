#!/usr/bin/env bash
# Report active workflow runs for every peer repo and flag conflicts.
#
# A peer machine must have AT MOST ONE in_progress run: its run holds the
# tailscale hostname and syncs hermes/ state back to the repo at shutdown, so
# two concurrent runs collide.
#
# Exit 0 = no repo has more than one in_progress run.
# Exit 1 = conflict found (the offending repo is printed).
#
# Usage: scripts/peer-run-state.sh
set -uo pipefail

owner="${GH_OWNER:-Shabakebehdasht}"
# peer-name:repo triples — keep in sync with references/peer-registry.md
peers=(kimya:my-kim sevda:my-sev sonia:my-son kylie:my-kyl)

conflicts=0

for pair in "${peers[@]}"; do
  peer="${pair%%:*}"
  repo="${pair##*:}"

  echo "== $peer ($owner/$repo)"
  if ! runs=$(gh run list -R "$owner/$repo" -L 5 \
        --json databaseId,status,conclusion,createdAt,event 2>&1); then
    echo "   ERROR: gh run list failed"
    echo "$runs"
    continue
  fi

  echo "$runs" | jq -r \
    '.[0:3][] | "   \(.databaseId) \(.status) \(.conclusion // "-") \(.createdAt) \(.event)"'

  active=$(echo "$runs" | jq '[.[] | select(.status == "in_progress" or .status == "queued")] | length')
  if [ "$active" -gt 1 ]; then
    echo "   >>> CONFLICT: $active runs active. Cancel the NEWER one:"
    echo "$runs" | jq -r \
      'map(select(.status == "in_progress" or .status == "queued")) | sort_by(.createdAt) | .[:-1][] | "       gh run cancel \(.databaseId) -R '"$owner/$repo"'"'
    conflicts=$((conflicts + 1))
  elif [ "$active" -eq 1 ]; then
    echo "   OK: one run active"
  else
    echo "   asleep (no active run)"
  fi
  echo
done

if [ "$conflicts" -gt 0 ]; then
  echo "RESULT: $conflicts repo(s) with duplicate active runs — resolve before dispatching."
  exit 1
fi

echo "RESULT: no duplicate active runs. Safe to dispatch."
exit 0
