#!/bin/bash
# core / reference / UI Pkg.test() at below-normal priority, one after another.
T=$1; shift; OUT='W:\temp\claude\gridsim-improve'; BS='\'; R='W:\Claude_projects\GridSim'
H="${R}${BS}docs${BS}evidence${BS}gridsim-m9${BS}harness"
for n in "$@"; do
  case $n in core) P="$R";; ui) P="${R}${BS}ui";; ref) P="${R}${BS}reference";; esac
  cmd //v:on //c "start /belownormal /b /wait julia --project=$P ${H}${BS}pkgtest.jl > ${OUT}${BS}suite-${n}-${T}.log 2>&1 & exit !errorlevel!"
  echo "$n exit=$?"
  grep -E "^Test Summary|tests passed|Some tests did not pass|Error During|Test Failed" -A1 /w/temp/claude/gridsim-improve/suite-$n-$T.log | tail -6
done
