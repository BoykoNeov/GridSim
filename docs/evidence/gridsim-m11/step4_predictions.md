# M11 step 4 — predictions, written before any comparison ran (D8)

Written 2026-10-21, after the probes below and before our `ac_opf` and PowerModels' AC
OPF were compared on anything. Nothing here is adjusted after a gap was read; anything a
later run contradicts is recorded in `docs/plans/m11-context.md` ("What step 4
measured"), not edited in here.

**One thing seen early, said plainly.** Each probe printed its own answer rounded to
1e-4 MW / 1e-6 pu, and the two printouts agree at that rounding (cost 5325.266075 on
both; B9 at 0.9 on both at 1.5×; L94's receiving end at 60.0000 MVA on theirs). That is
five orders above the band below. No difference between the two sides has been computed
at any precision.

## What was run first (one side at a time, never a comparison)

Scratch, under `W:\temp\claude\gridsim-m11-step4` (copied into `step4/` with this file):

1. **`reference/` re-resolved** (`resolve.jl`, on a scratch copy of its `Project.toml` +
   `Manifest.toml` first, then for real). The manifest recorded GridSim's step-2 extension
   list (`GridSimDispatchExt` only); `Pkg.resolve()` added `GridSimOPFExt = ["Ipopt",
   "JuMP"]` and `Ipopt` to GridSim's weakdeps. **321 → 321 packages, nothing moved, nothing
   added or removed**; `reference/Project.toml` untouched. `GridSimOPFExt` and
   `GridSimDispatchExt` both load there.
2. **Their side alone** (`theirs_probe.jl`): `solve_opf(data, ACPPowerModel, Ipopt)` on
   step 2's typed `C9_MATPOWER` text with three new `matpower_edit` edits — `b0` (line
   charging zeroed: our case9 has none), `held` (each generator bus's Vmin = Vmax = its
   gen row's `Vg`, read from THEIR text; PowerModels' OPF never reads `Vg`), `load` (bus
   `Pd` and `Qd` scaled). `R` kept. Read back through their reader: every `b_fr`, `b_to`
   0; buses 1–3 at vmin = vmax = 1.04 / 1.025 / 1.025, 4–9 at 0.9 / 1.1; 1.5× loads
   1.35 / 1.5 / 1.875 pu with Q 0.45 / 0.525 / 0.75; the edits at their defaults parse `==`
   to the unedited text.
   - LOCALLY_SOLVED at τ = 1e-8 and 1e-10 on published, 1.5× and L94 at 60 MVA; at 1e-11
     **ALMOST_LOCALLY_SOLVED on 1.5×**, at 1e-12 on all three. So their tight run is 1e-10.
   - 1.75×: LOCALLY_INFEASIBLE / INFEASIBLE_POINT at every τ.
   - Their own convergence `|run(1e-8) − run(1e-10)|`: 6.2e-13 (published), 6.4e-12
     (1.5×), 7.6e-13 (L94) pu on outputs and flows; ≤ 1.6e-12 on `qg`, ≤ 1e-13 on `vm`;
     ≤ 9.0e-10 $/h on cost.
   - Their branch quantities: `pf, qf` at the from end, `pt, qt` at the to end, each the
     power entering the branch from that end (on 1→4, `pf` = +90.72, `pt` = −90.72 MW)
     — the same convention as our `flow`/`qflow` and `flow_rev`/`qflow_rev` (our
     `_ac_opf_result` sums `flow_rev` into what bus `t` sends out).
   - L94 at 60 MVA: |S| = 60.0000 MVA at the **to end (bus 4)**, 57.23 at the from end —
     it binds on their side, at the end it binds on ours (step 3).
   - Largest branch angle difference 0.176 rad (1.5×), against their ±60° (1.0472).
   - Largest reactive output 132.4 of 300 MVAr (G1 at 1.5×): no reactive limit binds.
   - Their reader warns "the voltage setpoint on generator k does not match the value at
     bus k" (the bus rows' `Vm` column is 1, `Vg` is 1.04 / 1.025): a starting value only,
     the held bounds decide.
3. **Our side alone** (`ours_probe.jl`, in `reference/`'s environment):
   `ac_opf(net; margin_V = 0, margin_S = 0)` on `case9(; costed = true)` (constant power)
   at the same three load levels and L94 at 60 MVA.
   - LOCALLY_SOLVED at 1e-9 and 1e-10 on all three; at 1e-11 **SLOW_PROGRESS on 1.5× and
     ALMOST_LOCALLY_SOLVED on L94**, which `ac_opf` throws (as step 3 found). Tight run
     1e-10.
   - 1.75×: `:locally_infeasible` at every τ.
   - Our own convergence `|run(1e-9) − run(1e-10)|`: 3.6e-14 (published), 5.6e-13 (1.5×),
     7.8e-14 (L94) pu on outputs and flows; ≤ 8.2e-11 $/h on cost. **Not zero** — this is
     interior point, not step 2's active-set QP — so `O` is a real term in the band.
   - `at_band == [:B9]` at 1.5×, `at_limit == [:L94]` on the rating fixture, nothing
     binding on published; `q_at_limit` empty everywhere.

## How D9's margin is read here

As at step 2, and for the same reason: an oracle comparison hands the answer to no strict
tool, and a margin would swamp the band. B9's floor moved by `margin_V = 1e-6` moves the
outputs by ~1e-5 pu at 1.5×; L94's rating moved by `margin_S = 1e-5` moves 6e-6 pu of
flow — six orders above the convergence terms below. **Our side runs at `margin_V = 0`,
`margin_S = 0` against PowerModels' unmargined band and rating: the same problem on both
sides, compared strictly.** The margins stay checked in-house (step 3's 24.1, 24.3 and the
rating testset run at the defaults). The read-back's refusals still run, against the real
limits (a margined limit with zero margin is the limit).

## The comparison

Ours: `ac_opf(net; tol = 1e-9, margin_V = 0, margin_S = 0)` on `case9(; costed = true)`,
constant-power loads, and its variants (`mw` scaled; L94's rating replaced). Theirs:
`oracle_ac_opf(text; tol = 1e-8)` on `matpower_edit(C9_MATPOWER; b0 = true, held = true,
load = s, rate = …)`. **`R` is kept on both sides** — the AC physics is the same formula
on both, unlike step 2's DC strength.

Channels, mapped by bus number: each machine's output `P` ↔ `pg` and reactive output
(`Qgen` at its bus) ↔ `qg`; each bus's `Vm` ↔ `vm` and `θ` ↔ `va` (both reference bus 1
at angle 0); each branch's `flow`, `flow_rev`, `qflow`, `qflow_rev` ↔ `pf`, `pt`, `qf`,
`qt`; cost.

**Both sides use Ipopt.** This checks the formulation — the network equations, the held
voltages, the band, the ratings at both ends, the costs and their units — not the solver.
The checks that do not share it are step 3's: the answer handed back to `ac_powerflow`
(24.1), the cost bound (24.2) and the two starts (24.5).

**Default (voltage-dependent) loads have no outside check here**: PowerModels has no ZIP
load. Step 3's 24.1, 24.2 and 24.5 run on them; this step does not.

## The band — stated, and from each side's own convergence

Step 2's form. Per channel `c`:

**`band_c = 2·(O_c + T_c) + ρ_c`**

- `O_c = |ours(1e-9) − ours(1e-10)|`, `T_c = |theirs(1e-8) − theirs(1e-10)|`, max over the
  channel, computed in the test per fixture (the tight runs are 1e-10 on both sides: the
  stall points above).
- `ρ_c = 1e-11` pu (`1e-11·|cost|` on cost), step 2's round-off allowance, unchanged.

Expected bands from the probes: ~1.3e-11 pu on published and L94, ~2.4e-11 pu on 1.5×.
Expected gaps: of the order of their own convergence (6e-13 to 6e-12 pu), since ours is
nearer its own tight answer — inside the band with a factor of two or more to spare.

## Fixtures and what each is for

| Fixture | Our side | Their text | Expected |
|---|---|---|---|
| A1 published | `case9(; costed = true)` | `b0`, `held` | nothing binds on either; inside the band on every channel |
| A2 1.5× (the voltage fixture) | `mw = 1.5·315` | + `load = 1.5` | B9 on 0.9 on both: ours `at_band == [:B9]`, theirs `|vm₉ − 0.9| ≤ band_Vm`; inside the band |
| A3 L94 at an INVENTED 60 MVA | rating replaced | + L94 (9, 4) rateA/B/C = 60 | L94 on its rating at the **to end** on both: ours `at_limit == [:L94]`, theirs `|S_t| − 0.6 ≤ band`; inside the band |
| A4 1.75× | `mw = 1.75·315` | + `load = 1.75` | ours `:locally_infeasible`, theirs LOCALLY_INFEASIBLE — **reported side by side, never called agreement**: both are Ipopt's local word |

On A1–A3: their ±60° bound present on every branch and **never binding** (every angle
difference < 1.0472 − 0.5 rad); `q_at_limit` empty on ours and every `qg` strictly inside
±3 pu on theirs (no fixture tests D4's switch — none reaches a reactive limit); the held
buses' `vm` equal to their `Vg` on theirs and `V_set` on ours.

## Sabotages, and which fixture sees each (written before running them)

Each run against the step-4 testset alone. Every mutant gets Ipopt's 120 s CPU limit on
our side (step 3's patch); the oracle sets a 120 s wall-time limit always.

| Sabotage | A1 | A2 | A3 | A4 |
|---|---|---|---|---|
| **SQ** — the plan's: a reactive limit typed wrong on OUR side only. `Q_max = 3.0` → `1.0` in `scripts/outage_screen.jl` (100 MVAr on every machine, where the file says 300) | green — **blind**: no output reaches 100 MVAr (G1 at 79.4) | red: G1 needs 132.4 MVAr at the shared optimum, so ours either moves to a dearer point with G1 on 100 or is locally infeasible — not predicted which | green — blind (G1 at 84.0) | green — still infeasible |
| **SC** — THEIR side only: line charging left in (`b0` not applied in the comparison) | red on the reactive channels, voltages, and the outputs (charging changes the losses) | red, same | red, same | not predicted: charging adds reactive support and may let their side solve; if it does, red (the test asserts they do not) |

SQ's blindness on A1 and A3 is the reason it is set at 100 MVAr and not lower: a limit
only shows where it is reached, and the table says where that is before the run. A
typo below 79 MVAr would turn every fixture red and show less. SC shows the comparison
sees the edit that matters most to the AC side: without it, their network is not ours.
