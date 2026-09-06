# M5 — The detailed machine tier: voltage as a real unknown · Plan

Companion docs: `m5-context.md` (decisions and, as steps run, what was measured),
`m5-tasks.md` (the checklist). Layers on `docs/SPEC.md` §2–4 and the M1–M4 trios.

**This plan rests on `m5-prestudy.md` and deliberately does not restate it.** The
physics — the machine equations, the degeneration algebra, the initialisation
back-substitution, the `SauerPaiMachine` source reading — is worked there, and §8
of that file states its own boundary: *"what the trio should decide, not this
file."* So every physics claim below is a citation (`§2`, `§2a`, `§3`, …) into the
pre-study, never a second copy. Two copies of the flux equations in `docs/plans/`
would drift, and the pre-study is the one with the working. What this plan adds is
everything the pre-study does not cover: how the tier lands in *this repo* — which
types change, which engine, which half of the interface, in what order, gated on
what, and what gets cut if the milestone runs long.

## Goal

Build the tier the architecture has pointed at since M2 and named "M2b" in
`src/model/network_model.jl`'s own header: **bus voltages as genuine algebraic
unknowns**, machines with flux dynamics and a voltage regulator behind them,
initialised from a power-flow solution rather than from chosen angles.

Its purpose is one measurement, not a feature list. `m5-prestudy.md` §1 turns the
Iberian ceiling into a single relative criterion:

> On the two-area case, at the tie strength at which the **classical** tier loses
> synchronism at the report's cascade, the detailed tier must **both** lose
> synchronism **and** carry an export swing whose peak exceeds that tier's
> `P_max` — because the transfer is no longer bounded by a constant voltage
> product.

Everything before the last step exists to make that measurement attributable. It
is deliberately relative: the absolute 5,000 MW depends on inputs the ENTSO-E
report never states (`entsoe-iberia-reproduction.md` §2), the relative statement
depends only on the mechanism.

## What M5 is not

- **Not a sixth-order machine.** Ours is fourth-order (two-axis). PowerDynamics'
  `SauerPaiMachine` is sixth; at `X″ = X′` it becomes ours exactly
  (`m5-prestudy.md` §2a), which is what makes it an oracle. Sub-transient states
  are a later tier if anything ever needs them.
- **Not `PowerFlows.jl` / `PowerSystems.jl`.** Roadmap item 5 still owns those.
  The power flow here is `NetworkDynamics.find_fixpoint` on the static network
  (D7) — the tool the repo already owns, on the shape it already has.
- **Not AGC.** Out of scope since M3 (`m3-context.md` D3), still out.
- **Not, on present evidence, a real-time detailed tier.** See D2. Whether this
  tier steps in real time is an unmeasured question with a measurement attached,
  and this plan refuses to assume the answer in either direction.
- **Not inverter-based resources.** SPEC §7.6 names three lessons a fidelity
  overlay teaches — inter-machine swings, voltage coupling, IBR behaviour. M4
  delivered the first. M5 delivers the **second**. The third still has no tier.

## The order, and why it is the order

`m5-prestudy.md` §8 gives the sequence that keeps every discrepancy attributable
— D7's rule (`m4-context.md`) applied one level finer than M4 needed it. The steps
below are that sequence, with a repo-integration step in front of it and the
milestone's actual purpose at the end.

Each step commits, leaves the suite green, and carries its own gate. **No step is
"done" because it runs; it is done when its named check passes with a positive
control and an executed anti-vacuity mutation** — M3's standing rule, which caught
a real bug in M3 step 7 and another in M4 step 4.

### Step 0b — Split `test/runtests.jl` before adding a milestone to it

(Step 0 is planning — writing this trio — following `m4-tasks.md`'s convention.
The number is `0b` in all four files; an item carried under two names is the
failure this milestone's own step-0 box warns about.)

4,922 lines, one outer `@testset`. M5 adds roughly a milestone's worth of tests to
it. `docs/plans/README.md` §Structure notes already contains the plan and the trap:
the helpers (`ratio_ring`, `lockstep_coi`, `pb_both`, `overlay_pair`, …) are
defined *between* testsets inside the outer testset's local scope, so an `include`d
file would not see them. The split therefore means moving every helper to
`test/helpers.jl`, `include`d at top level, then one file per milestone in the
same order.

Refactor-before-feature, for M2's stated reason: **the old suite is the only
oracle**, so it gets restructured while it is still known-green rather than while
a new tier is moving underneath it.

**Gate:** the test *count* is identical before and after (1873 core), and the diff
is a pure move — no assertion text changes in the same commit. That count is the
check; a mechanical move that silently drops a testset is exactly the failure this
step could introduce.

### Step 1 — The algebraic network, the power flow, and the flat run

The formulation reversal (`m5-prestudy.md` §5, and a second independent argument
in §2a): bus voltages become algebraic states with `mass_matrix = 0` on the bus
vertex, solved by a stiff DAE solver. Machines sit on **terminal** buses.

Lands together because none of the three is testable without the others:

- a bus vertex model carrying `(V_re, V_im)` with Kirchhoff's current law as its
  residual;
- `NetworkModel` extended to express it — a load type, buses without machines, and
  the one-machine-per-bus rejection moved out of the constructor and into the
  classical engine as a precondition (D3);
- initialisation: `find_fixpoint` on the **static** network, then closed-form
  back-substitution of every machine state (`m5-prestudy.md` §4).

**Gates.**

1. The fixpoint is **checked, not trusted** (`m5-prestudy.md` §4): `|V| ∈ [0.9,
   1.1]`, branch flows below rating, residual `< 1e-10`. The M2 spike's lesson —
   `find_fixpoint` converges to whatever self-consistent solution the guess leads
   to — with the flat guess and the joint-solve trap both stated in the code.
2. **The flat run**, per state, at two tolerances: no disturbance, full horizon,
   every state constant to solver tolerance. Asserted **per state, never on
   `f_coi`** — a wrong `E′d` leaves frequency flat while the voltage rings. This
   is the check no overlay can perform, because both sides of an overlay share the
   same wrong start.
3. **Measurement S3** (D10): steps and wall-clock per simulated second on the
   two-area case, DAE against the classical tier. This is the number that decides
   D2, and it is taken here rather than assumed anywhere.

### Step 2 — The two-axis machine, and the frozen-flux degeneration

The machine of `m5-prestudy.md` §2, with the flux equations present but the
default parameters degenerating it (D4). The oracle is **internal**: at
`X′d = X′q` and `T′do = T′qo = ∞` the tier must reproduce `SwingEngine`.

**Stated in the plan so it is never later read as more than it is:** this check
validates the swing equation, the stator algebra, the rotor-frame rotation, the
network and the initialisation. It **cannot validate the flux equations at all**,
because they are switched off in that limit, and the anti-vacuity mutation M4's
plan proposed for it ("perturb one flux coefficient") is *invisible* here
(`m5-prestudy.md` §3). Step 4 owns the flux equations.

**Reconciliation, not a band.** Ours-classical puts `E′` at the bus; ours-detailed
puts it behind `X′d` on a terminal bus. Those coincide **only on a radial pair**,
through exactly the reduction `reference/src/oracle.jl` already implements as
`reduced_line_reactance` (`m5-prestudy.md` §7 point 1). So this internal
comparison runs on `two_machine_system()` only — and the meshed ring, which cannot
take the reduction, is nevertheless a valid case for the *external* oracle in step
3, because there both sides sit on terminal buses (§2a). The two comparisons have
opposite topology restrictions, which is worth knowing before either is written.

**Gate:** agreement to solver tolerance at two tolerances; anti-vacuity =
perturb the stator algebra (not the flux terms) and watch it go red.

### Step 3 — The external oracle, with flux switched off on both sides

PowerDynamics `SauerPaiMachine` at `X″ = X′`, entering `build_oracle` as a second
`tier` alongside `:swing`. Flux frozen on **both** sides, so the only residual left
is the stator-`ω` term of `m5-prestudy.md` §2a.

**That residual is identified by its signature, not absorbed into a band.** It is
`(ω − 1)·V`, first order in slip, exactly the shape D14 already proved this pair
can be pinned by. A band wide enough to hide it would also hide a real error of the
same size.

**Two spikes run first** (D10), because both are statements about someone else's
tooling and either can invalidate the step's design:

- **S1** — can PowerDynamics express the frozen limit at all? They write the
  *multiplied* form `T′d0 · Dt(E′q) ~ rhs`, so `T′ = Inf` is `Inf·ẋ ~ finite`,
  which `mtkcompile` is not obliged to accept. Fallback is large-but-finite with a
  `1/T′` convergence check (the residual falls a decade as `T′` rises one) —
  which is a *different* check from an exactness assertion and must be scoped as
  such.
- **S2** — what does MTK's initialiser do with `bounds = (0, Inf)` on `vf`, `τ_m`
  and `τ_e`? If the bounds bite, a machine absorbing at equilibrium fails to
  initialise for a reason that does not name itself, and the guard is a
  build-time precondition on the model, shaped like `_assert_governor_free`.

**The free positive control** (`m5-prestudy.md` §2a): `X_ls` is a parameter of
*their* component that survives nowhere in the degeneration, so varying it across a
run must leave every comparison channel bit-identical. If anything moves, the
degeneration did not take. It costs one extra solve and it tests the assumption all
three flux oracles rest on — the cheapest control in the milestone.

Their two sub-transient states are **seeded from our fixpoint** by the closed forms
in §2a, so a flat run still checks *our* initialisation rather than their power
flow (`m4-context.md` D5's argument, unchanged). A per-state flat comparison skips
those two: a state that drives nothing has no counterpart to be equal to.

### Step 4 — Flux on: three oracles for the equations step 2 could not see

- **The other limit.** `T′do, T′qo → 0` must reproduce the steady-state
  constant-`Efd` `(Xd, Xq)` machine. With step 2's frozen limit this brackets the
  flux equation from both sides.
- **The closed form.** Single machine on an infinite bus through `Xe`, regulator
  off: the field flux decays with `T′d = T′do·(X′d + Xe)/(Xd + Xe)` — the
  Heffron–Phillips `K₃T′do` constant, which pins `(Xd − X′d)` and `T′do` *inside*
  the equation. **The anti-vacuity mutation lives here**: perturb `(Xd − X′d)` and
  the measured time constant must move by the predicted amount.
- **External.** PowerDynamics with flux on. Because their component at `X″ = X′`
  *is* ours, the flux equations get an external check with the mechanism switched
  on, and do not depend on the frozen limit at all.

The *change* from step 3 to step 4 is the flux term, by construction — that is the
whole reason step 3 exists as a separate step.

### Step 5 — The voltage regulator

Static exciter, one lag, hard limits (`m5-prestudy.md` §2). The limits are
**saturations in the derivative** — the M1 carried-forward rule, and the same
construction PowerDynamics' `AVRTypeI` arrived at independently. `isoutofdomain`
gains two indices per machine for the reason `ΔPm` has one.

**A matched-fidelity comparison is not available for the limited exciter**, and
the plan says so rather than discovering it: `AVRTypeI`'s limits sit on the
regulator output `vr`, not on `Efd`, and it degenerates to our form only in a
limit (`Ta → 0`) that makes the run stiffer than the machine comparison. So:
unlimited exciter is compared externally; the **limit** is checked by a closed form
(a ceiling that holds and releases unaided) and labelled accordingly in the ledger.

### Step 6 — Voltage-dependent load

ZIP (`m5-prestudy.md` §6), constant-impedance as the default because that is the
case with the closed form (it folds into the admittance) and the case
PowerDynamics' `ZIPLoad` configures down to. Frequency-dependent load stays on the
machine until something measures the difference.

This is the step that lets voltage actually *fall*, and it is the last mechanism
the exit criterion needs.

### Step 7 — The criterion

The measurement in §Goal, on the two-area case, run as a sweep over tie strength
in the shape M3 step 6 established: the classical tier's slip boundary located
first, then the detailed tier run at that same tie strength.

**It ships a positive control and an anti-vacuity control like everything else**,
and the anti-vacuity one is specific: freeze the voltages (constant-`E′`
degeneration, step 2's configuration) and the criterion must **fail** — because
that is the classical tier, and the classical tier provably cannot satisfy it.
If it passes with voltages frozen, the criterion is not measuring what it claims.

Every number lands in `entsoe-iberia-reproduction.md` under §7.3's discipline: a
tuned parameter is not a result (§7.3's own recorded failure), and the report's
`[GUESS]` inputs are marked as such.

### Step 8 — The voltage-visible window

M4's plan made a promise on this milestone's behalf, in writing: *"Voltage
coupling and inverter behaviour need a tier that has voltage in it, and that is
M5."* Step 8 keeps the voltage half of it — a **playback** overlay showing bus
voltage magnitude alongside frequency, over the classical/detailed pair, on the
scrubbable window M4 step 3 already built.

Playback, not real-time, and that is D2 rather than a shortcut. `smoke_render`
offscreen first, then the live window; render before claiming.

## The size decision, taken openly

M4's plan said this tier is *"plausibly larger than M2 and M3 combined."* Nine
steps is a large milestone and pretending otherwise would repeat the mistake M4
avoided by splitting. So the cut line is stated **now**, before any of it is
built, rather than discovered at step 6:

| | |
|---|---|
| **Cannot be cut** | Steps 0b–4, 6, 7. The tier is not validated without 1–4, and without 6 the criterion in §Goal has no mechanism to satisfy it — M5 would have bought nothing on the case it exists for. |
| **Cut first, if the milestone runs long** | Step 8 (the window). It slips loudly, into its own small batch, and the promise it inherits is restated there rather than dropped. |
| **Cut second** | Step 5 (the regulator), *provided* step 6 lands — voltage-dependent load alone is enough to make voltage fall. The exciter then becomes M6's opening step. |
| **Already out** | Real-time stepping of this tier (D2), the meshed ring as an *internal* comparison case (impossible, step 2), IEEE 9-bus (needs `PowerSystemCaseBuilder`, roadmap item 5), the sixth-order machine. |

The one thing that must not happen is a step landing with its gate weakened
because the milestone is running long. A cut step is honest; a step with a band
widened to fit is the failure mode `entsoe-iberia-reproduction.md` §7.3 exists to
document.

## Standing rules carried forward

Unchanged from M3 and M4, restated because each was earned:

- **Every check ships a positive control and an anti-vacuity control, and the
  mutation is RUN, not described.** M3 step 7 and M4 step 4 each found a real bug
  that way; five planned M3 checks would each have passed against the very bug
  they targeted.
- **Two tolerances.** A number below the solver's own tolerance is not a result
  until it survives the tolerance changing.
- **The band is written before the gap is seen.**
- **A residual is identified by its signature, not bounded by a tolerance.**
- **Every long-running test self-terminates on a fixed step count, never on a
  condition.**
- **`docs/validation-ledger.md` gains a row per mechanism**, with its label —
  including `un-oracled` ones, stated out loud. Unmarked is the only sin.
- **The oracle is a floor, not a ceiling** (`m4-context.md` D7). Exceeding
  PowerDynamics is permitted work; exceeding it silently is not.
