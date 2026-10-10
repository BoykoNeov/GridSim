# M9 step 5 — predictions, written before any new code ran (2026-10-10)

Step 5 adds the dip: one dynamic run per generator outage in the detailed tier, seeded
from the AC screen's own base solution, trip at 1 s, every outage run whatever the AC
screen said (step 0's mistake was skipping a column on the refused rows). Entered at
`030d143`; fresh captures at HEAD, identical to step 2's committed `*-STEP2.txt`.

## Decisions fixed BEFORE any lossy run (recorded in `m9-context.md` D9)

1. **"Agree" is `tolerance_band`, not `convergence_band`.** The plan names
   `convergence_band`, which needs a coarse/fine PAIR for each of two different
   integrations (four series). The two dip runs are one engine, one solver, two
   tolerances — the case `tolerance_band` documents. Per judged channel (the COI
   frequency and each surviving machine's speed), band = `3 · 1e-6 · excursion` of the
   1e-8 run's channel; the pair agrees when every channel's extreme deviation differs
   by no more than its band. If this comes out too tight for FBDF's global error over a
   long slide, that is a finding: the band is not widened and no third tolerance is tried.
2. **The frozen pair:** FBDF, reltol 1e-6 / abstol 1e-8, and reltol 1e-8 / abstol 1e-10
   (abstol = reltol/100, as step 0's fine run).
3. **The stopping rule, derived from what it can miss.** After the trip the run advances
   in 0.5 s chunks; at each chunk end `coi_rocof` is read (the RHS's own derivative,
   not a finite difference). The slowest settling is the damping-only slide of a
   governor-capped grid, `f(t) ≈ f∞ + A·e^(−t/τ)`, `τ = 2ΣH/ΣD` over the surviving
   machines (system base); its remaining shortfall is `τ·|ḟ|`. The run stops once
   `τ·|ḟ| ≤ 1e-5 Hz` has held at every chunk end for `τ` seconds — one more `τ` than
   the arithmetic needs, so a trough (where `ḟ` passes zero) cannot stop it. Horizon:
   `40τ` after the trip; reached first, the outcome is `:not_reached`, never the last
   sample. **Departure from the plan's sentence** "a minimum followed by a recovery
   fixes the dip on its own": a governor that caps later can slide below the first
   trough, so every run waits for settling. No damping (`ΣD = 0`) gives no `τ` and is
   refused by name.
4. **The re-initialisation after the trip is classified, not text-matched.** Voltage
   band → `:refused_at_trip` with reason `:voltage`; branch rating (still sending-end
   only, carried since step 1) → `:refused_at_trip`, reason `:rating`; a stalled
   static solve (`NetworkInitError`, caught by type) or a residual over threshold →
   `:solver_failure`. The dynamic-KCL check stays a hard throw: it means an event wrote
   one parameter vector and not the other, a bug. A failed integration is read off the
   integrator's own retcode, not the error text.
5. **The dip is judged on the largest |deviation| either way**, every surviving machine,
   with the COI reported beside it (Hurdle 16.3; step 4's `abs` rule). The machine
   extremes are the running ones in the engine, over every output sample while the
   machine is online.

## Predicted

- **Gate:** all five captures byte-identical after the change (fields added to
  `DetailedEngine` change no recorded number).
- **Stop times on the two capped rows** (lossless, mesh G1; `τ = 2(4·1.5 + 3.5·1.2) /
  (2·1.5 + 1.5·1.2) = 20.4/4.8 = 4.25 s`): constant power stops ≈ `τ·ln(10.94/1e-5) + τ`
  ≈ 60–65 s after the trip; default loads sooner (load relief speeds the slide; step 0's
  argmin moved 103 → 72 s), ≈ 40–50 s. Both well inside `40τ = 170 s`.
- **Regression against step 0's lossless table** (four printed decimals), wherever the
  pair judges: COI dip, settled value (now the value at the stop, which the rule puts
  within 1e-5 Hz of step 0's 150 s value), worst machine and its id — all to the printed
  digits. Not bit-for-bit: the chunk ends are tstops, so the step sequence differs.
  The engine's running extremes see every output sample, so they can only equal or
  exceed step 0's series reads, never fall short.
- **Positive control for 16.5:** lossless mesh-default G2 comes back `:solver_failure`
  (FBDF 1e-8 `Unstable` at 5.6 s in step 0). **Stated risk:** the chunk tstops change the
  step sequence, and an instability that depends on it may not reproduce. If it does not,
  that is reported, and the pair is not changed to make it come back.
- **Refused at the trip, lossless:** case9 constant-power G1 and G2, case9 default G1 —
  with case9-constant-power G2 the only one the AC screen calls `:secure` (the
  mismatch set). **Lossy (the report grids):** the same three refused, the same one
  mismatch.
- **Lossy dips:** within 5 % of their lossless counterparts, deeper where the losses
  deepen the settled value (mesh-cp G3: AC settled 0.200 lossy against 0.193 lossless).
- **The two tolerances agree** on every short-trough outage; the capped G1 slides are
  the ones at risk of `:disagree` (a 100 s integration's global error at 1e-6 against a
  band of 3e-6 relative). Honestly uncertain; recorded so the result cannot move it.
- **Exactness:** on a short run inside the recorder's capacity the engine's per-machine
  minimum equals the minimum of the recorded series bit for bit; with a capacity small
  enough to decimate, it is never shallower than the series.

## Outcomes of the first probe (lossless, before any `src/` edit), appended 2026-10-10

Probe: `probe_chunk.jl` here (run at HEAD, no `src/` change), FBDF,
lossless copies, horizon 150 s, both tolerances, one-shot `solve!` against 0.5 s chunks.

- **The 16.5 positive control did NOT survive chunking — the stated risk happened.**
  Mesh-default G2 at 1e-8: one-shot `Unstable` at t = 5.6015 s ("dt forced below
  floating point epsilon", step 0's failure reproduced exactly); chunked, it runs, and
  agrees with 1e-6 (nadir −0.3911552 against −0.3911548 Hz). The failure depends on
  where the steps land — itself the evidence for 16.5 (an answer that moves with step
  placement is not one) — but it is no longer a control. Kept chunking (the design was
  written before the probe); the control is replaced by (a) a stall built from model data
  (case9 constant power, every `Branch.R` ×1.1 — step 3's T1b reproducer as data, not as a
  mutation) and (b) a failed integration from `init!`'s own `maxiters`.
- **Decision 1 (the `tolerance_band` agreement) FAILED on the headline case.** Mesh
  constant-power G1 (capped slide): 1e-8 dip −10.937499879 Hz, 1e-6 dip −10.937463848 Hz;
  gap 3.60e-5 Hz against a band of `3·1e-6·10.9375 = 3.28e-5` Hz — ratio 1.098, a
  `:disagree`. The exact value is −10.9375 Hz (closed form, lossless constant power), so
  the gap is the 1e-6 run's global error over a 100 s slide, which `tolerance_band`'s
  factor (two runs at ONE tolerance) never bounded. **The gap was seen before the
  replacement rule was chosen.** The user chose (2026-10-10, asked with that stated):
  **the dip is judged at both tolerances and counts only where the two verdicts agree** —
  pass only if both pass, fail only if both fail, otherwise `:tolerance_dependent`. No
  band at all. The fine run's own error is pinned against the closed form instead
  (1.2e-7 Hz here).
- **Cost:** 0.1–5.6 s per run after compilation; a 1e-8 capped slide is the dearest.

## Before comparing with step 0 at full precision (appended 2026-10-10)

The regression band, stated before the full-precision comparison: every judged value
(COI dip, worst machine, settled-at-stop against step 0's value at 150 s) within
**1e-5 Hz** of the step-0 capture (`dips-HEAD.txt`) — the stopping rule's shortfall
bound, which dominates the settled value; the dips themselves should differ only at
the solver's tolerance (~1e-7). The plan's weaker "to the printed digits" is implied.

## Sabotages — predicted before any ran (appended 2026-10-10)

`mutate.py` here; focused run `run_d.jl` (step 4's verdict tests + `test/m9_dips.jl`).

| | Sabotage | Predicted |
|---|---|---|
| D1 | extremes read from the recorder | red — only the decimating-recorder check (`deeper`); the in-capacity check is green by construction |
| D2 | COI read in place of every machine | red — regression `worst`, every-machine testset |
| D3 | last sample reported at the horizon | red — the `horizon = 1` control |
| D4 | one tolerance (both at 1e-8) | red — `c < f` premise and the tolerance-dependent pair |
| D5 | no hold (stop at the first quiet read) | **uncertain, probably green**: a 0.5 s read landing on a trough's zero crossing to within 1e-5/τ is unlikely on these fixtures |
| D6 | shortfall bound ×100 | red — the slowest-case shortfall and the 1e-5 regression |
| D7 | the coarse run settles on its own | red — mesh-default G3 back to `:not_reached` |
| D8 | a voltage refusal classified as a failure | red — the refusal-mismatch testset |
| D9 | a stall classified as a refusal | red — the stall control |
| D10 | `<` for `≤` in the dip verdict | red — the limit exactly on the value |
| D11 | the runs' model check dropped | red — case9's runs against the mesh |
| D12 | the online guard dropped from the extremes | **green** — a tripped rotor does not move at this tier (torque and current zeroed), so there is nothing for the guard to exclude |
| D13 | only the fine run judged | red — the tolerance-dependent pair |
| D14 | a run that measured nothing passes | red — the refused rows' verdict |
