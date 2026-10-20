#!/bin/bash
# dynamic_snapshot.jl at below-normal priority, output to scratch; run once per tree and cmp.
#   bash W:/Claude_projects/GridSim/docs/evidence/m10-close/dynamic_run.sh TAG TREE(windows path)
T=$1; P=$2; OUT='W:\temp\claude\gridsim-m10-close-dyn'; BS='\'
mkdir -p /w/temp/claude/gridsim-m10-close-dyn
S='W:\Claude_projects\GridSim\docs\evidence\m10-close\dynamic_snapshot.jl'
cmd //v:on //c "start /belownormal /b /wait julia --project=$P $S $P > ${OUT}${BS}dyn-$T.txt 2> ${OUT}${BS}dyn-$T.err & exit !errorlevel!"
echo "dyn $T exit=$?"
