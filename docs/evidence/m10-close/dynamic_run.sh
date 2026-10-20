#!/bin/bash
# run.sh TAG TREE(windows path)
T=$1; P=$2; OUT='W:\temp\claude\gridsim-m10-close-dyn'; BS='\'
S='W:\Claude_projects\GridSim\docs\evidence\m10-close\dynamic_snapshot.jl'
cmd //v:on //c "start /belownormal /b /wait julia --project=$P $S $P > ${OUT}${BS}dyn-$T.txt 2> ${OUT}${BS}dyn-$T.err & exit !errorlevel!"
echo "dyn $T exit=$?"
