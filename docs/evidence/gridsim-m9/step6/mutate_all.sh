#!/bin/bash
# M9 step 6: apply each named sabotage, run the focused tests, restore.
#   bash mutate_all.sh R1_window_ignored R2_H_machine_base ...
D=/w/Claude_projects/GridSim/docs/evidence/gridsim-m9/step6
for m in "$@"; do
  echo "### $m"
  python $D/mutate.py $m || { echo "apply failed"; continue; }
  bash $D/run_r.sh $m | grep -E "exit=|^m9r|Test Summary"
  python $D/mutate.py restore
done
git -C /w/Claude_projects/GridSim diff --stat -- src
