# The M9 gate harness

The scripts later M9 steps reuse, runnable from here. The per-step folders beside
this one (`step1/`, `step2/`) are the record of what was run at the time and are not
edited; this folder is the working copy.

- `captures.sh TAG [OUTDIR]` — six full-precision snapshots (`swing`, `criterion`,
  `ac`, `screen`, `dips`, and from the close `verdict` — M9's own lossy dips, rates and
  verdicts, traces in full, ~11 MB) written to scratch (default `W:\temp\claude\gridsim-m9\captures`).
  Take them at HEAD before the first edit, again after, and compare with `cmp`.
- `oracle_snapshot.jl` (M9 step 3) — the PowerDynamics oracle on lossless models at
  full precision, all four tiers and the inverter case. Not in `captures.sh`: it runs
  in the `reference` environment —
  `julia --project=W:/Claude_projects/GridSim/reference oracle_snapshot.jl > out.txt`.
- `suites.sh TAG [core|ref|ui ...]` — the three `Pkg.test()` suites at below-normal
  priority, one after another.
- `run_m9.jl` with `--project=…/harness/testenv` — the M9 testsets alone.
- From M10's close, beside this folder: `../../m10-close/m10_captures.sh` (the oracle,
  M10's 32 serialized screens, the double-outage report) and
  `../../m10-close/dynamic_snapshot.jl` (M10's detailed-tier runs at full precision; its
  committed output is `dynamic_snapshot.out.txt`). A close takes all of these as well.
- The swing capture's reference is `../step2/swing-STEP2.txt`, not `swing-HEAD.txt`
  (which predates M9's caller-order fix by one negated line).

Never edit `src/` while a capture or suite runs: each Julia launch loads the working
tree.
