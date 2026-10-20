#!/bin/bash
# M10 close: delete the four manifests and re-resolve them in sequence (root first), below-normal.
# Copies of the old ones: docs/evidence/m10-close/ (root, reference, ui) and scratch (testenv).
R='W:\Claude_projects\GridSim'; BS='\'; OUT='W:\temp\claude\gridsim-m10-close'
H="${R}${BS}docs${BS}evidence${BS}gridsim-m9${BS}harness${BS}testenv"
for n in root reference ui testenv; do
  case $n in root) P="$R";; reference) P="${R}${BS}reference";; ui) P="${R}${BS}ui";; testenv) P="$H";; esac
  rm -f "$(cygpath -u "$P")/Manifest.toml"
  cmd //v:on //c "start /belownormal /b /wait julia --project=$P ${OUT}${BS}resolve.jl > ${OUT}${BS}resolve-$n.log 2>&1 & exit !errorlevel!"
  echo "$n exit=$?"
done
