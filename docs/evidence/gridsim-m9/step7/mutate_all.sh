#!/bin/bash
# Each sabotage in turn, on a scratch COPY of the report script (the tree is never
# edited): copy, apply, run the step-5 + step-7 testsets at below-normal priority with
# the copy standing in for the script (run_report.jl reads GRIDSIM_OS_SCRIPT), keep the
# output.
#   bash W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/step7/mutate_all.sh OUTDIR
# OUTDIR is a Windows path under W:\temp\claude.
O=$1; BS='\'; S=/w/Claude_projects/GridSim/scripts/outage_screen.jl
H='W:\Claude_projects\GridSim\docs\evidence\gridsim-m9'
U=$(cygpath -u "$O"); mkdir -p "$U"
for m in P1 P2 P3 P4 P5; do
  cp "$S" "$U/outage_screen_$m.jl"
  python "$(cygpath -u "$H")/step7/mutate.py" $m "$U/outage_screen_$m.jl" || exit 1
  export GRIDSIM_OS_SCRIPT="$(cygpath -w "$U/outage_screen_$m.jl")"
  cmd //v:on //c "start /belownormal /b /wait julia --project=${H}${BS}harness${BS}testenv ${H}${BS}step7${BS}run_report.jl > ${O}${BS}$m.txt 2>&1 & exit !errorlevel!"
  echo "$m exit=$?"
done
