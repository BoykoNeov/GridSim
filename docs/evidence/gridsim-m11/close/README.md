# M11 close and the D13 fix (2026-11-13)

What was run, so it can be run again. Scratch output went to
`W:\temp\claude\gridsim-improve\` and was deleted at the end of the batch; the scripts
here write there (edit the paths at the top of each to use them again).

- `d13_probe.jl` — the capped-governor fixture (case9, default loads, G1 given 10 MW of
  schedule reserve, G2 lost) under four solver settings: the largest distance `ΔPm` gets
  above its cap. Run before and after a change to `_governor_cap_callbacks`.
- `capture_diff.py` — compares two tags of the M9 captures line by line and reports the
  largest relative difference per capture, and every line that differs in more than its
  numbers. `d13_capture_diff.txt` is its output for the D13 fix (before = `64bc695`,
  after = the fix): the record behind the table in `m11-context.md`, "D13 fixed".
- `resolve_all.sh` — deletes the four manifests and re-resolves them, root first.
- `manifest_diff.py`, `moved.txt` — which packages moved at the close.
- `suites.sh TAG core ref ui` — the three `Pkg.test()` suites at below-normal priority,
  one after another.

Order at a close: captures (`../../gridsim-m9/harness/captures.sh TAG OUTDIR`, then
`../../m10-close/dynamic_snapshot.jl` with `--project=<tree> <tree>` — it needs the tree
as its argument), `resolve_all.sh`, captures again, compare, suites.

What the close found is in `docs/plans/m11-tasks.md`, step 6.
