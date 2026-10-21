# M11 — The network optimal power flow · Tasks

Living checklist. Tick in place, with what each step found. Plan: `m11-plan.md`;
decisions and measurements: `m11-context.md`.

Entered 2026-10-21 at `931c07e` with **25167 core / 1439 reference / 4212 UI** (the
M10 cleanup's counts: the full core suite ran once with one check failing on its
expected text, corrected, and that group re-run alone, 187/187).

## Step 0 — Name the hurdles before the plan

- [x] **Re-measured whether an outside checker resolves** (D1.1): PowerModels 0.21.7
      + Ipopt resolve alone, beside core, beside core + `reference/`, and beside
      core's test target, moving nothing of ours. M6's "unresolvable at any
      version" annotated as re-measured in SPEC, the ledger, the plans README and
      M6's trio. Evidence: `docs/evidence/gridsim-m11/step0/`.
- [x] **Usable, and where the network binds** (D1.2): case9 AC 5296.69 / DC 5216.03
      as published; shaped as ours, AC held-V 5325.27. **No line binds on case9 as
      published** — the DC network optimum is M6's network-free one.
- [x] **The DC conventions differ** (D1.3): `x/(r²+x²)` against `1/X`, 0.014 MW per
      ring line at one dispatch.
- [x] **What bounds the held-voltage AC case** (D1.4): the load-bus voltage floor.
- [x] **The user's five choices** (D2): DC then AC; voltages held; PowerModels in
      `reference/`; case9 only; the DC oracle given our formula.
- [x] **Hurdles 22–24 named** (D0) in `m11-context.md` and `docs/plans/README.md`.
- [x] **Review of the plan** (2026-10-21) added D9 (an optimum on a limit vs strict
      checks: a stated margin), D10 (the costed case9 in the script, `costed`
      keyword), D11 (voltage-dependent loads: the load-draw shift reported apart),
      and D7's reader path (`parse_matpower`; its ±60° angle bound).

## Step 1 — The DC OPF (Hurdle 22)

- [ ] Predictions file: bands for the degeneration, the cap identity and the closed
      form; which fixture sees which sabotage.
- [ ] `case9(; costed = true)` in `scripts/outage_screen.jl` (D10) and its row-for-row
      check against `_ed_case9`.
- [ ] `dc_opf` in core (formulation, refusals, D9's margin) + its HiGHS method in
      `GridSimDispatchExt`; the result type.
- [ ] Gate: captures and counts unchanged.
- [ ] 22.1 degeneration on case9 as published.
- [ ] 22.2 L82 ≡ G2's cap.
- [ ] 22.3 a ring line rated low (invented, labelled): it binds, every output moves.
- [ ] 22.4 the three-bus closed form with one binding line, and its non-binding
      control.
- [ ] The `dc_powerflow` identity; the refusals; an infeasible set of limits as an
      outcome.
- [ ] Sabotages executed, each red where predicted.

## Step 2 — PowerModels' DC OPF in `reference/` (Hurdle 23)

- [ ] Re-measure resolution in `reference/` itself; add PowerModels + Ipopt;
      restore `reference/Project.toml`'s comments.
- [ ] case9's rows typed from MATPOWER's file (URL + commit), the oracle's data
      built from them (D7).
- [ ] Band stated first (23.3); comparisons on case9 and the binding fixtures with
      `R = 0` in the oracle's DC copy.
- [ ] The formula difference with `R` left in: measured, printed, not a band (23.1).
- [ ] Sabotages executed.

## Step 3 — The AC OPF, voltages held (Hurdle 24)

- [ ] Re-measure the root environment with Ipopt as a weak dependency; add it;
      restore `Project.toml`'s comments; extension in place.
- [ ] Predictions file: bands for the handed-back flow, the two starts.
- [ ] `ac_opf`: held voltages (D4), voltage band, larger-end ratings, both load
      models.
- [ ] 24.1 handed back to `ac_powerflow`, both load models.
- [ ] 24.2 the bound against M6's dispatch-then-flow, recomputed, feasibility first.
- [ ] 24.3 the voltage fixture and its positive control — the control's margin
      re-measured on the exact dispatch first.
- [ ] 24.4 1.75× reported as Ipopt's word; the floor-lowered variant pins the cause.
- [ ] 24.5 two starts agree.
- [ ] Sabotages executed.

## Step 4 — PowerModels' AC OPF in `reference/`

- [ ] Band stated first; case9 published and 1.5×, constant-power loads; a ring-line
      fixture if one binds in AC (measured).
- [ ] The shared solver named in the test's header.
- [ ] Sabotage executed.

## Step 5 — The report

- [ ] `scripts/network_dispatch.jl`; claims asserted at printed precision; prose
      after the table.
- [ ] The optimum handed to the detailed tier's flat run.
- [ ] Window: the user's call.

## Step 6 — Close

- [ ] Fresh `-HEAD` captures; manifests re-resolved; counts; captures byte-compared.
- [ ] Ledger, README row and hurdles, SPEC, memory.
