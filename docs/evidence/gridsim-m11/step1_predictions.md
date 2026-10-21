# M11 step 1 — predictions, written before any comparison ran (D8)

Written 2026-10-21, after the probes below and before `dc_opf` existed. Nothing here was
adjusted after a gap was read; anything a later run contradicts is recorded as a finding
in `docs/plans/m11-context.md` ("What step 1 measured"), not edited in here.

## What was run first (not comparisons)

`W:\temp\claude\gridsim-m11-step1\probe.jl` (scratch), on case9 shaped as `_ed_case9`:

1. **Our** `dc_powerflow` at `economic_dispatch`'s schedule (MW, branch orientation):
   L14 +86.5645, L45 +33.7377, L56 −56.2623, L36 +94.0579, L67 +37.7957, L78 −62.2043,
   L82 −134.3776, L89 +72.1732, L94 −52.8268. (Step 0's 60 % table came from PowerModels'
   `x/(r²+x²)` with `R` in; these are ours, `1/X`.)
2. HiGHS solves the θ formulation (angles as variables, zero cost on them) with
   `qp_regularization_value = 0` as well as at its default `1e-7`: OPTIMAL /
   FEASIBLE_POINT / FEASIBLE_POINT on case9 published, L82 at 100 MVA, L45 at 30 MVA.
3. On a hand-provable infeasible set of limits (below, "Infeasible") HiGHS reports
   termination INFEASIBLE, primal INFEASIBLE_POINT, dual **INFEASIBILITY_CERTIFICATE**
   at both regularizations — a certificate, so "infeasible" may be reported as a proof.

## Notation and the margin (D9)

`τ` = the solver tolerance handed to HiGHS (primal, dual, optimality), pu. `ε` = its
QP regularization. `n` = buses (9 on case9), `m` = machines. `δ` = the rating margin:
the optimiser holds each branch to `rating·(1 − δ)`. **Default `δ = 1e-6`** — on case9's
smallest rating (150 MVA) that is 1.5e-4 MW = 1.5e-6 pu, three orders above `τ = 1e-9`,
so a flow the solver puts "on" the margined limit (to within `(n+1)τ`) is strictly inside
the true rating. Every identity below uses the **margined** rating; a gap of `r·δ` against
the unmargined one is the margin, not a bug.

## The band (position, pu) — derived, not fitted

M6's band for a network-free dispatch (`_ed_band_pu`, test/m6_economic_dispatch.jl) is
`2·(w(2τ + 2εp̄) + τ)` with `w = 1/(2·min a2)`, `p̄ = max pmax`. The θ formulation changes
two things:

- **Balance per bus.** `n` balance rows each hold to `τ`, so the total balance error is
  up to `nτ` where M6 had `τ`: the `+τ` term becomes `+nτ`.
- **The regularization touches the angles.** If HiGHS adds `ε` to every Hessian
  diagonal (assumed: the comparisons at `ε = 0` do not need the assumption), the angle
  stationarity reads `L_red·π = εθ`: bus prices `π` differ from the reference bus's by
  at most `ε·‖Z‖∞·‖θ‖∞`, `Z = L_red⁻¹` the reactance matrix seen from the slack. Crude
  bounds: `‖Z‖∞ ≤ (n−1)·ΣX`, `‖θ‖∞ ≤ ΣX·D` (D = total load, pu). A price difference `Δπ`
  moves a free unit by at most `w·2Δπ`. Term: `2w·ε·(n−1)·(ΣX)²·D`. On case9 (ΣX = 0.8595,
  D = 3.15): ≈ 2.2e-9 pu at `ε = 1e-7` — the same order as the `τ` terms, so it is kept.

**`_opf_band_pu = 2·( w(2τ + 2εp̄) + nτ + 2w·ε·(n−1)·(ΣX)²·D )`.** The factor 2 is M6's
stated headroom for HiGHS measuring on its own scaled problem, and is the only underived
number. A comparison of the OPF against `economic_dispatch` allows `_opf_band_pu +
_ed_band_pu` (two answers, each off the exact optimum on its own). Cost bands through
M6's `_ed_band_cost`. At `τ = 1e-9` these are ~1e-8 pu ≈ 1e-6 MW and ~1e-5 $/h.

## 22.1 — Degeneration (case9 as published, `case9(; costed = true)`)

- No branch at its limit (the largest flow is L82's 134.38 MW on 250).
- Each machine's output equals `economic_dispatch`'s within the band, at `ε = 0` and at
  `ε = 1e-7`, `τ = 1e-9`; the cost within its band (5216.03 $/h). A gate, not an oracle:
  both answers are HiGHS on one cost.

## Identity — the dispatch handed to `dc_powerflow` gives the OPF's flows

`dc_powerflow` solves `Bθ = P` exactly; the OPF's θ satisfies it to a residual `|r_v| ≤ τ`
per bus, and the projected dispatch differs from the solver's by `≤ τ` per machine. Every
DC PTDF entry is in [−1, 1], so `|Δflow_e| ≤ (n + m)τ`; asserted with factor 2:
**`2(n + m)τ` pu** per branch, on 22.1, 22.2, 22.3 and 22.4's fixtures.

## 22.2 — L82 rated `r = 100` MVA ≡ G2's maximum at `r(1−δ)`

L82 joins B2 (G2 alone) to B8, oriented 8 → 2, so G2's power flows **negative** on it:
its **lower** limit binds. Prediction: the OPF puts L82 at `−r(1−δ)/S_base` (within
`2(n+1)τ`), and every output equals `economic_dispatch` on the same model with G2's
`Pmax = 100(1−δ)` MW (G2's `P0` moved down to it, G1 taking the balance — D10) within
`_opf_band_pu + _ed_band_pu`. G2's unconstrained output is 134.38 MW, so the cap binds.

## 22.3 — L89 rated 50 MVA (INVENTED, labelled)

Unconstrained flow +72.17 MW (8 → 9), so its **upper** limit binds. Predictions:

- L89 at `+50(1−δ)` MW, within `2(n+1)τ`; no other branch at its limit.
- Directions, from the ring's geometry (slack at B1, behind G1): G2 injects at B8, upstream
  of L89; G3 at B6, with part of its path to B4 running 6 → 7 → 8 → 9; G1 at B1/B4 is
  downstream. So **G1 rises, G2 and G3 fall**, each by more than 1 MW; the cost rises by
  more than 1 $/h over 5216.03.
- **Quantitatively, against a second formulation**: the PTDF closed form below, on
  case9, with the PTDFs measured by `dc_powerflow` on unit injections (a different
  formulation than the θ one, the same network code M6 checked). Band as 22.4's.

## 22.4 — The three-bus closed form (hand PTDFs)

Triangle A, B, C; `X_AB = 0.1`, `X_AC = 0.1`, `X_BC = 0.2` pu on 100 MVA (ΣX = 0.4). The
cheap unit (case9's G2 row, 0.085 / 1.2) at A, the dear one (G1's row, 0.11 / 5.0) at B,
200 MW of load at C. PTDFs with C as the reference, by hand (path reactances): an injection at A withdrawn at C splits over A–C (reactance 0.1) and A–B–C
(0.3) as 0.75 / 0.25, so `PTDF_AC,A = 0.75`, `PTDF_AB,A = 0.25`, `PTDF_BC,A = 0.25`. An
injection at B splits over B–C (0.2) and B–A–C (0.2) as 0.5 / 0.5: `PTDF_BC,B = 0.5`,
`PTDF_AC,B = 0.5`, `PTDF_AB,B = −0.5`.

- **Control, A–C rated 250**: nothing binds; the closed form is M6's equal incremental
  cost: λ = 22.036, p_A = 122.56, p_B = 77.44 MW; A→C carries 130.64 MW.
- **A–C rated 120 (binding, upper limit, positive orientation)**: `0.75p_A + 0.5p_B =
  120(1−δ)`, `p_A + p_B = 200` ⇒ p_A = 80, p_B = 120 MW (at δ = 0); `2a₂ₖpₖ + a₁ₖ = λ −
  μ·PTDF_AC,k` ⇒ 14.8 = λ − 0.75μ, 31.4 = λ − 0.5μ ⇒ **μ = 66.4 > 0** (the sign an
  upper limit needs), λ = 64.6 $/MWh. A→B −40 MW, B→C 80 MW (120 + 80 = the 200 MW at C): neither near 250.
  The test solves the `n + 2 = 4` system by backslash at the margined rating, in MW
  from the literal rows, and asserts μ > 0 and both units strictly inside their limits.
- **Band**: with two units, balance and the binding flow fix the dispatch alone:
  `p_A = (flow − 0.5D)/0.25`. Each holds to `(n+1)τ` ⇒ `|δp| ≤ 2·4·1.5·(n+1)τ` pu
  (factor 2 headroom) = 3.6e-8 pu at τ = 1e-9 (n = 3). 22.3's closed form uses the
  same shape of bound with case9's numbers: `2·(n+1)τ·‖K⁻¹‖∞` of its own 5 × 5 system,
  computed in the test from the literal matrix (no solver). Both closed-form comparisons
  run at `ε = 0`, where the derivation has no regularization term; at the default `ε`
  they are run again with `_opf_band_pu`'s `ε` terms added.

## Infeasible — a cut-set provable by hand

B5 (90 MW of load) is fed only by L45 and L56. Rated 40 MVA each, at most
`80(1−δ) < 90` MW reaches it: no dispatch exists. Prediction: outcome `:infeasible`,
the statuses as probed, no error thrown. **Positive control**: both at 46 MVA
(`92(1−δ) > 90`) — `:optimal`.

## Refusals

By name, through the shared checks: no machines, an uncosted machine, a machine with no
minimum, a load above every maximum (unreachable, kept — M6), below every minimum, an
inverter. **A model in pieces and a zero rating are unreachable**: `NetworkModel`
refuses a disconnected grid and `Branch` refuses `rating ≤ 0`, so the OPF relies on
those guards (tested as the constructors' refusals) rather than adding a bypass to make
its own reachable. An **infinite** rating is reachable (`rating > 0` admits `Inf`) and
means "no limit": no constraint is written for it.

## Sabotages — which fixture sees each (written before running them)

| Sabotage | 22.1 | identity | 22.2 (lower) | 22.3 (upper) | 22.4 (upper) |
|---|---|---|---|---|---|
| S1a upper limit only (`flow ≤ r`) | green | green | **red** | green | green |
| S1b lower limit only (`flow ≥ −r`) | green | green | green | **red** | **red** |
| S2 rating not divided by `S_base` | green | green | **red** | **red** | **red** |
| S3 `X` where `1/X` belongs (both in flow and balance) | green | **red** | green¹ | **red** | **red** |
| S4 balance on the total, not per bus | green | **red** | **red** | **red** | **red** |

¹ L82 is a bridge: its flow is G2's output whatever its strength, so its cap is the same.
22.1 is green under every sabotage — the degeneration is a gate, and why it is not the
check.
