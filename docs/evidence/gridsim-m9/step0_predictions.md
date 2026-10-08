# M9 step 0 — predictions, written BEFORE the first run (2026-10-08)

Measurement: every generator outage of case9 (no line charging, invented droop/damping,
Tg 1.0 s default) and the five-bus mesh (Tg 0.4–0.6 s), on constant-power and default
loads, in the DETAILED tier (the only dynamic tier that takes `Load`). Trip at t = 1 s.
Recorded: COI nadir (engine's running nadir), time of nadir, each machine's own lowest
speed, initial RoCoF, settled deviation, and the AC screen's settled Δf beside it.

## P1 — initial COI RoCoF = ΔP / (2 Σ H·S of the survivors) · f0 (constant-power loads)
- mesh: G1 3.68 Hz/s, G2 0.78, G3 0.48
- case9: G1 0.84, G2 1.11, G3 0.94
On default loads, smaller by the load relief at t⁺ (M7 D16's mechanism), sign only.
Read over the first 0.1 s, so expect a few % below the instantaneous value.

## P2 — the dip undershoots the settled value where the governors stay uncapped
Single-machine estimate: ζ ≈ 0.38 (case9), ≈ 0.5 (mesh); the governor's zero adds
overshoot. Predicted dip / settled: 1.5–3.0 for every uncapped outage.
case9's G1 (settled −0.40 Hz DC, −0.46 AC constant power): dip −0.8 to −1.2 Hz.

## P3 — where the governors cap (mesh G1), the dip ≈ the settled value (monotone)
Within 2 %. Approach on the damping time constant 2H/D ≈ 10–20 s, so the run needs
≥ 120 s to settle. The detailed tier at ~11 Hz low may misbehave; that is a finding.

## P4 — the lowest single-machine speed is below the COI dip by < 10 %
Largest gap in the outage with the biggest inter-machine swing (mesh G1).

## P5 — settled values agree with the AC screen's Δf (M8 step 5 already checked this,
to load relief on default loads). Just a consistency check here.

## P6 — vacuity watch
If every dip/settled ratio is < 1.05 on these fixtures, a dip criterion is untestable on
them and a fixture with real overshoot is needed. Predicted NOT to happen (P2).

---

# Outcomes (run 2026-10-08, log: step0_dips.log, step0_probe_g2.log)

NOT PREDICTED, first: **the dynamic tiers refuse line resistance**, and both report
fixtures are lossy, so the dip cannot be measured on the grids the screen reports on.
Everything below is on LOSSLESS copies (R dropped), AC screen re-run on the same copies.

| case | dip Hz | t after trip | settled Hz | AC screen Hz | dip/settled | RoCoF0 Hz/s | worst machine Hz |
|---|---|---|---|---|---|---|---|
| case9 cp G1 | refused at re-init: B1 0.773 pu (AC screen refuses it for voltage too) |
| case9 cp G2 | refused at re-init: B2 0.889 pu |
| case9 cp G3 | −0.741 | 1.41 | −0.449 | −0.449 | 1.65 | 0.935 | G2 −0.744 |
| case9 def G1 | refused at re-init: B1 0.882 pu |
| case9 def G2 | −0.656 | 1.41 | −0.397 | −0.455 | 1.65 | 0.827 | G1 −0.658 |
| case9 def G3 | −0.581 | 1.41 | −0.352 | −0.398 | 1.65 | 0.734 | G2 −0.583 |
| mesh cp G1 | −10.94 | 103 | −10.94 | −10.94 | 1.00 | 3.60 | G3 −10.94 |
| mesh cp G2 | −0.510 | 1.38 | −0.424 | −0.424 | 1.20 | 0.771 | G3 −0.550 |
| mesh cp G3 | −0.255 | 1.03 | −0.193 | −0.193 | 1.32 | 0.468 | G2 −0.263 |
| mesh def G1 | −8.67 | 72 | −8.67 | −11.22 | 1.00 | 3.10 | G3 −8.67 |
| mesh def G2 | FBDF 1e-8: Unstable at 5.6 s. FBDF 1e-6, 1e-10 and Rodas5P 1e-8 all agree: −0.391 at 1.34 s, −0.322 at 60 s (not settled) |
| mesh def G3 | −0.167 | 1.03 | −0.127 | −0.163 | 1.32 | 0.308 | G2 −0.174 |


- P1 HELD: RoCoF0 within 2–3 % of ΔP/(2ΣHS)·f0 on constant power; smaller on default loads.
- P2 PARTLY WRONG: case9 1.65 (inside 1.5–3.0), the mesh 1.20–1.32 (below). Dip is real
  in every uncapped outage, so a dip criterion is NOT vacuous on these fixtures (P6 held).
- P3 HELD: mesh G1 monotone, dip == settled, reached at ~100 s (cp) / ~72 s (default).
- P4 HELD: worst single machine deeper than the average dip by up to 7.7 % (mesh G2).
- P5: constant power agrees with the AC screen to the printed digits; default loads are
  shallower dynamically (load relief), mesh G1 by a lot (−8.67 vs −11.22).
- NOT PREDICTED: solver fragility on mesh def G2 (one setting fails, three agree) — a
  per-outage dynamic run must never turn a solver stall into a verdict.

# Sourced limits (Commission Regulation (EU) 2017/1485, SO GL)
Annex III Table 1, OJ L 220/116 (read from the page image, W:\temp\claude\gridsim-m9\sogl\sogl.pdf):
CE maximum instantaneous frequency deviation 800 mHz; maximum steady-state 200 mHz;
standard range ±50 mHz. GB 800/500; IE/NI 1000/500; Nordic 1000/500.
Reference incident CE 3 000 MW each direction, Art. 153(2)(b)(i).
These are DESIGN values for the reference incident on a whole synchronous area, not a
per-outage pass/fail rule on a small grid. Naively applied here: no uncapped dip
exceeds 800 mHz, but most settled values exceed 200 mHz (5 % droop on small grids).
