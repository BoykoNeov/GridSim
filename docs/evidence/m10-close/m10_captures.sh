#!/bin/bash
# M10 close: the captures captures.sh does not take — the PowerDynamics oracle (reference env),
# M10's 32 serialized screens (step6/snapshot.jl, harness testenv) and the printed report.
#   bash W:/temp/claude/gridsim-m10-close/m10_captures.sh TAG
T=$1; OUT='W:\temp\claude\gridsim-m10-close\captures'; mkdir -p /w/temp/claude/gridsim-m10-close/captures
R='W:\Claude_projects\GridSim'; BS='\'
H="${R}${BS}docs${BS}evidence${BS}gridsim-m9${BS}harness"; S="${R}${BS}docs${BS}evidence${BS}gridsim-m10${BS}step6"
cmd //v:on //c "start /belownormal /b /wait julia --project=${R}${BS}reference ${H}${BS}oracle_snapshot.jl > ${OUT}${BS}oracle-$T.txt 2> ${OUT}${BS}oracle-$T.err & exit !errorlevel!"
echo "oracle exit=$?"
cmd //v:on //c "start /belownormal /b /wait julia --project=${H}${BS}testenv ${S}${BS}snapshot.jl $R ${OUT}${BS}snap-$T > ${OUT}${BS}snap-$T.txt 2> ${OUT}${BS}snap-$T.err & exit !errorlevel!"
echo "snap exit=$?"
cmd //v:on //c "start /belownormal /b /wait julia --project=$R ${R}${BS}scripts${BS}double_outage_screen.jl > ${OUT}${BS}report-$T.txt 2> ${OUT}${BS}report-$T.err & exit !errorlevel!"
echo "report exit=$?"
