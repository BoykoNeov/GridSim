#!/bin/bash
# M9 step 5: apply each named sabotage, run the focused tests, restore.
#   bash mutate_all.sh D1_extremes_from_recorder D2_coi_for_machines ...
D=/w/Claude_projects/GridSim/docs/evidence/gridsim-m9/step5
for m in "$@"; do
  echo "### $m"
  python $D/mutate.py $m || { echo "apply failed"; continue; }
  bash $D/run_d.sh $m | grep -E "exit=|^m9d|Test Summary"
  python $D/mutate.py restore
done
git -C /w/Claude_projects/GridSim diff --stat -- src
