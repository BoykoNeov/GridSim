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

### What S3 measured (2026-09-06, step 1) — the caution is lifted, not confirmed

Both tiers, `reltol 1e-3` / `abstol 1e-6`, 20 s horizon, `saveat = 0.02`, an
identical +0.05 rad offset on machine 1. Steps per simulated second is the primary
number because it is deterministic; wall clock is best-of-3 and noisy (step 0b
measured 1m25–5m15 for identical work on this machine).

| case | tier | accepted steps | steps / s-sim | wall / s-sim |
|:---|:---|---:|---:|---:|
| two-area (2 bus, 1 branch) | classical, `Tsit5` | 41 | 2.05 | 1e-5 s |
| two-area | detailed, `Rodas5P` | 45 | 2.25 | 9e-5 s |
| ring (3 bus, 3 branch) | classical, `Tsit5` | 228 | 11.40 | 3e-5 s |
| ring | detailed, `Rodas5P` | **126** | 6.30 | 3.2e-4 s |

**The detailed tier runs 3,000–11,000× faster than real time on both cases**, so
the honest reading is that it *is* steppable and D2's playback-first default was a
caution rather than a finding. One number came back with the opposite sign to the
expectation: on the ring the DAE takes **fewer** steps than the ODE (126 against
228), because the implicit method is not paying for stiffness the explicit one is.
The DAE's cost is per step (~8.5× on the two-area case), not per second.

**What does not change.** `step!` stays unimplemented for this tier in step 1: the
measurement says the solver could sustain it, which is a different claim from a
shipped, tested real-time path, and building one is not step 1's scope. Two
caveats belong with the number — these are 2- and 3-bus cases, and the per-step
cost of a sparse linear solve grows with size in a way two points cannot
extrapolate.

**A scope constraint discovered here, which step 7 inherits:** the two-area case
has a **single tie**, so a line trip islands it and each island needs its own
angle reference — which the DAE's single pinned slack cannot supply. S3 therefore
used an off-equilibrium start rather than an event, and step 7's criterion will
have to face the same thing when it trips that tie.

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
of three. So the detailed parameters arrive as keywords, which keeps the single
validated path intact. M2/M3 call sites are untouched either way; this is about the
new arguments only.

> **Corrected when step 2 built it: the keywords are on the INNER constructor, and
> the outer one this paragraph asked for cannot exist.** Keyword arguments do not
> participate in Julia's dispatch, so an outer `Machine(id, bus, S_rated, H, D,
> Xd′, E′, P0; Xd = …, …)` has the *same* positional signature as the inner
> constructor's eight-argument form — it is a redefinition, not a second method,
> and the two collide. Keywords **on** the inner constructor achieve both of the
> things the paragraph above actually wanted: one method, one place validation
> lives, and six names that are never positional (asserted with a `MethodError`
> test, so a later positional twelfth argument cannot land in one by accident).
> The step also cut the list to the six the two-axis machine needs; the regulator's
> five (`K_A, T_E, Efd_min, Efd_max, Vref`) belong to plan step 5.

**And one thing the defaults silently reinterpret, which is worth stating because
nothing errors when it stops being true.** At the classical tier `Machine.E′` is
the constant internal voltage *at the bus*. At the detailed tier it is the
magnitude of the q-axis voltage **behind `(Ra + jXq)`** — the quantity a steady
state actually pins, because `Ẽ = V + (Ra + jXq)·I` lies on the q-axis for the
two-axis machine and `|Ẽ|` together with the scheduled `P` is what closes the power
flow. With `Xq = X′d` and `Ra = 0` those are the same number, which is why every
pre-M5 fixture solves to the same answer bit for bit. They stop being the same
number the moment `Xq` is a realistic synchronous reactance, and a fixture with a
real `Xq` will sit at a terminal voltage well below its `E′` — close enough to
`_check_power_flow`'s `[0.9, 1.1]` band to be worth checking before step 4 builds
one. Named here rather than found as a "bug" later.

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

### What step 1 measured (2026-09-06) — the right design, the wrong stated reason

**The rotational gauge does not force the separate static network.**
`find_fixpoint` on the dynamic network does fail from a flat guess (MaxIters,
residual `2.6e-10` against `1e-10` — only a factor of 2.6, so loosening the
tolerance would have "fixed" it and returned a gauge-arbitrary answer). The
Jacobian has exactly one null direction (`2.72, 0.472, 2.6e-11`). But
**`SwingEngine`'s fixpoint problem is rank-deficient in the same way** (`1.46e-14`
against `314`) and converges anyway, seeding at the true solution does not help,
and pinning the slack angle *inside* the dynamic network converges to `1.3e-15`.

**What forces it is the spurious equilibrium — and its residual misleads.**
Slack pinned, seeding one rotor angle away from its true value:

| seed for δ₂ | converged δ₂ | \|V\| | residual |
|:---|---:|:---|---:|
| true (−0.0287) | −0.028673 | (1.010, 1.004, 0.978) | 1.8e-13 |
| true + π | 2.943790 | (0.389, 0.203, 0.131) | **5.0e-16** |
| true + 2.5 rad | 2.943790 | (0.389, 0.203, 0.131) | 4.4e-16 |

The collapsed point is self-consistent and converges **400× tighter than the true
one**. No residual test separates them; only the `|V| ∈ [0.9, 1.1]` band does —
so that band is a discriminator in the code, not a comfort check, and its docstring
says which of the two jobs it is doing. Back-substitution avoids the question
entirely: `δ` is computed, never seeded, so there is no basin to fall out of.

**One static network, two jobs.** The same network serves the power flow and the
post-event re-initialisation, switched by a per-machine `mode` on the third
residual: `Pe − Pset` (solve the angle) or `δ − δ_target` (pin it). The power flow
pins one machine; the re-initialisation pins every machine and re-solves the
voltages, which is exactly "hold the differential states, restore the algebraic
ones" and needs no second solver.

## D13 — The slack is a DISPATCH choice, not a gauge choice (measured, and it changed the control)

The expected shape was D5's, one level down: the angle reference is physically
arbitrary, every observable is a difference, so by the standing rule that a
parameter surviving nowhere is a control and not a column it becomes an engine
keyword whose *irrelevance is a free positive control*. Half of that survived
measurement.

| model | max\|ΔV\| | max\|Δ(δ−δ₁)\| | max\|ΔPm\| |
|:---|---:|---:|---:|
| `two_machine_system`, `three_machine_ring` (no load) | 2.2e-16 | 2.8e-17 | 1.1e-16 |
| `load_bus_system` (constant-impedance load) | 3.6e-4 | 1.5e-2 | 4.6e-2 |

**It survives, into the dispatch.** The slack machine's power is free while every
other machine holds its schedule, so the slack is whoever absorbs the mismatch —
and once a load's draw depends on voltage there *is* a mismatch, because the
schedule balances at `|V| = 1` and the solved network does not sit there. Both
answers are correct operating points of the same schedule, each self-consistent:
with G1 as slack `Σ Pm = 1.054270` and the load draws `1.054270`; with G2,
`1.053793` and `1.053793`.

**So it stays an engine keyword** — it is a decision about a *case*, not a property
of the network — but for a different reason than the one above, and the positive
control now carries its precondition: *on a model with no voltage-dependent load*,
changing the slack must change nothing to machine precision. Written without that
boundary the invariance test would have failed the first time anyone put a load in
a model, and it would have looked like a bug in the power flow.

## D14 — Three guards moved, not two, and the third could not have stayed

D3 named the machine-free-bus and two-machine-bus rejections. The
`|P0ᵢ| ≤ Σⱼ K_ij` reachability guard had to move to `SwingEngine` as well, and
the reason is stronger than a tier boundary: `K_ij = E′ᵢE′ⱼ/X_ij` is
**uncomputable** on a model with a machine-free bus, because there is no `E′` at
one end. A guard that cannot be *evaluated* on the cases the constructor must now
accept is not a guard that merely belongs elsewhere.

Two consequences worth keeping. `branch_arrays` — which carries `K` — took the same
precondition, so it is no longer callable on every valid model, and
`branch_topology` was added as the machine-free view (`src`, `dst`, `X`). And
`machine_arrays` is now documented **machine-indexed** with a `bus` column rather
than vertex-indexed: the two were the same number until a bus could lack a machine,
and the alternative (vertex-indexed with holes) would need a sentinel `H`, which
sits in a denominator.

## D15 — The flat run needed a fixture built for it, or it would have been vacuous

`load_bus_system()` is a positive control, not a convenience. On every fixture the
repo shipped before M5 the detailed tier's headline check has **no content**: with
`Ra = 0` and no `Load`, the air-gap power equals `P0` exactly for every non-slack
machine, so `Pm := Pe` (correct) and `Pm := P0` (the bug) are indistinguishable and
the flat run would come out flat either way — passing against the very bug it
exists to catch, which is the failure mode this repo has hit repeatedly.

With a load it has content: the slack settles at `0.65427` against a scheduled
`0.7`, because the load at `|V| = 0.979` draws `1.054` rather than `1.100`. The
positive control is therefore **the real bug** rather than a stand-in, and it makes
the run diverge by 6.6 rad with `f_coi` moving 0.157 Hz.

**An honest limit, recorded rather than glossed.** The plan says "assert per state,
never on `f_coi`" — and at step 1 `f_coi` *would* have caught this. The per-state
form is required for step 2's flux states, where a wrong `E′d` rings a voltage and
leaves frequency flat. The test asserts both halves so the claim is dated instead
of assumed to have always held.

## D16 — The re-initialisation needed a THIRD static mode, because step 1's is a statement about a machine at rest

Step 1 built `_static_network` with two modes and called it "one static network,
two jobs": `_PF_SOLVE` (the machine holds its scheduled power, `δ` is the unknown)
and `_PF_PIN` (the rotor angle is held, the power is whatever the network gives).
`_reinitialise_algebraic!` used `_PF_PIN` for every machine after an event.

Both modes represent the machine as a **steady-state source** — a q-axis voltage
`Ẽ = E∠δ` of *fixed magnitude* behind `(Ra + jXq)`. That is a statement about a
machine at rest, and it is exactly what makes the power flow closable. It is also
**false mid-transient** as soon as the flux is allowed to move: after a swing the
machine's internal voltage is `(E′q, E′d)`, and `|Ẽ|` is no longer `Machine.E′`.

So step 2 added `_PF_HOLD`: the machine's **actual stator algebra** at the held
`(δ, E′q, E′d)`, with the same `δ − δ_target` residual. At the frozen-flux
degeneration the two modes agree exactly, which is why step 1's version was not
wrong — only narrower than it looked. Worth recording as its own decision because
the alternative (a second static network for the re-initialisation) would have put
the network equations in a third place, and the header of `detailed.jl` argues
against exactly that.

## D17 — The classical tier had to grow a DATA precondition, which the plan did not name

D3 moved three *structural* preconditions out of the `NetworkModel` constructor and
into `SwingEngine`. Step 2 needed a fourth guard of a different kind, and nothing in
the plan asked for it: once `Machine` can carry `(Xd, Xq, X′q, T′do, T′qo, Ra)`,
**nothing at the classical tier reads any of them.** That tier *is* the frozen-flux
limit — a constant-magnitude `E′` at the bus — so a machine with real synchronous
reactances handed to `SwingEngine` or `coi_model` would run as a different machine
than its data describes, silently, and produce a plausible answer.

`_assert_frozen_flux(net, who)` refuses it by name, next to
`_assert_one_machine_per_bus` and in the same shape. The condition is exactly
`Machine`'s default, so no pre-M5 model notices it exists.

**`Ra` is in the list even though it does not change the degeneration's dynamics**,
and the reason generalises: it changes the *initialisation*, because the air-gap
power exceeds the terminal power by `Ra·|I|²`. A model carrying it is therefore
dispatched differently at the two tiers. Dropping data quietly is the failure;
whether the drop is numerically large is a different question the guard does not
ask.

**Owed, and named rather than left silent:** `reference/src/oracle.jl`'s
`build_oracle` has no such guard. It compiles `Library.Swing` from `ma.E` and
`ma.Xd′` and would ignore detailed data the same way. Step 3 adds the
`:sauer_pai` tier there and is where that guard belongs.

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

### What step 0b measured (2026-09-06)

**Done, at 1873/1873 on both sides.** Nine files: `helpers.jl` at top level, then
`scaffold`, `m1_frequency`, `orchestration`, `m2_network`,
`m3_governors_protection`, `m2_events_and_coi`, `m3_two_area`, `m4_playback`
included, in that order, inside the one outer testset. `m5-tasks.md` step 0b carries
the findings; three of them change how a later step should be run.

**The plan's own instruction was self-contradictory, and the contradiction was the
finding.** "One file per milestone, in the same order as today" cannot both hold:
M3 inserted its steps 1-5 *ahead of* M2's tail, so the line-trip block `89c7074`
appended at the end of M2's tests now sits 1,600 lines further down than M3's newest
test. The order was kept and the milestone grouping given up, because reordering
execution is the one change a test count cannot attribute. M2 and M3 therefore have
two files each. Regrouping stays available as a later commit that *only* reorders.

**The count is a weaker gate than D9 assumed, and the anti-vacuity run measured how
much weaker.** With one `include` removed the suite reported 1811/1811, exited **0**
and printed `Testing GridSim tests passed`. A green suite does not distinguish "all
1873 ran" from "1811 ran and 62 silently did not". So the move was emitted
mechanically from a table of line ranges and gated on a **reconstruction check** --
reassemble the pre-split file from the split files on disk and diff. 4,892 content
lines byte-identical. That check, not the count, is what makes "pure move"
a claim rather than an assurance.

**Two Julia facts the split rests on**, both now written into `runtests.jl`:
`include` evaluates at *module* top level regardless of where the call sits (so the
helpers *had* to be hoisted -- the README's trap, confirmed), and `@testset` nesting
is *dynamic* via a task-local stack (so testsets in included files still register
under the outer one and the summary stays a single tree).

**Hoisting is a collision hazard both ways**: inside the testset the fifteen helpers
were locals, which silently *shadow* an import; at module scope the same name
*collides*. Checked against `names(GridSim)`, `names(Test)` and `names(Base)` --
none. Worth re-running whenever a helper is added, for the reason the GLMakie export
check exists.

**A line-ending trap, and it would have destroyed the evidence.** `.gitattributes`
says `* text=auto eol=lf`, so a checkout gives LF -- but the working copy was CRLF,
and `text=auto` normalises on comparison, so `git status` called it clean. A split
generated from the stale copy is a whole-file diff, which is precisely the diff the
gate needs to be readable. Generate from the checked-out form; take the line ending
from the source.

**S3's measurement needs a quiet machine, and this one was not.** Four runs of
suites with *identical* content took 1m25, 2m28, 5m15 and 1m46, tracking an
unrelated long-lived `julia.exe`. No timing claim is made about the split -- and
**S3 (D10) is a wall-clock measurement that decides D2**, so it must be taken with
the contending processes checked first, or D2 gets decided by noise.

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

### All three resolved (S3 in step 1, S1 and S2 in step 3, 2026-09-06)

**S1 — `T′ = Inf` IS expressible, so the fallback is not needed.** `mtkcompile`
accepts `Inf·Dt(E′q) ~ rhs` and the derivative comes out exactly zero. The
convergence ladder that was to have been the fallback is kept as the spike's own
positive control instead: with the flux equation made live (`X_d = 1.8`), the drift
over a 2 s horizon is 3.547e-9 at `T′ = 1e8`, 3.547e-7 at 1e6 and 3.548e-5 at 1e4 —
a clean `1/T′` law — while `Inf` gives 0.0. **The first form of the spike was
vacuous**: run at the degeneration, where `X_d = X′_d` makes the right-hand side
identically zero, `E′q` holds for every `T′` and nothing is established.

One qualification the step then measured: `T′ = Inf` freezes the *equation*
exactly, but on a three-machine ring the trajectory still drifts by one ulp
(2.2e-16), because a differential state with a zero Jacobian row still sits inside
the implicit solver's Newton system. **Our own side drifts by the identical
amount**, so it is a property of stiff integration rather than of PowerDynamics —
and it is the same cause as the two "reaches nothing" controls not being
bit-identical. `===` is not available for a decoupled state inside an implicit
solver, adaptive stepping or not.

**S2 — the bounds are metadata, not enforced, so no precondition is added.** A
machine built with `τ_m_set = −0.5` compiles, solves, and returns `τ_e = −0.316`
straight through a variable declared `bounds = (0, Inf)`. This mattered more than
it looks: **every** fixture in the repo balances with a negative-`P0` machine, so
if the bounds had bitten there would have been no runnable case at all and the
question would have become a scope decision rather than a guard.

**And the argument that M4 had already answered S2 was reading the wrong
component.** `ClassicalMachine`'s `τ_m_set` carries no bounds at all;
`SauerPaiMachine` adds them to `vf_set`, `τ_m_set`, `vf`, `τ_m` and `τ_e`. Same
authors, same library, different declarations — the same shape as the torque
finding in `m5-prestudy.md` §2a, and the reason that section says to READ the
source rather than carry an answer across.

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

## D18 — The flux closed form's precondition is the LOADING, not the inertia (measured, step 4)

The Heffron-Phillips constant `T′d = T′do·(X′d + Xe)/(Xd + Xe)` is derived with the
rotor angle **held fixed**. The plan did not say how to hold it, and the obvious
answer — a very large `H` — is wrong, which cost a measurement to find out and is
worth writing down because the same reflex will come back for the regulator's
closed form in step 5.

**Why large `H` does not work.** After a field-voltage step the rotor's *new
equilibrium* angle is `ΔP/K_syn`. There is no `H` in that expression. A heavier
rotor takes longer to travel there — the swing period goes as `√H` — but over a fit
window of a few `τ` the angle has still moved by the same order. Measured across a
**64× range**: the fitted constant's error is +21.8 % at `H = 200` and +25.8 % at
`H = 12800`. A contamination that scaled as `1/H` would have fallen by 64×.

**What does work: zero loading.** At `P0 = 0` the whole solution sits on the real
axis. `δ ≡ 0`, so `Iq ≡ 0`, so `E′d ≡ 0`, so `Pe ≡ 0` — the swing equation has
nothing to integrate and the rotor is *immobile* rather than merely heavy. The law
is then exact rather than approximate: fitted against predicted to **3e-9** at
`reltol` 1e-9 and 3e-6 at 1e-6, with `|δ|` at zero to the bit. `infinite_bus_system()`
therefore defaults to the unloaded case, and the loaded one is a **boundary test**
(the error must survive 64× the inertia) rather than a second closed form.

**And a sub-finding that is really a naming trap.** The first pass read
`|δ_G1 − δ_G1(0)|`, saw 2.8e-3, and concluded the rotor was pinned. It was not: the
*infinite-bus machine's own* rotor had moved 1.4e-2. An infinite bus built out of a
machine has a rotor, and the angle in the law is the **relative** one. The 21 %
error is quantitatively what that excursion predicts, which is what turned a
puzzling number into an identified one.

**What the unloaded fixture therefore does NOT check**, asserted rather than
implied: at `δ ≡ 0` the q axis carries no current, so `T′qo` and `(Xq − X′q)` are
multiplied by zero here exactly as `(Xd − X′d)` was in step 2's frozen limit. Ten
times `T′qo` moves nothing. The q-axis flux is checked by the `T′ → 0` limit and by
PowerDynamics, and by nothing in the closed form.

## D19 — Three oracles for one equation, and they resolve it four orders apart

Step 4 gives the flux equations three checks, and the plan implicitly treated them
as interchangeable evidence. They are not, and the ledger now records the
difference:

| oracle | resolves a wrong `T′do` / `(Xd − X′d)` at | what limits it |
|:---|:---|:---|
| closed form (`test/`) | **1e-4** | the fit, agreeing at two tolerances |
| `T′ → 0` limit (`test/`) | ~1 % on `Xd` | the linear-in-`T′` residual it measures |
| PowerDynamics (`reference/`) | ~10 % | **the stator-`ω` residual, not solver noise** |

The external check's honest `E′q` gap is 1.56e-5 — 304 bands, so not noise: it is
step 3's `(ω − 1)·V` residual arriving on the flux channel through `Id`. A 1 % `Xd`
error only doubles it. So the newest and most impressive-looking oracle is the
**least** sharp of the three on these equations, and a closed form — the oldest and
cheapest technique in the repo — is four orders better. That is not an argument for
dropping the external one: it is the only check that a *different implementation*
agrees, and it is the only one of the three that would catch an error the closed
form and the limit share. It is an argument against reading "checked externally" as
"checked tightly", which is exactly what `m4-context.md` D7 means by the oracle
being a floor and not a ceiling.


## D20 — A step-rejecting domain guard and a saturation in the derivative do not compose (measured, step 5)

**The plan asked for `isoutofdomain` to gain two indices per machine, for the reason
`ΔPm` has one. It was written, and it kills the run.**

The guard accepts a proposed step only if the state lands at or below
`limit + 1e-10`. Above the limit the saturated derivative is zero, so the limit is
not something the solution crosses — it is a point the solution has to LAND on. As
the state closes on it, the derivative there is still finite (83 pu/s for this
exciter), so a step of size `h` overshoots by `≈ 83h` and must be under `1.2e-12` to
be accepted. Take that step and the state is closer still, and the next must be
smaller again. **The acceptance window is narrower than the precision with which a
step can be aimed**, so it shrinks geometrically and the run dies.

Measured on `regulator_bus_system(; Efd_max = 0.95)` with a line trip at 1 s,
Rodas5P at reltol 1e-9:

| | outcome |
|:---|:---|
| guard on, `K_A = 200`, `T_E = 0.05` | MaxIters at t = 1.0021, `dt` = 9.1e-11 |
| guard on, `K_A = 50`, `T_E = 0.2` | MaxIters at t = 1.0361, `dt` = 1.7e-09 |
| guard on, `K_A = 20`, `T_E = 0.5` | MaxIters at t = 1.2560, `dt` = 1.5e-08 |
| guard off, same case | Success; `Efd` exceeds its ceiling by 3.4e-8, once |

In every failing run `Efd = 0.94999999…`: approaching from below, never arriving. On
a raw solve of the same right-hand side the guard accepted **199,944** steps without
reaching the limit.

**This falsifies a claim written in the repo.** `engines/swing.jl` says of its own
guard: *"During continuous integration it cannot stall, because the derivative is
already zero at the ceiling, which puts the solution at headroom, not above it."*
The derivative is zero at the ceiling; what does not follow is that the solution
gets there.

**But the engines that still carry the guard are not stalling, and the reason is one
number nobody chose.** A `SwingEngine` governor driven onto its headroom for 20,000 s
LANDS: `ΔPm` settles **3.1e-11 pu above** its ceiling and stays there, `dt` around
0.09 s. The overshoot a state produces on the step that lands is set by how fast that
state is — a 1 s governor lag needs 3e-11 and fits inside the absolute `1e-10` window
with 3× to spare; a 0.05 s exciter lag needs 5e-8 and does not fit at all. So
`SwingEngine`'s guard is inside its margin by a factor of three, on a constant written
for round-off. **Left alone deliberately**: changing it would move M2, M3 and M4
numbers, and that is not step 5's to decide.

**What bounds the state instead** is the thing that was always doing the work — the
saturation in the derivative. Above the limit the derivative is zero, so the state
cannot continue to rise, and the only excursion possible is the overshoot of the
single step that crosses. That number is asserted in `test/`, and it is a LOCAL-ERROR
effect rather than a constant: 5.3e-5 at reltol 1e-6 and 5.0e-8 at 1e-9, and the
ordering is what is asserted.

**What a domain guard is still right for** is the case M1 built it for: a limit that
MOVES, leaving the state stranded far outside it. That is a data problem, fixed at the
event boundary by re-initialising into the new limit. Our field-voltage limits are
constant model data and `init!` refuses a dispatch outside them.

**The leftover, also measured.** A hard saturation makes the right-hand side
discontinuous in the state it saturates, and a stiff adaptive solver is entitled to
find that hard. Swept over eight ceilings (1.05 … 3.0) at reltol 1e-9, seven complete
and `Efd_max = 1.2` does not — and it is isolated in the TOLERANCE too, completing at
1e-6 (overshoot 8.3e-6) and at 1e-11 (6.1e-10) and failing only at the 1e-9 between
them. Non-monotone in two parameters at once is conditioning at the kink, not a
boundary of the model. `FBDF` completes it (1.7e-9), and `init!` already takes a
`solver`, so the workaround is a parameter rather than a change.

## D21 — `Vref` is derived, and the open-loop reading of a setpoint error is wrong by 11x (step 5)

The plan listed the exciter's five parameters as `K_A, T_E, Efd_min, Efd_max, Vref`.
Four of them are model data; **`Vref` is not, and cannot be.** At a steady state the
exciter's own equation has one unknown left once the power flow has run
(`Vref = |V| + Efd/K_A`), so a setpoint supplied as data is a setpoint that does not
match the dispatch — the machine starts off its own equilibrium and every check
downstream measures a startup transient instead of the thing it names. This is the
`Pm`-from-the-power-flow rule (D15) one mechanism along, and it was not on the list.

**And the positive control corrected its own prediction.** "A `Vref` off by 0.01 pu
drives the field by `K_A·ΔVref = 2.0 pu`" is the open-loop reading and it is wrong by
11×: the loop closes through the network, because the extra field raises the terminal
voltage and cancels most of the error that produced it. The DC loop gain is

    G = K_A · dV/dEfd = K_A · Xe/(Xe + Xd) = 10.11

and the answer is `K_A·ΔVref/(1 + G) = 0.180 pu`, which lands to nine digits
(0.9660369472 predicted, 0.9660369472 measured). `dV/dEfd` is not a new constant — it
is the two closed forms this step already has, composed. It became the only check in
the milestone that reads `K_A` **inside** an equation rather than as a label.

**The same open-loop intuition then set two more thresholds, and both were wrong** —
which makes it a pattern rather than one slip, and worth naming as one:

- The external suite's anti-vacuity control said "doubling `K_A` must move their field
  voltage by more than 0.05". It moves it by **0.00575** (0.06499 → 0.07074), because
  doubling `K_A` doubles `G` too and `K_A/(1 + G)` is already near its ceiling. The
  threshold became the predicted difference at `rtol = 5e-3`.
- The clamp mutation's step-size signature said the endpoint flux error halves when
  `h` halves. It moves by **0.78** per halving, because by 24 s the voltage loop has
  closed around the clamped run as well and the endpoint is a settled observable. The
  signature moved onto the excess field, which is clean-linear in `h` over 40×.

The rule this step earned: **once a regulator is in the loop, no threshold may be
written from an open-loop gain.** All three that were, were wrong — by 11×, by 9×, and
by a factor that was not even the right *shape*.

## D22 — The exciter's external oracle cannot run on the exciter's own fixture (step 5)

`_assert_sauer_pai_tier` refuses a machine-free bus, and `regulator_bus_system`'s two
bare junctions — the third and fourth buses that make a second line trip survivable —
are exactly that. So the external comparison moved to `infinite_bus_system`, which has
two buses and two machines and no load.

Two buses means a line trip would island the machine, so the disturbance became a
**setpoint step**: a parameter on our side (`Vref_pidx`) and a parameter on theirs
(`gen₊avr₊vref`), needing no event type on either. That turned out to be a gift rather
than a compromise. At zero loading `ω ≡ 1` exactly on both sides, so the stator-`ω`
residual that held M5 step 4's external oracle to ~10 % (D19) **vanishes identically
here**, and the only difference left between the two models is the exciter's own extra
lag. The band is therefore derivable rather than measured: `Ta·(1 + G)/T_E` relative,
first order in `Ta`, and the check that matters is that halving `Ta` halves the gap.
**Run, it does**: the gap ratio at `Ta` = 0.001 against 0.0005 came out inside 15 % of
the predicted 0.5, and both gaps sat inside the derived band — a prediction confirmed
is worth more than a prediction alone, so both numbers are asserted, not just the band.

The LIMITED exciter is refused by name. `AVRTypeI`'s hard limits sit on the regulator
output `vr`, one block upstream of the field voltage, so our `Efd ∈ [Efd_min, Efd_max]`
has no counterpart at all; comparing them would be two different models and the gap
would be read as a fidelity finding. Its oracle is the closed form in the core suite,
which is four orders sharper than this comparison anyway — the same shape D19 found
for the flux.

## D23 — The load's singularity at zero voltage is NAMED, not softened (step 6)

A ZIP load with a constant-power share draws `I = (G + jB)·V·(a_z + a_i/|V| +
a_p/|V|²)`, which diverges as `|V| → 0`. The obvious response is a low-voltage
cut-over to constant impedance, which is what production load models do. **It is not
done here, and the reason is that the cut-over voltage is a parameter nobody has
chosen** — and step 7, whose whole subject is voltage collapse, is exactly the run
where a number picked for numerical comfort would change the answer it is supposed to
be measuring.

What is done instead is to record it: in `_load_current`'s docstring, in the ledger as
a stated boundary, and here. A load that draws constant power from a collapsed bus is
a model with no solution, and a divergent current followed by a clean solver failure is
that fact arriving rather than being hidden.

Three things make this the cheap choice rather than a brave one. **D20 already paid
for the alternative**: a step-rejecting domain guard does not compose with this
engine's construction, and reaching for `isoutofdomain` on a voltage would be
re-running a failure this milestone has already measured. **PowerDynamics made the same
call**: their `ConstantCurrentLoad` carries an explicit `ε` regularisation and their
`ZIPLoad` — the component step 6 is checked against — carries none, so the oracle
would not have accepted a regularised comparison anyway. And **the regime is not
reached in step 6's own runs**: the fixpoint starts flat at `|V| = 1` and every dynamic
run starts from the fixpoint. If step 7 does reach it, that is a finding, and it will
have a measurement behind it rather than a threshold in front of it.

## D24 — A settled system's frequency cannot carry a difference of equilibria (measured, step 6)

Step 5's F4b established that a settled observable cannot carry a rate. Step 6 found
the same edge from the other side, and it changes which channel a check may read.

The measurement: our engine built on a constant-impedance load, PowerDynamics' on a
constant-power one, same fixture, no disturbance. The two sides sit at **different
equilibria** — 8.1e-3 apart on a rotor angle, 4.0e-3 on the load bus voltage, against
the 1e-13 the honest comparison agrees to. And both runs are perfectly flat, because
each side is at rest at its own equilibrium. So every channel that can only report
MOTION reports agreement: `f_coi` reads 1.4e-14, which is exactly what it reads with
no mutation at all, and `ω`, `E′q`, `E′d` and `Efd` are all at round-off too.

**A load model wrong by 4 % in drawn power is invisible in frequency.** `f_coi` is the
default channel throughout `reference/test/runtests.jl`; on this comparison it is the
one channel that must not be used. Nor is every position channel safe — `δ_G1` is the
slack, pinned at zero on both sides by construction, and carries it no better (7.8e-14).

The rule this turns into: **a check on a quantity that differs only in WHERE the
system settles must read a position channel, and must name it.** The general form of
both findings is that "which channel the recorder looks at" is part of the claim, not
part of the plumbing — which is the third time in M5 that has decided red from green
(step 5's clamp mutation was the second).

## D25 — A mutation's magnitude is not its identity (step 6)

The anti-vacuity mutation written first for the ZIP wiring — the dynamic path drops
the shares the power flow honoured — produces +0.157 Hz and ~6.6 rad. Those are, to
three digits, the numbers step 1's `Pm`-from-the-schedule control already produces,
and running it is the only way that surfaced.

It is not a coincidence and it is not a bug. Both mutations create the same 0.046 pu
imbalance between what the machines inject and what the load draws; they differ only in
which side of that equality is the wrong one, and a trajectory cannot see that. So the
first mutation, run on its own, would have been a second copy of an existing control
wearing a new name — the exact shape of vacuity this milestone's standing rule exists
to catch, arriving inside the anti-vacuity check itself.

The mutation that does discriminate is the mirror image: the power flow solves a
constant-impedance load and the dynamic path draws constant power. Same 0.046 pu, other
direction, **−0.15616 Hz**. What is asserted is the SIGN, because the sign is the only
thing that separates the two bugs. Both are kept and both are labelled — the
indistinguishable one because saying so is the finding.
