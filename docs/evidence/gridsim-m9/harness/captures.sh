#!/bin/bash
# The gate captures (M9 steps 1-2): five full-precision snapshots, compared byte for
# byte before and after a change. Output goes to scratch, never into the repo.
#   bash W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/harness/captures.sh TAG [OUTDIR]
T=$1; OUT=${2:-'W:\temp\claude\gridsim-m9\captures'}; mkdir -p "$(cygpath -u "$OUT")"
H='W:\Claude_projects\GridSim\docs\evidence\gridsim-m9\harness'; P='W:\Claude_projects\GridSim'; BS='\'
run() {
  local out="${OUT}${BS}$1-$T.txt" err="${OUT}${BS}$1-$T.err"
  cmd //v:on //c "start /belownormal /b /wait julia --project=$P ${H}${BS}$2 > $out 2> $err & exit !errorlevel!"
  echo "$1 exit=$?"
}
run swing swing_snapshot.jl
run criterion criterion_snapshot.jl
run ac ac_snapshot.jl
run screen screen_snapshot.jl
run dips dips_snapshot.jl
