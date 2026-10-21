# M11 step 3 — the instruments behind the predictions and the findings

Julia 1.12.6. Results are written up in `docs/plans/m11-context.md`, "What step 3
measured"; the predictions they are read against are `../step3_predictions.md`. Every
script was first run from `W:\temp\claude\gridsim-m11-step3` (the paths inside them say
so); these are those files, kept. The probe environment was a scratch project with this
repo `dev`ed plus JuMP, HiGHS, Ipopt, Printf and Test.

- `resolve.jl` — Ipopt (then JuMP + HiGHS) added to a scratch copy of the ROOT
  `Project.toml` + `Manifest.toml`: 190 → 201 → 215 packages, nothing moved or removed.
- `probe.jl` → `probe.out.txt` — the runs made **before** the predictions, one side at a
  time: M6's dispatch through `ac_powerflow` (the 24.2 feasibility facts, the 24.3
  control's B9 on the exact dispatch, the flow Jacobian's inverse norm), and the
  optimiser alone on every fixture (statuses, what binds, its own convergence).
- `probe_rating.jl` → `probe_rating.out.txt` — the AC rating fixture chosen: L94 at an
  invented 60 MVA binds at its receiving end on both load models; 50 MVA is locally
  infeasible; L56 makes Ipopt stop at ALMOST_LOCALLY_SOLVED.
- `run_m11.jl` — the M11 core testsets alone (with M6's dispatch file, whose helpers they
  use); what each sabotage was run against.
- `numbers.jl` → `numbers.out.txt` — every comparison's gap beside its band, read after
  the first passing run (the tests assert them).
- `sabotage.py` — the five sabotages as exact string replacements in
  `ext/GridSimOPFExt.jl`, each with Ipopt's 120 s CPU limit; applied one at a time, the
  file restored from a copy and `cmp`-checked after the last.
- `captures.sh` — the eleven gate captures step 1 named, written to this step's scratch.
