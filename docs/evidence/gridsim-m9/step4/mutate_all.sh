#!/bin/bash
D=/w/temp/claude/gridsim-m9-step4
for m in "$@"; do
  echo "### $m"
  python $D/mutate.py $m || { echo "apply failed"; continue; }
  bash $D/run_v.sh $m | grep -E "exit=|^m9v|Test Summary"
  python $D/mutate.py restore
done
cmp $D/frequency_verdict.jl.orig /w/Claude_projects/GridSim/src/steadystate/frequency_verdict.jl && echo "src restored"
