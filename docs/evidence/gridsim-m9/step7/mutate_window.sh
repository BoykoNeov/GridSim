#!/bin/bash
# Each window sabotage in turn: back up, apply in place, run the window's testsets with
# the precompile workload off (GRIDSIM_UI_PRECOMPILE=0), restore. OUTDIR under W:\temp\claude.
#   bash W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/step7/mutate_window.sh OUTDIR RUNNER
O=$1; R=$2; BS='\'; F=/w/Claude_projects/GridSim/ui/src/frequency_screen_window.jl
B=$(cygpath -u "$O")/frequency_screen_window.jl.bak; mkdir -p "$(dirname "$B")"
cp "$F" "$B"; trap 'cp "$B" "$F"' EXIT
export GRIDSIM_UI_PRECOMPILE=0
for m in ${MUTS:-W1 W2 W3 W4 W5}; do
  cp "$B" "$F"
  python W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/step7/mutate_window.py $m || exit 1
  cmd //v:on //c "start /belownormal /b /wait julia --project=W:\Claude_projects\GridSim\ui $R > ${O}${BS}$m.txt 2>&1 & exit !errorlevel!"
  echo "$m exit=$?"
done
