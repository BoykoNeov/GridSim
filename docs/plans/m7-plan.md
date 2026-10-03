# M7 — Inverter-based resources and low-inertia grids · Plan

Companion docs: `m7-context.md` (decisions and, as steps run, what was measured),
`m7-tasks.md` (the checklist). Layers on `docs/SPEC.md` §2–4 and the M1–M6 trios.

**Read `m7-context.md` D0 first.** The three hurdles there were named before this
plan was written, and every step below is justified against one of them.

M7 has **no separate pre-study**. The physics that would have gone in one — the
droop/swing equivalence, the grid-following existence limit, the PLL's response —
is short enough to live in D0, and the one thing that was genuinely unknown (do
the outside components build, initialise and behave as their source says) was
measured at step 0 rather than argued (D1).

## Goal

Make the repo able to answer **"what changes when the generation has no
rotor?"** — and answer it with numbers that are checked, not with the M1 closed
form re-run at a smaller `H`.

By the end of M7 a `NetworkModel` can carry inverters of two kinds; the
grid-forming kind runs in the swing and detailed tiers and is checked by an exact
algebraic equivalence to a machine; the grid-following kind runs in the detailed
tier with a phase-locked loop and is checked by closed forms and an outside
model; the frequency read-outs say what they are when there is no rotor to read;
and one study displaces synchronous machines by each kind of inverter and reports
what happens to RoCoF, nadir and stability, with the fixture's influence on the
answer made visible.

## What M7 is not

- **Not electromagnetic transients.** The detailed tier stays a phasor model. Where
  that stops being honest for inverters is Hurdle 12, and it is named, not
  approximated (D8).
- **Not inverter current limiting, fault ride-through or DC-link dynamics.** Owed
  and named (D8). Current limiting is the one that matters most and is the first
  candidate for M8.
- **Not a reproduction of an Iberian mechanism.** The scenario file records that
  inverter-based resources carry no inertia and how much PV tripped; it records
  nothing about their control modes, so no Iberian claim here goes beyond those
  figures (D7).
- **Not the network OPF**, still owed from M6.

## The order, and why it is the order

The ordering rule is M4 D7's, carried through M5 and M6: **never let two things
change at once between a number and its check.** So the data model moves first
under an invariant that no existing number moves, and every consumer that would
silently drop an inverter refuses it by name until its own step implements it. The
aggregate tier goes next because its check is a closed form. The grid-forming
inverter then enters the swing tier, where its exact equivalence is the sharpest
check available, before it enters the detailed tier, where the equivalence still
holds but the voltage droop that breaks it is live. The grid-following inverter
goes after both, because it needs a voltage source to follow, and by then the repo
has two kinds. The frequency read-outs come once there is a PLL to read, and the
study comes last, because it is the first step that is a *result* rather than a
mechanism.

Each step commits, leaves all three suites green, and carries its own gate. **No
step is "done" because it runs; it is done when its named check passes with a
positive control and an executed anti-vacuity mutation** — the standing rule since
M3.

### Step 1 — The `Inverter` type, added without moving a number, and refused everywhere it is not yet built

`Inverter` (D2): id, bus, own rating `S_rated`, dispatch `P0` (MW, positive =
injecting) and `Q0` (MVAr, grid-following), `mode` (`:grid_forming` /
`:grid_following`), and the per-mode parameters — grid-forming: `K_p`, `τ_p`,
`K_q`, `τ_q`, `V_set`, `X_c`; grid-following: PLL gains. Gains on the inverter's
own rating; the field list is settled here and recorded in the context file.
`NetworkModel` gains `inverters::Vector{Inverter}` (keyword, default empty). The
active-power balance guard counts inverter injections. Bus roles (M6 D3) derive a
grid-forming inverter's bus as voltage-controlled and a grid-following one's as a
load-type bus; the declared slack may be a grid-forming bus. The scenario file
reads and writes an `[[inverter]]` table.

**Every existing consumer that reads `net.machines` and would silently drop an
inverter refuses a model carrying one, by name**, until its own step builds it:
`coi_model`, `SwingEngine`, `DetailedEngine`, `FrequencyResponseEngine` via
`coi_model`, `dc_powerflow`, `ac_powerflow`, the cheapest dispatch, and
`build_oracle`. The list is walked from the code (`grep` for `net.machines` /
`machine_arrays`), not from memory, and each site is recorded as refusing or as
deliberately unaffected.

**Gate — the invariant, two claims:** (a) every pre-existing core test passes; (b)
M5's recorded criterion values are **bit-identical** to the capture taken at HEAD
before the first edit (`W:\temp\claude\m7\criterion-HEAD.txt`). Anti-vacuity: an
inverter-carrying fixture is refused by each consumer above (a test per consumer,
asserting the refusal *names the inverter*), and one fixture shows the balance
guard counting the inverter's `P0` (a model balanced only with the inverter
counted is accepted, and one with it dropped is rejected).

### Step 2 — The aggregate tier: inertia that is there, and inertia that is not

`coi_model` compiles inverters into the aggregate: a grid-forming inverter
contributes virtual inertia `τ_p/(2K_p)` and damping `1/K_p` (converted to the
system base once), a grid-following one contributes zero inertia and zero
response. **The inverter's damping rides on its own unit and leaves with it when
it trips** (D9) — `GeneratingUnit` gains a per-unit damping field defaulting to
zero, so no existing number moves. That is D4's "the equivalence is the compiled view here".

Checks (closed forms, the M1 pair): `RoCoF₀ = −f0·ΔP/(2·(H_sync + H_virt))` and
`Δω_ss = ΔP/(D + 1/R_eq + Σ 1/K_p)` on a model where both kinds are present, with
the grid-following inverter's contribution to each being **exactly zero** (not
small). The displacement closed form: replacing a synchronous machine of rating
`S` and inertia `H` by a grid-following inverter of the same dispatch raises
`|RoCoF₀|` by the factor `H_sys/(H_sys − H·S/S_base)`, asserted over a sweep.
Hurdle 10 claim 3: an all-grid-following model is refused by the aggregate
read-out by name. Anti-vacuity: `K_p` converted on the wrong base moves `RoCoF₀`
by the predicted factor.

### Step 3 — The grid-forming inverter in the swing tier, checked by its exact equivalence

A new vertex model in `SwingEngine`, built from the inverter's **own** states
(`δ`, `P_filt`) and its droop law — never by converting to a machine and calling
`swing_vertex!` (D4). Voltage magnitude at the bus, `K_q` not read (this tier
holds `|V|` by construction, and says so).

The oracle (Hurdle 11 claim 1): the same network run twice, once with an
`Inverter`, once with a `Machine` carrying `H = τ_p/(2K_p)`, `D = 1/K_p` (converted
to the machine's own base by hand, in the test, from the formula — not through the
code under test), `E′ = V_set`. **Agreement to within solver error, falling with the
tolerance** on a network-side disturbance (a line trip). *(Written first as "to
round-off"; corrected in step 3 — the two models integrate different state
variables, so the adaptive steps differ and the gap is the solver's.)* Anti-vacuity: `K_p` read on the wrong base; the filter
time constant dropped (`τ_p → 0`, which makes the inverter an inertia-free droop
and must open a gap). Positive control: the pre-registered non-equivalence
(claim 2) — under a `P_set` step the inverter's frequency jumps by exactly
`K_p·ΔP_set` at `t⁺` and the machine's does not.

Then, and only then, `SPEC.md` §7.6's "an inverter has no swing equation" is
corrected to say which kind of inverter it is true of.

### Step 4 — The grid-forming inverter in the detailed tier, with voltage droop live

A new detailed-tier vertex: the droop inverter as a voltage `V∠δ` behind `X_c`,
injecting `(V∠δ − V_bus)/(jX_c)` into the bus's Kirchhoff sum, like a machine.
`V = V_set − K_q(Q_filt − Q_set)` is live here. Initialisation through the
existing static-network path, with the inverter's bus a voltage-controlled bus.

The power flow learns the same inverter here: `ac_powerflow` and `dc_powerflow`
treat a grid-forming bus as voltage-controlled (`P0`, `V_set`), and the check is
exact — the solved state is **bit-identical** to the same model with a `Machine`
of the same `P0` and `V_set` in its place, since the power flow reads nothing
else of either. **The rating is where the two differ** (D10): the solved reactive
output at a grid-forming bus is either checked against `√(S_rated² − P0²)` or
named as unchecked — decided here, with the measurement.

Checks: (i) the equivalence again, at `K_q = 0`, against a classical detailed
machine with `X′d = X_c` — round-off; (ii) **PowerDynamics**, at matched
fidelity: `IdealDroopInverter` at an internal bus plus an explicit line of
reactance `X_c`, `K_q` **live**, which is the part no in-house check reaches;
band from solver tolerance, stated before the gap is seen (M4 D7). Anti-vacuity:
`K_q` sign flipped (voltage rises with reactive output) must open a gap against
PowerDynamics; `X_c` dropped must open one against both.

### Step 5 — The grid-following inverter in the detailed tier

A new detailed-tier vertex: an **ideal** current source phased by a PLL. States:
the PLL's angle and frequency (and its integrator, matching whichever PLL form is
chosen — recorded); the injected current is `(i_d + j·i_q)·e^{jθ_pll}` with
`(i_d, i_q)` from the dispatch at initialisation. No filter or current-loop state
(Hurdle 12 — the gap to the outside model is the point).

The power flow learns it too: a grid-following inverter is a fixed `P0 + jQ0`
injection on a load-type bus, checked against the two-bus closed form
`V_t = √(|V_g|² − X²i_d²)` at unity power factor, and a model whose reference bus
carries only a grid-following inverter is refused (D5).

Checks: (i) **existence limit** (Hurdle 11 claim 3): on the two-bus fixture the
initialisation succeeds below `P = |V_g|²/(2X)` and is refused above it, located
by a scan; (ii) the **PLL's closed-form response** to a phase step at a stiff bus:
natural frequency and damping from its gains, peak frequency excursion predicted
before the run; (iii) D5's refusal — a model with no voltage source is refused by
name; (iv) **PowerDynamics' `SimpleGFL`** at matched dispatch, with the gap
reported as a function of their current-loop gain and asserted to **shrink** as
the loop stiffens (Hurdle 12). Anti-vacuity: PLL error signal sign flipped (the
loop must diverge, not lock); current injected in the wrong frame (the bus frame
instead of the PLL frame) must open a gap to the closed forms.

### Step 6 — Frequency without a rotor: the read-outs

`state_series` gains per-bus PLL frequency channels where a grid-following
inverter sits, under their own names; the centre-of-inertia channel counts
grid-forming virtual inertia and refuses when its weights sum to zero; and a
helper reports RoCoF three ways (centre-of-inertia derivative, `windowed_rocof`
over a stated window, PLL-derived) side by side.

Checks: Hurdle 10 claims 1 and 2 as closed forms — the phase-step spike size, and
the dependence of measured RoCoF on window length for a known trajectory — and
claim 3's refusal. Anti-vacuity: a PLL read-out averaged into `ω_coi` must move the
centre-of-inertia channel on a case where it should not move.

*(As built — `m7-context.md` D14: a measurement-only `PLLMeter` was added at the
user's choice, so step 7's grid-forming sweep has a PLL to read; the
centre-of-inertia derivative is a live read (`coi_rocof`), not a recorded channel,
because the reference oracle mirrors the detailed channel list; the zero-weight
refusal lives in the new read-outs, while the swing tier's live channel keeps M2's
`NaN`. Step 6 also found that step 7's event does not exist at the tier step 7
needs — see D14's last paragraph.)*

### Step 7 — The low-inertia study

One scenario, `scripts/low_inertia.jl`: a multi-machine case where synchronous
machines are displaced step by step, once by grid-following inverters and once by
grid-forming ones, at matched dispatch, with the largest-unit trip at each share.
Reported per share: centre-of-inertia `RoCoF₀`, nadir, the worst local
(PLL-measured) RoCoF, and whether the run stays synchronous. The aggregate tier's
closed form is overlaid, so the point where the network result leaves it is
visible. The fixture's own influence is tested, not assumed: the same sweep on a
second topology, and the claim written only after reading both tables (M3 step 6's
lesson — two claims went in ahead of the numbers and both were wrong).

Positive control: at zero share the study reproduces M1's recorded values.
Anti-vacuity: the grid-forming sweep with `τ_p → 0` must lose the inertia benefit
the plain sweep shows.

**Cut-first within this step:** the second topology can be cut to a stated
limitation if time runs out; the first sweep cannot.

*(As built — `m7-context.md` D15/D16: the step began by building the source trip the
detailed tier did not have, for all three kinds. "The largest-unit trip" became TWO
events at the user's choice, because M1's largest unit is 38 % of the fleet and its trip
turns grid-following displacement into a voltage event below the band; the table runs on
the default loads, with M1's number reproduced exactly on constant-power loads as its own
section. The second topology was not cut. The aggregate overlay is the RoCoF₀ closed
form; the aggregate nadir is not drawn, because `coi_model` refuses a `Load`. The finding
that reorganised the claims: on default loads the formula and the network rank the two
inverter kinds opposite ways, and load relief at t⁺ accounts for the difference exactly.)*

### Step 8 — The editor, and a window

The editor is owned by whichever milestone changes the model (`README.md`
"Scenario editor"), and M7 changes the model: it gains an inverter tool, the mode
and per-mode fields in its panel, and save/open round-trips them. **Not cut.**

A window drawing the step-7 comparison live (both displacement kinds, PLL
read-outs beside the centre-of-inertia trace) is **cut-first**: if the milestone
runs long it is named un-built rather than implied.

### Step 9 — Close

Manifests deleted and re-resolved in all three environments, counts re-measured,
ledger rows, `SPEC.md` §7.6 / §9 annotations, README row, memory.

## Cut-first, in order

1. The step-8 window.
2. The second topology in step 7.
3. Step 5 check (iv)'s gain sweep reduced to two gains (the shrinking claim still
   needs two points).

Nothing else is cut without recording the decision in `m7-context.md` first.
