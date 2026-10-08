# The M9 gate harness

The scripts later M9 steps reuse, runnable from here. The per-step folders beside
this one (`step1/`, `step2/`) are the record of what was run at the time and are not
edited; this folder is the working copy.

- `captures.sh TAG [OUTDIR]` — five full-precision snapshots (`swing`, `criterion`,
  `ac`, `screen`, `dips`) written to scratch (default `W:\temp\claude\gridsim-m9\captures`).
  Take them at HEAD before the first edit, again after, and compare with `cmp`.
- `suites.sh TAG [core|ref|ui ...]` — the three `Pkg.test()` suites at below-normal
  priority, one after another.
- `run_m9.jl` with `--project=…/harness/testenv` — the M9 testsets alone.

Never edit `src/` while a capture or suite runs: each Julia launch loads the working
tree.
