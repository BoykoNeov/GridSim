#!/bin/bash
# Pkg.test() for core / reference / UI at below-normal priority, one after another
# (never concurrently: they share the depot). Logs go to scratch.
#   bash W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/suites.sh TAG [core|ref|ui ...]
T=$1; shift; OUT='W:\temp\claude\gridsim-m9\suites'; mkdir -p /w/temp/claude/gridsim-m9/suites
H='W:\Claude_projects\GridSim\docs\evidence\gridsim-m9\harness'; BS='\'; R='W:\Claude_projects\GridSim'
which=${@:-core ref ui}
for n in $which; do
  case $n in core) P="$R";; ui) P="${R}${BS}ui";; ref) P="${R}${BS}reference";; esac
  cmd //v:on //c "start /belownormal /b /wait julia --project=$P ${H}${BS}pkgtest.jl > ${OUT}${BS}${n}-${T}.log 2>&1 & exit !errorlevel!"
  echo "$n exit=$?"
done
for n in $which; do echo "== $n"; grep -E "^Test Summary|tests passed|tests failed|Error During|Test Failed" -A1 /w/temp/claude/gridsim-m9/suites/$n-$T.log | tail -4; done
