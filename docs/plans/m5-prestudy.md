# M5 pre-study — the detailed tier, worked on paper before it is planned

**What this is.** `m4-plan.md` says M5's plan trio gets written when M4 lands,
informed by what the oracle harness costs. That still holds; this is not the trio.
It is the *physics and numerics* of the detailed tier worked out in advance —
derivations, not measurements — so that the trio, when written, is written from
these and from M4's measurements rather than from memory. Nothing here was
executed. Where a claim needs a measurement, the measurement is named.

**Why now.** Three of the M4 plan's own "what M5 already knows it must do" bullets
are stated in a way that would pass against a wrong model (§3 below), and the
Iberian exit criterion that justifies M5 at all (`entsoe-iberia-reproduction.md`
§7.3 d) has never been turned into a number a test could assert (§1). Both are
cheaper to fix on paper than after a milestone is scoped around them.

Conventions as everywhere in the repo: per unit, machine data on the machine base
converted once (`machine_arrays`), `ω` a per-unit speed deviation, `δ` in radians,
`ω₀ = 2πf₀`.

---

## 1. The hurdle, as one measurable exit criterion

The classical two-area model reproduces the Iberian separation **or** the ≈5,000 MW
export swing, **never both** (§7.3 d): the swing peak on a constant-voltage tie *is*
`P_max = E′₁E′₂/X`, and a `P_max` large enough to carry 5 GW is one that never
slips a pole at the report's cascade. The report says the surge rode on collapsing
voltages across ES–FR, ES–PT and ES–MA. So the exit criterion for M5 is:

> On the two-area case, at the tie strength `P_max` (constant-voltage
> equivalent) at which the classical tier loses synchronism at the report's
> cascade, the detailed tier must **both** lose synchronism **and** carry an export
> swing whose peak exceeds `P_max` — because the transfer `|V₁||V₂| sin θ / X`
> is no longer bounded by a constant product.

Two consequences shape the tier:

- Voltage magnitude must be a genuine unknown at the tie's ends, so the tie must
  connect **terminal buses**, not internal `E′` nodes. That is the algebraic
  network of §5, and it is why M2a's "one machine per bus, `E′` at the bus"
  cannot be extended — it has to be replaced at this tier.
- Something must make voltage *fall*: flux decay under heavy reactive demand
  (§2), a regulator hitting its ceiling (§2), and voltage-dependent load (§6).
  Without at least one of those the detailed tier's voltage stays near 1 pu and
  the ceiling of §7.3 (d) survives, and the milestone will have bought nothing on
  the case it exists for. **The flat "does the swing exceed `P_max`" run at
  matched fidelity is the first thing to measure, before any regulator tuning.**

This is deliberately a *relative* criterion (exceeds `P_max`), not "reproduces
5,000 MW". The absolute number depends on `[GUESS]` inputs (`KE_CE`, corridor
reactances) the report never states; the relative one depends only on the
mechanism.

## 2. The machine: two-axis model with a regulator

Standard fourth-order (two-axis / "E′q, E′d") machine plus the swing states,
Sauer–Pai convention, stator resistance `Ra` kept (it costs nothing and its
absence is a common source of a 1–2 % initialisation mismatch against another
implementation):

```
dδ/dt    = ω₀ ω
2H dω/dt = Pm − Pe − D ω
T′do dE′q/dt = −E′q − (Xd − X′d) Id + Efd
T′qo dE′d/dt = −E′d + (Xq − X′q) Iq

Vd = E′d + X′q Iq − Ra Id            # stator algebra, rotor (d,q) frame
Vq = E′q − X′d Id − Ra Iq
Pe = E′d Id + E′q Iq + (X′q − X′d) Id Iq
```

with `(Vd, Vq)` the terminal voltage in the rotor frame, obtained from the
network's bus voltage `V∠θ` by `Vd + jVq = V e^{j(θ − δ + π/2)}` (q-axis leads the
rotor angle by the usual `π/2`; pick one convention and assert it — §7 lists the
test that catches the other). `Id, Iq` follow from inverting the stator algebra
given `(Vd, Vq, E′d, E′q)`.

Exciter, simplest useful form (static, one lag, hard limits):

```
T_E dEfd/dt = −Efd + K_A (Vref − V),   Efd ∈ [Efd_min, Efd_max]
```

The limits are **saturations in the derivative**, exactly as the governor
headroom is (the M1 rule carried forward): at a limit with the derivative
pointing outward, `dEfd/dt = 0`; never clamp the state. The step-rejecting
`isoutofdomain` predicate gains two more indices per machine for the same reason
`ΔPm` has one.

Mechanical side unchanged from M3: `Pm = Pm₀ + ΔPm + ramp`, droop and headroom as
built. AGC stays out (D3, M3).

**Per-unit hazard, named now.** `Xd, Xq, X′d, X′q, Ra, H, D` on the machine base;
`T′do, T′qo, T_E` in seconds (base-free); `Efd` on the machine's field base as the
data sheet gives it. `machine_arrays` grows columns; nothing else converts.
Reactances scale **inversely** with `S_rated/S_base` — the `Xd′` row in
`machine_arrays` already does this and is the template.

## 3. The degeneration oracle, stated correctly

`m4-plan.md` says the classical limit is three conditions together: constant field
voltage, `X′d = X′q`, no damper winding. **Two of those are wrong for the model
above, and the check as written would pass against a wrong flux equation** —
which is precisely the failure it was meant to prevent.

- *Constant `Efd` does not freeze `E′q`.* With `Efd` constant and `T′do` finite,
  `E′q` relaxes toward `Efd − (Xd − X′d) Id`, which moves with loading. That is
  the classic **field-flux decay**, the mechanism that reduces synchronising
  torque in the seconds after a disturbance — a *physical effect*, not the
  classical model. A test that only held `Efd` constant would compare a
  flux-decaying machine to `SwingEngine` and read a genuine difference as a bug,
  or set a band wide enough to hide it.
- *"No damper winding" is not a condition of a two-axis model.* Dampers are the
  sub-transient states (`E″`); a two-axis model has none. The condition is only
  meaningful if M5 ships a sixth-order machine, in which case it reads
  `X″ = X′` and `T″ → ∞` alongside the conditions below.

The exact classical limit of the two-axis model is **frozen flux**:

1. `X′d = X′q = X′` — so the stator algebra collapses to a single internal phasor
   `E′ = E′d + jE′q` behind `jX′` (the cross term `(X′q − X′d) Id Iq` vanishes),
2. `T′do = T′qo = ∞` — so `dE′q/dt = dE′d/dt = 0` identically and `E′d, E′q` keep
   their initial values in the rotor frame,

whence `|E′|` is constant and `∠E′ = δ + const`, which is the classical machine.
`Efd` then multiplies `1/T′do = 0` and is irrelevant; the regulator may be on or
off. In code `T = Inf` is fine: `(finite)/Inf = 0.0` exactly, and the fixpoint
solve sees a zero derivative rather than a `0/0`.

**What that oracle checks and what it cannot.** So configured, the detailed tier
must reproduce `SwingEngine` — *after* the `E′`-behind-`X′` vs `E′`-at-the-bus
reconciliation of §7 — to solver tolerance at two tolerances. That validates the
swing equation, the stator algebra, the `(d,q)` rotation, the network, and the
initialisation. It **cannot validate the flux equations**, because they have been
switched off, and the plan's proposed anti-vacuity mutation ("perturb one flux
coefficient") is therefore *invisible* in this limit. The flux equations need
their own oracles, all three cheap:

- **The other limit.** `T′do = T′qo → 0` (in practice `1e-3` s with a stiff
  solver) must reproduce the *steady-state* machine `E′q = Efd − (Xd − X′d) Id`,
  `E′d = (Xq − X′q) Iq`, i.e. the constant-`Efd` `(Xd, Xq)` model. The two limits
  bracket the flux equation from both sides.
- **The flux-decay time constant, closed form.** Single machine, infinite bus
  through `Xe`, regulator off: a small step in `Pm` decays the field flux with
  `T′d = T′do · (X′d + Xe)/(Xd + Xe)`. This is the Heffron–Phillips `K₃T′do`
  constant, textbook, and it pins `(Xd − X′d)` and `T′do` *inside* the equation.
  The anti-vacuity mutation lives here: perturb `(Xd − X′d)` and the measured time
  constant must move by the predicted amount.
- **External**: PowerDynamics `SauerPaiMachine` at matched parameters, once the
  M4 step-4 harness exists (D7: matched fidelity first, then switch things on).

The M4 plan bullet should be corrected to the above when the M5 trio is written;
`m4-tasks.md` carries the pointer.

## 4. Initialisation from a power flow, and the flat-run test

Given the network solution at a machine's bus — `V∠θ` and the injected `P + jQ`
(system base; convert to machine base with `1/w`) — every machine state follows in
closed form, and the check is that the RHS is zero before the first step:

```
I  = (P − jQ) / conj(V∠θ)                       # terminal current phasor
Ẽ  = V∠θ + (Ra + jXq) I                          # lies on the q-axis
δ₀ = angle(Ẽ)
(Vd + jVq) = (V∠θ) · e^{−j(δ₀ − π/2)};  (Id + jIq) likewise
E′q = Vq + Ra Iq + X′d Id
E′d = Vd + Ra Id − X′q Iq
Efd = E′q + (Xd − X′d) Id
Pm  = Pe = E′d Id + E′q Iq + (X′q − X′d) Id Iq   # (+ Ra |I|² if Pe is defined at the terminal)
Vref = V + Efd / K_A                             # static exciter at rest
ω = 0, ΔPm = 0
```

**The flat-run test** (from the M4 plan, kept): no disturbance, full horizon,
every state constant to solver tolerance at two tolerances. A mis-initialised
model opens with a transient nobody injected, and no overlay catches it because
both sides of an overlay would share the same wrong start. Assert *per state*,
not on `f_coi` — a wrong `E′d` can leave frequency flat while the voltage rings.

**Where the power flow comes from — not a new solver.** The bus voltages are the
steady state of the algebraic network with each machine replaced by its scheduled
`P` (PV bus) or `P + jQ` (PQ bus) and one slack. That is a nonlinear system on a
sparse structure, and the repo already owns the tool for exactly that shape:
`NetworkDynamics.find_fixpoint` on a network whose vertex models carry the
algebraic bus equations (`mass_matrix = 0`). NetworkDynamics assembles the
residual edge by edge, so **no admittance matrix is ever formed** — sparse from
day one holds by construction, as it does for `SwingEngine`. Two cautions the M2
spike already taught: `find_fixpoint` converges to *whatever* self-consistent
solution the initial guess leads to, so the guess is a flat start (`V = 1`,
`θ = 0`) and the solution is checked (`|V| ∈ [0.9, 1.1]`, branch flows below
rating, residual `< 1e-10`) rather than trusted; and the fixpoint solve is run on
the **static** network first and the machine states are back-substituted from it
(above), never solved jointly with the dynamic states from a flat guess — the
joint problem has spurious equilibria (a machine at `δ + π`) that look converged.

`PowerFlows.jl` stays out (roadmap item 5 owns it, and it pulls `PowerSystems`).
The two-area and three-machine cases need nothing it offers.

## 5. Network formulation — reversing the M4 plan's default, with the reason

The M4 plan chose "dynamic RL branches, not the algebraic constraint", to keep an
ODE, and asked whoever reverses it to say what happens to `isoutofdomain` and the
step-rejecting protection. Worked, both options:

**Dynamic RL branches** carry `di/dt = (V_i − V_j − R i)/L` per branch — but the
bus voltages `V_i` are then *still algebraic* unless every bus is given a shunt
capacitance to integrate `dV/dt = (Σ i)/C`. With real `C` (line charging, a few
percent) the bus time constants are microseconds against swing dynamics of
seconds: a stiffness ratio of `1e5–1e6`. `Tsit5` would take steps set by the
fastest capacitor, real-time stepping is gone, and an implicit solver is needed
anyway. Inflating `C` to tame it changes the physics the tier exists to capture
(the voltage response). Dynamic branches keep the *letter* of "an ODE" and lose
its point.

**Algebraic bus voltages** — a DAE with a mass matrix. `VertexModel` takes
`mass_matrix`; a bus vertex carries `(V_re, V_im)` with zero rows, its residual
being Kirchhoff's current law summed over incident edges, and a machine's terminal
current is what its stator algebra produces from `(V, E′, δ)`. Index-1, solved by
`Rodas5P` or `FBDF`. What survives unchanged, checked against how each piece is
built today:

- `isoutofdomain` is applied at step acceptance by the generic stepping loop, not
  by the explicit-RK path; a rejected step on a Rosenbrock/BDF method retries with
  a smaller `dt` exactly as now.
- `ContinuousCallback` root-finding works on the interpolant of any solver with
  dense output; Rosenbrock methods have one (`calck` semantics unchanged).
- `step!(integ, dt, true)`, `add_tstop!`, `add_saveat!`, `inject!`'s
  `derivative_discontinuity!` / `auto_dt_reset!` are all solver-agnostic.
- The recorder and `_record_at!` read `u`; algebraic states are in `u`.

What changes: **the solver class and the cost per step** (a sparse linear solve
per stage; NetworkDynamics supplies the Jacobian sparsity), and one new failure
mode — after a discontinuity (a trip) the algebraic states must be **re-solved for
consistency** before stepping resumes, which is the "re-init algebraic state for
the network tiers" SPEC §6 predicted. `inject!` at this tier therefore ends with a
consistent-initialisation call, and the flat-run test is re-run *across an event*
(trip a line on a system whose post-trip equilibrium is known, assert no spurious
transient beyond the physical one).

So the recommendation is the reverse of the M4 plan's default: **algebraic
network, stiff solver, the classical tier keeps `Tsit5`.** The measurement that
decides it, on the two-area case at matched fidelity, is steps per simulated
second and wall-clock per simulated second for both formulations — the number the
M4 plan's last bullet ("better than PowerDynamics needs a named axis") asks for
anyway. If the DAE is not real-time steppable on a two-area case, the tier is
playback-only there, which the mode router was built for.

## 6. Loads

M2a's "a load is a machine with negative `P0`" cannot survive a tier whose point
is voltage: a rotating mass at constant `E′` holds voltage up by construction. The
detailed tier needs a load model at the bus, and the one that produces voltage
collapse with the fewest parameters is the ZIP load
`P = P₀(a_z V² + a_i V + a_p)`, `Q` likewise — constant-impedance (`a_z = 1`) as
the default, because it is the case with the closed form (it folds into the
admittance) and the case PowerDynamics' `ZIPLoad` can be configured down to.
Frequency dependence of load (`D`) stays where it is, on the machine, until
something measures the difference.

## 7. The external oracle for the swing tier (M4 step 4) — what to settle *before* the band

This is M4's step, not M5's, but the derivation belongs with the machine
conventions above. Three questions decide whether PowerDynamics' `ClassicalMachine`
and `SwingEngine` are the same model, and each has a test that answers it before
any band is written down:

1. **`E′` behind `X′d` vs `E′` at the bus.** PowerDynamics' machine sits behind
   its transient reactance on an algebraic bus; ours puts `E′` at the bus with
   `K = E′ᵢE′ⱼ/X_ij`. These coincide **only on a radial pair**, by reducing the
   PowerDynamics line to `X_line = X_ours − X′d,ᵢ − X′d,ⱼ` (system base). On
   `two_machine_system()`: `X′d` = 0.25 on 250 MVA → 0.100 and 0.30 on 400 MVA →
   0.075 on the 100 MVA base, so `X_line = 0.25 − 0.175 = 0.075` — positive, so
   the reduction exists. On `three_machine_ring()` it does not (every machine has
   degree 2; `model/network_model.jl` point 2), so the ring is **not** a valid
   oracle case for the classical tier and must not be used as one.
2. **Damping convention.** `D ω` with `ω` per unit, or `D Δω` with `Δω` in rad/s,
   or `D (ω − 1)`: three conventions differing by `ω₀`. Discriminate with a
   damping-only closed form before comparing anything else — one machine against
   an infinite bus, small `Pm` step, the envelope decays at `D/(4H)` (pu
   convention); a factor `2π·50` apart is not a band, it is a different model.
3. **`H` base.** Machine base or system base. Discriminate with the initial RoCoF
   after a trip, which the aggregate tier already pins in closed form.

Then the band, **derived**: `3 · max(reltol_ours, reltol_PD) · excursion`
(`tolerance_band`, the M4 step-1 argument: two independently error-controlled
paths), **plus** the initialisation offset — PowerDynamics initialises from its
own power flow to a residual `ε`, ours from `find_fixpoint`; on a radial pair the
angle offset is `≈ ε/K`, which at `ε = 1e-8` is far below the solver term and can
be *stated* as negligible rather than absorbed into a wider band. Compare angle
**differences** only (gauges differ), and `f_coi` — computed on our side from
PowerDynamics' per-machine speeds with *our* `H` weights, so the comparison is
inertia-weighted mean against inertia-weighted mean and not one machine against
an aggregate.

The positive control (agreement when agreement is real, inside that band) and the
anti-vacuity control (perturb one coefficient in `swing_vertex!`; the check must
go red) are as `m4-tasks.md` lists them. One addition: **run the three convention
tests against PowerDynamics with the wrong convention deliberately** once, so the
harness is seen to reject a wrong mapping and not only to accept the right one.

## 8. Cost and sequencing — what the trio should decide, not this file

- Two-area first (the exit criterion of §1 is a two-area statement), the ring
  second (meshed, the case with no closed form), IEEE 9-bus only if
  `PowerSystemCaseBuilder` arrives with roadmap item 5.
- The order that lets every discrepancy be attributed (D7): flat run → frozen-flux
  degeneration against `SwingEngine` on the radial pair → PowerDynamics at matched
  fidelity → flux on (both limits + the `K₃T′do` closed form) → regulator on →
  ZIP load → the Iberian criterion of §1.
- Every long-running test self-terminates on a fixed step count. Every band is
  written before the comparison runs. Every mutation is executed. Nothing new
  here; it is the reason the previous three milestones' numbers can be trusted.
