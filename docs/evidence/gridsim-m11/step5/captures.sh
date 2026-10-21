#!/bin/bash
# M11 step 5 gate (the headroom fix): the eleven captures step 1 took (the M9 harness's six, the oracle, M10's
# serialized screens, both report scripts, the dynamic-run capture), output to this step's
# scratch only. Never edit src/ while it runs.
#   bash W:/temp/claude/gridsim-m11-step5/captures.sh TAG
T=$1; OUT='W:\temp\claude\gridsim-m11-step5\captures'; mkdir -p /w/temp/claude/gridsim-m11-step5/captures
R='W:\Claude_projects\GridSim'; BS='\'
H="${R}${BS}docs${BS}evidence${BS}gridsim-m9${BS}harness"; S="${R}${BS}docs${BS}evidence${BS}gridsim-m10${BS}step6"
C="${R}${BS}docs${BS}evidence${BS}m10-close"
run() {  # name env script [args]
  local name=$1 env=$2 script=$3; shift 3
  cmd //v:on //c "start /belownormal /b /wait julia --project=$env $script $* > ${OUT}${BS}$name-$T.txt 2> ${OUT}${BS}$name-$T.err & exit !errorlevel!"
  echo "$name exit=$?"
}
for s in swing criterion ac screen dips verdict; do run $s "$R" "${H}${BS}${s}_snapshot.jl"; done
run oracle "${R}${BS}reference" "${H}${BS}oracle_snapshot.jl"
run snap "${H}${BS}testenv" "${S}${BS}snapshot.jl" "$R" "${OUT}${BS}snap-$T"
run report10 "$R" "${R}${BS}scripts${BS}double_outage_screen.jl"
run report8 "$R" "${R}${BS}scripts${BS}outage_screen.jl"
run dynamic "$R" "${C}${BS}dynamic_snapshot.jl" "$R"
