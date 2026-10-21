# M11 step 1 — the instruments behind the predictions and the findings

Julia 1.12.6. Results are written up in `docs/plans/m11-context.md`, "What step 1
measured"; the predictions they are read against are `../step1_predictions.md`.

- `probe.jl` — the runs made **before** the predictions (not comparisons): our
  `dc_powerflow` flows at the dispatch's schedule, HiGHS's statuses on the θ
  formulation at both regularizations, and on the hand-provable infeasible fixture.
  The predictions file cites it at its first scratch path,
  `W:\temp\claude\gridsim-m11-step1\probe.jl`; this is that file, kept.
  Run: `julia --project=docs/evidence/gridsim-m9/harness/testenv probe.jl`.
- `numbers.jl` — prints every step-1 fixture's outcome, outputs, flows and the 22.4
  band, read by eye beside the predictions (the tests assert them). Same environment.
- `sabotage.py` — the five sabotages as exact string replacements (each must match
  once), plus the 120 s solver time limit every mutant got after S4's first run spun
  for two hours. Applied one at a time, the M11 testset run, the files restored from
  copies; never committed.
