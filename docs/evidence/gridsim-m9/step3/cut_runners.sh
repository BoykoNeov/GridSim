#!/bin/bash
# Cut the two focused reference runners mutate.py uses out of reference/test/runtests.jl,
# by section MARKERS (line numbers shift with every edit to that file).
#   bash W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/step3/cut_runners.sh OUTDIR
# run_s3.jl      = the shared helpers + the detailed-tier helpers + the M9 step-3 block
# run_oracleB.jl = the shared helpers + the M6 step-4 oracle-B block
F=/w/Claude_projects/GridSim/reference/test/runtests.jl; O=$(cygpath -u "$1"); mkdir -p "$O"
ln() { grep -n -F -- "$1" "$F" | head -1 | cut -d: -f1; }
h_end=$(( $(ln '@testset "M4 step 4 — PowerDynamics as an external oracle"') - 1 ))
d_beg=$(( $(ln '# Fixtures and helpers for the detailed tier (M5 steps 3 and 4)') - 1 ))
d_end=$(ln 'chan(k) = s -> getproperty(s, k)')
s_beg=$(( $(ln '# M9 step 3 — line resistance reaches PowerDynamics') - 1 ))
b_beg=$(( $(ln '# M6 step 4, oracle B — PowerFlows.jl') - 1 ))
b_end=$(ln 'end # M6 step 4 oracle B')
{ sed -n "1,${h_end}p" $F; sed -n "${d_beg},${d_end}p" $F; sed -n "${s_beg},\$p" $F; } > "$O/run_s3.jl"
{ sed -n "1,${h_end}p" $F; sed -n "${b_beg},${b_end}p" $F; } > "$O/run_oracleB.jl"
