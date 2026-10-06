#!/bin/bash
# Deliver a prompt file to each peer. One offline peer must not abort the batch.
#
# Usage: peer-dm-batch.sh kimya:/path/msg-a.txt sevda:/path/msg-b.txt ...
# Or read `peer:prompt-file` pairs from stdin, one per line.
#
# Run this with background=true + notify=true: a peer doing real work can take
# minutes to answer and will exceed the 600s foreground cap. Do not re-run it
# while it is alive - that is a second DM of the same task.

pairs=("$@")
if [ ${#pairs[@]} -eq 0 ]; then
  read -r -a pairs <<< "$(cat)"
fi

for pair in "${pairs[@]}"; do
  [ -z "$pair" ] && continue
  peer="${pair%%:*}"
  file="${pair#*:}"
  echo "########## $peer ($(basename "$file")) ##########"
  ok=0
  for i in 1 2 3; do
    out=$(hermes peer dm "$peer" "$(cat "$file")" 2>&1)
    rc=$?
    echo "--- attempt $i rc=$rc ---"
    echo "$out"
    if [ $rc -eq 0 ]; then ok=1; break; fi
    sleep 20
  done
  echo "===== $peer : $([ $ok -eq 1 ] && echo DELIVERED || echo FAILED) ====="
done