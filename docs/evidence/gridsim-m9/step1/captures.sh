#!/bin/bash
# usage: captures.sh TAG   — runs the four gate captures against W:\Claude_projects\GridSim
T=$1; D='W:\temp\claude\gridsim-m9\step1'; P='W:\Claude_projects\GridSim'; BS='\'
run() {
  local out="${D}${BS}$1-$T.txt" err="${D}${BS}$1-$T.err"
  echo "cmd: julia $2 > $out"
  cmd //v:on //c "start /belownormal /b /wait julia --project=$P $2 > $out 2> $err & exit !errorlevel!"
  echo "$1 exit=$?"
}
run criterion 'W:\temp\claude\gridsim-m8\criterion_snapshot.jl'
run ac 'W:\temp\claude\gridsim-m8\ac_snapshot.jl'
run screen "${D}${BS}screen_snapshot.jl"
run dips "${D}${BS}dips_snapshot.jl"
