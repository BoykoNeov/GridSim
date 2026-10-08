# M8 step 4 — predictions, written 2026-10-07 BEFORE any run

## Box 1, answered from the source (no run needed)

`_assert_classical_tier` (src/engines/swing.jl:660) REFUSES any `Load`, and the tier
holds a constant E′ at every bus. So the swing tier has NO voltage term at all and
no load object; the only frequency relief is `D` on a negative-P0 machine (M2a's
"a load is a machine with negative P0"). The oracle fixture is therefore: one
machine per bus, loads as negative-P0 machines with D > 0, lossless, no Load.
`dc_powerflow` reads the same object (bus_injections sums machine P0, incl. negative).

## Design decisions (go to m8-context.md as D7)

- `pickup_shares(net, lost::Symbol)` → (; Δω, responders, pickup, capped), pu on
  S_base. THROWS ArgumentError by name for the two refusals.
- `dc_generator_outages(net)` → `DCGeneratorOutages`; every MACHINE screened
  (negative-P0 ones too: losing one is a load trip, Δω > 0, no down-floor, as the
  swing tier). Refusals are per-outage outcomes, never throws (D3):
  `:shared`, `:no_response`, `:reserve_exhausted`.
- Responders = surviving machines (invR, D, headroom from machine_arrays) AND
  grid-forming inverters (gain 1/K_p from _inverter_arrays, D = 0, headroom Inf —
  the swing tier's gfm has droop and no P limit). Grid-following: no response.
  Inverter outages are NOT screened (the plan's "generators" are machines).
- Exact solve: x = −Δω; T(x) = Σ min(x·gᵢ, hᵢ) + x·Σd, piecewise linear,
  non-decreasing, breakpoints hᵢ/gᵢ. Walk them. No root-finder, no tolerance.
  T recomputed directly at each breakpoint (no accumulation).
  ΣD = 0 and total headroom == loss exactly: Δω not unique; return the SMALLEST |Δω|.
  P_lost < 0: Δω = −P_lost/Σ(g + d), no cap (no floor).
  P_lost = 0: Δω = 0, every pickup 0, `:shared`.
- Flows: same b vector and reduced factorisation as step 2; ONE solve per outage
  with the post-outage injections (B does not change: the bus stays).
- Losing the slack's machine: in DC the reference bus is a gauge and the shares
  rebalance every injection, so it is screened like any other. AC (step 5) is the
  user's call.

## The fixture (invented, declared)

Buses A–E, S_base 100. Branches AB .10, AC .20, BC .15, BD .25, CD .30, DE .10, BE .20
(step 2's mesh + BE, so no bridge and no cut VERTEX: the swing trip removes a bus).
Machine(id,bus,S_rated,H,D,Xd′,E′,P0,R,Pmax,Tg):
 G1 A 300 5.0 1.0 .25 1.05  150 .05 220 .5   → sys: g 60,   d 3.0, h .70
 G2 C 150 4.0 2.0 .25 1.04   60 .04 100 .4   → sys: g 37.5, d 3.0, h .40
 G3 E 120 3.5 1.5 .25 1.02   40 .06  45 .6   → sys: g 20,   d 1.8, h .05
 LB B 100 1.0 2.0 .25 1.00 −130              → d 2.0
 LD D 100 1.0 1.5 .25 1.00 −120              → d 1.5

## Predictions (closed form, before any code)

P1 trip G3 (0.40): uncapped. Δω = −0.4/107 = −3.738318e-3. G1 = (60+3)·3.738e-3 = 0.23551,
   G2 = 40.5·… = 0.15140, LB = 7.477e-3, LD = 5.607e-3.
P2 trip G2 (0.60): G3 capped (breakpoint 2.5e-3). Δω = −(2.5e-3 + (0.6 − 88.3·2.5e-3)/68.3)
   = −8.05271e-3. G3 pickup = 0.05 + 1.8·8.0527e-3 = 0.064495 pu → 1.45 MW above Pmax.
P3 trip G1 (1.50), damped: G2 and G3 both capped, Δω ≈ −0.1265 (6.3 Hz). Reported, NOT refused.
P4 same, every D = 0: total headroom 0.45 < 1.5 → `:reserve_exhausted`.
P5 every R = Inf and D = 0: every outage `:no_response` (except P_lost = 0).
P6 trip LB (−1.30): Δω = +1.3/126.8 = +0.010252, no cap.
P7 zero-damping trip G3: Δω = −0.4/97.5 exactly droop alone; damped − droop-alone
   Δω difference = 0.4/97.5 − 0.4/107 (predicted, asserted).
P8 DC flows = rebuild (machine removed, survivors' P0 += pickup) + dc_powerflow, to
   round-off (≤ 1e-13 pu). Slack moved → same flows (≤ 1e-13).
P9 gfm variant (G3 → Inverter :I3 at E, 120 MVA, 40 MW, K_p .05 → K_p_sys .041667, g 24):
   trip G2: Δω = −0.6/90.5.

## Cross-tier oracle band (stated BEFORE the run)

Swing run at reltol 1e-10, abstol 1e-12, settled. Pickup read from the NETWORK side
(Σ branch_power out of the bus, after − before); Δω on EVERY survivor's ω.
BAND: 1e-7 pu on each pickup and on Δω (1e-5 MW; ~1e-6 Hz·50). Settledness shown by
(a) the same numbers at T and 1.5T and (b) at reltol 1e-10 vs 1e-12, both ≪ band.
Capped ΔPm vs h: predicted within 1e-9 (the out-of-domain guard).
Zero-damping swing run: may NOT settle (only governors damp the swings) — measured,
not promised.
Tripped bus must not be a cut vertex (fixture checked above).

## Sabotages (each must go red)

S1 drop D from the weights. S2 invR from Machine.R on the machine's own base
(1/R, no ·S_rated/S_base). S3 cap applied to the damping term too
(min(x·g + x·d, h)). Plus S4 (own): gfm left out of the responders.
