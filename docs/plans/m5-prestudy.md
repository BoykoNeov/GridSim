# M5 pre-study — the detailed tier, worked on paper before it is planned

**What this is.** `m4-plan.md` says M5's plan trio gets written when M4 lands,
informed by what the oracle harness costs. That still holds; this is not the trio.
It is the *physics and numerics* of the detailed tier worked out in advance —
derivations, not measurements — so that the trio, when written, is written from
these and from M4's measurements rather than from memory. Nothing here was
executed. Where a claim needs a measurement, the measurement is named. §2a is the
one section written *after* M4 landed, and it is source reading rather than
derivation — PowerDynamics 5.0.0, the version `reference/Manifest.toml` pins.

**Why now.** Three of the M4 plan's own "what M5 already knows it must do" bullets
are stated in a way that would pass against a wrong model (§3 below), and the
Iberian exit criterion that justifies M5 at all (`entsoe-iberia-reproduction.md`
§7.3 d) has never been turned into a number a test could assert (§1). Both are
cheaper to fix on paper than after a milestone is scoped around them.

**What §2a added, and what it cost the rest of the file.** M4 step 4 found a
convention question nobody had listed — PowerDynamics' `ClassicalMachine` takes a
mechanical *torque* where we take a *power* (D14) — and this file's §7 responded by
requiring that the richer machine's convention be **read from its source rather
than assumed to carry over**. §2a is that reading, and it changes §2, §3, §4, §5,
§7 and §8. Short version: the swing equation *does* match, so D14's asymmetry is
absent; the question relocated into the stator, where their speed multiplies the
flux terms and ours does not; and the separator §7 proposed for it (low loading)
does not work, because flux decay scales with loading too.

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

**The `ω` that is missing from those stator equations is a choice, not an
omission.** The full Sauer–Pai stator carries the rotor speed on the flux terms
(`Vq = ω(E′q − X′d Id) − Ra Iq`); dropping it is the standard `ω ≈ 1`
simplification, and it is what makes the bracket `E′d Id + E′q Iq + (X′q−X′d) Id Iq`
an air-gap **power** rather than a torque — which in turn is what lets `Pm` enter
the swing equation flat and keeps M3's power-denominated governor untouched.
Carrying the `ω` while writing `2H dω/dt = Pm − Pe` would subtract a torque from a
power. The two coherent packages, the residual this one leaves against
PowerDynamics, and the run that attributes it are §2a.

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

## 2a. `SauerPaiMachine` read from source — the fourth question, relocated

**This is §7's box discharged, not deferred.** That box says M5 must re-read
PowerDynamics' `SauerPaiMachine` for the torque question rather than assume M4's
answer carries over. This section is that reading, against
`src/Library/Machines/SauerPaiMachine.jl` at **PowerDynamics 5.0.0** — the version
`reference/Manifest.toml` pins, the same tree M4 step 4 read. Source and algebra
only; the two claims that need a run are named as such.

### What the component actually is

```
τ_e ~ ψ_d I_q − ψ_q I_d
Dt(δ)    ~ ωbase (ω − ωframe)                  # ωframe is PINNED to 1 in 5.0
2H Dt(ω) ~ τ_m − τ_e − D (ω − 1)

0 ~ R_s I_d + ω ψ_q + V_d                      # static stator (the default)
0 ~ R_s I_q − ω ψ_d + V_q

T′_d0 Dt(E′_q) ~ −E′_q − (X_d−X′_d)(I_d − γ_d2 ψ″_d − (1−γ_d1) I_d + γ_d2 E′_q) + vf
T′_q0 Dt(E′_d) ~ −E′_d + (X_q−X′_q)(I_q − γ_q2 ψ″_q − (1−γ_q1) I_q − γ_q2 E′_d)
T″_d0 Dt(ψ″_d) ~ −ψ″_d + E′_q − (X′_d − X_ls) I_d
T″_q0 Dt(ψ″_q) ~ −ψ″_q − E′_d − (X′_q − X_ls) I_q
ψ_d ~ −X″_d I_d + γ_d1 E′_q + (1−γ_d1) ψ″_d
ψ_q ~ −X″_q I_q − γ_q1 E′_d + (1−γ_q1) ψ″_q

γ_d1 = (X″_d − X_ls)/(X′_d − X_ls),   γ_d2 = (X′_d − X″_d)/(X′_d − X_ls)²   (q likewise)
```

It is **sixth order, not fourth**: `(δ, ω, E′_q, E′_d, ψ″_d, ψ″_q)`. §2's machine
is its `X″ = X′` degeneration, not its equal. §3's remark that "no damper winding"
is only a meaningful condition against a sixth-order machine turns out to describe
the oracle rather than a hypothetical.

### Three conventions that do carry over from M4

- **The rotor frame.** `T_to_glob(δ) = [sin δ, cos δ; −cos δ, sin δ]` gives
  `u = (V_d + jV_q)·e^{j(δ − π/2)}`, i.e. `V_d + jV_q = V e^{j(θ − δ + π/2)}` —
  **§2's stated convention exactly**, and §4's initialisation rotation with it.
  The current uses the transpose, `I_d + jI_q = i·e^{−j(δ − π/2)}`, also as §4 has
  it. `ClassicalMachine` writes the same transform as `−T_park(−δ)`, which *looks*
  like a sign difference and is algebraically identical to `T_to_loc(δ)`; do not
  read a convention change into it.
- **Speed.** `ω` is absolute per unit sitting at 1; ours is the deviation, so
  `ω_ours = ω_PD − 1`, unchanged from M4. `ωframe` is pinned to 1 in 5.0, so
  `Dt(δ) ~ ωbase(ω − ωframe)` is our `dδ/dt = ω₀ ω`.
- **Damping.** `D (ω − 1)` with `ω` per unit — the same term we write as `D ω`,
  with no `ω₀` and no rescaling. The same expression, differently labelled (below).

### The degeneration, worked

Set `X″_d = X′_d` and `X″_q = X′_q`. Then `γ_d1 = γ_q1 = 1` and `γ_d2 = γ_q2 = 0`,
both *exactly*, and every line collapses onto §2 with nothing approximated:

| PowerDynamics at `X″ = X′` | §2 |
|---|---|
| `ψ_d = E′_q − X′_d I_d`, `ψ_q = −E′_d − X′_q I_q` | (the fluxes §2 never names) |
| `T′_d0 Ė′_q = −E′_q − (X_d−X′_d) I_d + vf` | the `E′q` flux equation, `vf ≡ Efd` |
| `T′_q0 Ė′_d = −E′_d + (X_q−X′_q) I_q` | the `E′d` flux equation |
| `τ_e = E′_d I_d + E′_q I_q + (X′_q−X′_d) I_d I_q` | `Pe`, **character for character** |
| `V_d = −R_s I_d + ω(E′_d + X′_q I_q)` | `Vd = E′d + X′q Iq − Ra Id` **at `ω = 1`** |
| `V_q = −R_s I_q + ω(E′_q − X′_d I_d)` | `Vq = E′q − X′d Id − Ra Iq` **at `ω = 1`** |

Four of the six lines are ours outright. §4's initialisation inverts exactly these,
so it is confirmed too, including the sign on `E′d = Vd + Ra Id − X′q Iq`.

### The one thing that does not collapse: `ω` in the stator

Their stator carries the rotor speed on the flux terms; §2's does not:

    theirs:  V_q = ω (E′_q − X′_d I_d) − R_s I_q
    ours:    V_q =     E′_q − X′_d I_d  − R_s I_q

With `R_s = 0` the whole internal voltage pair is exactly `ω ×` ours, so **at equal
states their terminal voltage is `ω` times ours** — a residual of `(ω − 1)·V`, first
order in the slip with an order-one coefficient. That is **the same order and the
same blindness as D14**: identically zero at `ω = 1`, so the flat run of §4, the
fixpoint residual and every steady-state identity are all incapable of seeing it,
and it is visible only in a transient. The fourth convention question did not go
away when the swing equation turned out to match — **it moved one equation down.**

### Torque or power: a package, not a switch

The naming is not cosmetic, and the `ω` above is why. Their static stator gives
`P_terminal = −R_s|I|² + ω τ_e`, i.e. `τ_e = (P + R_s|I|²)/ω` — the source says so
in a comment and it follows in two lines. Therefore:

- **With `ω` in the stator, `ψ_d I_q − ψ_q I_d` is a torque**, and `τ_m − τ_e` is a
  consistent torque balance. `SauerPaiMachine` is self-consistent — unlike
  `ClassicalMachine`, which divides *only* the mechanical side (`τ_m/ω − τ_e` with
  `τ_e` a power). **M4's answer does not carry over, and it does not carry over in
  our favour**: this is a different and cleaner convention, so the specific
  asymmetry D14 identified is simply absent here.
- **Without `ω` in the stator, the same bracket is the air-gap power**, and
  `Pm − Pe` is a consistent power balance. That is §2.

Both are self-consistent; the mixed forms are not. Keeping `ω` in the stator while
writing `2H dω/dt = Pm − Pe` would subtract a torque from a power — precisely
`ClassicalMachine`'s sin, committed by us. So there are two coherent options:

| | **A — torque form** | **B — power form (§2 as written)** |
|---|---|---|
| swing | `2H ω̇ = τ_m − τ_e − D Δω` | `2H ω̇ = Pm − Pe − D Δω` |
| stator | `ω` on the flux terms | `ω ≈ 1` (the PSS/E-class simplification) |
| vs PowerDynamics | exact | residual `≈ Δω·V`, predicted |
| vs M3 | needs `τ_m = Pm/ω` — reintroduces D14's `/ω` on **our** side | untouched |

**M3 decides this, not the oracle.** M3's mechanical side is denominated in power
end to end — `Pm₀ + ΔPm + ramp`, droop `−Δω/R`, headroom in MW — and its droop and
headroom closed forms are validated against that denomination. Option A would put a
`/ω` between the governor and the shaft and move every one of those closed forms,
for the sake of removing a residual we can predict. **So: option B, and the residual
is identified by its signature rather than absorbed into a band** — the pattern D14
already proved works on this pair. §2 now says this out loud; it previously read as
though the `ω` had never been a question.

### The attribution run that separates the two effects

D14's residual was pinned by *linearity in loading*. That will not work here:
flux decay also scales with loading, so both candidate causes move together, and
§7's "run the bracket at a loading low enough that a torque-form term cannot be
mistaken for a flux one" does not in fact separate them. **The separator is
fidelity, not loading.** Run the PowerDynamics comparison with **flux switched off
on both sides** — `T′` large, so `E′` is frozen over the horizon — and the only
residual left is the stator `ω`. Then switch flux on, and the *change* is the flux
term. That is D7's order applied one level finer.

**A named measurement, not a derivation.** §3's "`T = Inf` is fine, `finite/Inf =
0.0` exactly" is an argument about **our** formulation, where the time constant is
a divisor. PowerDynamics writes the **multiplied** form `T′_d0 * Dt(E′_q) ~ rhs`,
so `T′_d0 = Inf` is `Inf * Dt(E′_q) ~ finite` — not obviously an equation with a
solution, and certainly not one `mtkcompile` is guaranteed to accept. The frozen
limit on their side must therefore be **large-but-finite, with a `1/T′` convergence
check** (the residual falls a decade as `T′` rises one) rather than an assertion of
exactness. Whether `Inf` is expressible at all is a question for the first run.

### Construction facts the builder will need

Each is a default that would otherwise be discovered by a failure:

- **`vf_input` and `τ_m_input` both default to `true`.** A bare
  `SauerPaiMachine()` exposes two unconnected `RealInput`s. The builder must pass
  `vf_input = false, τ_m_input = false` to get `vf_set` / `τ_m_set` *parameters* —
  the shape `build_oracle` already uses for `ClassicalMachine`, and the shape a
  scheduled `ComponentAffect` needs in order to write to them. Pass
  `stator_dynamics = false` explicitly too, for `oracle.jl`'s own stated reason:
  a default is not a guarantee.
- **`vf`, `τ_m` and `τ_e` all carry `bounds = (0, Inf)`.** A model with negative
  mechanical power, or a machine absorbing at equilibrium, will not initialise.
  That is a precondition on the **model**, in the shape of `_assert_governor_free`
  — thrown at build time, not met as a solver failure.
- **`X_ls` has no default**, and `γ_d1` divides by `X′_d − X_ls`. `X_ls < X′_d`
  strictly is a hard precondition, and `X_ls` is a data-sheet quantity §2's
  parameter list does not yet carry: `machine_arrays` gains a column for it, and
  being a reactance it scales inversely with `S_rated/S_base` like the rest.
- **Their two extra states must be seeded, or their initialiser runs.** §4 hands
  PowerDynamics *our* fixpoint precisely so a flat run checks `find_fixpoint`
  rather than their power flow (`oracle.jl`'s argument, unchanged). The two states
  §2 does not carry have closed forms from the equations above:

      ψ″_d = E′_q − (X′_d − X_ls) I_d,      ψ″_q = −E′_d − (X′_q − X_ls) I_q

  At the degeneration these are **decoupled** — `1 − γ_1 = 0` removes them from the
  flux linkages and `γ_2 = 0` from the `E′` equations — so they integrate but feed
  nothing. Seeding them keeps the flat run flat; a **per-state** flat comparison
  must skip them, because a state that drives nothing has no counterpart on our
  side to be equal to.

### The exciter, while the source was open

`AVRTypeI` is the closest component to §2's static exciter, and it is a *two*-lag
system with a stabiliser and a saturation ceiling. It degenerates to
`T_E dEfd/dt = −Efd + K_A(Vref − V)` with `Kf = 0` (no stabiliser),
`Se1 = Se2 = 0` (no ceiling), `Ke = 1`, `tmeas_lag = false`, and `Ta → 0` — and
`Ta → 0` is a limit, not a setting, so the exciter comparison is one lag *plus* one
small time constant, i.e. a stiffer run than the machine comparison. Worth knowing
before it is scheduled. Note also that their limits sit on the **regulator** output
`vr`, not on `Efd`, so §2's `Efd ∈ [Efd_min, Efd_max]` has no direct counterpart and
the limited exciter is not a matched-fidelity comparison. One agreement worth
recording: `AVRTypeI`'s anti-windup is written as `ifelse(at the limit and pushing
outward, 0, …)` **inside the derivative** — the construction M1's headroom rule
demands and §2 asks of `Efd`, arrived at independently by someone else.

### What this does to §5's recommendation

`SauerPaiMachine` sits behind its reactance on an **algebraic terminal bus**: it is
`ClassicalMachine`-shaped, not `Swing`-shaped. On the M2/M3 tier that shape is what
forced `reduced_line_reactance` and what makes the meshed ring an invalid oracle
case (D13) — and it would come back here, **except that §5 has already put our
detailed tier's machines on terminal buses too**. Two terminal-bus models need no
reduction between them: they are handed the same line reactance, and the ring is a
valid case for the detailed tier.

That is a **second, independent argument for §5's algebraic network**, reached from
the oracle rather than from stiffness. §5 recommended the DAE because dynamic RL
branches buy a stiffness ratio of `1e5–1e6` for nothing; it is also the only
formulation under which M5's external oracle costs no reduction and loses no
topology. The most expensive recommendation in this file now has two reasons that
do not depend on each other.

---

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
- **External**: PowerDynamics `SauerPaiMachine`, once the M4 step-4 harness exists
  (D7: matched fidelity first, then switch things on). Read from source in §2a, and
  it is better news than "at matched parameters" suggests: their component is
  *sixth* order, but at `X″ = X′` its two flux equations become §2's **exactly**,
  so the flux equations get an external oracle **with the flux switched on** and do
  not depend on the frozen limit at all. Two cautions from the same reading: the
  frozen limit on their side cannot be `T′ = Inf` (they write the multiplied form —
  §2a), and one residual survives matched fidelity by construction, the stator `ω`.

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
Pm  = Pe = E′d Id + E′q Iq + (X′q − X′d) Id Iq   # AIR-GAP, not terminal (§2a)
Vref = V + Efd / K_A                             # static exciter at rest
ω = 0, ΔPm = 0
```

**The flat-run test** (from the M4 plan, kept): no disturbance, full horizon,
every state constant to solver tolerance at two tolerances. A mis-initialised
model opens with a transient nobody injected, and no overlay catches it because
both sides of an overlay would share the same wrong start. Assert *per state*,
not on `f_coi` — a wrong `E′d` can leave frequency flat while the voltage rings.

`Pe` above is the **air-gap** quantity, and §2a settles the parenthesis that line
used to carry: PowerDynamics' static stator gives `P_terminal = −Ra|I|² + ω·τ_e`,
so terminal power is smaller by the stator loss and the air-gap form is the one
that belongs in the swing equation. When the oracle is seeded from this
initialisation it must also be handed PowerDynamics' two sub-transient states,
which have closed forms and which their own initialiser would otherwise solve for
— §2a lists both, and why a per-state flat comparison has to skip them.

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

**A second argument, from a direction this section did not look in.**
PowerDynamics' `SauerPaiMachine` sits behind its reactance on an algebraic terminal
bus. If our detailed tier kept `E′` at the bus, the external oracle would need M4's
`reduced_line_reactance` and would be invalid on any meshed topology (D13) — the
ring excluded again. Putting our machines on terminal buses removes the reduction
entirely and keeps the ring. So the algebraic network is not only the formulation
that avoids a `1e5–1e6` stiffness ratio for nothing; it is also the only one under
which M5's external oracle costs no reduction and loses no topology. See §2a.

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

> **What happened when step 4 ran — read this section with it (D13/D14).** The
> three questions below were all answered from PowerDynamics' source and **all
> three come out our way**. But the section's premise is wrong: `ClassicalMachine`
> is not the component that matches us. `Library.Swing` is — `swing_vertex!` line
> for line, constant voltage magnitude at the bus included — and it needs no
> radial reduction, so **point 1's "the ring is not a valid oracle case" does not
> apply to it** and the meshed ring went through the external oracle after all.
> There is also a **fourth** convention question this section does not have, and it
> is the one that bites: `ClassicalMachine`'s mechanical input is a **torque**
> (`τ_m/ω`) where ours is a **power**. It acts like a change in damping, is
> proportional to loading, and is identically zero at `ω = 1`, so nothing in
> points 1–3 could have found it. **M5 must re-read `SauerPaiMachine`'s source for
> the same question rather than assuming the answer carries over**, and run the
> degeneration bracket at a loading low enough that a torque-form term cannot be
> mistaken for a flux one. See `m4-context.md` D13/D14.
>
> **That re-read is done — §2a, and it corrects two things in this paragraph.**
> `SauerPaiMachine`'s swing is `2H ω̇ = τ_m − τ_e − D(ω−1)` with **no `/ω`**, and its
> `τ_e` is our `Pe` character for character, so D14's specific asymmetry is absent
> here: the mechanical input is *labelled* a torque but enters exactly as our power
> does. The convention question does not disappear, it **relocates** — into the
> stator, where their `ω` multiplies the flux terms and ours does not, at the same
> order and with the same blindness to every steady-state check. And the separator
> named just above is wrong: loading does **not** discriminate a torque term from a
> flux one, because both scale with it. Fidelity does — flux off on both sides
> first, then on.

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
  degeneration against `SwingEngine` on the radial pair → PowerDynamics with **flux
  off on both sides**, which leaves the stator-`ω` residual of §2a alone and nothing
  else → flux on, against PowerDynamics *and* against the two internal limits and
  the `K₃T′do` closed form → regulator on → ZIP load → the Iberian criterion of §1.
  The flux-off step is new since §2a; without it the stator-`ω` residual and flux
  decay arrive together and scale together, and neither can be attributed.
- Every long-running test self-terminates on a fixed step count. Every band is
  written before the comparison runs. Every mutation is executed. Nothing new
  here; it is the reason the previous three milestones' numbers can be trusted.
