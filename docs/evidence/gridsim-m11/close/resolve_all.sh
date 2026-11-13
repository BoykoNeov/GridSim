#!/bin/bash
R='W:\Claude_projects\GridSim'; BS='\'; OUT='W:\temp\claude\gridsim-improve'
H="${R}${BS}docs${BS}evidence${BS}gridsim-m9${BS}harness${BS}testenv"
for n in root reference ui testenv; do
  case $n in root) P="$R";; reference) P="${R}${BS}reference";; ui) P="${R}${BS}ui";; testenv) P="$H";; esac
  rm -f "$(cygpath -u "$P")/Manifest.toml"
  cmd //v:on //c "start /belownormal /b /wait julia --project=$P ${R}${BS}docs${BS}evidence${BS}m10-close${BS}resolve.jl > ${OUT}${BS}resolve-$n.log 2>&1 & exit !errorlevel!"
  echo "$n exit=$?"
done
