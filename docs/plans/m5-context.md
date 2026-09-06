# M5 context — decisions, and what the steps actually measured

Companion to `m5-plan.md` (the how) and `m5-tasks.md` (the checklist). Decision
numbering restarts per milestone, as in M2/M3/M4 — a cross-milestone reference is
written in full (`m4-context.md` D13), never as a bare `D13`.

**State of this file.** Everything below D1–D12 was decided *at planning time*,
from `m5-prestudy.md` and from what M1–M4 measured. Nothing in M5 has been
executed. As steps run, each gains a "what it measured" section appended beneath
it — that is how `m4-context.md` grew, and it is why its D-numbers are not in
chronological order.

**Where the physics lives.** `m5-prestudy.md`. This file records *repo* decisions:
which type changes, which engine, which half of the interface, what is gated on
what. Where a decision rests on a derivation, it cites the section rather than
repeating it.

---

## D1 — The network is algebraic (a DAE), reversing the M4 plan's default

`m4-plan.md` chose dynamic RL branches "to keep an ODE", and asked whoever reversed
it to account for `isoutofdomain` and the step-rejecting protection.
`m5-prestudy.md` §5 worked both and reversed it; this is that reversal adopted.

**Why.** Dynamic branches keep the letter of "an ODE" and lose its point: the bus
voltages stay algebraic unless every bus gets a shunt capacitance, and with
realistic line charging the bus time constants are microseconds against swing
dynamics of seconds — a stiffness ratio of `1e5–1e6`, bought for nothing. Inflating
the capacitance to tame it changes the very physics the tier exists to capture.

**What survives unchanged** (checked in §5 against how each piece is actually
built): `isoutofdomain` is applied by the generic stepping loop, not the explicit-RK
path, so a rejected step retries with a smaller `dt` on a Rosenbrock/BDF method
exactly as now; `ContinuousCallback` root-finding works on any dense-output
solver; `step!(integ, dt, true)`, `add_tstop!`, `add_saveat!` and `inject!`'s
`derivative_discontinuity!` / `auto_dt_reset!` are solver-agnostic; the recorder
reads `u`, and algebraic states are in `u`.

**What changes:** the solver class, the cost per step (a sparse linear solve per
stage — NetworkDynamics supplies the Jacobian sparsity), and one new failure mode,
which is D8.

**The second, independent argument** arrived from the oracle rather than from
stiffness (`m5-prestudy.md` §2a): PowerDynamics' `SauerPaiMachine` sits behind its
reactance on an algebraic terminal bus. If our detailed tier kept `E′` at the bus,
the external oracle would need M4's radial reduction and would be invalid on any
meshed topology (`m4-context.md` D13) — the ring excluded again. Terminal buses on
both sides remove the reduction entirely. The most expensive decision in this
milestone now has two reasons that do not depend on each other.

## D2 — Playback first. Real-time stepping is a measurement, not an assumption

The detailed engine implements the **playback** half of the interface in its first
landing: `init!` / `solve!` / `state_series` — **and `inject!`**. The single
deferred method is `step!` (with `timestep`), i.e. wall-clock stepping, added only
if the measurement says the tier is steppable.

**`inject!` is not the real-time half, and the boundary is narrower than "playback
vs real-time" suggests.** `src/engines/interface.jl` states the playback contract
itself: scheduled perturbations are applied "at exactly that instant through the
same `inject!` the real-time loop uses" (`m4-context.md` D8 — not a
`PresetTimeCallback`, deliberately, so a scheduled trip has exactly one path into
an engine). So a playback-only engine still needs `inject!`; plan step 7's
scheduled line trip needs it, and D8 below is written on the assumption that it
exists. Deferring it would collide with both.

**Why.** Whether a stiff DAE steps in wall-clock real time on a two-area case is
genuinely unknown. Writing a plan that assumes it would force one of two bad
outcomes later: a measurement read charitably to protect the plan, or a silent
scope change. The mode router exists precisely so a tier can be playback-only
(SPEC §3.3), and M4 built the shared playback driver (`src/engines/playback.jl`)
so a new engine adds a `solve!` method, a `_record_at!` and an
`_aggregate_weight` — a small surface.

**The measurement is S3** (D10): steps and wall-clock per simulated second, DAE
against the classical tier, two-area, same tolerance. It is taken in step 1, as
soon as there is a network to take it on, not deferred to whenever real time is
wanted. It is also the number `m4-plan.md`'s last bullet demands before anyone
says "better than PowerDynamics" — that claim needs a named axis, and this is one
of the three.

**Consequence for the UI** (plan step 8): the voltage window is a playback overlay
on M4's scrubbable window. If S3 comes back well, real-time is a later addition
that costs a `step!` method, not a redesign.

## D3 — One canonical `NetworkModel`, extended — and the tier check moves to the engine

SPEC §3.2 allows exactly one canonical model. M5 therefore **extends**
`NetworkModel` rather than forking a second type: a load model at a bus, buses
without machines, and the detailed machine parameters of D4.

The obstacle is that `src/model/network_model.jl`'s constructor currently *rejects*
both a machine-free bus and a two-machine bus, and the file says why: at the
classical tier a bus without a machine is an algebraic node with no differential
state, i.e. this tier, and the rejection made the tier boundary "a loud error
rather than a quietly wrong answer." That rejection is still right — **for the
classical engine**. It is wrong for the model.

**So the check moves, it does not disappear.** `SwingEngine` gains a build-time
precondition in the shape `reference/src/oracle.jl` already uses
(`_assert_governor_free`, `_assert_radial`): a model this engine cannot represent
is refused at construction, by name, with the tier named in the message. The
boundary stays loud; it stops being a property of the data.

**Why not a second model type.** A `DetailedNetworkModel` beside `NetworkModel`
is exactly the "parallel hand-maintained copy" SPEC §3.2 forbids and
`m4-context.md` D5 enforced for the oracle builder. It would also mean two
`coi_model` derivations, two per-unit converters, and two places for the M2
conversion bug to reappear.

**`coi_model` gets the same treatment, and it needs saying because it is SPEC
§3.2's one working proof.** The aggregate tier is *compiled* from `NetworkModel`
via `machine_arrays`, so widening that model widens what `coi_model` may be handed.
It **refuses** a model carrying loads or machine-free buses, by a precondition of
the same shape as the `SwingEngine` one above — not silently aggregates over the
machines and folds ZIP loads into `D`. Folding a voltage-dependent load into an
aggregate damping constant is a *modelling claim* nobody has validated, and it
would land inside the one derivation the repo points at to show reduced models are
derived views rather than parallel copies. An aggregate view of the detailed tier
is real work, and it is not this milestone's.

**The M2a load convention survives.** "A load is a machine with negative `P0`" —
how `three_machine_ring()`'s −110 MW bus works — is unchanged: a negative-`P0`
machine stays a machine. The new load type is an *addition* for buses that carry no
rotating mass, not a replacement, which is why every existing scenario constructs
unchanged and still compiles a COI view.

**Cost, stated:** this is a change to the one type every existing test constructs,
so it is a refactor under a green suite — which is why the test split (D9) goes
first and why step 1 is a single step rather than three.

## D4 — The detailed machine's defaults ARE the classical degeneration

`Machine` gains its new parameters as **defaulted positional arguments** — the
precedent M3 set when it added `R`, `Pmax` and `Tg` so that every M2 model still
described a real system rather than an accidentally-governed one.

The defaults are chosen so that a machine constructed the M2/M3 way is exactly the
frozen-flux machine of `m5-prestudy.md` §3: `Xd = Xq = X′q = Xd′`, `T′do = T′qo =
Inf`, `Ra = 0`, regulator off.

**Why this particular choice.** It makes the degeneration oracle of plan step 2
the *default configuration* rather than a special test fixture, which means the
comparison against `SwingEngine` runs on the scenarios that already exist
(`two_machine_system()`, the Iberian two-area case) without a parallel set of
"detailed" scenario constructors — the same forked-data hazard as D3, one level
down. `T = Inf` is safe in our formulation because the time constant is a
divisor: `finite/Inf = 0.0` exactly, and the fixpoint solve sees a zero derivative
rather than `0/0`. **That argument is about our form only** and does not transfer
to PowerDynamics, which writes the multiplied form — see S1 in D10.

**The signature shape is named here rather than discovered at build time.**
`Machine`'s inner constructor is positional-only *on purpose* — `network_model.jl`
says so, because it is the only path and therefore the only place validation can
live — and it is already 11 arguments (8 required, plus M3's 3 defaulted). Eleven
more would make it ~22 positionals, which is a different thing from M3's precedent
of three. So the detailed parameters arrive as **keywords on an outer constructor**
that fills them and calls the positional inner one, which keeps the single
validated path intact. M2/M3 call sites are untouched either way; this is about the
new arguments only.

New columns in `machine_arrays`: `Xd, Xq, X′q, T′do, T′qo, Ra`, and for the
regulator `K_A, T_E, Efd_min, Efd_max, Vref`. Reactances scale **inversely** with
`S_rated/S_base`; time constants are in seconds and base-free; `Efd` is on the
machine's field base. The `Xd′` row is the template and `machine_arrays` stays the
single place any conversion happens.

## D5 — `X_ls` is not a column, and its irrelevance is a free positive control

PowerDynamics' component needs a leakage reactance `X_ls` (with no default, and a
hard `X_ls < X′d` precondition because `γ_d1` divides by `X′d − X_ls`). It does
**not** become a `Machine` field.

**Why.** Trace it through the degeneration (`m5-prestudy.md` §2a) and it survives
nowhere: `γ_1 = 1` and `γ_2 = 0` are independent of it, the `E′` brackets reduce to
`I_d` and `I_q`, and the flux linkages lose their `ψ″` terms — only the two
decoupled sub-transient equations still mention it, and those drive nothing. It is
a constant the *builder* supplies to a foreign component, not a parameter of our
canonical model. Giving it a column would import someone else's model into the one
thing SPEC §3 keeps canonical.

**And its irrelevance is checkable, cheaply.** Vary `X_ls` across an oracle run
and every comparison channel must come back **bit-identical**. If anything moves,
`γ_d1 ≠ 1` and the degeneration did not take. That is the "check that the switch
actually switched" control M3 and M4 each had to build by hand, available here for
one extra solve, testing the assumption all three flux oracles rest on.

## D6 — The power form, decided by M3's governor rather than by the oracle

`m5-prestudy.md` §2a shows there are two self-consistent packages, and only two:
**A**, a torque balance with the rotor speed on the stator flux terms; **B**, a
power balance with the standard `ω ≈ 1` stator. Mixing them subtracts a torque from
a power, which is precisely what makes PowerDynamics' `ClassicalMachine`
inconsistent (`m4-context.md` D14).

**We take B**, and the deciding argument is not accuracy — it is M3. Our mechanical
side is denominated in power end to end (`Pm₀ + ΔPm + ramp`, droop `−Δω/R`,
headroom in MW) and M3's droop and headroom closed forms are validated against that
denomination. Option A would insert a `/ω` between the governor and the shaft and
move every one of those validated closed forms, to remove a residual we can
predict in advance.

**So the residual is predicted, not absorbed.** Against `SauerPaiMachine` at equal
states their terminal voltage is `ω ×` ours, a residual of `(ω − 1)·V`: first order
in slip, order-one coefficient, and **identically zero at synchronous speed** — so
the flat run, the fixpoint residual and every steady-state identity are blind to
it by construction, exactly as they were to D14. It is identified by its signature.
A band wide enough to swallow it would swallow a real error of the same size.

**The separator is fidelity, not loading.** The pre-study originally proposed
comparing at low loading, on the analogy of D14, which was pinned by linearity in
loading. That does not work here: flux decay scales with loading too, so both
candidate causes move together. Hence plan steps 3 and 4 — flux off on both sides
first, leaving the stator-`ω` residual alone; then flux on, and the *change* is the
flux term. This is the one place M5's step list is finer-grained than
`m4-plan.md`'s D7 rule required, and the reason is written here so a later reader
does not merge the two steps back together.

## D7 — The power flow is `find_fixpoint` on the static network; no new solver

Bus voltages come from the steady state of the algebraic network with each machine
replaced by its scheduled injection and one slack — a nonlinear system on a sparse
structure, which is the exact shape `NetworkDynamics.find_fixpoint` already solves
for `SwingEngine`. NetworkDynamics assembles the residual edge by edge, so **no
admittance matrix is ever formed** and SPEC §6's "sparse from day one" holds by
construction rather than by discipline.

`PowerFlows.jl` stays out: roadmap item 5 owns it, it pulls `PowerSystems`, and
the two-area and three-machine cases need nothing it offers.

**Two cautions the M2 spike already paid for, carried into the code as asserts.**
`find_fixpoint` converges to whatever self-consistent solution the initial guess
leads to, so the guess is a flat start and the solution is *checked* (`|V| ∈
[0.9, 1.1]`, flows below rating, residual `< 1e-10`) rather than trusted. And the
fixpoint is solved on the **static** network first, with machine states
back-substituted from it in closed form (`m5-prestudy.md` §4) — never jointly with
the dynamic states from a flat guess, because the joint problem has spurious
equilibria (a machine at `δ + π`) that look converged.

The back-substitution yields the **air-gap** power for `Pm`, not the terminal
power; §2a settles that from PowerDynamics' own static stator, where terminal power
is smaller by the stator loss.

## D8 — `inject!` gains a consistent re-initialisation, and the flat run is re-run across an event

The one new failure mode D1 buys, and the one SPEC §6 predicted as "re-init
algebraic state for the network tiers": after a discontinuity — a line trip, a
shed — the algebraic states no longer satisfy their constraints, and stepping from
an inconsistent point is not a well-posed problem.

So `inject!` at this tier ends with a consistent-initialisation call, and the test
that guards it is **the flat run re-run across an event**: trip a line on a system
whose post-trip equilibrium is known, and assert no spurious transient beyond the
physical one. A flat run before the event proves the initialisation; a flat run
*across* the event proves the re-initialisation, and nothing else does — an overlay
cannot, for the same reason it cannot catch a bad start.

**M3's protection carries to this tier**, because every piece of it is machine-
bound and power-denominated: the shed ladder, the out-of-step tie relay and the
scheduled generation ramp all act on quantities this tier still has. What changes
is that each now fires into a DAE, i.e. through the re-initialisation above. They
are wired at the step that needs them (plan step 7, the Iberian criterion), and
each is re-validated at this tier against the M3 closed form that still applies —
not assumed to carry because the code compiles.

## D9 — The test file is split first, and the count is the check

`test/runtests.jl` is 4,922 lines in one outer `@testset`, and M5 adds roughly a
milestone to it. It is split in **step 0b**, before any M5 code exists. (Step 0 is
planning, following `m4-tasks.md`; `0b` is the number in all four files.)

**Why first rather than last.** M2's lesson, in its own words: refactor before
feature, because the old suite is the only oracle. D3 changes the one type every
existing test constructs; doing that under an unreadable suite, or splitting the
suite while a new tier moves underneath it, are both worse than doing the
mechanical move now while everything is known-green.

**The trap is already written down** (`docs/plans/README.md` §Structure notes) and
is the reason this is not a blind `sed`: the helpers are defined *between* testsets
inside the outer testset's local scope, so an `include`d file would not see them.
The split means moving every helper to `test/helpers.jl`, `include`d at top level
before the outer testset, then one file per milestone in the same order.

**Gate:** identical test count before and after (1873 core), and no assertion text
changed in the same commit. A mechanical move that silently drops a testset is the
failure this step could introduce, and the count is what catches it.

## D10 — Three questions about someone else's tooling are spikes, scheduled before what depends on them

`m5-prestudy.md` names three claims it explicitly refuses to make, because each is
a statement about a tool nobody here has run. They get their own boxes, ahead of
the steps whose design they can invalidate — rather than a plan written as though
all three resolved favourably.

| | Question | Fallback if it goes the other way | Before |
|---|---|---|---|
| **S1** | Can PowerDynamics express `T′ = Inf`? They write the multiplied form `T′d0·Dt(E′q) ~ rhs`, so it reads `Inf·ẋ ~ finite`. | Large-but-finite `T′` with a `1/T′` convergence check — the residual falls a decade as `T′` rises one. A *different* check from an exactness assertion, and scoped as one. | Step 3 |
| **S2** | What does MTK's initialiser do with `bounds = (0, Inf)` on `vf`, `τ_m`, `τ_e` — enforce, or hint? | If they bite: a build-time precondition on the model shaped like `_assert_governor_free`, so a machine absorbing at equilibrium is refused by name instead of failing to initialise for a reason that does not name itself. | Step 3 |
| **S3** | Steps and wall-clock per simulated second for the DAE, two-area, against the classical tier at the same tolerance. | If the tier is not real-time steppable it is playback-only there, which is D2 and which the mode router was built for. | Decides D2; taken in step 1 |

A spike is not a step: it produces a number and a paragraph in this file, not a
feature. But a spike that is skipped becomes an assumption, so each has a box in
`m5-tasks.md`.

## D11 — The cut line is stated before anything is built

Nine steps is larger than M3 (seven) or M4 (five), and `m4-plan.md` already
predicted this tier is "plausibly larger than M2 and M3 combined". The cut order
is in `m5-plan.md` §The size decision: the window goes first, the regulator second
(provided voltage-dependent load lands, because that alone makes voltage fall),
and steps 0b–4, 6 and 7 cannot be cut without the milestone buying nothing on the
case it exists for.

**What must not happen** is a step landing with its gate weakened because the
milestone is running long. A cut step is honest and gets its own later batch. A
step with a band widened to fit is the failure `entsoe-iberia-reproduction.md`
§7.3 exists to document — a tuned parameter that became a quoted result.

## D12 — The UI keeps M4's promise as playback, and says so if it slips

`m4-plan.md` step 3 wrote a commitment on this milestone's behalf: the overlay
delivers only the first of SPEC §7.6's three lessons, and *"voltage coupling and
inverter behaviour need a tier that has voltage in it, and that is M5."*

M5 keeps the **voltage** half: a playback overlay on M4's scrubbable window with
bus voltage magnitude alongside frequency, classical against detailed. Inverter
behaviour has no tier in this milestone and does not acquire one by implication —
that is a third fidelity, unnamed and unscheduled.

It is the first thing cut (D11), and if it is cut, the inherited promise is
restated in the follow-on batch rather than quietly dropped. The discipline is
M4's: `smoke_render` offscreen first, then the live window; render before
claiming; and a `Label` with the right text that was never added to the figure
passes every text assertion anyone can write about it.
