# M11 step 5 — the instruments behind D12 (the reference's up-reserve) and D13

Run from scratch at the time (`W:\temp\claude\gridsim-m11-step5\`); kept here so the numbers
in `docs/plans/m11-context.md` ("What the fix measured", D13) can be re-derived.

- `captures.sh TAG` — the eleven gate captures (step 3's, output to this step's scratch).
  Taken as `HEAD` before the first `src/` edit and `FIX` after; ten byte-identical.
- `report10.diff.txt` — the one printed capture that moved: M10's report, HEAD → FIX.
- `snapdiff.jl HEAD_DIR FIX_DIR` — names every entry the fix moved in M10's serialized
  screens (harness `testenv`).
- `fixprobe.jl` — the shift and the up-reserve per report grid, screen against detailed tier.
- `tight_probe.jl` — M8's tight-reserve fixture: the real reserve AC needs (61.1281 MW) and
  the schedule's threshold under the fix (64.1463 MW).
- `cap_probe.jl` — D13: the detailed tier's governor passing its cap and staying there.
- `run_headroom.jl` — `test/m11_headroom.jl` alone, in the harness `testenv`.
- `run_report.jl` — `test/m11_report.jl` alone, in the `reference` environment.
- `margin_probe.jl` (+ `.out.txt`) — the report's blind anti-vacuity mutation: every AC
  optimum solved at margin 0 still starts in the detailed tier.
