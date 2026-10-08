# M8 step 5 — predictions, written before the run they describe

Context: `W:\Claude_projects\GridSim\docs\plans\m8-context.md` D8 (decisions + the two
plan corrections). Everything below is written BEFORE the first run of the code it
describes. Outcomes are appended under "Outcome" afterwards, never edited above.

## Fixture (invented, declared)

`_m8_acmesh`: step 4's mesh (A–E; AB .10, AC .20, BC .15, BD .25, CD .30, DE .10,
BE .20; X pu), buses 230 kV, S_base 100.
- G1 @A (slack) 300 MVA, H 5, D 1, Xd′ .25, P0 150, R .05, Pmax 220, Tg .5, V_set 1.05
- G2 @C 150 MVA, H 4, D 2, P0 60, R .04, Pmax 100, Tg .4, V_set 1.04
- G3 @E 120 MVA, H 3.5, D 1.5, P0 40, R .06, Pmax 45, Tg .6, V_set 1.02
- Loads as `Load`: B 130 + j30, D 120 + j25 MW/MVAr. `a_p = 1` (constant power) or
  the default (constant impedance).
- Options: `r` (R = r·X; 0 lossless, 0.1 lossy), loads, reference bus, gfm at E
  instead of G3, a Q_max on G1.

## Bands, stated first

- **B1, solution vs solution** (degeneration, reference move, DC-vs-AC on lossless
  constant power): 1e-10 pu on Vm, θ (differences), flows, pickups and Δω. Reason:
  both sides pass the 1e-10 residual gate with residuals expected ≲1e-13, and a
  five-bus mesh is well conditioned (Jacobian inverse O(10)); so the expected gap is
  ~1e-12 and 1e-10 is the gate, not a fit.
- **B2, residual plug-in** (no band of its own): the shared residual at
  `ac_powerflow(rebuilt)` ≤ n·max(res_rebuilt, eps), M6 step 3's form.
- **B3, losses identity**: |Σpickup − P_lost − ΔΣloss − ΔΣPload| ≤
  n·(max(res_base, eps) + max(res_post, eps)), one term per solve.
- **B4, cross-tier, constant power**: 1e-7 pu on pickups (network side) and every
  survivor's ω, at reltol 1e-10, 300 s (step 4's band and its tolerance sweep).

## Predictions

P1. **Degeneration.** Only G1 responds (G2, G3: R = Inf, D = 0; G1 Pmax 400): losing
    G3 equals `ac_powerflow` on the model without G3 with G1's P0 raised by 40 MW,
    within B1, on lossless/constant power AND lossy/default loads. Plug-in within B2.
P2. **Losses identity** holds within B3 for every machine lost (G1 = the reference
    included), on lossy constant power and lossy default loads. On the default loads
    the load term |ΔΣPload| > 1e-3 pu for every outage; on constant power it is ≤
    1e-14. On lossless constant power both terms are ≤ 1e-14 and Σpickup = P_lost.
P3. **DC-vs-AC, lossless + constant power**: Δω and every pickup equal
    `dc_generator_outages`' within B1 for every outage, including one where a
    governor caps (G3's headroom 5 MW: losing G2 caps G3 — check in the run). The
    capped machine sits at headroom + x·d.
P4. **Reference move** (internal reference argument, same base): reference at C
    instead of A gives the same Δω, pickups, Vm and flows within B1; every angle
    shifted by one constant (spread of θ_moved − θ ≤ 1e-10). Lossy default loads.
P5. **Losing the reference's machine (G1)**: B1/A has θ == 0.0, role :load,
    Vm ≠ V_set (solved, below 1.05). `ac_powerflow` on a model without G1 (G2/G3
    P0 raised to balance) still throws ArgumentError naming the sourceless slack.
    case9 with invented droop: G1's outage screens (outcome not a throw).
P6. **Reference Q limit enforced**: G1 Q_max chosen between its base Q and its
    post-G2-loss Q: shared solve lists A in `limited`, |V_A| < 1.05; `ac_powerflow`
    on the rebuilt (G2 removed, G1 P0 +60) holds |V_A| = 1.05 with Q above Q_max.
P7. **Inverter Q cap follows P**: gfm I3 at E rated so its base Q is at the cap
    (bus switched in the base); after losing G2 its P rises and at the solve
    P² + Q² = S² to 1e-12 relative, outcome :secure. A smaller rating whose share
    takes |P| past S gives :overload, kind :inverter, id I3.
P8. **Refusals**: no governors and no damping → :no_response every outage; no
    damping, small headroom, large loss → :reserve_exhausted; a reference bus with
    two sources refuses the screen by name. Governor back-off: predicted
    UNREACHABLE through a fixture (capping raises x, never lowers it), so its piece
    is tested directly.
P9. **Cross-tier, constant power, lossless**: the detailed tier's settled trip of
    G2 (and of G3, uncapped) matches the AC shares and Δω within B4.
P10. **Cross-tier, default loads**: the detailed tier (frozen field, T_E = Inf)
    settles to a SMALLER |Δω| than the AC solve, because without a voltage regulator
    its voltages sag further after the trip and constant-impedance loads draw less.
    Σpickup_detailed < Σpickup_AC. Size not predicted. With a regulator (finite K_A)
    the gap is smaller, same sign.

## Sabotages (in the step-5 code only), predicted reds

- SB1 the reference machine's lost power read as its schedule P0 (base losses kept
  as phantom generation): red in P2's G1 rows on LOSSY fixtures only; green on
  lossless constant power (base losses ~0). Green in P1 (G3 lost).
- SB2 cap applied to the damping term too: red in P3's capped outage (and cross-tier
  capped, P9).
- SB3 inverter reactive cap left at its base-P value: red in P7 (the :secure case
  becomes :overload, P²+Q² > S²).
- SB4 governor switching skipped: red in P3's capped outage, P9 capped.
- SB5 responders at the reference bus given zero weight: red in P1 (→ :no_response),
  P3, P4?, P9. GREEN in P2 (the identity reads the reported pickups, which stay
  consistent).
- SB6 the reference skipped in reactive-limit switching: red only in P6.
- SB7 the reference's real-power row uses the base output without the pickup (the
  row exists, the share does not): red in P1, P2 G1? (no — G1 lost has no
  responder at A; G1 rows green), P3, P4.

## Outcome

(appended after the runs)

## Amendments, written BEFORE the sabotage runs (after the first green test run)

- The identity test read `P_lost` from `_ac_shared_setup`, the very code SB1 breaks,
  so SB1 would have been green there by construction. Changed to read it off the
  base (`b.Pgen[1]` for the slack's machine) and the model (`P0/S_base`). SB1 is
  now predicted red in: the "base" testset (P_lost == base.Pgen[1]) and the identity
  G1 rows on the two LOSSY fixtures; green on lossless constant power.
- SB5 is implemented in `_ac_shared_round` only (the solve), while the reported
  pickups still come from `_shared_pickups`: the report then disagrees with the solve,
  so the identity goes RED for the G2/G3 rows (the reference's responder alive),
  not green as written above. Also red: degeneration (→ :reserve_exhausted, the
  round's slope is zero), DC-vs-AC, reference move, detailed constant power.
- SB7 (reference row without the pickup): red in the identity G2/G3 rows, the
  degeneration, DC-vs-AC, reference move, the detailed tier; green in G1 rows.
- SB4 also red in the refusals test: with no damping, G1's loss never caps, so it
  solves instead of `:reserve_exhausted`.
- SB2 predicted red: DC-vs-AC (G1, G2 rows), the cap test, the detailed G2
  constant-power and load-relief rows. Green: the identity (consistent).

## Outcome (sabotages, mutate5.py, mut5-*.log) — every one red

- SB1: red in the base testset and the identity (G1 lossy rows) only. As amended.
- SB2: red as predicted (DC-vs-AC, cap test, detailed) AND more widely: losing G1 caps
  G2 and G3, and with their damping capped too nothing moves with x, so G1's outage
  becomes :reserve_exhausted and every test that reads its solution errors (base
  "all secure", identity, reference move, reference machine lost, gfl). The identity
  "green" prediction was wrong for that reason, not because it saw the cap.
- SB3: red only in the inverter test. As predicted.
- SB4: red in DC-vs-AC, cap test, refusals, detailed. As amended.
- SB5 and SB7: IDENTICAL 25 failing lines. Both remove the reference's share from
  the solve while the report keeps it, so they are one sabotage written two ways.
  Red beyond prediction: the cap test, the inverter test and the refusals.
- SB6: red only in the reference-limit test. As predicted.

## Review follow-ups (after the step-5 commit), predictions BEFORE the test/sabotage runs

User's decision (2026-10-07): a base whose slack is already past its own reactive
limits REFUSES the screen. Spike step5_spike5.jl measured the fixtures (orientation).

- F1: lossy constant power, G1 Q_max 0.30 pu (base Q 0.359): ArgumentError naming the
  slack and "reactive limits"; Q_max 0.478 screens. SB8 (refusal removed): red only in
  F1's test.
- F2: grid-forming inverter I1 (175 MVA, K_p 0.05, V_set 1.05) as the slack's one
  source, G2/G3 machines, lossy constant power. Losing G3: :secure, A held at its
  inverter cap, |S| = rating to 1e-12, identity within B3 with P_lost = G3's P0.
  Losing G2: :overload kind :inverter id :I1. SB9 (the slack inverter's base output
  left at its schedule 1.5 instead of the solved 1.5302): the cap is computed from too
  low a power, so G3's row is no longer at the rating: red in F2's G3 row only.
- F3: a negative-P0 machine LM (−30 MW at B, D 2) on the lossless constant-power mesh:
  its loss gives Δω > 0, nothing capped, shares = DC screen within B1, identity holds.
- F4: the detailed tier's capped/default runs read at 300 s AND 450 s, both inside B4;
  measured worst 8.1e-10 (AVR, G2 lost, 300 s).

## Outcome (follow-ups)

- M8 runner: 953 green (+47).
- SB8: red only in F1's refusal test (1 line). As predicted.
- SB9: red only in F2's G3 row (secure-and-limited; |S| at the rating). As predicted.
- F4 measured: every detailed read at 300 s and 450 s ≤ 8.1e-10 (band 1e-7).
