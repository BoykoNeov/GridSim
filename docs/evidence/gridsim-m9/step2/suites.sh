#!/bin/bash
# usage: suites.sh TAG [core|ui|ref ...]  — Pkg.test() at below-normal priority, sequentially
T=$1; shift; D='W:\temp\claude\gridsim-m9\step2'; BS='\'; R='W:\Claude_projects\GridSim'
which=${@:-core ref ui}
for n in $which; do
  case $n in core) P="$R";; ui) P="${R}${BS}ui";; ref) P="${R}${BS}reference";; esac
  out="${D}${BS}${n}-${T}.log"
  cmd //v:on //c "start /belownormal /b /wait julia --project=$P W:\temp\claude\gridsim-m8\pkgtest.jl > $out 2>&1 & exit !errorlevel!"
  echo "$n exit=$?"
done
for n in $which; do echo "== $n"; grep -E "^Test Summary|tests passed|tests failed|Error During|Test Failed" -A1 /w/temp/claude/gridsim-m9/step2/$n-$T.log | tail -4; done
