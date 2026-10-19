# M10 step 4 — predictions, written before the tests and the sabotages ran

Written 2026-10-19, after the spike (`step4_spike.jl`, `step4_relay_probe.jl`, outputs
beside them) and a smoke run of the first version of the code, before any test in
`test/m10_double_outages.jl`'s step 4 testset existed. What the spike settled is in
`m10-context.md` D10; this file is what the tests and the sabotages are predicted to do.

## What the spike already measured (not predictions)

- One re-solve of the final network passes where two did not: default loads L45+L67,
  L56+L78, L67+L89 all pass; constant power L56+L78 passes; constant power **L45+L67
  (B5 0.866) and L67+L89 (B9 0.8954) are refused at the trip instant**, although step 3's
  AC screen called L67+L89 secure in both pieces. So on constant power ONE two-live-piece
  pair is left for the oracle, L56+L78; the oracle is widened to the default loads by
  carrying the load-draw term (below).
- A dead bus grounded through its own load slot (`G = 1`, `B = a_i = a_p = 0`) solves to
  `|V| = 0.0` exactly on both load models, where left alone it solves to 1.83e9 pu
  (constant power) and 0.0 (default); the band check is then the only refusal left.
- The relay path today (before the fix): the refused trip leaves L12 open in both
  networks, `n_events = 0`, the relay's log `tripped = true` with `armed = true`; a
  `solve!` continued from there collapses its step size at t = 9.23 s.
- A machine bus de-energised (case9 L36 alone, G3 cut off): the run aborted with NaN in
  G3's `Efd` Jacobian row — `hypot`'s derivative at exactly zero, read by the exciter even
  with the regulator off. Fixed by `_exciter_vmag` (exact `hypot` away from zero).

## Bands, stated before the runs

- **Bit-identity (20.2, direct `inject!`):** a refused event, then a run on, against a twin
  never injected: every channel of `state_series`, the event log, `lines_online`, both
  parameter vectors, `u_static` — `isequal`, no band.
- **19.4 (L36 alone against `TripGenerator(:G3)`):** the same equilibrium, reached by two
  step sequences; at reltol 1e-10, 400 s, every surviving machine's ω within **1e-9** and
  every bus but B3 within **1e-9** in |V|.
- **Per-piece identity (the oracle):** each live piece, settled,
  `ω_dyn − Δω_AC = −[(L_dyn + D_dyn) − (L_AC + D_AC)] / Σw_piece`, with `L` the piece's
  internal losses (both ends of every in-service branch inside it), `D` its loads' draw,
  `Σw` = Σ(1/R + D) over its online machines; **rtol 1e-6** (M9 step 1's), anti-vacuity
  |lhs| > 1e3·|lhs − rhs|. Machines of one piece agree in ω within **1e-10**; the reading at
  300 s and at 400 s agrees within **1e-10** (settled). Precondition: every piece
  `:secure` and no governor in it capped (`ac.capped`).
  Cases: constant power L56+L78 (two pieces, one up and one down) and L45+L56 (the rest of
  the grid, B5's load gone); default loads L45+L67, L56+L78, L67+L89.
- **Prediction about what the identity needs**: with the WHOLE grid's `Σw` instead of the
  piece's, or the whole grid's losses, the identity fails by far more than its rtol on
  every two-piece case — asserted in the test as anti-vacuity, not run as a sabotage.

## Sabotages, each red where named (and nowhere a reason was not given)

- **S1 — no restore** (`_refusable!` returns without `_restore!`): red on the twin
  bit-identity (direct path), on the positive control's "the refused first `TripLine` left
  L45 in service", and on the relay testset's "L12 back in service / status 1.0".
  Green on every run that is never refused (19.4, the identity, the dead piece, swing).
- **S2 — the intermediate network** (`_trip_elements!` re-solves after each line): red on
  the positive control (default L45+L67 refused at its first line, as at step 0) and on the
  identity's default-load L45+L67 case. Whether the other pairs' intermediate networks
  pass is not known; no prediction either way for them.
- **S3 — no de-energising** (`_deenergise!` a no-op): red on the dead-piece testset (both
  load models refused, as the spike showed — constant power by the band at 1.8e9, default
  by the band at 0.0) and on 19.4 (B3's row `0 = 0` after G3 trips: stalled or refused).
- **S4 — a cut-off source left online** (the `auto` list emptied): red on 19.4 (G3 still
  online, no `trip G3` in the log). The dead piece's testset stays green (B5 holds no
  source).
- **S5 — the relay's record not put back** (the `try/catch` in `out_of_step.jl` removed):
  red on the relay testset's "the relay did not operate" only.
- **S6 — no halt** (the relay closure does not set `halted`): red on the relay testset's
  "a later `solve!` and `inject!` refuse" only.

## Dated note, 2026-10-19, after the first test run and BEFORE any sabotage ran

The first run passed 90 of 91: the identity testset lost constant-power L45+L56 to an FBDF
step-size collapse at t = 367.66 s, with every state's weighted error ~1e-43 (the cases after
it never ran). `step4_settle_probe.jl` ran all six to 400 s three ways: FBDF also collapses on
that case at 228.73 s when the run is split differently, and on default-load L45+L56 at reltol
1e-9 (not at 1e-10) — isolated, non-monotone in the tolerance, only where a bus is grounded;
Rodas5P at 1e-10 completes all six, settled 300→400 s within 6.8e-13. The identity testset now
uses Rodas5P at 1e-10. Nothing else in the predictions above changes; the bands are as stated.

Second dated note, same day, still before any sabotage: the rerun passed every identity
assertion and failed only the testset's two counts, which were written wrong (11 pieces and 5
up/down splits; the case list holds four two-piece splits and two dead-piece rests, so 10 and
4 — what the run counted). Corrected in the test; no measured number moved.

## Added 2026-10-19 after the step-4 commit (review): the inverter half, predictions first

The report grids carry no inverter, so nothing above reached `TripElements`' inverter code: the
`lost[q]` line added to `_pair_piece_kind`, the online-only grid-following list, and
`_source_off!`'s two inverter branches. Two cases on step 2's corner triangle, with a 10 MW load
added at A (G1 at 70 MW) so that cutting {B, C} off leaves A live:

- **Grid-forming:** `TripGenerator(:I3)`, then `TripElements` on AB+CA. Predicted: runs; {B, C}
  holds LB and only the tripped I3, so it is load lost — `deenergised_buses == [:B, :C]`, the
  log ends `trip_line` ×2, `deenergise` B, C, and no `trip_generator` (I3 is already out).
- **Grid-following:** `TripElements` on AB+CA. Predicted: I3 tripped in the same event
  (`trip_generator I3` logged, offline), B and C de-energised.
- **S7 — the `lost[q]` line deleted:** red on the grid-forming case only — {B, C} then reads as
  live (the tripped I3 counted as a source), B and C are not grounded, and the re-solve of a
  piece with load and no source refuses or the de-energised list is wrong. The grid-following
  case and everything else green.

And two testsets that ground a bus move from FBDF to Rodas5P (the 19.4 run and the dead
piece), for the identity testset's reason; their bands are unchanged.

Dated note, same day, after the first run of the two inverter cases and before S7 ran: both ran
as predicted (B and C de-energised, the logs as written), but the grid-following case's grounded
buses integrate to |V| = 5e-324, not to an exact 0.0 as the test had asserted (the prediction
said only "de-energised"). The assertion now reads <= 1e-300.
