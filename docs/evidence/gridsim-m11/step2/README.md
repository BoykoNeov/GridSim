# M11 step 2 — the instruments behind the predictions and the findings

Julia 1.12.6. Results are written up in `docs/plans/m11-context.md`, "What step 2
measured"; the predictions they are read against are `../step2_predictions.md`. Every
script names the scratch paths it was first run at (`W:\temp\claude\gridsim-m11-step2`);
these are those files, kept. The downloaded `case9.m` is not kept here (MATPOWER's
licence does not cover its case files, D7) — the URL, commit and sha256 are in the
predictions file.

- `resolve.jl` — PowerModels, Ipopt, JuMP and HiGHS added to a scratch COPY of
  `reference/Project.toml` + `Manifest.toml` (the `[sources]` path made absolute), every
  version diffed before and after. 300 → 321, nothing moved, nothing removed. The real
  `reference/` add then produced a manifest identical to the probed one (paths aside).
- `reader.jl` — `GridSimDispatchExt` loads beside PowerModels; `parse_matpower` of the
  typed rows (the text that is now `C9_MATPOWER` in `reference/test/m11_dc_opf_oracle.jl`,
  written to a scratch file) is `==` to `parse_file` of the downloaded file; their
  reader's ±60° angle bounds, branch orientation and per-unit ratings.
- `theirs_probe.jl` — PowerModels + Ipopt alone on every fixture at four tolerances
  (statuses, solution keys, their own convergence). Prints nothing of ours.
- `ours_probe.jl` — `dc_opf` alone at `margin = 0`, `regularization = 0`, its own
  convergence (exactly 0). Prints nothing of theirs.
- `run_step2.jl` — the step-2 testset alone in the reference environment (what the
  sabotages ran against).
- `sabotage.py` — SA1, SA2, SB as exact string replacements (each must match once), plus
  a 120 s HiGHS time limit on every mutant; `apply` backs the file up to scratch,
  `restore` puts it back. Never committed.
