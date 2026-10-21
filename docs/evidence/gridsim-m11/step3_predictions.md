# M11 step 3 — predictions, written before any comparison ran (D8)

Written 2026-10-21, after the one-side runs below and before the AC OPF's answer was
handed to `ac_powerflow`, and before its two starts were compared. Nothing here is
adjusted after a gap was read; anything a later run contradicts is recorded in
`docs/plans/m11-context.md` ("What step 3 measured"), not edited in here.

## What was run first (one side at a time, never a comparison)

Scratch, under `W:\temp\claude\gridsim-m11-step3` (copied into `step3/` with this file).

1. **The root environment, re-measured** (`resolve.jl` on a scratch copy of the root
   `Project.toml` + `Manifest.toml`): Ipopt 1.16.0 (Ipopt_jll 300.1400.1902) alone 190 →
   201 packages, then JuMP 1.32.1 + HiGHS 1.26.1 beside it (the test target's set) → 215.
   **Nothing moved and nothing was removed** (NetworkDynamics 1.3.0, OrdinaryDiffEq 7.8.1,
   NonlinearSolve 4.32.0, NonlinearSolveBase 2.55.0, SciMLBase 3.58.0, Graphs 1.15.0,
   Observables 0.5.5, CommonSolve 0.2.14 held). Then the real change: `Pkg.add("Ipopt";
   target = :weakdeps)` (the file had no comments to lose), the extension, `[compat]`
   Ipopt = 1.16.0, `[extras]` and the test target by hand. In one session `using GridSim,
   JuMP, HiGHS, Ipopt` loads **both** `GridSimDispatchExt` and `GridSimOPFExt`.
2. **The power flow alone** (`probe.jl`, part A): M6's network-free dispatch (HiGHS,
   `regularization = 0`) handed to `ac_powerflow` at published load —

   | | constant power | default (constant impedance) |
   |---|---|---|
   | dispatch, MW | 86.564498 / 134.377586 / 94.057917 | same |
   | flowed cost, \$/h | 5325.285712 | 4897.545590 |
   | slack G1's solved P, MW (in [10, 250]) | 91.017862 | 72.401110 |
   | Q of G1 / G2 / G3, MVAr (in ±300) | 79.35 / 48.96 / 37.86 | 74.32 / 45.82 / 35.35 |
   | min \|V\| | 0.953702 (B9) | 0.959227 (B9) |
   | worst loading | L82 143.02 / 250 MVA | L82 141.97 / 250 MVA |
   | losses / load-draw shift, MW | 4.453 / 0 | 4.298 / −18.462 |
   | ‖J⁻¹‖∞ of the flow's equations at its solution | 1.2961 | 1.4110 |

   At 1.5× load, the **exact** DC OPF dispatch (135.905416 / 198.230538 / 138.364047 MW,
   nothing binding — it is M6's) through `ac_powerflow`: **constant power refused,
   `:voltage`, B9 at 0.899554438** (the unchecked solve: ‖J⁻¹‖∞ = 1.3833); **default loads
   pass** (`:secure`, min |V| 0.918901; ‖J⁻¹‖∞ = 1.5751). So the control's margin is
   4.5e-4 pu on the exact dispatch — not thin; 1.5× is kept (the plan's "between 1.5× and
   1.75× if it stays thin" is not needed). And the voltage fixture is a
   **constant-power** fixture only: on default loads the DC dispatch already passes.
3. **The optimiser alone** (`probe.jl`, part B; `probe_rating.jl`), flat start:

   | fixture | outcome | cost \$/h | P MW | binds |
   |---|---|---|---|---|
   | published, cp | locally optimal | 5325.266075 | 90.721 / 134.411 / 94.332 | nothing |
   | published, default | locally optimal | 4883.325762 | 81.858 / 129.066 / 89.952 | nothing |
   | 1.5×, cp | locally optimal | 10241.634349 | 149.111 / 195.111 / 138.703 | B9 at 0.9000010 (the margined floor) |
   | 1.5×, default | locally optimal | 8279.215842 | — | nothing |
   | 1.75×, cp | **LOCALLY_INFEASIBLE** | — | — | — |
   | 1.75×, cp, floor 0.8 | locally optimal | 13469.230919 | — | L82 (min \|V\| 0.8673) |
   | 1.75×, cp, Q limits removed | **LOCALLY_INFEASIBLE** | — | — | — |
   | 1.75×, default | locally optimal | 10146.294950 | — | nothing |
   | L94 at an INVENTED 60 MVA, cp | locally optimal | 5582.661610 | 53.869 / 167.704 / 99.697 | L94, **receiving end** at the limit, sending end 57.23 MVA |
   | the same, default | locally optimal | 4910.930983 | 69.459 / 140.346 / 90.994 | L94, receiving end at the limit, sending end 57.56 MVA |

   (`margin_S = 1e-6` in that run, before the default moved to 1e-5 — below.) The
   published and 1.75×-floor-0.8 costs equal step 0's PowerModels figures (5325.2661,
   13469.23) — read, not asserted. The rating fixture's line was chosen from the
   unconstrained optimum's end-to-end table: L56, L78, L94 (and G2's own L82) carry the
   larger |S| at the **receiving** end; L94 the most (68.59 → 71.73 MVA). L94 at 50 MVA
   is LOCALLY_INFEASIBLE; L56 at 45–50 MVA makes Ipopt stop at ALMOST_LOCALLY_SOLVED
   (a throw), so it is not used.
   - Ipopt at `tol = 1e-11`: SLOW_PROGRESS (published default) or ALMOST_LOCALLY_SOLVED
     (1.5× cp, 1.75× default) — the tight run is **1e-10**.
   - **Its own convergence** `|run(1e-8) − run(1e-10)|`: 4e-13 – 6.2e-12 pu on P and
     flows, ≤ 9.7e-14 on |V|, ≤ 9e-10 \$/h on cost. The recomputed balance residual of
     every answer is 4e-15 – 1e-14 pu.
   - The DC-OPF start reaches LOCALLY_SOLVED on published cp, 1.5× cp and both L94
     fixtures (statuses only, no comparison).

## The margins (D9), sized here

**24.1's band on the bus state** (|V| and θ, every bus). The OPF's point satisfies the
power flow's equations to its constraint tolerance `τ` per equation (Ipopt's
`constr_viol_tol`, unscaled), plus `τ` from the projection of `P` into its limits; the
handed-back flow satisfies them to `ρ_pf = 1e-10` (its residual gate). The two solutions
of one set of equations then differ by at most

    band_x = 2·κ·(2τ + ρ_pf)

to first order, `κ = ‖J⁻¹‖∞` of the flow's equations, the factor 2 for the linearization.
**κ is computed in the test at the handed-back flow's own solution** (one side: the flow),
by central differences on `_ac_residual!` — measured 1.30 – 1.58 at the points above. At
`τ = 1e-9`: `band_x ≈ 2·1.58·2.1e-9 = 6.6e-9` pu.

**24.1's band on the branch flows** (P and Q at both ends, and |S|). Each end's
`S_f = conj(y)(V_f² − V_f V_t e^{jθ_ft})` moves by at most `|y|·(4V̄ + 2V̄²)·band_x` with
`V̄ = 1.1`, i.e. `6.82·|y|max·band_x`; case9's largest `|y|` is L14's `1/0.0576 = 17.36`,
so `band_S = 118.4·band_x ≈ 7.8e-7` pu.

**24.1's band on the slack's real output**: B1 has one branch (L14) and no load, so
`band_S + 2τ + ρ_pf`.

**The margins against them.** `margin_V = 1e-6` pu is ~150× `band_x`, so a bus the
optimiser holds on the margined floor is strictly above 0.9 after the re-solve.
`margin_S` was 1e-6 in step 1's sense (relative); on L94 at 60 MVA that is 6e-7 pu —
**below** `band_S`. **So `ac_opf`'s default is `margin_S = 1e-5`** (6e-6 pu on L94, 7–8×
`band_S`). The test asserts both inequalities from the fixture's own κ.

## Bands for the other claims

- **24.2 (the bound)**: a plain inequality, `cost_OPF ≤ cost_flowed(M6)`, **per load
  model**, after asserting that M6's flowed point is feasible for the OPF's own MARGINED
  problem: every machine's Q in its limits (the slack's included), the slack's P in
  `[Pmin, Pmax]`, every bus inside `[0.9 + margin_V, 1.1 − margin_V]`, every branch's
  larger-end |S| inside `rating·(1 − margin_S)`. Predicted margins: 0.0196 \$/h
  (constant power), 14.2 \$/h (default). No band: an OPF that bends its constraints by
  `τ` gains at most ~(marginal cost ≈ 2.5e3 \$/h per pu)·τ ≈ 2.5e-6 \$/h, and in the
  direction that keeps the inequality.
- **24.3**: the control refused with `:voltage` at B9 (0.899554 predicted); the OPF's
  `at_band == [:B9]` with B9 within `near` of `0.9 + margin_V`; its schedule passes
  `ac_powerflow` with B9 in `(0.9, 0.9 + margin_V + band_x]`.
- **24.4**: 1.75× cp is `:locally_infeasible`, its status naming LOCALLY_INFEASIBLE; the
  floor at 0.8 solves; the Q limits removed does not. The cause is the floor.
- **24.5 (two starts)**: flat and DC-OPF starts on published cp, published default,
  1.5× cp and both L94 fixtures. Band, step 2's form: each start's own convergence
  `c = |run(τ) − run(1e-10)|`, measured in the test, `band = 2(c_flat + c_dc) + ρ`,
  `ρ = 1e-11` pu (`1e-11·|cost|` on cost), on P, |V|, θ, flows and cost. Predicted gaps:
  at the 1e-12 level, as each run's own convergence.
- **D11 identity**: `Σ P − demand = losses + load_shift` to `n·residual + 2τ·n_m`; on
  default loads `load_shift < 0` on every fixture (−18.08 MW published).

## Sabotages — which fixture sees each (predicted before any is run)

Each applied to `ext/GridSimOPFExt.jl` only, by an exact string replacement, the M11 AC
testset run, the file restored. Every mutant gets Ipopt's `max_cpu_time = 120` (step 1's
lesson).

| sabotage | 24.1 published cp / default | 24.1 1.5× cp | L94 fixture (cp / default) | 24.2 | 24.3 | 24.5 |
|---|---|---|---|---|---|---|
| SA: a branch's `R` dropped from the optimiser's copy (`g = 0`) | red / red (losses ~4.5 MW onto the slack) | red | red | green (blind: a lossless copy is cheaper) | red (B9 re-solves below the floor or the slack moves) | green (blind: same wrong problem from both starts) |
| SB: the rating at the sending end only | green (nothing binds) | green | **red** — the receiving end runs ~2.8 MVA over, refused by the read-back | green | green | green |
| SC: a held voltage left free (machine buses' \|V\| a variable in the band) | red (the OPF raises the generator voltages; the read-back and the flow hold `V_set`) | red | red | green or red (it can only get cheaper) | red | green |
| SD: the load model read as constant power where it is not (`a_p = 1` in the optimiser's draw) | green / **red** | green (cp fixture: blind by construction) | green / **red** | green | green | green |

SD on a constant-power fixture is invisible by construction — that is why 24.1 runs on
both load models.
