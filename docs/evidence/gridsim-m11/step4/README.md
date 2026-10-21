# M11 step 4 — the instruments behind the predictions and the findings

Julia 1.12.6. Results are written up in `docs/plans/m11-context.md`, "What step 4
measured"; the predictions they are read against are `../step4_predictions.md`. Every
script names the scratch paths it was first run at (`W:\temp\claude\gridsim-m11-step4`);
these are those files, kept.

- `resolve.jl` — `Pkg.resolve()` on a scratch COPY of `reference/Project.toml` +
  `Manifest.toml` (the `[sources]` path and the manifest's GridSim path made absolute),
  every version diffed before and after: 321 → 321, nothing moved, nothing added or
  removed; the only manifest change is GridSim's weakdeps gaining `Ipopt` and its
  extensions gaining `GridSimOPFExt`. Both extensions load. The real `reference/` was
  then resolved the same way (`Project.toml` untouched).
- `theirs_probe.jl` (+ `.out.txt`, PowerModels' reader warnings stripped) — PowerModels'
  AC OPF alone on the step-4 fixtures at four tolerances: the edits read back through
  their reader, statuses, flows at both ends, angle differences, their own convergence.
  Prints nothing of ours.
- `ours_probe.jl` (+ `.out.txt`) — `ac_opf` alone at `margin_V = margin_S = 0` on the same
  fixtures, its statuses and own convergence. Prints nothing of theirs.
- `run_step4.jl` — the step-2 and step-4 testsets alone in the reference environment (step
  4 reuses step 2's module and text); what the sabotages ran against.
- `sabotage.py` — SQ (our `Q_max` typed 1.0 for 3.0 in `scripts/outage_screen.jl`) and SC
  (their text built without `b0`), each an exact string replacement that must match once,
  plus Ipopt's 120 s CPU limit in `ext/GridSimOPFExt.jl` on every mutant; `apply` backs the
  files up to scratch, `restore` puts them back. Never committed.
