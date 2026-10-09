#!/usr/bin/env bash
# Wake peers ONLY when their machine is currently OFF.
#
# Rule (non-negotiable): never dispatch a peer workflow while that same
# peer's run is in_progress or queued. One peer = one machine; two live runs
# collide on the tailscale hostname and both write hermes/ state back.
#
# This script is fail-CLOSED: if `gh run list` errors for a peer, that peer is
# NOT dispatched — an unreadable state is treated as "maybe awake".
#
# Usage:  scripts/peer-wake.sh [peer ...]      (default: all five)
# Env:    GH_OWNER (default Shabakebehdasht), PEER_REPO (default my-rey)
#
# Exit 0 = every requested peer is now booting or already awake.
# Exit 1 = gh failed, or a dispatch did not land.
set -uo pipefail

owner="${GH_OWNER:-Shabakebehdasht}"
repo="${PEER_REPO:-my-rey}"
all=(kimya sevda sonia kylie rebecca)
peers=("$@")
[ ${#peers[@]} -eq 0 ] && peers=("${all[@]}")

rc=0
for peer in "${peers[@]}"; do
  wf="$peer.yml"
  runs=$(gh run list -R "$owner/$repo" --workflow "$wf" -L 10 \
    --json databaseId,status,conclusion,createdAt,event,url 2>&1)
  if [ $? -ne 0 ]; then
    echo "!! $peer: could not read run state — NOT dispatching (fail closed)"
    echo "$runs" | head -3
    rc=1
    continue
  fi

  active=$(jq -r '[.[] | select(.status == "in_progress" or .status == "queued")] | length' <<<"$runs")
  if [ "$active" -ge 1 ]; then
    echo "== $peer: SKIPPED — already booting/awake, not dispatching again"
    jq -r '[.[] | select(.status == "in_progress" or .status == "queued")][]
           | "     run \(.databaseId) \(.status) since \(.createdAt) — \(.url)"' <<<"$runs"
    continue
  fi

  echo "== $peer: off — dispatching $wf"
  if ! out=$(gh workflow run "$wf" -R "$owner/$repo" 2>&1); then
    echo "!! $peer: dispatch FAILED: $out"
    rc=1
    continue
  fi
  echo "   $out"

  # Verify the dispatch landed: a queued/in_progress run must now exist.
  sleep 4
  after=$(gh run list -R "$owner/$repo" --workflow "$wf" -L 3 \
    --json databaseId,status,url 2>&1)
  if [ $? -ne 0 ] || [ "$(jq -r '[.[] | select(.status == "in_progress" or .status == "queued")] | length' <<<"$after" 2>/dev/null)" = "0" ]; then
    echo "!! $peer: dispatch did NOT land — no active run after 4s"
    echo "$after" | head -3
    rc=1
    continue
  fi
  jq -r '.[0] | "   OK run \(.databaseId) \(.status) — \(.url)"' <<<"$after"
done

echo
if [ "$rc" -eq 0 ]; then
  echo "RESULT: all requested peers are up or booting. No machine woken twice."
else
  echo "RESULT: failures above — inspect before assuming anything is awake."
fi
exit $rc
