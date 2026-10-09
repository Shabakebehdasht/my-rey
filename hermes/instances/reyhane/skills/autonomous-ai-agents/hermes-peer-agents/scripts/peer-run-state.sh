#!/usr/bin/env bash
# Report active workflow runs for every peer workflow and flag conflicts.
#
# ALL peer workflows live in ONE repo: Shabakebehdasht/my-rey (kimya.yml,
# sevda.yml, sonia.yml, kylie.yml). The old per-peer repos (my-kim, my-sev,
# my-son, my-kyl) return 404 — do not reintroduce them.
#
# A peer machine must have AT MOST ONE in_progress run of ITS OWN workflow: the
# run holds the tailscale hostname and syncs hermes/ state back to the repo at
# shutdown, so two concurrent runs of the same workflow collide. Different
# peers are different machines and may run at the same time. `reyhane` is this
# orchestrator's own workflow — an in_progress reyhane run is normal.
#
# Exit 0 = no peer workflow has more than one in_progress/queued run.
# Exit 1 = conflict found (the offending workflow is printed).
#
# Usage: scripts/peer-run-state.sh
set -uo pipefail

owner="${GH_OWNER:-Shabakebehdasht}"
repo="${PEER_REPO:-my-rey}"
# peer workflow names — keep in sync with references/peer-registry.md
peers=(kimya sevda sonia kylie rebecca)

conflicts=0
runs=$(gh run list -R "$owner/$repo" -L 20 \
  --json databaseId,name,status,conclusion,createdAt,event 2>&1)
if [ $? -ne 0 ]; then
  echo "ERROR: gh run list failed for $owner/$repo"
  echo "$runs"
  exit 1
fi

for peer in "${peers[@]}"; do
  echo "== $peer ($owner/$repo :: $peer.yml)"
  echo "$runs" | jq -r \
    --arg p "$peer" \
    'map(select(.name == $p))[0:3][] | "   \(.databaseId) \(.status) \(.conclusion // "-") \(.createdAt) \(.event)"'

  active=$(echo "$runs" | jq \
    --arg p "$peer" \
    '[.[] | select(.name == $p and (.status == "in_progress" or .status == "queued"))] | length')
  if [ "$active" -gt 1 ]; then
    echo "   >>> CONFLICT: $active '$peer' runs active. Cancel the NEWER one(s):"
    stale=$(echo "$runs" | jq -r \
      --arg p "$peer" \
      'map(select(.name == $p and (.status == "in_progress" or .status == "queued"))) | sort_by(.createdAt) | .[:-1][].databaseId')
    for id in $stale; do
      echo "       gh run cancel $id -R $owner/$repo"
    done
    conflicts=$((conflicts + 1))
  elif [ "$active" -eq 1 ]; then
    echo "   OK: one run active"
  else
    echo "   asleep (no active run)"
  fi
  echo
done

if [ "$conflicts" -gt 0 ]; then
  echo "RESULT: $conflicts peer workflow(s) with duplicate active runs — resolve before dispatching."
  exit 1
fi

echo "RESULT: no duplicate active runs. Safe to dispatch."
exit 0
