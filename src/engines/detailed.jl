# The detailed (DAE) tier — M5 step 1 (docs/plans/m5-plan.md, m5-context.md D1/D7).
#
# THE TIER, STATED. Bus voltages are **algebraic unknowns**: every bus carries
# `(V_re, V_im)` with a zero row in the mass matrix, and its residual is
# Kirchhoff's current law summed over the incident branches. A machine sits on a
# **terminal** bus and injects the current its stator algebra produces from
# `(V, E, δ)`. The whole system is therefore an index-1 DAE, integrated by a stiff
# solver, and no bus voltage is eliminated in closed form. That is the one
# structural difference from `SwingEngine`, and everything else in this file
# follows from it.
#
# THE MACHINE IS THE TWO-AXIS ONE (M5 step 2, `m5-prestudy.md` §2), in the POWER
# form (D6): four states per machine before the governor — `(δ, ω, E′q, E′d)` — with
# the stator algebra `Vd = E′d + X′q Iq − Ra Id`, `Vq = E′q − X′d Id − Ra Iq` solved
# for the terminal current, and the air-gap power
# `Pe = E′d Id + E′q Iq + (X′q − X′d) Id Iq` entering the swing equation flat.
#
# `Machine.Xd′`, carried and unused since M2, is read here: on a terminal bus each
# machine has exactly one internal reactance and it is not shared across incident
# branches, which is the double-counting that made "E′ behind X′d" inexpressible at
# the classical tier (see `model/network_model.jl`'s tier note).
#
# WHY THE `ω` IS ABSENT FROM THE STATOR, AND WHY THAT IS A CHOICE RATHER THAN AN
# OMISSION (`m5-prestudy.md` §2a, D6). The full Sauer–Pai stator carries the rotor
# speed on the flux terms (`Vq = ω(E′q − X′d Id) − Ra Iq`). Dropping it is the
# standard `ω ≈ 1` simplification, and it is precisely what makes the bracket above
# an air-gap **power** rather than a torque — which in turn lets `Pm` enter the
# swing equation flat and leaves M3's power-denominated governor untouched. Keeping
# the `ω` while writing `2H ω̇ = Pm − Pe` would subtract a torque from a power. Both
# packages are self-consistent; the mixed one is not, and M3 decides which we take.
# The residual this leaves against PowerDynamics is `(ω − 1)·V` — first order in
# slip, identically zero at synchronous speed, and therefore invisible to the flat
# run, the fixpoint residual and every steady-state identity in this file. It is
# identified by that signature in plan step 3, never absorbed into a band.
#
# THE DEFAULTS ARE THE CLASSICAL DEGENERATION (D4), not a special test fixture.
# `Xd = Xq = X′q = X′d`, `T′do = T′qo = Inf`, `Ra = 0` is what `Machine` builds
# when nobody asks for anything, and in that limit `E′d ≡ 0`, `E′q ≡ E′`, the
# saliency term vanishes and this engine is `SwingEngine` on a terminal-bus
# network. That is what makes plan step 2's oracle run on the scenarios that
# already exist. What it CANNOT check is the flux equations, because they are
# switched off — and plan step 4 is what checks them, three ways at three very
# different resolutions: a CLOSED FORM for the field-flux decay
# (`T′d = T′do·(X′d + Xe)/(Xd + Xe)`, exact to 3e-9 on `infinite_bus_system()`),
# the `T′ → 0` LIMIT from the other side (this tier with `X′ := X` and the flux
# frozen IS the quasi-steady machine, and the gap falls linearly in `T′`), and
# PowerDynamics with the mechanism live. The external one is the COARSEST of the
# three — ~10 %, because the stator-`ω` residual above arrives on the flux channel
# through `Id` and is larger than a small parameter error. See the ledger rows and
# `m5-context.md` D19.
#
# WHY ALGEBRAIC RATHER THAN DYNAMIC BRANCHES (m5-prestudy.md §5, D1). Dynamic RL
# branches keep the letter of "an ODE" and lose its point: the bus voltages stay
# algebraic unless every bus is given a shunt capacitance, and with realistic line
# charging the bus time constants are microseconds against swing dynamics of
# seconds — a stiffness ratio of 1e5–1e6 bought for nothing.
#
# ─────────────────────────────────────────────────────────────────────────────
# THE INITIALISATION, AND THE TWO THINGS MEASURED BEFORE IT WAS WRITTEN
#
# The steady state does NOT come from `find_fixpoint` on the network below. It
# comes from a separate **static** network (`_static_network`), solved with one
# machine's rotor angle pinned, whose solution is then back-substituted. Two
# spikes decided that, and the reasons are not the ones the plan gave:
#
#   1. **The joint problem is rank-deficient by exactly one — and so is
#      `SwingEngine`'s.** Measured on a three-bus ring: the dynamic network's
#      Jacobian at the true solution has singular values `2.72, 0.472, 2.6e-11`,
#      i.e. one null direction, which is the rotational gauge (rotate every `δ`
#      and every `V` together and nothing changes). `find_fixpoint` then stalls at
#      a residual of `2.6e-10` against its `1e-10` tolerance — a factor of 2.6,
#      close enough that loosening the tolerance would "fix" it and hand back a
#      gauge-arbitrary answer. Seeding it AT the true solution does not help,
#      which is what rules out a bad initial guess as the cause.
#
#      But `SwingEngine`'s fixpoint problem is rank-deficient in the same way
#      (`1.46e-14` against `314`) and converges anyway. **So the gauge alone is
#      not the argument**, and pinning the slack angle inside the dynamic network
#      does converge, to `1.3e-15`. The gauge is why a reference must be pinned
#      somewhere; it is not why the network below is not the thing pinned.
#
#   2. **The joint solve finds WRONG equilibria, not no equilibria — and its
#      residual actively misleads.** That is the argument. Measured on the same
#      ring, with the slack pinned, seeding one machine's rotor angle away from
#      its true value:
#
#        seed δ₂ = true       -> δ₂ = -0.0287, |V| = (1.010, 1.004, 0.978), res 1.8e-13
#        seed δ₂ = true + π   -> δ₂ =  2.9438, |V| = (0.389, 0.203, 0.131), res 5.0e-16
#        seed δ₂ = true + 2.5 -> the same collapsed point,                  res 4.4e-16
#
#      The spurious point is self-consistent and converges to a residual **400×
#      tighter than the true one**, so no residual test distinguishes them. Only
#      the `|V| ∈ [0.9, 1.1]` band does — which is exactly why `_check_power_flow`
#      below tests the band and not just the residual. And the basin is narrower
#      than `π`: a 2.5 rad seed already falls into the collapsed solution.
#
#      Back-substitution sidesteps the whole question: `δ` is never *seeded*, it
#      is *computed* from a converged network solution, so there is no basin to
#      fall out of.
#
# ONE STATIC NETWORK, TWO JOBS. `_static_network` serves both the power flow and
# the post-event re-initialisation, switched by a per-machine `mode` parameter on
# the third residual:
#
#   mode = 0 (SOLVE)  residual is `Pe − Pset` — the machine holds its scheduled
#                     power and its rotor angle is the unknown. This is a PV bus.
#   mode = 1 (PIN)    residual is `δ − δ_target` — the rotor angle is held and the
#                     machine's power is whatever the network gives it.
#
# The power flow pins exactly one machine (the slack, which supplies the angle
# reference) and solves the rest. The re-initialisation after a line trip pins
# EVERY machine at the rotor angle it currently has and re-solves the voltages,
# which is precisely "hold the differential states, restore the algebraic ones".
# Building a second solver for that would have been a second place for the network
# equations to live.
#
# WHERE THE SLACK COMES FROM — AND IT IS NOT PURELY A GAUGE CHOICE, WHICH IS NOT
# WHAT THIS COMMENT SAID BEFORE IT WAS MEASURED.
#
# The obvious argument is that the angle reference is physically arbitrary: every
# observable is a difference, so rotating the whole solution changes nothing. By
# the standing rule that a parameter surviving nowhere is a control and not a
# column, that would make it an engine keyword whose irrelevance is a free
# positive control. Half of that is right. The measurement:
#
#   no voltage-dependent load (two_machine_system, three_machine_ring)
#     max|ΔV| = 2.2e-16   max|Δ(δ−δ₁)| = 2.8e-17   max|ΔPm| = 1.1e-16
#   with a constant-impedance load (load_bus_system)
#     max|ΔV| = 3.6e-4    max|Δ(δ−δ₁)| = 1.5e-2    max|ΔPm| = 4.6e-2
#
# **The slack survives, and it survives into the dispatch.** The slack machine's
# power is free while every other machine holds its schedule, so the slack is
# whoever absorbs the mismatch — and once a load's draw depends on voltage there
# IS a mismatch, because the schedule balances at |V| = 1 and the network does
# not sit there. Both answers are correct operating points of the same schedule,
# and each is self-consistent: with G1 as slack ΣPm = 1.054270 and the load draws
# 1.054270; with G2, 1.053793 and 1.053793. Neither is an error.
#
# So it stays an **engine keyword** — it is a dispatch decision about a case, not
# a property of the network — but for a different reason than the one above, and
# the positive control has a precondition attached: *on a model with no
# voltage-dependent load*, changing the slack must change nothing to machine
# precision. That is a real check with a real boundary, rather than an invariance
# claim that would have failed the first time anyone put a load in a model.
#
# `Pm` IS TAKEN FROM THE POWER FLOW, NOT FROM `Machine.P0`, and the difference is
# not cosmetic. `NetworkModel` balances the SCHEDULE at nominal voltage, but the
# solved network sits at |V| ≠ 1, where a constant-impedance load draws
# `P0·|V|²` — so the slack machine absorbs the difference and its mechanical power
# is not its scheduled one. Measured on the step-1 spike: a 0.8 pu load at
# |V| = 0.978 draws 0.765, and the slack settles at 0.465 against a scheduled 0.5.
# Set `Pm = P0` there and the flat run is not flat.
#
# **That is invisible on every fixture the repo shipped before M5.** With `Ra = 0`
# and no `Load` anywhere, the air-gap power equals `P0` exactly for every
# non-slack machine, so the flat run would pass whether or not the back-
# substitution were right. `load_bus_system()` exists for that reason: it is the
# fixture on which this check has content.
#
# THE VOLTAGE REGULATOR (M5 step 5) is a static exciter with one lag and hard
# limits, `T_E·dEfd/dt = −Efd + K_A(Vref − |V|)`, and `Efd` is a STATE. The
# defaults are the regulator OFF — `K_A = 0`, `T_E = Inf` — which by the same
# `finite/Inf` arithmetic the flux uses makes `dEfd/dt` exactly zero and holds the
# field voltage at whatever the power flow dispatched. That is the case every check
# written before step 5 runs on, so those checks did not have to move. `Vref` is
# DERIVED at initialisation from the solved `(|V|, Efd)` rather than taken as model
# data, for the same reason `Pm` is (see below): a supplied setpoint that does not
# match the dispatch turns the flat run into a startup transient. The limits are
# saturations in the DERIVATIVE and by nothing else — the `isoutofdomain` guard this
# tier was supposed to grow was written, measured to make the ceiling unreachable,
# and removed. That measurement is the block above `_check_power_flow`.
#
# WHAT IS DELIBERATELY NOT HERE YET, each named rather than discovered later:
#   - (`inject!(::TripGenerator)` was listed here until M7 step 7 built it: a tripped
#     source turns its bus into a passive node through an in-service flag on its
#     CURRENT, never `E = 0` — see that method;)
#   - more than one machine on a bus. The canonical model expresses it (M5 step 1
#     made sure of that); this engine's vertex models do not yet, and say so.
#
# THE RE-INITIALISATION IS NOT VALIDATED BY THE FLAT RUN, and this needs saying
# because the two look alike. Step 1's flat run has NO event in it: it proves the
# initialisation. The flat run *across* an event is D8's, and it belongs to the
# step that arms protection at this tier. `inject!(::TripLine)` below does the
# re-initialisation because S3 needs a run with real dynamics in it to measure,
# not because step 1 checks it.

# Mode codes for the static machine vertex (see the header). The first two use the
# STEADY-STATE representation of the machine — a q-axis source `Ẽ = E∠δ` behind
# `(Ra + jXq)` — and differ only in their third residual. The third uses the
# machine's actual TRANSIENT stator algebra at held `(δ, E′q, E′d)`, which is what
# a re-initialisation after an event needs and what the steady-state source stops
# being able to express the moment the flux is allowed to move.
const _PF_SOLVE = 0.0   # steady-state source; residual `Pe − Pset`   (a PV machine)
const _PF_PIN   = 1.0   # steady-state source; residual `δ − δ_target` (the slack)
const _PF_HOLD  = 2.0   # TRANSIENT stator at (δ, E′q, E′d); residual `δ − δ_target`

# The steady-state solve's own acceptance thresholds (m5-prestudy.md §4, D7).
# `_PF_VMIN`/`_PF_VMAX` are the band that catches the collapsed spurious solution
# the header measures; they are NOT a modelling assumption about acceptable
# voltage, they are the discriminator between two self-consistent answers.
const _PF_VMIN = 0.9
const _PF_VMAX = 1.1
const _PF_RESIDUAL = 1.0e-10

# The detailed tier's default output cadence. Coarser than `SwingEngine`'s 0.02 s
# because this tier is playback-first (D2): the number that would justify a
# real-time cadence is S3, and it is measured, not assumed.
const _DETAILED_DT0 = 0.02

# ─────────────────────────────────────────────────────────────────────────────
# Vertex and edge models
# ─────────────────────────────────────────────────────────────────────────────

"""
    _branch_current!(e, v_src, v_dst, p, t)

One branch's current, `I = status·(V_src − V_dst)/(jX)`, split into real and
imaginary parts and wrapped by the caller in `AntiSymmetric` so the far end sees
`−I`. Shared by the static and dynamic networks, which is what makes the power
flow a solve of *the same network* the engine integrates rather than of a second
one written beside it.

Dividing by `jX` rotates by `−90°`: `(a + jb)/(jX) = (b − ja)/X`.

`status` is the line's in-service flag, `1.0` or `0.0`. It multiplies the current
rather than the admittance so that an out-of-service line is an open circuit
exactly, with no `X = Inf` anywhere near a denominator.
"""
function _branch_current!(e, v_src, v_dst, p, t)
    X, status = p[1], p[2]
    e[1] =  status * (v_src[2] - v_dst[2]) / X
    e[2] = -status * (v_src[1] - v_dst[1]) / X
    return nothing
end

"""
    _machine_injection(Vre, Vim, δ, E, Ra, Xq, status) -> (Ire, Iim, Pe)

The current the machine injects into its terminal bus **at a steady state**, and
the air-gap power that goes with it. Used by the power flow only; the dynamic
vertex uses `_stator` below, which is a different (and more general) thing.

`I = (E∠δ − V)/(Ra + jXq)`, and the reason the denominator is the **synchronous
q-axis** impedance is the one algebraic fact the whole initialisation rests on
(`m5-prestudy.md` §4). At a steady state the two-axis machine satisfies
`Vd = Xq Iq − Ra Id`, i.e. the phasor `Ẽ = V + (Ra + jXq)·I` has zero d-component
— it lies **on the q-axis** — so `Ẽ = Ẽq∠δ` and its magnitude is a single number
that closes the power flow alongside the scheduled `P`. `Machine.E′` is that
number at this tier (see its docstring); at the classical degeneration `Xq = X′d`
and `Ra = 0`, so it is also the classical internal voltage and every pre-M5
fixture solves bit-identically.

`Pe = Re(Ẽ · conj(I))` is the **air-gap** power, and that is provable rather than
asserted: in the rotor frame it is `Ẽd Id + Ẽq Iq = Ẽq Iq`, and substituting the
steady-state flux relations into `E′d Id + E′q Iq + (X′q − X′d) Id Iq` leaves
exactly `Ẽq Iq` — the three saliency terms cancel identically. It is therefore the
same quantity `_stator` computes, evaluated where the machine is at rest.
"""
@inline function _machine_injection(Vre, Vim, δ, E, Ra, Xq, status)
    Ere, Eim = E * cos(δ), E * sin(δ)
    dre, dim = Ere - Vre, Eim - Vim
    den = Ra * Ra + Xq * Xq
    Ire = status * (dre * Ra + dim * Xq) / den
    Iim = status * (dim * Ra - dre * Xq) / den
    return Ire, Iim, Ere * Ire + Eim * Iim
end

"""
    _stator(Vre, Vim, δ, E′q, E′d, Ra, Xd′, Xq′, status)
        -> (Id, Iq, Ire, Iim, Pe)

The two-axis machine's stator algebra (`m5-prestudy.md` §2), solved for the
terminal current at the machine's *current* internal state. This is the dynamic
tier's machine, and every one of the four steps below is a place a convention can
go wrong silently, so each is written out.

**The rotor frame.** `Vd + jVq = V·e^{−j(δ − π/2)}` — the q-axis leads the rotor
angle by the usual `π/2` — which as a matrix is `[sin δ, −cos δ; cos δ, sin δ]`,
and the current transforms back through its transpose. This is PowerDynamics'
`T_to_glob(δ)` character for character (`m5-prestudy.md` §2a), and it is the
convention a wrong sign here would silently swap.

**The inversion.** `Vd = E′d + X′q Iq − Ra Id` and `Vq = E′q − X′d Id − Ra Iq`
rearrange to `[Ra, −X′q; X′d, Ra]·[Id; Iq] = [E′d − Vd; E′q − Vq]`, whose
determinant is `Ra² + X′d·X′q`. `Machine` guards `X′q > 0` precisely because at
the default `Ra = 0` that determinant is `X′d·X′q`.

**The power is the air-gap one**, `E′d Id + E′q Iq + (X′q − X′d) Id Iq`. The third
term is the saliency term and it vanishes at the degeneration, which is why no
check that runs there can see it.

`status` is the machine's in-service flag. It multiplies the CURRENT, so an
out-of-service machine injects nothing and produces no air-gap power while its
rotor states drift harmlessly. Carried since M5 for symmetry with the branch flag;
`inject!(::TripGenerator)` writes it as of M7 step 7.
"""
@inline function _stator(Vre, Vim, δ, E′q, E′d, Ra, Xd′, Xq′, status)
    sδ, cδ = sin(δ), cos(δ)
    Vd = Vre * sδ - Vim * cδ
    Vq = Vre * cδ + Vim * sδ
    den = Ra * Ra + Xd′ * Xq′
    ΔEd = E′d - Vd
    ΔEq = E′q - Vq
    Id = status * (Ra * ΔEd + Xq′ * ΔEq) / den
    Iq = status * (Ra * ΔEq - Xd′ * ΔEd) / den
    Ire =  Id * sδ + Iq * cδ
    Iim = -Id * cδ + Iq * sδ
    Pe  = E′d * Id + E′q * Iq + (Xq′ - Xd′) * Id * Iq
    return Id, Iq, Ire, Iim, Pe
end

"""
    _dq(re, im, δ) -> (d, q)

The rotor-frame components of a global `(re, im)` pair — `_stator`'s rotation,
exposed so the initialisation rotates the same way the RHS does rather than
through a second copy of the same two lines.
"""
@inline _dq(re, im, δ) = (re * sin(δ) - im * cos(δ), re * cos(δ) + im * sin(δ))

# ─────────────────────────────────────────────────────────────────────────────
# The grid-forming inverter (M7 step 4, `docs/plans/m7-context.md` D3/D4/D11)
#
# THREE ONE-LINE LAWS, EACH WRITTEN ONCE. The dynamic vertex, the static vertex, the
# initialisation's back-substitution and the read-outs all call these, so the step's
# two anti-vacuity mutations (the `K_q` sign, the coupling reactance) change the
# model CONSISTENTLY — initialisation included — and have to show up as a different
# TRAJECTORY. A mutation that only broke the build-time residual check would go red
# for a reason that proves nothing (M6's lesson).
# ─────────────────────────────────────────────────────────────────────────────

"""
    _gfm_speed(K_p, P_filt, P_set) -> ω

The droop law, `ω = −K_p·(P_filt − P_set)` (pu deviation, `K_p` on the system base).
`ω` is not a state: it is read off the filtered power, which is why a setpoint step
moves it instantly (Hurdle 11 claim 2) and a rotor's cannot.
"""
@inline _gfm_speed(K_p, P_filt, P_set) = -K_p * (P_filt - P_set)

"""
    _gfm_voltage(V_ref, K_q, Q_filt) -> E

The voltage droop, `E = V_ref − K_q·Q_filt` — the magnitude of the voltage the
inverter forms behind its coupling reactance. `V_ref` is the droop's intercept,
`V_set + K_q·Q_set` in the component's own terms; only that combination enters the
dynamics, so it is one DERIVED parameter (`init!`, D11), never two pieces of data.
`K_q = 0` holds `E` at `V_ref` exactly and is the degeneration that makes this
inverter a classical machine.
"""
@inline _gfm_voltage(V_ref, K_q, Q_filt) = V_ref - K_q * Q_filt

"""
    _gfm_current(Vre, Vim, δ, E, X) -> (Ire, Iim, P, Q)

The current a voltage `E∠δ` behind a reactance `X` injects into a bus at `V`, and
the power **at the source terminal**: `I = (E∠δ − V)/(jX)`, `P + jQ = E∠δ·conj(I)`.

**Measured at the source, not at the bus, and that is a choice with a size.** `P` is
the same at both ends of a lossless reactance; `Q` is not — the source sees
`Q_bus + |I|²X`. This model is checked against PowerDynamics' `IdealDroopInverter`
with an explicit line of reactance `X_c` (D3), and that component measures its power
at its own terminal, which is this source. Measuring at the bus would put a
`|I|²X_c` difference into `Q_filt` and, through `K_q`, into the voltage.
"""
@inline function _gfm_current(Vre, Vim, δ, E, X)
    Ere, Eim = E * cos(δ), E * sin(δ)
    dre, dim = Ere - Vre, Eim - Vim
    Ire =  dim / X
    Iim = -dre / X
    return Ire, Iim, Ere * Ire + Eim * Iim, Eim * Ire - Ere * Iim
end

"""
    _load_current(Vre, Vim, G, B, a_i, a_p) -> (Ire, Iim)

A ZIP load's drawn current (M5 step 6). `P = P₀·(a_z|V|² + a_i|V| + a_p)` and `Q`
likewise, so `S = (P₀ + jQ₀)·f(|V|)` and

    I = conj(S)/conj(V) = (G + jB)·V·k(|V|),   k = a_z + a_i/|V| + a_p/|V|²

with the same `G = P₀`, `B = −Q₀` the constant-impedance case has always used. **The
whole ZIP is one voltage-dependent scalar on the admittance that was already
there** — the constant-impedance term folds into `Y` exactly (`k = a_z`), and the
other two are that same `Y` scaled by a function of `|V|` alone.

`a_z` is not passed: the shares sum to one (`Load` enforces it), so `a_z = 1 − a_i −
a_p` and the form used below is `k = 1 + a_i(1/|V| − 1) + a_p(1/|V|² − 1)`. That
grouping makes two exactnesses hold in floating point rather than approximately:
`k = 1` at `|V| = 1` for every share split — which is what makes `P₀` mean "drawn at
nominal voltage" — and `k = 1` identically when `a_i = a_p = 0`.

**The constant-impedance path is bitwise what it was**, and deliberately: it returns
before the `hypot` and the division, so the default load model is the same
arithmetic it was before this step and every M5 number measured against it still
stands. The branch is on parameters, not states, so it costs no type stability.

**There is no guard at `|V| → 0`, and that is a decision (m5-context.md D23).** With
`a_p > 0` the current diverges there, because a load that draws constant power from
a collapsed bus is a model with no solution — the singularity is the model telling
the truth. A low-voltage cut-over to constant impedance is what production load
models do, and it is a threshold nobody here has chosen; step 7's collapse runs are
what would earn one. Note that PowerDynamics made the same call: its
`ConstantCurrentLoad` carries an explicit `ε` regularisation and its `ZIPLoad` — the
component this step is checked against — carries none.

A bus with no load carries `G = B = a_i = a_p = 0`, which is arithmetically no load
at all rather than a special case.
"""
@inline function _load_current(Vre, Vim, G, B, a_i, a_p)
    Ire = G * Vre - B * Vim
    Iim = G * Vim + B * Vre
    # Constant impedance (and "no load at all"): k ≡ 1, and no sqrt is computed.
    (a_i == 0.0) & (a_p == 0.0) && return (Ire, Iim)
    k = _zip_k(hypot(Vre, Vim), a_i, a_p)
    return (k * Ire, k * Iim)
end

"""
    _zip_k(Vm, a_i, a_p) -> Float64

The ZIP voltage scalar `k = 1 + a_i(1/|V| - 1) + a_p(1/|V|^2 - 1)`, extracted from
`_load_current` at M6 step 3 so the **power flow and the DAE tier cannot come to
hold different load models** — which is the whole content of step 4's flat-run
oracle (`m6-context.md` D11). The grouping is `_load_current`'s exactly, and it is
that grouping rather than the algebraically equal `a_z + a_i/|V| + a_p/|V|^2`
because it makes `k = 1` hold **in floating point** at `|V| = 1` for any split and
at `a_i = a_p = 0` for any voltage.

Called only after `_load_current`'s early return, so the constant-impedance hot
path still computes no `hypot` and is bitwise the arithmetic M5 measured.
"""
@inline function _zip_k(Vm, a_i, a_p)
    invV = inv(Vm)
    return 1 + a_i * (invV - 1) + a_p * (invV * invV - 1)
end

"""
    _detailed_machine_bus!(dv, v, esum, p, t)

A bus carrying one machine. State `v = (V_re, V_im, δ, ω, ΔPm, E′q, E′d, Efd)` with
mass matrix `Diagonal(0, 0, 1, 1, 1, 1, 1, 1)`: the first two rows are the
algebraic constraint, the next three are the same differential equations
`swing_vertex!` integrates, the next two are the field- and damper-axis transient
flux, and the last is the exciter (M5 step 5).

The two algebraic rows are Kirchhoff's current law at the bus:

    I_machine − I_load + Σ(incident branch currents) = 0

`esum` is the sum of the edge outputs at this vertex, and `AntiSymmetric` gives
the source end `−I` — so `esum` is the net current flowing INTO the bus from the
network, and the balance is a plain sum. (`SwingEngine`'s sign note says the same
thing one quantity up, for power.)

The governor block is `swing_vertex!`'s, unchanged and deliberately so: `ΔPm` is a
**control** state on a power-denominated governor, so it is tier-independent
(m5-context.md D6). Its headroom saturation is a saturation in the derivative,
never a clamp on the state — the M1 landmine, still live here.
"""
function _detailed_machine_bus!(dv, v, esum, p, t)
    Vre, Vim, δ, ω, ΔPm, E′q, E′d, Efd = v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8]
    Pm                  = p[1]
    Xd, Xq, Xd′, Xq′    = p[2], p[3], p[4], p[5]
    Td0′, Tq0′, Ra      = p[6], p[7], p[8]
    H, D, ω₀            = p[9], p[10], p[11]
    invR, headroom, Tg  = p[12], p[13], p[14]
    G, B, a_i, a_p      = p[15], p[16], p[17], p[18]
    mstat               = p[19]
    K_A, T_E            = p[20], p[21]
    Efd_min, Efd_max, Vref = p[22], p[23], p[24]
    rate, t_start, duration = p[25], p[26], p[27]
    Id, Iq, Ire, Iim, Pe = _stator(Vre, Vim, δ, E′q, E′d, Ra, Xd′, Xq′, mstat)
    Lre, Lim = _load_current(Vre, Vim, G, B, a_i, a_p)
    dv[1] = Ire - Lre + esum[1]                 # KCL, real
    dv[2] = Iim - Lim + esum[2]                 # KCL, imaginary
    dv[3] = ω₀ * ω
    # The scheduled generation ramp (M5 step 7), and it is `swing_vertex!`'s line
    # unchanged — same expression, same three parameters, same reason for being a
    # continuous ramp rather than a staircase of discrete trips (a staircase's edges
    # are jump discontinuities in exactly the signal the shed ladder and the
    # out-of-step relay root-find on). `rate == 0` is the un-ramped machine and is
    # `Pm + 0.0`, bit for bit, which is what lets every run recorded before this step
    # keep its numbers.
    Pm_eff = Pm + rate * clamp(t - t_start, 0.0, duration)
    dv[4] = (Pm_eff + ΔPm - Pe - D * ω) / (2 * H)
    dΔPm = (-ω * invR - ΔPm) / Tg
    if ΔPm >= headroom && dΔPm > 0
        dΔPm = zero(dΔPm)                       # saturate the DERIVATIVE (see above)
    end
    dv[5] = dΔPm
    # The transient flux.
    #
    # `T = Inf` is the frozen limit and is arithmetic, not a branch: `finite/Inf` is
    # `0.0` exactly, so the derivative is zero and the state holds. That is the
    # whole reason the time constant is a divisor here rather than a multiplier —
    # PowerDynamics writes `T·ẋ ~ rhs` and cannot do this (`m5-prestudy.md` §2a).
    dv[6] = (-E′q - (Xd - Xd′) * Id + Efd) / Td0′
    dv[7] = (-E′d + (Xq - Xq′) * Iq) / Tq0′
    # THE EXCITER (M5 step 5, `m5-prestudy.md` §2). Static, one lag, hard limits:
    #
    #     T_E·dEfd/dt = −Efd + K_A·(Vref − |V|)
    #
    # `Efd` is a STATE rather than a parameter, and unconditionally so. A vertex
    # model's state count is fixed when the network compiles, so "a parameter when
    # the regulator is off and a state when it is on" is not available; instead
    # `T_E = Inf` — the default — makes `dEfd/dt` exactly `0.0` by the same
    # `finite/Inf` arithmetic the flux uses two lines up, and the field voltage
    # holds at whatever the initialisation dispatched. That IS the regulator-off
    # case, and it is what every check written before step 5 runs on.
    #
    # `Vref` is a parameter DERIVED at initialisation, never model data — see
    # `init!`. Here it is simply read.
    #
    # THE LIMITS ARE SATURATIONS IN THE DERIVATIVE, NEVER A CLAMP ON THE STATE.
    # This is M1's carried-forward rule (CLAUDE.md, SPEC §7) applied to a second
    # quantity: clamping `Efd` after the fact would corrupt the integration, and an
    # adaptive solver would keep proposing steps that walk back out. At a limit with
    # the derivative pointing outward the derivative is zeroed, so the solution sits
    # *at* the limit and stays there while the demand persists — and comes off it
    # unaided, with no event and no state surgery, the moment the demand reverses.
    # PowerDynamics' `AVRTypeI` writes its own anti-windup the same way
    # (`ifelse(at the limit and pushing outward, 0, …)` inside the derivative),
    # which is agreement reached independently rather than a convention copied.
    #
    # `±Inf` limits are the unlimited case and cost no branch of their own:
    # `Efd >= Inf` and `Efd <= -Inf` are both false.
    dEfd = (-Efd + K_A * (Vref - hypot(Vre, Vim))) / T_E
    if (Efd >= Efd_max && dEfd > 0) || (Efd <= Efd_min && dEfd < 0)
        dEfd = zero(dEfd)
    end
    dv[8] = dEfd
    return nothing
end

"""
    _detailed_passive_bus!(dv, v, esum, p, t)

A bus with no machine: a load bus, or a bare junction. State `(V_re, V_im)`, mass
matrix zero throughout, residual Kirchhoff's current law. **This vertex is the
whole reason the tier exists** — the classical tier cannot carry it, because it
has no differential state at all.
"""
function _detailed_passive_bus!(dv, v, esum, p, t)
    Lre, Lim = _load_current(v[1], v[2], p[1], p[2], p[3], p[4])
    dv[1] = -Lre + esum[1]
    dv[2] = -Lim + esum[2]
    return nothing
end

# ─────────────────────────────────────────────────────────────────────────────
# The grid-following inverter (M7 step 5, `docs/plans/m7-context.md` D12)
# ─────────────────────────────────────────────────────────────────────────────

"""
    _pll_error(Vre, Vim, θ) -> e

The PLL's error signal, `e = −sin θ·V_re + cos θ·V_im = |V|·sin(θ_V − θ)` — the
bus voltage's q-component in a frame whose d-axis sits at the PLL angle, which the
loop drives to zero. PowerDynamics' `PLL_LPF` line for line (D12), and deliberately
NOT divided by `|V|`: that is their form, so the gains act on `|V|·sin` and are
"on an angle" only at `|V| = 1`.
"""
@inline _pll_error(Vre, Vim, θ) = -sin(θ) * Vre + cos(θ) * Vim

"""
    _gfl_current(i_d, i_q, θ) -> (Ire, Iim)

The current an ideal current source injects when its setpoint `(i_d, i_q)` is held in
the PLL's frame: `I = (i_d + j·i_q)·e^{jθ}` — the d-axis ALONG the PLL angle, which is
PowerDynamics' `_dq_to_ri` convention, and NOT the machine's `_dq` (whose q-axis
leads the rotor angle). At lock `θ = arg V`, so `P = |V|·i_d` and `Q = −|V|·i_q`.
"""
@inline _gfl_current(i_d, i_q, θ) = (cos(θ) * i_d - sin(θ) * i_q,
                                     sin(θ) * i_d + cos(θ) * i_q)

"""
    _pll_rhs(Vre, Vim, θ, Δω, Δω_i, K_p, K_i, τ) -> (dθ, dΔω, dΔω_i)

The PLL's three derivatives — `PLL_LPF` (D12), the ONE copy of the law. Two things
carry a PLL: a grid-following inverter (which injects a current phased by it) and a
[`PLLMeter`](@ref) (which injects nothing, M7 step 6). Both call this, so a meter
with an inverter's gains at that inverter's bus is the same loop on the same voltage,
and `test/` asserts it reads the inverter's own channel to the bit.

    e          = −sin θ·V_re + cos θ·V_im       (`_pll_error`, NOT divided by |V|)
    dθ/dt      = Δω                             rad/s against the synchronous frame
    τ·dΔω/dt   = Δω_i + K_p·e − Δω              the PI, through the output filter
    dΔω_i/dt   = K_i·e
"""
@inline function _pll_rhs(Vre, Vim, θ, Δω, Δω_i, K_p, K_i, τ)
    e = _pll_error(Vre, Vim, θ)
    return Δω, (Δω_i + K_p * e - Δω) / τ, K_i * e
end

"""
    PLLMeter(bus; K_p = 2π·10, K_i = (2π·10)²/4, τ = 1/(2π·300))
    PLLMeter(inv::Inverter)

A **measurement-only** phase-locked loop at a bus (M7 step 6): the instrument a
frequency or RoCoF relay actually reads, attached to `DetailedEngine` through its
`meters` keyword. It locks onto its bus voltage with the same law a grid-following
inverter uses (`PLL_LPF`, D12 — `_pll_rhs`, the one copy) and **injects nothing**:
its three states read the bus voltage and nothing reads them back.

Why it exists: every frequency this repo reported before M7 was a rotor speed or an
inertia-weighted mean of them. What a relay at a bus sees is neither — it is a PLL's
estimate, and in this tier a bus angle JUMPS at every event, so the estimate spikes
where no rotor speed moved (Hurdle 10). A grid-following inverter carries one such
loop for its own control; a meter puts the same loop at any bus, so a study that
displaces machines by GRID-FORMING inverters (which carry no PLL) can still report
what a relay there would read, measured the same way as in the grid-following sweep.

The defaults are the grid-following `Inverter`'s — a 10 Hz loop, critically damped
without its filter, and a 300 Hz output filter. `PLLMeter(inv)` copies an inverter's
own gains and bus, which is how `test/` shows a meter reads that inverter's PLL
channel bit for bit.

An engine option, not model data — like a relay or a shed ladder, it is an
instrument armed on a case, not part of the network — so the scenario file does not
carry it.
"""
struct PLLMeter
    bus::Symbol
    K_p::Float64    # 1/s
    K_i::Float64    # 1/s²
    τ::Float64      # s
    function PLLMeter(bus::Symbol; K_p::Real = _PLL_KP, K_i::Real = _PLL_KI,
                      τ::Real = _PLL_TAU)
        K_p > 0 || throw(ArgumentError("PLLMeter at $bus: K_p ($K_p) must be > 0 1/s."))
        K_i > 0 || throw(ArgumentError("PLLMeter at $bus: K_i ($K_i) must be > 0 1/s²."))
        τ > 0 || throw(ArgumentError(
            "PLLMeter at $bus: τ ($τ) must be > 0 s — it divides the frequency filter; " *
            "zero would remove a state, not set a value."))
        return new(bus, Float64(K_p), Float64(K_i), Float64(τ))
    end
end
PLLMeter(inv::Inverter) =
    PLLMeter(inv.bus; K_p = inv.K_pll_p, K_i = inv.K_pll_i, τ = inv.τ_pll)

# A bus vertex with a meter on it: the bus's own model on the first `nv` states and
# `np` parameters, untouched, and the meter's three states `(θ, Δω, Δω_i)` and three
# gains after them. The meter reads `v[1], v[2]` — THIS vertex's voltage — and writes
# only its own three rows, so it cannot inject into the Kirchhoff sum; `test/` checks
# that structurally (perturb the meter's states, every other row of the right-hand
# side is `==` unchanged) rather than by comparing runs, which differ in their
# adaptive steps whenever the state vector grows.
struct _Metered{F}
    f::F
    nv::Int
    np::Int
end
function (m::_Metered)(dv, v, esum, p, t)
    nv, np = m.nv, m.np
    m.f(view(dv, 1:nv), view(v, 1:nv), esum, view(p, 1:np), t)
    dv[nv + 1], dv[nv + 2], dv[nv + 3] =
        _pll_rhs(v[1], v[2], v[nv + 1], v[nv + 2], v[nv + 3], p[np + 1], p[np + 2], p[np + 3])
    return nothing
end

"""
    _detailed_gfl_bus!(dv, v, esum, p, t)

A bus carrying one **grid-following inverter** (M7 step 5): an IDEAL current source
phased by a PLL. State `v = (V_re, V_im, θ, Δω, Δω_i)`, mass `Diagonal(0,0,1,1,1)`:

    e          = −sin θ·V_re + cos θ·V_im       (`_pll_error`)
    dΔω_i/dt   = K_i·e
    τ·dΔω/dt   = Δω_i + K_p·e − Δω             the PI, through the output filter
    dθ/dt      = Δω                             rad/s against the synchronous frame
    I          = (i_d + j·i_q)·e^{jθ}           (`_gfl_current`)

No filter inductor and no current loop: the current IS its setpoint. That is the
tier's honest limit (Hurdle 12), and the gap it leaves to PowerDynamics' `SimpleGFL`
is identified by how it shrinks as their current loop stiffens, never banded away.

`(i_d, i_q)` are parameters fixed at initialisation from the dispatch — this model
has no outer power loop, so after a disturbance it holds its CURRENT, not its power.

Parameters `p = (i_d, i_q, K_p, K_i, τ, G, B, a_i, a_p)`.
"""
function _detailed_gfl_bus!(dv, v, esum, p, t)
    Vre, Vim, θ, Δω, Δω_i = v[1], v[2], v[3], v[4], v[5]
    i_d, i_q, K_p, K_i, τ = p[1], p[2], p[3], p[4], p[5]
    G, B, a_i, a_p        = p[6], p[7], p[8], p[9]
    Ire, Iim = _gfl_current(i_d, i_q, θ)
    Lre, Lim = _load_current(Vre, Vim, G, B, a_i, a_p)
    dv[1] = Ire - Lre + esum[1]
    dv[2] = Iim - Lim + esum[2]
    dv[3], dv[4], dv[5] = _pll_rhs(Vre, Vim, θ, Δω, Δω_i, K_p, K_i, τ)
    return nothing
end

"""
    _static_gfl_bus!(dv, v, esum, p, t)

The power-flow counterpart: state `(V_re, V_im)` only — a grid-following inverter
holds nothing, so it adds no unknown. Two modes, and they are different physics:

  - `_PF_SOLVE`/`_PF_PIN` — CONSTANT POWER, `I = conj(S/V)`: the dispatch, as
    `ac_powerflow` treats it. This is what the steady state is.
  - `_PF_HOLD` — CONSTANT CURRENT at the held PLL angle, `I = (i_d + j·i_q)·e^{jθ}`:
    what the dynamic vertex actually injects at an instant. A re-initialisation after
    an event must restore the network the RHS integrates, and the RHS holds current.

Parameters `p = (P, Q, i_d, i_q, θ_held, mode, G, B, a_i, a_p)`.
"""
function _static_gfl_bus!(dv, v, esum, p, t)
    Vre, Vim = v[1], v[2]
    P, Q, i_d, i_q, θ_held, mode = p[1], p[2], p[3], p[4], p[5], p[6]
    G, B, a_i, a_p = p[7], p[8], p[9], p[10]
    if mode > 1.5
        Ire, Iim = _gfl_current(i_d, i_q, θ_held)
    else
        V2 = Vre * Vre + Vim * Vim
        Ire = (P * Vre + Q * Vim) / V2
        Iim = (P * Vim - Q * Vre) / V2
    end
    Lre, Lim = _load_current(Vre, Vim, G, B, a_i, a_p)
    dv[1] = Ire - Lre + esum[1]
    dv[2] = Iim - Lim + esum[2]
    return nothing
end

"""
    _detailed_gfm_bus!(dv, v, esum, p, t)

A bus carrying one **grid-forming inverter** (M7 step 4). State
`v = (V_re, V_im, δ, P_filt, Q_filt)`, mass matrix `Diagonal(0, 0, 1, 1, 1)`:

    E          = V_ref − K_q·Q_filt              the voltage droop  (`_gfm_voltage`)
    I, P, Q    = source E∠δ behind X_c           at the source      (`_gfm_current`)
    dδ/dt      = ω₀·(−K_p·(P_filt − P_set))      the frequency droop (`_gfm_speed`)
    τ_p·dP_filt/dt = P − P_filt
    τ_q·dQ_filt/dt = Q − Q_filt

plus the bus's Kirchhoff balance with any load on it. Built from the inverter's OWN
states, never by converting it to a machine and calling `_detailed_machine_bus!`
(D4): at `K_q = 0` it is algebraically the classical machine with `2H = τ_p/K_p`,
`D = 1/K_p`, `X′d = X_c`, and that equivalence is a CHECK, which it could not be if
the two shared a right-hand side. With `K_q > 0` the equivalence ends — the internal
voltage moves with reactive output, which a classical machine's cannot.

Every gain and the reactance are on the SYSTEM base, converted once in
`_inverter_arrays`. No governor slot: this tier refuses ladders and ramps on an
inverter, so nothing indexes one (the swing tier's placeholder exists for its trip
bookkeeping only).

`istat` is the inverter's in-service flag (M7 step 7, D15) — the machine's `mstat`
for this vertex. It multiplies the CURRENT and the two powers measured with it, so a
tripped inverter injects nothing and its filters see nothing while its states drift
harmlessly. `1.0` is the arithmetic this vertex always did, to the bit.

Parameters `p = (P_set, K_p, τ_p, ω₀, K_q, τ_q, V_ref, X_c, G, B, a_i, a_p, istat)`.
"""
function _detailed_gfm_bus!(dv, v, esum, p, t)
    Vre, Vim, δ, P_filt, Q_filt = v[1], v[2], v[3], v[4], v[5]
    P_set, K_p, τ_p, ω₀         = p[1], p[2], p[3], p[4]
    K_q, τ_q, V_ref, X_c        = p[5], p[6], p[7], p[8]
    G, B, a_i, a_p              = p[9], p[10], p[11], p[12]
    istat                       = p[13]
    E = _gfm_voltage(V_ref, K_q, Q_filt)
    Ire, Iim, P, Q = _gfm_current(Vre, Vim, δ, E, X_c)
    Ire, Iim, P, Q = istat * Ire, istat * Iim, istat * P, istat * Q
    Lre, Lim = _load_current(Vre, Vim, G, B, a_i, a_p)
    dv[1] = Ire - Lre + esum[1]                 # KCL, real
    dv[2] = Iim - Lim + esum[2]                 # KCL, imaginary
    dv[3] = ω₀ * _gfm_speed(K_p, P_filt, P_set)
    dv[4] = (P - P_filt) / τ_p
    dv[5] = (Q - Q_filt) / τ_q
    return nothing
end

"""
    _static_gfm_bus!(dv, v, esum, p, t)

The power-flow counterpart of `_detailed_gfm_bus!`: state `(V_re, V_im, δ, E)`,
fully algebraic — one unknown more than the machine's static vertex, because the
inverter holds its **bus** voltage and the magnitude it forms behind `X_c` is what
that costs (D11). The machine's static vertex holds `|E| = E′` instead, which is why
it needs no fourth unknown; the inverter's `V_set` means the same thing here as in
`ac_powerflow` and in the swing tier (the magnitude at the bus), and one field does
not get two meanings.

Two residuals are Kirchhoff's; the other two are switched by `mode`, with the
machine's codes:

  - `_PF_SOLVE` — `P − P_set` and `|V| − V_set`: a PV bus.
  - `_PF_PIN`   — `δ − δ_target` and `|V| − V_set`: the slack, whose power is free.
  - `_PF_HOLD`  — `δ − δ_target` and `E − E_held`: the post-event re-initialisation,
                  which holds the differential states (the angle, and the voltage the
                  filtered reactive power sets) and restores the algebraic ones.

`istat` is the in-service flag, as in the dynamic vertex: a tripped inverter's
static vertex injects nothing, and `_PF_HOLD` still pins its two unknowns.

Parameters `p = (P_set, V_set, X_c, G, B, a_i, a_p, mode, δ_target, E_held, istat)`.
"""
function _static_gfm_bus!(dv, v, esum, p, t)
    Vre, Vim, δ, E       = v[1], v[2], v[3], v[4]
    P_set, V_set, X_c    = p[1], p[2], p[3]
    G, B, a_i, a_p       = p[4], p[5], p[6], p[7]
    mode, δ_target, E_held = p[8], p[9], p[10]
    istat                = p[11]
    Ire, Iim, P, _ = _gfm_current(Vre, Vim, δ, E, X_c)
    Ire, Iim, P = istat * Ire, istat * Iim, istat * P
    Lre, Lim = _load_current(Vre, Vim, G, B, a_i, a_p)
    dv[1] = Ire - Lre + esum[1]
    dv[2] = Iim - Lim + esum[2]
    dv[3] = mode > 0.5 ? (δ - δ_target) : (P - P_set)
    dv[4] = mode > 1.5 ? (E - E_held) : (hypot(Vre, Vim) - V_set)
    return nothing
end

"""
    _static_machine_bus!(dv, v, esum, p, t)

The power-flow counterpart of `_detailed_machine_bus!`: state `(V_re, V_im, δ)`,
fully algebraic. Two residuals are the same Kirchhoff balance; the third is
switched by `mode` (see the header):

  - `mode = 0` — `Pe − Pset`. The machine holds its scheduled power; `δ` is the
    unknown. A PV bus, with `|E|` rather than `|V|` specified, which is what a
    constant-`E` machine behind a reactance actually is.
  - `mode = 1` — `δ − δ_target`. The rotor angle is held; the machine's power is
    whatever the network gives it. Used for the slack (target `0`, supplying the
    angle reference).
  - `mode = 2` — `δ − δ_target` again, but the machine's current comes from its
    **transient** stator algebra at the `(E′q, E′d)` carried in the parameters
    rather than from the steady-state source. This is the post-event
    re-initialisation, and it needed a third mode rather than reusing mode 1: the
    steady-state source is a statement about a machine at rest (`Ẽ` on the q-axis,
    magnitude fixed), and once the flux is allowed to move that statement is false
    mid-transient. At the frozen-flux degeneration the two modes agree exactly,
    which is why step 1 could get away with two.

`ω` and `ΔPm` do not appear because they are zero at a steady state and enter no
algebraic equation — which is exactly what makes back-substitution possible.
`E′q`/`E′d` appear as PARAMETERS, not states, for the same reason: in mode 2 they
are held, not solved for.
"""
function _static_machine_bus!(dv, v, esum, p, t)
    Vre, Vim, δ = v[1], v[2], v[3]
    Pset, E, Xq, Ra       = p[1], p[2], p[3], p[4]
    G, B, a_i, a_p        = p[5], p[6], p[7], p[8]
    mode, δ_target, mstat = p[9], p[10], p[11]
    Xd′, Xq′, E′q, E′d    = p[12], p[13], p[14], p[15]
    if mode > 1.5
        _, _, Ire, Iim, _ = _stator(Vre, Vim, δ, E′q, E′d, Ra, Xd′, Xq′, mstat)
        Pe = zero(Ire)                          # unused in this mode; see below
    else
        Ire, Iim, Pe = _machine_injection(Vre, Vim, δ, E, Ra, Xq, mstat)
    end
    Lre, Lim = _load_current(Vre, Vim, G, B, a_i, a_p)
    dv[1] = Ire - Lre + esum[1]
    dv[2] = Iim - Lim + esum[2]
    dv[3] = mode > 0.5 ? (δ - δ_target) : (Pe - Pset)
    return nothing
end

# ─────────────────────────────────────────────────────────────────────────────
# Preconditions
# ─────────────────────────────────────────────────────────────────────────────

"""
    _assert_shed_denomination(net, shed)

**A shed ladder steps a machine's `Pm`, and at this tier `Pm` is MECHANICAL power,
not a net injection.** That is the whole difference the tier bought, and it makes
the classical tier's shed convention wrong here the moment a `Load` exists.

At the classical tier `Pm` is generation minus load at that bus, so disconnecting a
block of load raises it by exactly the block (`engines/swing.jl`, `_swing_shed!`).
Here the load is a separate element with its own voltage dependence — step 6's
mechanism — so raising `Pm` adds *generation* instead of removing *load*, and the
two differ by exactly the `|V|`-dependence that step built. On a model whose load is
folded into the machines' net injections (`iberia_two_area.jl`'s two areas, and every
M2/M3 fixture) the two are the same operation and the ladder carries over unchanged.

So the rule is the boundary and not a caveat: a ladder is refused, by name, on a
model that carries a `Load`. The step that lifts it is the one that gives
`LoadShedStage` a load to bind to rather than a machine.
"""
function _assert_shed_denomination(net::NetworkModel, shed)
    (isempty(shed) || isempty(net.loads)) && return nothing
    throw(ArgumentError(
        "DetailedEngine: `shed` is refused on a model carrying a Load " *
        "($(join([l.id for l in net.loads], ", "))). A ladder steps its machine's " *
        "`Pm`, which at this tier is MECHANICAL power — so it would add generation " *
        "rather than disconnect load, and the two differ by exactly the " *
        "voltage-dependence of the ZIP model (M5 step 6). The convention carries " *
        "only where the load is folded into a machine's net injection, which is " *
        "what every model without a `Load` does. A ladder bound to a Load is the " *
        "step that lifts this."))
end

"""
    _assert_detailed_tier(net::NetworkModel)

What this engine can represent, refused at build time by name — the same shape
`_assert_classical_tier` and `reference/src/oracle.jl` use.

The restrictions here are the OPPOSITE way round from the classical tier's, which
is the point of having two: a machine-free bus is fine (it is why this tier
exists) and a two-machine bus is not (yet), where the classical tier refuses both.
Each rejection names the step that lifts it, so a boundary is never mistaken for a
bug.
"""
function _assert_detailed_tier(net::NetworkModel)
    # M7 step 1 refused every inverter; step 4 built the grid-forming kind and step 5
    # the grid-following one. What is left to refuse about inverters is D5 — a model
    # with nothing to follow — and that runs first thing in `init!`.
    # M6 step 1. `Branch.R` exists in the model and this tier's edge current is
    # `(Vf − Vt)/(jX)`, so a lossy branch would be silently simulated as a lossless
    # one. Refused here until M6 step 3's power flow reads it.
    _assert_lossless_branches(net, "DetailedEngine")
    for (v, ks) in pairs(net.machines_at_bus)
        # M7 step 4: a grid-forming inverter is a source too, and a vertex model holds
        # exactly one. Without inverters this is the pre-M7 check, message for message.
        n_inv = length(net.inverters_at_bus[v])
        n_inv == 0 || length(ks) + n_inv <= 1 || throw(ArgumentError(
            "DetailedEngine: bus $(net.buses[v].id) carries $(length(ks) + n_inv) " *
            "sources (machines and inverters together). A vertex model holds exactly " *
            "one; more is unbuilt work, not a tier boundary."))
        length(ks) <= 1 || throw(ArgumentError(
            "DetailedEngine: bus $(net.buses[v].id) carries $(length(ks)) machines " *
            "($(join([net.machines[k].id for k in ks], ", "))). The canonical model " *
            "expresses this and this engine does not yet: a vertex model's state " *
            "count is fixed at compile time, so a second machine on a bus needs a " *
            "second vertex model rather than a wider one. Not a tier boundary — " *
            "unbuilt work, and named here so it cannot be mistaken for one."))
    end
    # The ZIP shares were refused here through step 5 and are solved as of step 6
    # (`_load_current`). Nothing replaces the rejection: `Load` already validates
    # that the three shares are non-negative and sum to one, and every split of
    # that sum is now integrated on both the dynamic and the power-flow path.
    return nothing
end

# ─────────────────────────────────────────────────────────────────────────────
# Building the two networks
# ─────────────────────────────────────────────────────────────────────────────

# The bus graph, shared by both networks. Identical to `SwingEngine`'s, and for
# the same reason: `NetworkModel` has already rejected parallel circuits and
# islands, so one edge per bus pair is exact.
function _detailed_graph(net::NetworkModel)
    bt = branch_topology(net)
    g = Graphs.SimpleGraph(length(net.buses))
    for e in eachindex(bt.src)
        Graphs.add_edge!(g, bt.src[e], bt.dst[e])
    end
    return g, bt
end

const _DETAILED_EDGE_PSYM = [:X, :status]

_detailed_edge() = NetworkDynamics.EdgeModel(
    g = NetworkDynamics.AntiSymmetric(_branch_current!),
    outsym = [:I_re, :I_im], psym = _DETAILED_EDGE_PSYM, name = :branch)

# The load seen at each VERTEX: the nominal admittance `Y = conj(S)/|V₀|²` with
# `|V₀| = 1`, plus the two ZIP shares that scale it (`_load_current`). Zero
# throughout where a bus carries no load, which is arithmetically no load rather
# than a branch in the RHS. `a_z` is not returned — it is `1 − a_i − a_p` and
# `_load_current` uses it in that form. Converted through `load_arrays`, the one
# place loads convert.
function _bus_load(net::NetworkModel)
    la = load_arrays(net)
    nb = length(net.buses)
    G   = zeros(Float64, nb)
    B   = zeros(Float64, nb)
    a_i = zeros(Float64, nb)
    a_p = zeros(Float64, nb)
    for k in eachindex(la.bus)
        v = la.bus[k]
        G[v]   =  la.P[k]
        B[v]   = -la.Q[k]
        a_i[v] =  la.a_i[k]
        a_p[v] =  la.a_p[k]
    end
    return G, B, a_i, a_p
end

# The kind of inverter vertex `v` carries — `:none`, `:grid_forming` or
# `:grid_following`. After `_assert_detailed_tier` a bus carries at most one.
_inv_kind(net::NetworkModel, v::Integer) =
    isempty(net.inverters_at_bus[v]) ? :none : net.inverters[net.inverters_at_bus[v][1]].mode

# The dynamic (DAE) network: a machine vertex where there is a machine, a
# grid-forming vertex where there is an inverter (M7 step 4), a passive vertex where
# there is neither. Heterogeneous vertex vectors and zero mass-matrix rows were both
# measured to work before any of this was written.
# One vertex kind: its right-hand side, state and parameter names, and mass-matrix
# diagonal. `metered = true` appends a `PLLMeter`'s three states and gains (M7 step 6)
# through `_Metered`, which leaves the kind's own equations exactly as they were.
function _detailed_vertex(f, sym, psym, mass, name; metered::Bool = false)
    metered || return NetworkDynamics.VertexModel(
        f = f, g = NetworkDynamics.StateMask(1:2), sym = sym, psym = psym,
        mass_matrix = LinearAlgebra.Diagonal(mass), name = name)
    return NetworkDynamics.VertexModel(
        f = _Metered(f, length(sym), length(psym)), g = NetworkDynamics.StateMask(1:2),
        sym = [sym; :θ_meter; :Δω_meter; :Δω_i_meter],
        psym = [psym; :K_meter_p; :K_meter_i; :τ_meter],
        mass_matrix = LinearAlgebra.Diagonal([mass; 1.0; 1.0; 1.0]),
        name = Symbol(name, :_metered))
end

# `metered[v]` says whether bus `v` carries a `PLLMeter`. All `false` — the default —
# builds exactly the four vertex models this function built before meters existed,
# so every run without a meter is the network it was.
function _dynamic_network(net::NetworkModel, g,
                          metered::AbstractVector{Bool} = falses(length(net.buses)))
    kinds = (
        machine = (_detailed_machine_bus!,
                   [:V_re, :V_im, :δ, :ω, :ΔPm, :E′q, :E′d, :Efd],
                   [:Pm, :Xd, :Xq, :Xd′, :Xq′, :Td0′, :Tq0′, :Ra,
                    :H, :D, :ω₀, :invR, :headroom, :Tg, :G, :B, :a_i, :a_p, :mstat,
                    :K_A, :T_E, :Efd_min, :Efd_max, :Vref,
                    :rate, :t_start, :duration],
                   [0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0], :machine_bus),
        passive = (_detailed_passive_bus!, [:V_re, :V_im], [:G, :B, :a_i, :a_p],
                   [0.0, 0.0], :passive_bus),
        gfm = (_detailed_gfm_bus!, [:V_re, :V_im, :δ, :P_filt, :Q_filt],
               [:P_set, :K_p, :τ_p, :ω₀, :K_q, :τ_q, :V_ref, :X_c, :G, :B, :a_i, :a_p,
                :istat],
               [0.0, 0.0, 1.0, 1.0, 1.0], :gfm_bus),
        gfl = (_detailed_gfl_bus!, [:V_re, :V_im, :θ_pll, :Δω, :Δω_i],
               [:i_d, :i_q, :K_pll_p, :K_pll_i, :τ_pll, :G, :B, :a_i, :a_p],
               [0.0, 0.0, 1.0, 1.0, 1.0], :gfl_bus))
    # One model object per (kind, metered) pair actually used — NetworkDynamics
    # batches vertices that share a model.
    cache = Dict{Tuple{Symbol,Bool},Any}()
    model(k, m) = get!(() -> _detailed_vertex(kinds[k]...; metered = m), cache, (k, m))
    kind(v) = !isempty(net.machines_at_bus[v]) ? :machine :
              _inv_kind(net, v) === :grid_forming ? :gfm :
              _inv_kind(net, v) === :grid_following ? :gfl : :passive
    verts = [model(kind(v), metered[v]) for v in 1:length(net.buses)]
    return NetworkDynamics.Network(g, verts, [_detailed_edge() for _ in 1:Graphs.ne(g)])
end

# The static network: same graph, same edges, same Kirchhoff residual, machines
# reduced to `(V_re, V_im, δ)` with the switchable third equation.
function _static_network(net::NetworkModel, g)
    vmachine = NetworkDynamics.VertexModel(
        f = _static_machine_bus!, g = NetworkDynamics.StateMask(1:2),
        sym = [:V_re, :V_im, :δ],
        psym = [:Pset, :E, :Xq, :Ra, :G, :B, :a_i, :a_p, :mode, :δ_target, :mstat,
                :Xd′, :Xq′, :E′q, :E′d],
        mass_matrix = LinearAlgebra.Diagonal(zeros(3)), name = :pf_machine_bus)
    vpassive = NetworkDynamics.VertexModel(
        f = _detailed_passive_bus!, g = NetworkDynamics.StateMask(1:2),
        sym = [:V_re, :V_im], psym = [:G, :B, :a_i, :a_p],
        mass_matrix = LinearAlgebra.Diagonal(zeros(2)), name = :pf_passive_bus)
    vgfm = NetworkDynamics.VertexModel(
        f = _static_gfm_bus!, g = NetworkDynamics.StateMask(1:2),
        sym = [:V_re, :V_im, :δ, :E],
        psym = [:P_set, :V_set, :X_c, :G, :B, :a_i, :a_p, :mode, :δ_target, :E_held,
                :istat],
        mass_matrix = LinearAlgebra.Diagonal(zeros(4)), name = :pf_gfm_bus)
    vgfl = NetworkDynamics.VertexModel(
        f = _static_gfl_bus!, g = NetworkDynamics.StateMask(1:2),
        sym = [:V_re, :V_im],
        psym = [:P, :Q, :i_d, :i_q, :θ_held, :mode, :G, :B, :a_i, :a_p],
        mass_matrix = LinearAlgebra.Diagonal(zeros(2)), name = :pf_gfl_bus)
    verts = [!isempty(net.machines_at_bus[v]) ? vmachine :
             _inv_kind(net, v) === :grid_forming ? vgfm :
             _inv_kind(net, v) === :grid_following ? vgfl : vpassive
             for v in 1:length(net.buses)]
    return NetworkDynamics.Network(g, verts, [_detailed_edge() for _ in 1:Graphs.ne(g)])
end

# WHY THIS TIER HAS NO `isoutofdomain` PREDICATE, MEASURED RATHER THAN ASSUMED
# (M5 step 5). One was written here first, on the plan's instruction and by analogy
# with `SwingEngine`'s `ΔPm` guard. It does not work, and the reason is not specific
# to this tier — it is a property of pairing a step-rejecting domain guard with a
# saturation in the derivative.
#
# THE MEASUREMENT. `regulator_bus_system(; Efd_max = 0.95)`, line trip at t = 1 s,
# `Rodas5P` at reltol 1e-9:
#
#   guard on,  K_A = 200, T_E = 0.05  -> MaxIters at t = 1.0021, dt = 9.1e-11
#   guard on,  K_A =  50, T_E = 0.2   -> MaxIters at t = 1.0361, dt = 1.7e-09
#   guard on,  K_A =  20, T_E = 0.5   -> MaxIters at t = 1.2560, dt = 1.5e-08
#   guard off, same case              -> Success, and Efd exceeds its ceiling by
#                                        3.4e-8 pu, once, and never more
#
# In every failing run `Efd = 0.94999999…`: the state is approaching the ceiling
# from BELOW and cannot arrive. On a raw solve of the same right-hand side the guard
# accepted 199,944 steps without reaching it.
#
# WHY. Above the limit the saturated derivative is zero, so the ceiling is not an
# attractor the solution crosses — it is a point the solution has to LAND on. The
# guard accepts a step only if it lands at or below `limit + 1e-10`. As the state
# closes on the limit, the derivative there is still finite (here 83 pu/s), so any
# step of size `h` overshoots by `≈ 83h`; to satisfy the guard, `h` must be under
# `1.2e-12`. Do that and the state is closer still, and the next `h` must be smaller
# again. The acceptance window is narrower than the precision with which a step can
# be aimed, so it shrinks geometrically and the run dies. Nothing about the exciter
# causes this; a fast state is only what makes it happen inside a test's horizon.
#
# THE CLAIM THIS FALSIFIES IS WRITTEN IN THIS REPO. `engines/swing.jl` says of its
# own guard: "During continuous integration it cannot stall, because the derivative
# is already zero at the ceiling, which puts the solution *at* headroom, not above
# it." The derivative IS zero at the ceiling; what does not follow is that the
# solution gets there. `SwingEngine`'s and `FrequencyResponseEngine`'s guards have
# the same construction — and they are NOT stalling, which was worth measuring
# rather than assuming in either direction. Driven onto its headroom and run for
# 20,000 s, a `SwingEngine` governor LANDS: `ΔPm` settles 3.1e-11 pu ABOVE its
# ceiling and stays there, `dt` stays around 0.09 s, nothing is rejected in a loop.
#
# THE REASON IS THE ONE NUMBER, AND NOBODY CHOSE IT. The guard's window is an
# absolute `1e-10`, and the overshoot a state produces on the step that lands is
# set by how fast that state is. A governor with a 1 s lag overshoots by 3.1e-11
# and fits inside the window with a factor of three to spare; this exciter with a
# 0.05 s lag needs about 5e-8 and does not fit at all. So `SwingEngine`'s guard is
# not broken — it is inside its margin by 3x, on a constant that was written for
# round-off rather than for this. Measured in `test/m5_detailed.jl` and left alone
# here: changing it would move M2, M3 and M4 numbers, which is not this step's to
# decide.
#
# WHAT BOUNDS THE STATE INSTEAD, and it is the thing that was always doing the work:
# the saturation in the derivative. Above the limit the derivative is zero, so the
# state cannot continue to rise; the only excursion possible is the overshoot of the
# single step that crosses, and that is what the 3.4e-8 above is. It is asserted as a
# NUMBER in `test/`, at two tolerances, rather than enforced by a guard that costs
# the run.
#
# WHAT IS LEFT OVER AFTER THE GUARD IS GONE, ALSO MEASURED. A hard saturation makes
# the right-hand side DISCONTINUOUS in the state it saturates, and a stiff adaptive
# solver is entitled to find that hard. Swept over the ceiling on the same fixture
# (`Efd_max` = 1.05, 1.1, 1.15, 1.2, 1.3, 1.5, 2.0, 3.0, Rodas5P at reltol 1e-9),
# seven of the eight complete and ONE does not: at `Efd_max = 1.2` the step size
# collapses to 1.3e-10 at the crossing and the run gives up. It is an isolated point,
# not a threshold — 1.15 and 1.3 both run — and it is isolated in the TOLERANCE too:
# the same case completes at reltol 1e-6 (overshoot 8.3e-6) and at 1e-11 (6.1e-10)
# and fails only at the 1e-9 in between. Non-monotone in two parameters at once is
# conditioning at the kink, not a boundary of the model. `FBDF` completes it with an
# overshoot of 1.7e-9, and `init!` already takes a `solver` keyword, so the
# workaround is a parameter rather than a change. Recorded here with the sweep because a default that
# fails at one isolated value is exactly the kind of thing that gets rediscovered as
# a physics finding.
#
# WHAT A DOMAIN GUARD IS STILL RIGHT FOR is the case M1 built it for: a limit that
# MOVES, leaving the state stranded far outside it. That is not a landing problem, it
# is a data problem, and it is fixed where M1 fixed it — at the event boundary, by
# re-initialising the state into the new limit. Our limits are constant model data
# and cannot move, and `init!` refuses a dispatch outside them.


# ─────────────────────────────────────────────────────────────────────────────
# The power flow, and the checks that make it a result rather than a fixpoint
# ─────────────────────────────────────────────────────────────────────────────

"""
    _check_voltage_band(net, Vm, what)

`|V| in [0.9, 1.1]` at every bus, `Vm` being the magnitudes in vertex order.

**This is the discriminator.** Not a comfort check on voltage quality — it is the
*only* thing that separates the true solution from the collapsed spurious one,
whose residual is 400x tighter (see the header). Split out of `_check_power_flow`
at M6 step 3 so the AC power flow **inherits the check itself** rather than
re-deriving the band (`m6-context.md` D6, D10).
"""
function _check_voltage_band(net::NetworkModel, Vm::AbstractVector{Float64},
                             what::AbstractString)
    for (v, b) in pairs(net.buses)
        _PF_VMIN <= Vm[v] <= _PF_VMAX || throw(ErrorException(
            "$what: bus $(b.id) solved to |V| = $(Vm[v]) pu, outside [$_PF_VMIN, $_PF_VMAX]. " *
            "A collapsed-voltage solution is SELF-CONSISTENT and converges to a " *
            "TIGHTER residual than the true one (measured: 5.0e-16 against 1.8e-13), " *
            "so this band is the discriminator and the residual is not. Either the " *
            "case is genuinely infeasible, or the solve fell into the spurious basin — " *
            "or, with a grid-following inverter pushing power through a reactance, it " *
            "is a REAL operating point on the right branch that sits below the band: " *
            "such an inverter reaches its transfer limit only at |V| ≈ 0.71 pu, so " *
            "between the band's edge and that limit the band IS the limit this repo " *
            "enforces (m7-context.md D13)."))
    end
    return nothing
end

"""
    _check_branch_ratings(net, flows, what)

Every branch's `|S|` (pu, indexed by branch) within its thermal rating, so a
"converged" answer that needs a line to carry three times its limit is refused
rather than reported.
"""
function _check_branch_ratings(net::NetworkModel, flows::AbstractVector{Float64},
                               what::AbstractString)
    for (e, br) in pairs(net.branches)
        mva = flows[e] * net.S_base
        mva <= br.rating || throw(ErrorException(
            "$what: branch $(br.id) carries $mva MVA against a rating of " *
            "$(br.rating) MVA. The solve converged, but onto a dispatch the network " *
            "cannot physically run."))
    end
    return nothing
end

"""
    _check_residual(residual, what)

The solve's residual below `1e-10`. **Last, deliberately**: it is necessary and
conspicuously not sufficient, and the band is what actually decides.
"""
function _check_residual(residual::Float64, what::AbstractString)
    residual < _PF_RESIDUAL || throw(ErrorException(
        "$what: the network solve converged to a residual of $residual, above the " *
        "$_PF_RESIDUAL threshold. This is necessary and not sufficient — the " *
        "|V| band check is what actually separates the true solution from a " *
        "self-consistent collapsed one."))
    return nothing
end

"""
    _check_power_flow(net, V, flows, residual, what)

The solution is CHECKED, NOT TRUSTED (m5-prestudy.md §4, D7). The three checks
above, composed — in significance order, which since M6 step 3 is also the order
they **execute** in (`m6-context.md` D10; before that the residual ran first while
this docstring already listed it third).

  1. `_check_voltage_band` — the discriminator.
  2. `_check_branch_ratings` — converged onto a dispatch the network cannot run.
  3. `_check_residual` — necessary, conspicuously not sufficient.

`V` is complex here because this caller has complex voltages to hand; the band
check takes magnitudes, which is what the AC power flow solves in directly.
"""
function _check_power_flow(net::NetworkModel, V::Vector{ComplexF64},
                           flows::Vector{Float64}, residual::Float64,
                           what::AbstractString)
    _check_voltage_band(net, abs.(V), what)
    _check_branch_ratings(net, flows, what)
    _check_residual(residual, what)
    return nothing
end

# |S| on each branch, from the solved bus voltages: `S = V_from · conj(I)`.
# Computed from the same current expression the edge model integrates, so the
# check and the physics cannot come to hold different conventions.
function _branch_flows(net::NetworkModel, bt, V::Vector{ComplexF64},
                       status::Vector{Float64})
    n = length(net.branches)
    out = Vector{Float64}(undef, n)
    for e in 1:n
        d = V[bt.src[e]] - V[bt.dst[e]]
        I = status[e] * d / (im * bt.X[e])
        out[e] = abs(V[bt.src[e]] * conj(I))
    end
    return out
end

# ─────────────────────────────────────────────────────────────────────────────
# The engine
# ─────────────────────────────────────────────────────────────────────────────

"""
    _GFMIndex

Where the detailed tier keeps each grid-forming inverter (M7 step 4), in model (bus)
order: its flat state and parameter indices in both networks, and the system-base
numbers the read-outs need (`K_p` for the droop speed, `K_q` for the formed voltage,
`H` for the virtual-inertia COI weight). One concretely typed record rather than
fourteen more engine fields, and empty on every model without inverters — which is
what keeps every pre-M7 read-out the arithmetic it was.
"""
struct _GFMIndex
    ids::Vector{Symbol}
    bus::Vector{Int}
    δ_idx::Vector{Int}
    Pf_idx::Vector{Int}
    Qf_idx::Vector{Int}
    Pset_pidx::Vector{Int}
    Vref_pidx::Vector{Int}
    K_p::Vector{Float64}
    K_q::Vector{Float64}
    H::Vector{Float64}
    sδ_idx::Vector{Int}
    sE_idx::Vector{Int}
    smode_pidx::Vector{Int}
    sδtarget_pidx::Vector{Int}
    sEheld_pidx::Vector{Int}
    # M7 step 7 — the in-service flag in each network. `H` above is ZEROED when the
    # inverter trips (its virtual inertia leaves with it, D15), so it is the live
    # weight rather than a property of the inverter.
    stat_pidx::Vector{Int}
    sstat_pidx::Vector{Int}
end

"""
    _GFLIndex

The grid-following inverters' places in both networks (M7 step 5), `_GFMIndex`'s
counterpart: the PLL's three states, the current setpoint's two parameters, and the
static vertex's mode and held angle. Empty on every model without one.
"""
struct _GFLIndex
    ids::Vector{Symbol}
    bus::Vector{Int}
    θ_idx::Vector{Int}
    Δω_idx::Vector{Int}
    Δωi_idx::Vector{Int}
    id_pidx::Vector{Int}
    iq_pidx::Vector{Int}
    smode_pidx::Vector{Int}
    sθheld_pidx::Vector{Int}
    # M7 step 7 — the static vertex's copy of the current setpoint, which a trip
    # zeroes alongside the dynamic one (`id_pidx`/`iq_pidx`).
    sid_pidx::Vector{Int}
    siq_pidx::Vector{Int}
end

"""
    _MeterIndex

The `PLLMeter`s' places in the dynamic network (M7 step 6), in the order the caller
armed them: the bus each reads, and its three states. The static network has no
meter in it — a meter holds nothing, so a re-initialisation leaves its states where
they are, which is exactly what makes a phase jump read as a spike. Empty when no
meter is armed.
"""
struct _MeterIndex
    buses::Vector{Symbol}
    bus::Vector{Int}
    θ_idx::Vector{Int}
    Δω_idx::Vector{Int}
    Δωi_idx::Vector{Int}
end

"""
    DetailedEngine{NW,SW,I,R} <: SimulationEngine

The detailed (DAE) tier's engine: bus voltages as algebraic states, machines on
terminal buses, a stiff solver.

**Playback-first (m5-context.md D2).** It implements `init!` / `solve!` /
`state_series` / `inject!`. `step!` — wall-clock stepping — is deliberately NOT
implemented: whether a stiff DAE steps in real time is a measurement (S3), not an
assumption, and the mode router exists precisely so a tier can be playback-only.

Four type parameters rather than `SwingEngine`'s three, because there are two
compiled networks: the dynamic one that is integrated and the static one that is
solved for the steady state and re-solved after an event.
"""
mutable struct DetailedEngine{NW,SW,I,R} <: SimulationEngine
    model::NetworkModel
    nw::NW
    nw_static::SW
    slack::Symbol
    lines_online::Set{Int}
    params::Vector{Float64}          # shared with integrator.p
    p_static::Vector{Float64}
    # The static solve's own state, carried between calls so a re-initialisation
    # seeds from where the network actually IS rather than from flat. That is not
    # an optimisation: the collapsed spurious solution's basin reaches to within
    # 2.5 rad of the true one, so a flat re-seed after an event is a real risk.
    u_static::Vector{Float64}
    dt::Float64
    integrator::I
    f0::Float64
    ω₀::Float64
    ids::Vector{Symbol}
    machine_bus::Vector{Int}
    δ_idx::Vector{Int}
    ω_idx::Vector{Int}
    ΔPm_idx::Vector{Int}
    E′q_idx::Vector{Int}
    E′d_idx::Vector{Int}
    Efd_idx::Vector{Int}
    Vre_idx::Vector{Int}
    Vim_idx::Vector{Int}
    Pm_pidx::Vector{Int}
    Vref_pidx::Vector{Int}
    status_pidx::Vector{Int}
    sVre_idx::Vector{Int}
    sVim_idx::Vector{Int}
    sδ_idx::Vector{Int}
    sPset_pidx::Vector{Int}
    smode_pidx::Vector{Int}
    sδtarget_pidx::Vector{Int}
    sstatus_pidx::Vector{Int}
    sE′q_pidx::Vector{Int}
    sE′d_pidx::Vector{Int}
    branch_to_edge::Vector{Int}
    branch_of_buses::Dict{Tuple{Symbol,Symbol},Int}
    H::Vector{Float64}
    w::Vector{Float64}
    Σw::Float64
    traj::R
    sample::Vector{Float64}
    log::Vector{EngineEvent}
    n_dropped::Int
    nadir::Float64
    # M3's protection, wired at this tier (M5 step 7, D8). Owned by the engine for
    # `SwingEngine`'s reason: a ladder and a relay are LIVE — they latch what has
    # fired — so the caller must not be able to hold a second reference to one and
    # arm two engines from it. `ramps` is inert data and is kept only so
    # `generation_ramp` can report what was scheduled.
    ladders::Vector{ShedLadder}
    relays::Vector{OutOfStepRelay}
    ramps::Vector{Pair{Symbol,GenerationRamp}}
    # M7 step 4 — the grid-forming inverters. `H`/`w` above stay machine-only; `Σw`
    # counts the inverters' virtual inertia too.
    gfm::_GFMIndex
    # M7 step 5 — the grid-following inverters. Weight zero in every aggregate (D6):
    # a PLL's estimate is a measurement, never averaged into `ω_coi`.
    gfl::_GFLIndex
    # M7 step 6 — measurement-only PLLs. Weight zero everywhere, for D6's reason.
    meters::_MeterIndex
    # M7 step 7 (D15) — the source trip. A machine's in-service flag in both networks
    # and the three governor/ramp parameters a trip zeroes; `online` is every source
    # (machines and both inverter kinds) still in service, the swing tier's `online`.
    mstat_pidx::Vector{Int}
    smstat_pidx::Vector{Int}
    invR_pidx::Vector{Int}
    hr_pidx::Vector{Int}
    rate_pidx::Vector{Int}
    online::Set{Symbol}
end

# Run the static network to convergence from the seeds in `u`, and read the answer
# back. `u` is a full static state vector, mutated in place with the solution.
#
# `t = 0.0` explicitly, for the reason M3 step 5 paid for: `find_fixpoint` defaults
# its evaluation time to `NaN`, which is harmless only while no RHS reads `t`.
# Nothing here reads it today; naming it costs nothing and removes the trap.
function _run_static!(eng_nw, u::Vector{Float64}, p::Vector{Float64})
    s = NetworkDynamics.NWState(eng_nw, copy(u), copy(p))
    fp = NetworkDynamics.find_fixpoint(eng_nw, s; t = 0.0)
    u .= NetworkDynamics.uflat(fp)
    du = similar(u)
    eng_nw(du, u, p, 0.0)
    return maximum(abs, du)
end

# Everything the rest of the engine wants out of a converged static solve.
function _read_static(net::NetworkModel, bt, u::Vector{Float64}, p::Vector{Float64},
                      sVre, sVim, sδ, sstatus, ma)
    nb = length(net.buses)
    V = Vector{ComplexF64}(undef, nb)
    for v in 1:nb
        V[v] = complex(u[sVre[v]], u[sVim[v]])
    end
    nm = length(net.machines)
    δ  = Vector{Float64}(undef, nm)
    Pe = Vector{Float64}(undef, nm)
    Iinj = Vector{ComplexF64}(undef, nm)
    for k in 1:nm
        v = ma.bus[k]
        δ[k] = u[sδ[k]]
        # Meaningful in the two STEADY modes only: it evaluates the steady-state
        # source, whose magnitude `ma.E[k]` is a statement about a machine at rest.
        # `_reinitialise_algebraic!` (mode `_PF_HOLD`) discards it for that reason.
        ire, iim, pe = _machine_injection(real(V[v]), imag(V[v]), δ[k],
                                          ma.E[k], ma.Ra[k], ma.Xq[k], 1.0)
        Pe[k] = pe
        # THE TERMINAL CURRENT, RETURNED RATHER THAN RECOMPUTED (M6 step 4). `init!`
        # used to call `_machine_injection` a second time with these exact arguments
        # to get it. Returning it is what lets the AC-seeded path hand the SAME
        # quantity in from a different source — the power flow's own `S` — without
        # the back-substitution underneath it forking into two copies, which is the
        # thing that would eventually let the two paths come to disagree.
        Iinj[k] = complex(ire, iim)
    end
    status = Float64[p[sstatus[e]] for e in eachindex(net.branches)]
    flows = _branch_flows(net, bt, V, status)
    return V, δ, Pe, Iinj, flows
end

"""
    init!(DetailedEngine, net::NetworkModel; t0=0.0, dt=0.02, slack=the model's slack bus,
          solver=Rodas5P(), reltol, abstol, powerflow=nothing, meters=PLLMeter[],
          capacity)

Build the detailed tier's engine: compile both networks, solve the power flow,
back-substitute every machine state, and place a stiff integrator on the result.

`meters` (M7 step 6) arms measurement-only [`PLLMeter`](@ref)s, at most one per bus,
each locked on its bus voltage at rest. They inject nothing; with none armed the
network compiled is the one it always was.

`powerflow` replaces the *first* of those with M6's other steady-state solve: pass
an [`ac_powerflow`](@ref) solution and the engine starts from it instead of from its
own fixpoint. Everything after the solve — the back-substitution, the `Vref`
derivation, the `Efd` limit check and both residual checks — is the same code on
either path. This is M6 step 4's oracle A: the two solves fix different unknowns
(`m6-context.md` D5), so a run from one that is flat under the other's equations is
the two agreeing without either being declared correct. `_seed_from_powerflow`
carries what it refuses and why (a lossy branch, and two machines on one bus).

`slack` names the machine whose rotor angle is the reference, and whose mechanical
power is therefore free while every other machine holds its schedule. It is a
keyword rather than model data because it is a decision about a *case*, not a
property of the network — but it is **not** merely a gauge choice, and the header
carries the measurement that says so: with a voltage-dependent load anywhere in
the model, two slacks give two different (both correct) dispatches.

`maxiters` is the **integrator's** step cap, not `solve!`'s: the two are separate
counters and this one is reached first (its library default is 1e5).

`Vref` never appears in this signature, and that is the point: the exciter's
setpoint is **derived** from the solved equilibrium (`Vref = |V| + Efd/K_A`), so a
machine with a regulator starts at rest exactly as one without does. The field
voltage itself comes from the power flow too (`Efd = E′q + (Xd − X′d)·Id`), and is
refused here if it falls outside the machine's own limits.

The steady state is **checked** (`_check_power_flow`) and then checked again a
different way: the dynamic network's own residual at the back-substituted point
must be at machine precision. That second check is what proves the
back-substitution, and it is separate from the flat run for a reason — it fails at
build time with a number attached, where a flat run fails later with a wobble.
"""
function init!(::Type{DetailedEngine}, net::NetworkModel; t0::Real = 0.0,
               dt::Real = _DETAILED_DT0,
               slack::Union{Symbol,Nothing} = nothing,
               solver = OrdinaryDiffEq.Rodas5P(),
               reltol::Real = _ENGINE_RELTOL,
               abstol::Real = _ENGINE_ABSTOL,
               dtmax::Real = Inf,
               # The INTEGRATOR's own step cap, distinct from `solve!`'s playback
               # cap and reached first: OrdinaryDiffEq defaults it to 1e5, and a
               # 20 s pole slip on this tier at reltol 1e-8 does not fit inside
               # that. Exposed because the standing "run it again tighter" rule
               # cannot be applied to a tier whose ceiling is unreachable — the
               # same argument that put `reltol`/`abstol` in this signature at M4.
               maxiters::Integer = 1_000_000,
               shed = Pair{Symbol,Vector{LoadShedStage}}[],
               out_of_step = Pair{Tuple{Symbol,Symbol},OutOfStepTrip}[],
               ramp = Pair{Symbol,GenerationRamp}[],
               # M6 step 4's oracle A. `nothing` is the default and every pre-M6
               # call therefore builds the identical engine. DELIBERATELY UNTYPED
               # in the signature: `ACPowerFlow` is defined in `steadystate/`,
               # which `GridSim.jl` includes AFTER the engines on purpose (so that
               # `branch_power`'s primary method stays the classical tier's), and a
               # type annotation here is evaluated when this method is DEFINED —
               # which would invert that ordering. The check is made below, by
               # name, at the one place it can be.
               powerflow = nothing,
               # M7 step 6 — measurement-only PLLs, one bus each (`PLLMeter`).
               meters::AbstractVector{PLLMeter} = PLLMeter[],
               capacity::Integer = _TRAJ_CAPACITY)
    # D5 FIRST (M7 step 5): with no machine and no grid-forming inverter there is no
    # voltage source — and a grid-following inverter has nothing to follow. Before
    # any other guard, so the message names the cause rather than a symptom of it.
    ia = _inverter_arrays(net)
    fa = _gfl_arrays(net)
    isempty(net.machines) && isempty(ia.id) && throw(ArgumentError(
        "DetailedEngine: the model has no machines and no grid-forming inverters, so " *
        "there is no voltage source, no angle reference and no differential state at " *
        "all. " * _nothing_to_follow(net)))
    _assert_detailed_tier(net)
    _assert_shed_denomination(net, shed)
    # M7 step 4. A ladder or a ramp acts on a MACHINE's mechanical power; on a droop
    # inverter's setpoint neither has a meaning anybody has validated. Refused by
    # name, as `SwingEngine` does, rather than as an unknown machine.
    let inv_ids = Set(ia.id)
        for (what, arg) in (("shed", shed), ("ramp", ramp)), pr in arg
            first(pr) in inv_ids && throw(ArgumentError(
                "DetailedEngine: $what is armed on `:$(first(pr))`, which is a " *
                "grid-forming inverter. Load shedding and generation ramps act on a " *
                "machine's power; on an inverter's droop setpoint they are an " *
                "unvalidated model (M7)."))
        end
    end

    ma = machine_arrays(net)
    g, bt = _detailed_graph(net)
    nb, nm, ne = length(net.buses), length(net.machines), length(net.branches)
    ids = Symbol[m.id for m in net.machines]
    G, B, aI, aP = _bus_load(net)
    ω₀ = 2π * net.f0
    t0f = Float64(t0)

    # M6 step 1 (`m6-context.md` D3). The KEYWORD still names a MACHINE — a rotor
    # angle is what this engine pins, and a passive bus has none — but the DEFAULT
    # now reads the model's declared reference bus instead of "whichever machine
    # came first". On every pre-M6 model those are the same machine to the bit:
    # `NetworkModel` defaults `slack` to `machines[1].bus` after the bus sort, so
    # its first machine is `net.machines[1]`, which is what `ids[1]` was.
    #
    # M7 step 4: a grid-forming inverter holds an angle too (the one it forms), so it
    # may be the slack — and with no machine in the model it is the model's default
    # reference bus (m7-context.md D2). With a machine on the slack bus nothing here
    # changes.
    slack_id = slack
    if slack_id === nothing
        vs = net.bus_index[net.slack]
        ks = net.machines_at_bus[vs]
        js = findall(==(vs), ia.bus)
        isempty(ks) && isempty(js) && throw(ArgumentError(
            "DetailedEngine: the model's slack bus :$(net.slack) carries no machine " *
            "and no grid-forming inverter. The slack supplies the angle reference, so " *
            "it must hold one — a passive bus has no rotor angle to pin, nor a formed " *
            "one. Declare a slack bus " *
            "that carries a source, or pass `slack = <id>` explicitly."))
        slack_id = isempty(ks) ? ia.id[js[1]] : net.machines[ks[1]].id
    end
    k_slack = findfirst(==(slack_id), ids)
    j_slack = findfirst(==(slack_id), ia.id)
    k_slack === nothing && j_slack === nothing && throw(ArgumentError(
        "DetailedEngine: slack = :$slack_id is not a machine in this model, nor a " *
        "grid-forming inverter (machines: $(join(ids, ", ")); grid-forming " *
        "inverters: $(join(ia.id, ", "))). The slack supplies the angle reference; " *
        "it must be a source, because a passive bus has no angle to pin."))

    # M7 step 6 — where the meters sit. Refused by name on a bus the model does not
    # have, and two on one bus: a vertex carries one meter's three states, and two
    # identical instruments on one voltage would read the same number twice.
    metered = falses(nb)
    for m in meters
        v = get(net.bus_index, m.bus, 0)
        v == 0 && throw(ArgumentError(
            "DetailedEngine: a PLLMeter is armed on bus :$(m.bus), which is not in the " *
            "model (buses: $(join((b.id for b in net.buses), ", ")))."))
        metered[v] && throw(ArgumentError(
            "DetailedEngine: two PLLMeters are armed on bus :$(m.bus). A bus carries at " *
            "most one — two meters on one voltage are one reading, twice."))
        metered[v] = true
    end

    nw  = _dynamic_network(net, g, metered)
    nws = _static_network(net, g)
    SII = NetworkDynamics.SII

    # Flat indices, resolved once through the symbolic interface — nothing here
    # assumes a stride or an ordering, the discipline `SwingEngine` established.
    Vre_idx = Int[SII.variable_index(nw, NetworkDynamics.VIndex(v, :V_re)) for v in 1:nb]
    Vim_idx = Int[SII.variable_index(nw, NetworkDynamics.VIndex(v, :V_im)) for v in 1:nb]
    δ_idx   = Int[SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :δ)) for k in 1:nm]
    ω_idx   = Int[SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :ω)) for k in 1:nm]
    ΔPm_idx = Int[SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :ΔPm)) for k in 1:nm]
    E′q_idx = Int[SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :E′q)) for k in 1:nm]
    E′d_idx = Int[SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :E′d)) for k in 1:nm]
    Efd_idx = Int[SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :Efd)) for k in 1:nm]
    Pm_pidx = Int[SII.parameter_index(nw, NetworkDynamics.VPIndex(ma.bus[k], :Pm)) for k in 1:nm]
    Vref_pidx = Int[SII.parameter_index(nw, NetworkDynamics.VPIndex(ma.bus[k], :Vref)) for k in 1:nm]

    sVre_idx = Int[SII.variable_index(nws, NetworkDynamics.VIndex(v, :V_re)) for v in 1:nb]
    sVim_idx = Int[SII.variable_index(nws, NetworkDynamics.VIndex(v, :V_im)) for v in 1:nb]
    sδ_idx   = Int[SII.variable_index(nws, NetworkDynamics.VIndex(ma.bus[k], :δ)) for k in 1:nm]
    sPset_pidx    = Int[SII.parameter_index(nws, NetworkDynamics.VPIndex(ma.bus[k], :Pset)) for k in 1:nm]
    smode_pidx    = Int[SII.parameter_index(nws, NetworkDynamics.VPIndex(ma.bus[k], :mode)) for k in 1:nm]
    sδtarget_pidx = Int[SII.parameter_index(nws, NetworkDynamics.VPIndex(ma.bus[k], :δ_target)) for k in 1:nm]
    sE′q_pidx     = Int[SII.parameter_index(nws, NetworkDynamics.VPIndex(ma.bus[k], :E′q)) for k in 1:nm]
    sE′d_pidx     = Int[SII.parameter_index(nws, NetworkDynamics.VPIndex(ma.bus[k], :E′d)) for k in 1:nm]

    # M7 step 4 — the grid-forming inverters' indices, same discipline. Empty on a
    # model without them.
    ni = length(ia.id)
    vidx(nwk, j, s) = SII.variable_index(nwk, NetworkDynamics.VIndex(ia.bus[j], s))
    pidx(nwk, j, s) = SII.parameter_index(nwk, NetworkDynamics.VPIndex(ia.bus[j], s))
    nf = length(fa.id)
    fvidx(nwk, j, s) = SII.variable_index(nwk, NetworkDynamics.VIndex(fa.bus[j], s))
    fpidx(nwk, j, s) = SII.parameter_index(nwk, NetworkDynamics.VPIndex(fa.bus[j], s))
    gfl = _GFLIndex(copy(fa.id), copy(fa.bus),
                    Int[fvidx(nw, j, :θ_pll) for j in 1:nf], Int[fvidx(nw, j, :Δω) for j in 1:nf],
                    Int[fvidx(nw, j, :Δω_i) for j in 1:nf],
                    Int[fpidx(nw, j, :i_d) for j in 1:nf], Int[fpidx(nw, j, :i_q) for j in 1:nf],
                    Int[fpidx(nws, j, :mode) for j in 1:nf], Int[fpidx(nws, j, :θ_held) for j in 1:nf],
                    Int[fpidx(nws, j, :i_d) for j in 1:nf], Int[fpidx(nws, j, :i_q) for j in 1:nf])
    mbus = Int[net.bus_index[m.bus] for m in meters]
    mvidx(j, s) = SII.variable_index(nw, NetworkDynamics.VIndex(mbus[j], s))
    mtr = _MeterIndex(Symbol[m.bus for m in meters], mbus,
                      Int[mvidx(j, :θ_meter) for j in eachindex(meters)],
                      Int[mvidx(j, :Δω_meter) for j in eachindex(meters)],
                      Int[mvidx(j, :Δω_i_meter) for j in eachindex(meters)])
    gfm = _GFMIndex(copy(ia.id), copy(ia.bus),
                    [vidx(nw, j, :δ) for j in 1:ni], [vidx(nw, j, :P_filt) for j in 1:ni],
                    [vidx(nw, j, :Q_filt) for j in 1:ni],
                    [pidx(nw, j, :P_set) for j in 1:ni], [pidx(nw, j, :V_ref) for j in 1:ni],
                    copy(ia.K_p), copy(ia.K_q), copy(ia.H),
                    [vidx(nws, j, :δ) for j in 1:ni], [vidx(nws, j, :E) for j in 1:ni],
                    [pidx(nws, j, :mode) for j in 1:ni], [pidx(nws, j, :δ_target) for j in 1:ni],
                    [pidx(nws, j, :E_held) for j in 1:ni],
                    [pidx(nw, j, :istat) for j in 1:ni], [pidx(nws, j, :istat) for j in 1:ni])
    # M7 step 7 — what a machine trip writes (D15), resolved once like every index.
    mpidx(nwk, k, s) = SII.parameter_index(nwk, NetworkDynamics.VPIndex(ma.bus[k], s))
    mstat_pidx  = Int[mpidx(nw, k, :mstat) for k in 1:nm]
    smstat_pidx = Int[mpidx(nws, k, :mstat) for k in 1:nm]
    invR_pidx   = Int[mpidx(nw, k, :invR) for k in 1:nm]
    hr_pidx     = Int[mpidx(nw, k, :headroom) for k in 1:nm]
    rate_pidx   = Int[mpidx(nw, k, :rate) for k in 1:nm]

    # Branch ⇒ graph edge, through the UNORDERED vertex pair, so there is no
    # positional correspondence to get wrong (`SwingEngine`'s argument, unchanged).
    edge_of_pair = Dict{Tuple{Int,Int},Int}()
    for (ei, ed) in enumerate(Graphs.edges(g))
        edge_of_pair[minmax(Graphs.src(ed), Graphs.dst(ed))] = ei
    end
    branch_to_edge = [edge_of_pair[minmax(bt.src[e], bt.dst[e])] for e in 1:ne]
    status_pidx  = [SII.parameter_index(nw,  NetworkDynamics.EPIndex(branch_to_edge[e], :status)) for e in 1:ne]
    sstatus_pidx = [SII.parameter_index(nws, NetworkDynamics.EPIndex(branch_to_edge[e], :status)) for e in 1:ne]
    X_pidx  = [SII.parameter_index(nw,  NetworkDynamics.EPIndex(branch_to_edge[e], :X)) for e in 1:ne]
    sX_pidx = [SII.parameter_index(nws, NetworkDynamics.EPIndex(branch_to_edge[e], :X)) for e in 1:ne]

    # --- static parameters, then the power flow -------------------------------
    su = zeros(Float64, NetworkDynamics.dim(nws))
    sp = zeros(Float64, NetworkDynamics.pdim(nws))
    for v in 1:nb
        su[sVre_idx[v]] = 1.0                 # the flat start, and the only guess made
        su[sVim_idx[v]] = 0.0
        sp[SII.parameter_index(nws, NetworkDynamics.VPIndex(v, :G))]   = G[v]
        sp[SII.parameter_index(nws, NetworkDynamics.VPIndex(v, :B))]   = B[v]
        sp[SII.parameter_index(nws, NetworkDynamics.VPIndex(v, :a_i))] = aI[v]
        sp[SII.parameter_index(nws, NetworkDynamics.VPIndex(v, :a_p))] = aP[v]
    end
    for k in 1:nm
        su[sδ_idx[k]]        = 0.0
        sp[sPset_pidx[k]]    = ma.Pm[k]
        for (sym, val) in ((:E, ma.E[k]), (:Xq, ma.Xq[k]), (:Ra, ma.Ra[k]),
                           (:Xd′, ma.Xd′[k]), (:Xq′, ma.Xq′[k]), (:mstat, 1.0))
            sp[SII.parameter_index(nws, NetworkDynamics.VPIndex(ma.bus[k], sym))] = val
        end
        sp[smode_pidx[k]]    = k == k_slack ? _PF_PIN : _PF_SOLVE
        sp[sδtarget_pidx[k]] = 0.0
        # Mode 2's held flux. Zero here and never read at initialisation — the power
        # flow runs in the steady modes, and `_reinitialise_algebraic!` writes the
        # live values before it switches the mode.
        sp[sE′q_pidx[k]]     = 0.0
        sp[sE′d_pidx[k]]     = 0.0
    end
    # The grid-forming inverters: a PV bus holding its BUS voltage (D11), the formed
    # magnitude seeded at `V_set` and solved for. `E_held` is read only in `_PF_HOLD`.
    for j in 1:ni
        su[gfm.sδ_idx[j]] = 0.0
        su[gfm.sE_idx[j]] = ia.V_set[j]
        for (sym, val) in ((:P_set, ia.P[j]), (:V_set, ia.V_set[j]), (:X_c, ia.X_c[j]),
                           (:δ_target, 0.0), (:E_held, 0.0), (:istat, 1.0))
            sp[pidx(nws, j, sym)] = val
        end
        sp[gfm.smode_pidx[j]] = j == j_slack ? _PF_PIN : _PF_SOLVE
    end
    # The grid-following inverters (M7 step 5): constant power at the dispatch. The
    # current setpoint and the held angle are read only in `_PF_HOLD`, and are written
    # below once the steady state says what they are.
    for j in 1:nf
        for (sym, val) in ((:P, fa.P[j]), (:Q, fa.Q[j]), (:i_d, 0.0), (:i_q, 0.0),
                           (:θ_held, 0.0))
            sp[fpidx(nws, j, sym)] = val
        end
        sp[gfl.smode_pidx[j]] = _PF_SOLVE
    end
    for e in 1:ne
        sp[sX_pidx[e]]      = bt.X[e]
        sp[sstatus_pidx[e]] = 1.0
    end

    if powerflow === nothing
        res = _run_static!(nws, su, sp)
        V, δ0, Pe, Iinj, flows =
            _read_static(net, bt, su, sp, sVre_idx, sVim_idx, sδ_idx, sstatus_pidx, ma)
        what = "DetailedEngine power flow"
    else
        # M6 STEP 4, ORACLE A. The steady state comes from the OTHER solve — the one
        # whose unknowns and givens are swapped (`m6-context.md` D5) — and everything
        # below this branch is unchanged. That is the whole design: two solves answer
        # two questions, the back-substitution is written once, and the run that
        # follows is flat or one of the two is wrong.
        V, δ0, Pe, Iinj, res = _seed_from_powerflow(net, powerflow, ma)
        flows = _branch_flows(net, bt, V, ones(Float64, ne))
        # `su` AND `sp` ARE LEFT AS BUILT, and that is checked rather than assumed —
        # the AC answer was written into them here first, with a comment about
        # re-seeding after an event, and it was dead code. `u_static`'s only consumer
        # is `_reinitialise_algebraic!`, which overwrites EVERY entry it then reads
        # (each bus's V_re/V_im and each machine's δ — that is the whole static state
        # vector) from the live dynamic state before re-solving. Same for the stale
        # `sp[sPset_pidx]`, which still holds `ma.Pm[k]` while this path's derived
        # `Pm` differs at the slack: the re-solve runs in `_PF_HOLD`, where
        # `_static_machine_bus!` takes `dv[3] = δ − δ_target` and never reads `Pset`
        # at all. Both are inert, and the M6 step 4 sweep runs a seeded engine across
        # a line trip so that stays a measurement.
        what = "DetailedEngine power flow (seeded from ac_powerflow)"
    end
    _check_power_flow(net, V, flows, res, what)

    # --- the grid-forming inverters' operating point (M7 step 4) --------------
    # The formed voltage `E∠δ` behind `X_c`: from the static solve on the fixpoint
    # path, from the power flow's own `S` on the seeded one (`I = conj(S/V)`,
    # `E∠δ = V + jX_c·I` — the machine's `Ẽ` construction with `Ra = 0`). Then the
    # power AT THE SOURCE through `_gfm_current`, the function the RHS calls.
    iδ = Vector{Float64}(undef, ni); iE = Vector{Float64}(undef, ni)
    iP = Vector{Float64}(undef, ni); iQ = Vector{Float64}(undef, ni)
    for j in 1:ni
        vb = ia.bus[j]
        iδ[j], iE[j] = powerflow === nothing ?
            (su[gfm.sδ_idx[j]], su[gfm.sE_idx[j]]) :
            _seed_gfm_from_powerflow(powerflow, vb, V[vb], ia.X_c[j])
        Ire, Iim, iP[j], iQ[j] = _gfm_current(real(V[vb]), imag(V[vb]), iδ[j], iE[j],
                                              ia.X_c[j])
        # `E∠δ` and `(−E)∠(δ + π)` are the same phasor, so the static solve could in
        # principle land on the second — and there the droop `E = V_ref − K_q·Q`
        # would push the MAGNITUDE the wrong way. Refused rather than normalised.
        iE[j] > 0 || throw(ErrorException(
            "DetailedEngine: grid-forming inverter $(ia.id[j]) solved to a formed " *
            "voltage E = $(iE[j]) ≤ 0 — the same phasor as a positive E at δ + π, but " *
            "a droop that would push its magnitude the wrong way. A spurious branch " *
            "of the static solve, refused rather than integrated."))
        # D10, at this tier: the rating, on the BUS side (as `ac_powerflow` caps it).
        # This path holds `|V| = V_set` with no reactive limit, so it can ask for more
        # than the inverter has; `powerflow = ac_powerflow(net)` caps it instead.
        Sbus = abs(V[vb] * conj(complex(Ire, Iim)))
        Sbus <= ia.S[j] * (1 + 1e-9) || throw(ArgumentError(
            "DetailedEngine: grid-forming inverter $(ia.id[j]) is dispatched at " *
            "$(Sbus * net.S_base) MVA against a rating of $(ia.S[j] * net.S_base) MVA. " *
            "An inverter has no short-term overload. This tier's own steady state " *
            "holds the bus at V_set with no reactive limit; " *
            "`init!(DetailedEngine, net; powerflow = ac_powerflow(net))` starts from " *
            "the power flow, which caps its reactive output at the rating (D10)."))
    end

    # --- back-substitution ----------------------------------------------------
    # `Pm` from the POWER FLOW, not from `Machine.P0` — see the header. On a model
    # with no load this is `P0` to the bit for every non-slack machine, which is
    # exactly why the fixture that exercises it has a load on it.
    u0 = zeros(Float64, NetworkDynamics.dim(nw))
    p0 = zeros(Float64, NetworkDynamics.pdim(nw))
    for v in 1:nb
        u0[Vre_idx[v]] = real(V[v])
        u0[Vim_idx[v]] = imag(V[v])
        p0[SII.parameter_index(nw, NetworkDynamics.VPIndex(v, :G))]   = G[v]
        p0[SII.parameter_index(nw, NetworkDynamics.VPIndex(v, :B))]   = B[v]
        p0[SII.parameter_index(nw, NetworkDynamics.VPIndex(v, :a_i))] = aI[v]
        p0[SII.parameter_index(nw, NetworkDynamics.VPIndex(v, :a_p))] = aP[v]
    end
    # EVERY MACHINE STATE IN CLOSED FORM (`m5-prestudy.md` §4). `δ` is never
    # *seeded*, only computed from a converged network solution, which is what
    # sidesteps the spurious-equilibrium basin the header measures.
    worst_pm = 0.0
    for k in 1:nm
        vb = ma.bus[k]
        Vre, Vim = real(V[vb]), imag(V[vb])
        δ = δ0[k]
        # From the solve, whichever solve it was. The fixpoint path computes this
        # from `ma.E` and the seeded path from the power flow's own `S`; both are
        # the machine's terminal current at the same operating point, and taking
        # it from the caller is what keeps ONE back-substitution here.
        Ire, Iim = real(Iinj[k]), imag(Iinj[k])
        Id, Iq = _dq(Ire, Iim, δ)
        Vd, Vq = _dq(Vre, Vim, δ)
        E′q = Vq + ma.Ra[k] * Iq + ma.Xd′[k] * Id
        E′d = Vd + ma.Ra[k] * Id - ma.Xq′[k] * Iq
        Efd = E′q + (ma.Xd[k] - ma.Xd′[k]) * Id
        Pm  = E′d * Id + E′q * Iq + (ma.Xq′[k] - ma.Xd′[k]) * Id * Iq
        # A FREE CROSS-CHECK, AND ITS EXACT REACH. `Pm` above is the two-axis
        # air-gap power; `Pe[k]` is `Re(Ẽ·conj(I))` from the phasor form. They are
        # provably the same quantity (both reduce to `Vd Id + Vq Iq + Ra|I|²`), so
        # any disagreement is an inconsistency between the rotor-frame rotation and
        # the stator inversion — including a reflected frame such as
        # `Vd = Vre·sin δ + Vim·cos δ`, whose matrix is not a rotation and does not
        # preserve the inner product. What it CANNOT catch is a rotation that is
        # globally consistent but conventionally wrong (the whole frame turned by
        # π/2): both sides turn together and the difference cancels. That one is
        # pinned in `test/` by asserting `E′d = 0` and `E′q = E′` at the
        # degeneration, where the convention is what decides which state holds what.
        worst_pm = max(worst_pm, abs(Pm - Pe[k]))
        u0[δ_idx[k]]   = δ
        u0[ω_idx[k]]   = 0.0
        u0[ΔPm_idx[k]] = 0.0
        u0[E′q_idx[k]] = E′q
        u0[E′d_idx[k]] = E′d
        u0[Efd_idx[k]] = Efd
        p0[Pm_pidx[k]]  = Pm
        # THE SETPOINT IS DERIVED, NOT SUPPLIED (M5 step 5). At a steady state the
        # exciter's own equation `T_E·dEfd/dt = −Efd + K_A(Vref − |V|)` has one
        # unknown left once `Efd` and `|V|` come out of the power flow, and that is
        # `Vref`. Taking it as model data instead would be exactly the `Pm = P0`
        # mistake the header describes, one mechanism along: a setpoint that does not
        # match the dispatch, a flat run that is not flat, and every downstream check
        # then measuring a startup transient rather than the thing it names.
        #
        # `K_A = 0` is the regulator-off default, where the whole term is multiplied
        # by zero and any finite `Vref` is as good as any other; `|V|` is the one
        # that keeps the arithmetic free of `0/0`. `Machine` has already refused the
        # one combination where that would hide something (`K_A = 0` with a finite
        # `T_E`, which has no steady state at all).
        Vmag = hypot(Vre, Vim)
        p0[Vref_pidx[k]] = ma.K_A[k] > 0 ? Vmag + Efd / ma.K_A[k] : Vmag
        for (sym, val) in ((:Xd, ma.Xd[k]), (:Xq, ma.Xq[k]), (:Xd′, ma.Xd′[k]),
                           (:Xq′, ma.Xq′[k]), (:Td0′, ma.Td0′[k]), (:Tq0′, ma.Tq0′[k]),
                           (:Ra, ma.Ra[k]), (:H, ma.H[k]), (:D, ma.D[k]), (:ω₀, ω₀),
                           (:invR, ma.invR[k]), (:headroom, ma.headroom[k]),
                           (:Tg, ma.Tg[k]), (:mstat, 1.0),
                           (:K_A, ma.K_A[k]), (:T_E, ma.T_E[k]),
                           (:Efd_min, ma.Efd_min[k]), (:Efd_max, ma.Efd_max[k]),
                           # No ramp is the default, and it is `rate = 0` — the
                           # machine every model before M5 step 7 described, to the
                           # bit. The armed ramps overwrite these below.
                           (:rate, 0.0), (:t_start, 0.0), (:duration, 0.0))
            p0[SII.parameter_index(nw, NetworkDynamics.VPIndex(vb, sym))] = val
        end
        # THE DISPATCH MUST LIE INSIDE THE MACHINE'S OWN LIMITS, checked here with a
        # number rather than left to the solver. A field voltage that starts outside
        # its ceiling is not a transient that decays: the derivative saturation holds
        # it wherever it starts if the demand points outward, and the domain guard
        # rejects every step if it does not. Either way the run is meaningless, and
        # the cause is data, not integration.
        (ma.Efd_min[k] <= Efd <= ma.Efd_max[k]) || throw(ArgumentError(
            "DetailedEngine: machine $(net.machines[k].id) is dispatched at a field " *
            "voltage Efd = $Efd pu, outside its own limits " *
            "[$(ma.Efd_min[k]), $(ma.Efd_max[k])]. The power flow, not the exciter, " *
            "sets the initial field voltage — it is E′q + (Xd − X′d)·Id at the solved " *
            "operating point — so a limit tighter than the dispatch describes a " *
            "machine that cannot hold its own schedule."))
    end
    worst_pm < _PF_RESIDUAL || throw(ErrorException(
        "DetailedEngine: the back-substituted air-gap power disagrees with the " *
        "power flow's own by $worst_pm. These are two expressions for one quantity " *
        "— the two-axis bracket E′d·Id + E′q·Iq + (X′q−X′d)·Id·Iq and the phasor " *
        "Re(Ẽ·conj(I)) — so a gap here is the rotor-frame rotation disagreeing with " *
        "the stator inversion, not a solve that did not converge."))
    # THE GRID-FORMING INVERTERS, IN CLOSED FORM (M7 step 4). Both filters start at
    # the power they filter; `P_set` is the solved power (the slack's is free, like
    # a slack machine's `Pm`); and the droop's intercept is DERIVED (D11) — only
    # `V_set + K_q·Q_set` enters the dynamics, so it is one number, backed out
    # through `_gfm_voltage` itself: `E = V_ref − K_q·Q` ⇔ `V_ref = E − (0 − K_q·Q)`.
    # Written through the helper so a change to the droop law moves the derivation
    # with it, and the residual check below cannot be what catches it.
    for j in 1:ni
        u0[gfm.δ_idx[j]]  = iδ[j]
        u0[gfm.Pf_idx[j]] = iP[j]
        u0[gfm.Qf_idx[j]] = iQ[j]
        p0[gfm.Pset_pidx[j]] = iP[j]
        p0[gfm.Vref_pidx[j]] = iE[j] - _gfm_voltage(0.0, ia.K_q[j], iQ[j])
        for (sym, val) in ((:K_p, ia.K_p[j]), (:τ_p, ia.τ_p[j]), (:ω₀, ω₀),
                           (:K_q, ia.K_q[j]), (:τ_q, ia.τ_q[j]), (:X_c, ia.X_c[j]),
                           (:istat, 1.0))
            p0[pidx(nw, j, sym)] = val
        end
    end
    # THE GRID-FOLLOWING INVERTERS, IN CLOSED FORM (M7 step 5). At lock the PLL sits
    # on the bus angle with its frequency and integrator at rest, and the current
    # setpoint is the dispatch in that frame: `P = |V|·i_d`, `Q = −|V|·i_q`. Read from
    # the SCHEDULE on both paths — a grid-following bus holds its `P0 + jQ0` in
    # `ac_powerflow` as in the engine's own solve — and at the solved voltage. The
    # static vertex gets the same setpoint, for `_PF_HOLD`.
    for j in 1:nf
        vb = fa.bus[j]
        Vm = abs(V[vb])
        i_d, i_q = fa.P[j] / Vm, -fa.Q[j] / Vm
        u0[gfl.θ_idx[j]]   = angle(V[vb])
        u0[gfl.Δω_idx[j]]  = 0.0
        u0[gfl.Δωi_idx[j]] = 0.0
        for (sym, val) in ((:i_d, i_d), (:i_q, i_q), (:K_pll_p, fa.K_pll_p[j]),
                           (:K_pll_i, fa.K_pll_i[j]), (:τ_pll, fa.τ_pll[j]))
            p0[fpidx(nw, j, sym)] = val
        end
        sp[fpidx(nws, j, :i_d)] = i_d
        sp[fpidx(nws, j, :i_q)] = i_q
    end
    # THE METERS (M7 step 6): locked on their bus angle, at rest — a grid-following
    # inverter's PLL at start-up, with nothing injected.
    for (j, m) in enumerate(meters)
        u0[mtr.θ_idx[j]]   = angle(V[mbus[j]])
        u0[mtr.Δω_idx[j]]  = 0.0
        u0[mtr.Δωi_idx[j]] = 0.0
        for (sym, val) in ((:K_meter_p, m.K_p), (:K_meter_i, m.K_i), (:τ_meter, m.τ))
            p0[SII.parameter_index(nw, NetworkDynamics.VPIndex(mbus[j], sym))] = val
        end
    end
    for e in 1:ne
        p0[X_pidx[e]]      = bt.X[e]
        p0[status_pidx[e]] = 1.0
    end

    # The second, independent check: is this actually a fixpoint of the network we
    # are about to integrate? The power flow's own residual says nothing about
    # that — it is a residual of a DIFFERENT set of equations.
    du = similar(u0)
    nw(du, u0, p0, t0f)
    r = maximum(abs, du)
    r < _PF_RESIDUAL || throw(ErrorException(
        "DetailedEngine: the back-substituted state is not a fixpoint of the " *
        "dynamic network (|residual| = $r > $_PF_RESIDUAL). The power flow " *
        "converged, so this is the BACK-SUBSTITUTION, not the solve: a machine " *
        "state, a per-unit conversion, or the air-gap-vs-terminal power choice. " *
        "Checked here, at build time and with a number, rather than left to " *
        "surface later as a flat run that is not flat."))

    # --- M3's protection, wired here (M5 step 7, D8) --------------------------
    #
    # All three arming arguments go through `engines/swing.jl`'s OWN binders —
    # `_bind_ramps`, `_bind_shed`, `_bind_out_of_step` — rather than through copies
    # of them. Every guard those functions carry (an unknown machine, two ladders on
    # one machine, a ramp starting before `t0`, a relay on a branch that does not
    # exist, two relays on one branch) is therefore the shipped guard with the
    # shipped message, and a rule cannot come to differ between the two tiers. The
    # seam is index-based and knows nothing about a tier: a ladder needs "where does
    # this machine's speed live" and "how do I step its power", and both indices
    # exist here with the same meaning.
    #
    # THE RAMP IS ARMED AFTER THE RESIDUAL CHECK ABOVE, and that ordering is the
    # point rather than an accident. `_bind_ramps` refuses `t_start < t0`, so
    # `clamp(t0 − t_start, 0, duration)` is exactly zero at the start of the run and
    # the fixpoint check above sees the UN-ramped system — which is the system the
    # power flow solved. A ramp already under way at `t0` would put the engine on the
    # equilibrium of a different system and the run would ring from its first step
    # with pure initialisation artefact.
    ramps = _bind_ramps(ramp, ids, t0f)
    for (machine, r) in ramps
        k = findfirst(==(machine), ids)
        vb = ma.bus[k]
        p0[SII.parameter_index(nw, NetworkDynamics.VPIndex(vb, :rate))]     = r.rate
        p0[SII.parameter_index(nw, NetworkDynamics.VPIndex(vb, :t_start))]  = r.t_start
        p0[SII.parameter_index(nw, NetworkDynamics.VPIndex(vb, :duration))] = r.duration
    end

    ladders, bound_shed = _bind_shed(shed, ids, ω_idx, Pm_pidx)

    # The relay's affect calls this engine's own `inject!(::TripLine)`, which does
    # not exist yet — the box is filled on the constructor's last line. Same device,
    # same cost and same justification as `SwingEngine`'s.
    eng_box = Base.RefValue{Any}(nothing)
    branch_of_buses = Dict{Tuple{Symbol,Symbol},Int}(
        _bus_pair(br.from, br.to) => e for (e, br) in pairs(net.branches))
    # `bt` and not `branch_arrays(net)`: only `src`/`dst` are wanted, and `K` is
    # UNCOMPUTABLE on this tier's own models (there is no `E′` at a machine-free
    # bus — `network_model.jl`'s note on the guard that moved).
    #
    # THE ANGLE IS LOOKED UP BY BUS (M7 step 4, found, not planned). The binder reads
    # `δ_idx[bt.src[b]]` — a VERTEX index into what, until this step, was the
    # MACHINE-indexed `δ_idx`. The two orders agree only when every bus carries a
    # machine, which every relay fixture did; on a model with a passive bus the relay
    # read another machine's angle, or indexed past the end. `δ_of_bus` is the
    # vertex-indexed view it always assumed: a machine's rotor angle, a grid-forming
    # inverter's formed angle, and 0 at a passive bus — refused by name there,
    # because a bus with no source has no angle for the relay to watch.
    δ_of_bus = zeros(Int, nb)
    for k in 1:nm; δ_of_bus[ma.bus[k]] = δ_idx[k]; end
    for j in 1:ni; δ_of_bus[ia.bus[j]] = gfm.δ_idx[j]; end
    for (buspair, _) in out_of_step, bus in buspair
        v = get(net.bus_index, bus, 0)
        (v == 0 || δ_of_bus[v] != 0) || throw(ArgumentError(
            "DetailedEngine: out_of_step on $(buspair[1])–$(buspair[2]): bus $bus " *
            "carries no machine and no grid-forming inverter, so there is no angle " *
            "there for the relay to watch. Arm it on a branch between two sources."))
    end
    relays, bound_oos =
        _bind_out_of_step(DetailedEngine, out_of_step, net, bt, δ_of_bus,
                          branch_of_buses, eng_box)
    _guard_out_of_step_start(bound_oos, u0)

    prob = OrdinaryDiffEq.ODEProblem(nw, u0, (t0f, t0f + 1.0e6), p0)
    integrator = OrdinaryDiffEq.init(prob, solver; dt = Float64(dt),
                                     reltol = Float64(reltol), abstol = Float64(abstol),
                                     dtmax = Float64(dtmax), maxiters = maxiters,
                                     callback = SciMLBase.CallbackSet(
                                         shed_callbacks(bound_shed, net.f0),
                                         out_of_step_callbacks(bound_oos)),
                                     save_everystep = false, dense = false,
                                     calck = _ENGINE_CALCK)

    # M7 step 4: a grid-forming inverter's three channels — its formed angle, its
    # droop frequency and the magnitude it forms — after the machines' and before
    # the buses'. M7 step 5: a grid-following inverter's two, its PLL angle and its
    # PLL frequency (pu deviation), under names of their own — `ω_` means a speed
    # that is averaged into the COI, and a PLL's estimate never is (D6). None on a
    # model without inverters, so every pre-M7 channel list is the list it was.
    # M7 step 6: each `PLLMeter`'s angle and frequency, named by its BUS under a
    # prefix of its own (`θmeter_`/`ωmeter_`) — a bus id and an inverter id may be the
    # same symbol, so sharing `ωpll_` could put two channels under one name.
    channels = vcat([Symbol("δ_", id) for id in ids],
                    [Symbol("ω_", id) for id in ids],
                    [Symbol("E′q_", id) for id in ids],
                    [Symbol("E′d_", id) for id in ids],
                    [Symbol("Efd_", id) for id in ids],
                    [Symbol("δ_", id) for id in ia.id],
                    [Symbol("ω_", id) for id in ia.id],
                    [Symbol("E_", id) for id in ia.id],
                    [Symbol("θpll_", id) for id in fa.id],
                    [Symbol("ωpll_", id) for id in fa.id],
                    [Symbol("θmeter_", b) for b in mtr.buses],
                    [Symbol("ωmeter_", b) for b in mtr.buses],
                    [Symbol("V_", b.id) for b in net.buses], [:δ_coi, :f_coi])
    traj = TrajectoryRecorder(channels...; capacity = capacity)

    # The COI weight counts the inverters' virtual inertia `τ_p/(2K_p)` (D6); with
    # none present it is the machine sum it always was, to the bit.
    Σw = ni == 0 ? sum(ma.H) : sum(ma.H) + sum(ia.H)
    eng = DetailedEngine(net, nw, nws, slack_id, Set(1:ne), integrator.p, sp, su,
                         Float64(dt), integrator, net.f0, ω₀, ids, copy(ma.bus),
                         δ_idx, ω_idx, ΔPm_idx, E′q_idx, E′d_idx, Efd_idx,
                         Vre_idx, Vim_idx, Pm_pidx, Vref_pidx, status_pidx,
                         sVre_idx, sVim_idx, sδ_idx, sPset_pidx, smode_pidx,
                         sδtarget_pidx, sstatus_pidx, sE′q_pidx, sE′d_pidx,
                         branch_to_edge, branch_of_buses,
                         copy(ma.H), copy(ma.H), Σw, traj,
                         Vector{Float64}(undef, length(channels)),
                         EngineEvent[], 0, net.f0, ladders, relays, ramps, gfm, gfl,
                         mtr, mstat_pidx, smstat_pidx, invR_pidx, hr_pidx, rate_pidx,
                         Set{Symbol}(vcat(ids, ia.id, fa.id)))
    _record!(eng)                                 # seed the pre-disturbance point
    # The last line, and it has to be: an out-of-step relay's affect calls this
    # engine's own `inject!(::TripLine)`, and until now there was no engine to call
    # it on. Nothing can have fired before this point — `init` does not step.
    eng_box[] = eng
    return eng
end

# ─────────────────────────────────────────────────────────────────────────────
# Read-out
# ─────────────────────────────────────────────────────────────────────────────

# Inertia-weighted aggregate over the machines, the same gauge-fixing device
# `SwingEngine` uses: an individual rotor angle means nothing on its own, only its
# difference from the aggregate does.
#
# M7 step 4 (D6): a grid-forming inverter enters at its virtual inertia, with its
# formed angle and its DROOP frequency — `ω` is not one of its states, so it is read
# through `_gfm_speed`, the law the RHS integrates. `ginv` is the per-inverter value
# being averaged; with no inverters the second loop is empty and this is the pre-M7
# sum, term for term.
@inline function _coi(eng::DetailedEngine, u, idx::Vector{Int}, ginv)
    acc = 0.0
    @inbounds for k in eachindex(idx)
        acc += eng.w[k] * u[idx[k]]
    end
    g = eng.gfm
    @inbounds for j in eachindex(g.ids)
        acc += g.H[j] * ginv(j)
    end
    return acc / eng.Σw
end
@inline _gfm_ω(eng::DetailedEngine, u, j::Int) =
    @inbounds _gfm_speed(eng.gfm.K_p[j], u[eng.gfm.Pf_idx[j]], eng.params[eng.gfm.Pset_pidx[j]])
@inline _gfm_E(eng::DetailedEngine, u, j::Int) =
    @inbounds _gfm_voltage(eng.params[eng.gfm.Vref_pidx[j]], eng.gfm.K_q[j], u[eng.gfm.Qf_idx[j]])
@inline _ω_coi(eng::DetailedEngine, u) = _coi(eng, u, eng.ω_idx, j -> _gfm_ω(eng, u, j))
@inline _δ_coi(eng::DetailedEngine, u) =
    _coi(eng, u, eng.δ_idx, j -> @inbounds u[eng.gfm.δ_idx[j]])

"""
    current_state(eng::DetailedEngine) -> NamedTuple

`(; t, δ, ω, ΔPm, E′q, E′d, Efd, V, δ_coi, ω_coi, f_coi)`. `V` is the vector of bus
voltage MAGNITUDES in per unit, indexed by vertex — the quantity this whole tier
exists to produce, and the one `SwingEngine` cannot report at all because it does
not carry a bus voltage as an unknown.

`E′q`/`E′d` are the transient flux states, machine-indexed. At the classical
degeneration they are constants (`E′q = Machine.E′`, `E′d = 0`) and reading them is
how a test tells that the degeneration actually took.

`δ_inv`, `ω_inv`, `E_inv` (M7 step 4) are the grid-forming inverters', in model
order: the angle each forms, its droop frequency (read through the droop law — it is
not a state), and the magnitude it forms behind `X_c`. `θ_pll`, `ω_pll` (M7 step 5)
are the grid-following inverters' PLL angle and PLL frequency estimate (pu
deviation) — measurements, weighted into nothing. `θ_meter`, `ω_meter` (M7 step 6)
are the same two readings from each armed `PLLMeter`, in the order they were armed.
Empty vectors on a model without them. `δ`/`ω` stay machine-indexed, so no existing reader moves.
"""
function current_state(eng::DetailedEngine)
    u = eng.integrator.u
    ω_coi = _ω_coi(eng, u)
    V = Float64[hypot(u[eng.Vre_idx[v]], u[eng.Vim_idx[v]]) for v in eachindex(eng.Vre_idx)]
    ni = length(eng.gfm.ids)
    return (t = eng.integrator.t, δ = u[eng.δ_idx], ω = u[eng.ω_idx],
            ΔPm = u[eng.ΔPm_idx], E′q = u[eng.E′q_idx], E′d = u[eng.E′d_idx],
            Efd = u[eng.Efd_idx], V = V,
            δ_inv = u[eng.gfm.δ_idx], ω_inv = Float64[_gfm_ω(eng, u, j) for j in 1:ni],
            E_inv = Float64[_gfm_E(eng, u, j) for j in 1:ni],
            θ_pll = u[eng.gfl.θ_idx], ω_pll = u[eng.gfl.Δω_idx] ./ eng.ω₀,
            θ_meter = u[eng.meters.θ_idx], ω_meter = u[eng.meters.Δω_idx] ./ eng.ω₀,
            δ_coi = _δ_coi(eng, u), ω_coi = ω_coi, f_coi = eng.f0 * (1 + ω_coi))
end

# The playback driver's mid-step guard (`engines/playback.jl`). It asks "did a
# callback change WHO IS ONLINE underneath a batch of interpolated samples", and
# the answer is carried by the machine-inertia sum exactly as for `SwingEngine`.
#
# ALGEBRAIC STATES ARE OUTSIDE THIS, deliberately. A line trip changes the bus
# voltages — every one of them — and does not change this number at all, which is
# correct: the weight exists to catch a change in the machine set, not a change in
# the state. Reading a voltage into it would make the first line trip look like a
# weight change and abort a legitimate run.
_aggregate_weight(eng::DetailedEngine) = eng.Σw

function _record_at!(eng::DetailedEngine, t::Real, u::AbstractVector{<:Real})
    n = length(eng.ids)
    nb = length(eng.Vre_idx)
    @inbounds for k in 1:n
        eng.sample[k]      = u[eng.δ_idx[k]]
        eng.sample[n + k]  = u[eng.ω_idx[k]]
        eng.sample[2n + k] = u[eng.E′q_idx[k]]
        eng.sample[3n + k] = u[eng.E′d_idx[k]]
        eng.sample[4n + k] = u[eng.Efd_idx[k]]
    end
    # M7 step 4 — the grid-forming inverters' three channels; `ni = 0` on every
    # pre-M7 model, which leaves every offset below the one it was.
    ni = length(eng.gfm.ids)
    @inbounds for j in 1:ni
        eng.sample[5n + j]          = u[eng.gfm.δ_idx[j]]
        eng.sample[5n + ni + j]     = _gfm_ω(eng, u, j)
        eng.sample[5n + 2ni + j]    = _gfm_E(eng, u, j)
    end
    # M7 step 5 — the grid-following inverters' two.
    nf = length(eng.gfl.ids)
    @inbounds for j in 1:nf
        eng.sample[5n + 3ni + j]      = u[eng.gfl.θ_idx[j]]
        eng.sample[5n + 3ni + nf + j] = u[eng.gfl.Δω_idx[j]] / eng.ω₀
    end
    # M7 step 6 — the meters' two.
    nmt = length(eng.meters.buses)
    o = 5n + 3ni + 2nf
    @inbounds for j in 1:nmt
        eng.sample[o + j]       = u[eng.meters.θ_idx[j]]
        eng.sample[o + nmt + j] = u[eng.meters.Δω_idx[j]] / eng.ω₀
    end
    o += 2nmt
    @inbounds for v in 1:nb
        eng.sample[o + v] = hypot(u[eng.Vre_idx[v]], u[eng.Vim_idx[v]])
    end
    f_coi = eng.f0 * (1 + _ω_coi(eng, u))
    eng.sample[o + nb + 1] = _δ_coi(eng, u)
    eng.sample[o + nb + 2] = f_coi
    record!(eng.traj, t, eng.sample)
    f_coi < eng.nadir && (eng.nadir = f_coi)
    return nothing
end

_record!(eng::DetailedEngine) = _record_at!(eng, eng.integrator.t, eng.integrator.u)

"""
    state_series(eng::DetailedEngine) -> NamedTuple

`(; t, δ_<id>..., ω_<id>..., E′q_<id>..., E′d_<id>..., Efd_<id>...,
δ_<inv>..., ω_<inv>..., E_<inv>..., θpll_<inv>..., ωpll_<inv>...,
θmeter_<bus>..., ωmeter_<bus>..., V_<bus>..., δ_coi, f_coi)`, in that order.
Bounded and decimating, like every recorder in the repo.

The machines' five come first; then each grid-forming inverter's formed angle, droop
frequency and formed magnitude (M7 step 4); each grid-following inverter's PLL angle
and PLL frequency (pu deviation, M7 step 5); each armed `PLLMeter`'s angle and
frequency, named by bus in the order armed (M7 step 6); then the buses. Every group
after the machines is empty on a model or run without it, so a pre-M7 channel list is
the list it was. PLL and meter frequencies are measurements and are weighted into
nothing (D6).

**One channel per BUS, not per machine**, for the voltage: a machine-free bus is
exactly the thing this tier added, and it is often the one whose voltage matters.

**The flux states get channels of their own** because the flat run asserts per
state and `f_coi` cannot stand in for them — a wrong `E′d` rings a voltage and
leaves frequency flat. At the classical degeneration those two channels are
constant by construction (the flux is frozen), so a flat run proves nothing about
them there; that vacuity is asserted in `test/` rather than left to be inferred.

**`Efd` is a channel for the same reason and with the same caveat** (M5 step 5):
it is what a regulator moves, and the ceiling checks read its trajectory to see
that it holds at a limit and comes off unaided. With the regulator off — the
default — it is a constant, and a run proves nothing about it there either.
"""
state_series(eng::DetailedEngine) = series(eng.traj)

"""
    timestep(eng::DetailedEngine) -> Float64

The output cadence `solve!` defaults to. **Not a promise that the engine steps in
wall-clock at this rate** — `step!` is not implemented for this tier (D2), and
whether it could be is what S3 measures.
"""
timestep(eng::DetailedEngine) = eng.dt

machine_ids(eng::DetailedEngine) = copy(eng.ids)
event_log(eng::DetailedEngine) = copy(eng.log)
n_events(eng::DetailedEngine) = length(eng.log)
n_events_dropped(eng::DetailedEngine) = eng.n_dropped
system_inertia(eng::DetailedEngine) = eng.Σw

function _log_event!(eng::DetailedEngine, kind::Symbol, a::Symbol, b::Symbol)
    if length(eng.log) < _EVENT_LOG_CAP
        push!(eng.log, EngineEvent(eng.integrator.t, kind, a, b))
    else
        eng.n_dropped += 1
    end
    return nothing
end

"""
    solve!(eng::DetailedEngine, tspan; perturbations=[], saveat=eng.dt)

Playback over the whole horizon. One line on `engines/playback.jl`'s driver, the
same as `SwingEngine`'s — which is the point of that file existing.
"""
solve!(eng::DetailedEngine, tspan; perturbations = (),
       saveat = eng.dt, maxiters::Integer = _PLAYBACK_MAXITERS) =
    _playback!(eng, tspan, perturbations, saveat; maxiters = maxiters)

function _detailed_branch_index(eng::DetailedEngine, from::Symbol, to::Symbol)
    e = get(eng.branch_of_buses, _bus_pair(from, to), 0)
    e == 0 && throw(ArgumentError(
        "DetailedEngine: no branch between $from and $to."))
    return e
end

"""
    is_online(eng::DetailedEngine, from::Symbol, to::Symbol) -> Bool

Whether the branch between those two buses is in service. Tracked explicitly
rather than inferred from a parameter, the same discipline `SwingEngine` uses.
"""
is_online(eng::DetailedEngine, from::Symbol, to::Symbol) =
    _detailed_branch_index(eng, from, to) in eng.lines_online

"""
    shed_ladder(eng::DetailedEngine, machine::Symbol) -> ShedLadder
    out_of_step_relay(eng::DetailedEngine, from::Symbol, to::Symbol) -> OutOfStepRelay
    generation_ramp(eng::DetailedEngine, machine::Symbol) -> GenerationRamp

M3's three armed mechanisms, read back off this tier's engine. Same contract as
`SwingEngine`'s — `KeyError` for one that was never armed — and the same *bodies*,
shared through `_ladder_of` / `_relay_of` / `_ramp_of` rather than copied, so the
two tiers cannot come to disagree about what "never armed" means.

`generation_ramp` reports **what was scheduled, not what is left**, exactly as at
the classical tier.
"""
shed_ladder(eng::DetailedEngine, machine::Symbol) = _ladder_of(eng.ladders, machine)
out_of_step_relay(eng::DetailedEngine, from::Symbol, to::Symbol) =
    _relay_of(eng.relays, from, to)
generation_ramp(eng::DetailedEngine, machine::Symbol) = _ramp_of(eng.ramps, machine)

"""
    branch_power(eng::DetailedEngine, from::Symbol, to::Symbol) -> Float64

Active power flowing **from** bus `from` **into** the branch, per unit on
`model.S_base`, right now: `Re(V_from · conj(I))` with
`I = status·(V_from − V_to)/(jX)` — the same current expression the edge model
integrates, so the read-out and the physics cannot hold different conventions
(`_branch_flows` makes the same argument about the power flow's own check).

**This is the quantity the classical tier reports as `K·sin(δ_from − δ_to)`, and
that is the whole point of the shared name** (M5 step 7). There it is bounded by
`K = E′_from·E′_to/X`, because the voltages at the two ends are constants of the
model. Here the two ends are algebraic unknowns and there is no such bound —
which is the mechanism the milestone's criterion measures.

Reading it needs the bus voltage ANGLES, and `current_state` reports magnitudes
only. That is why this is a function on the engine rather than an arithmetic the
caller can do from the state: the information is not in the state read-out.
"""
function branch_power(eng::DetailedEngine, from::Symbol, to::Symbol)
    e = _detailed_branch_index(eng, from, to)
    bt = branch_topology(eng.model)
    u = eng.integrator.u
    # The branch's OWN orientation, for `SwingEngine`'s reason — `bt.src`/`bt.dst`
    # are the model's, not the graph's.
    Vf = complex(u[eng.Vre_idx[bt.src[e]]], u[eng.Vim_idx[bt.src[e]]])
    Vt = complex(u[eng.Vre_idx[bt.dst[e]]], u[eng.Vim_idx[bt.dst[e]]])
    status = eng.params[eng.status_pidx[e]]
    I = status * (Vf - Vt) / (im * bt.X[e])
    # The CALLER's order decides the sign — see `branch_power(::SwingEngine, …)`.
    return _oriented(eng.model.branches[e], from) ? real(Vf * conj(I)) :
                                                    -real(Vf * conj(I))
end

"""
    branch_power(eng::DetailedEngine) -> Vector{Float64}

Every branch's active power in **model branch order**, `from → to`, pu.
"""
branch_power(eng::DetailedEngine) =
    Float64[branch_power(eng, br.from, br.to) for br in eng.model.branches]

"""
    branch_power_series(eng::DetailedEngine, from::Symbol, to::Symbol) -> (; t, P)

The active power `from → to` (pu on `model.S_base`) at every sample the integrator
has saved — the classical tier's method of the same name, on this tier's algebra.
See `engines/swing.jl` for why the transfer is derived here rather than recorded as
a channel, and for the guard that refuses a branch an event has touched.

**This tier needs it more than the classical one does.** There, `δ` is a recorded
channel and the transfer can be reconstructed after the fact from `state_series`
alone. Here it cannot: the transfer needs the bus voltage ANGLES and
`current_state`/`state_series` report magnitudes.
"""
function branch_power_series(eng::DetailedEngine, from::Symbol, to::Symbol)
    e = _detailed_branch_index(eng, from, to)
    _branch_series_guard(eng.log, eng.model, e, from, to)
    bt = branch_topology(eng.model)
    ir, ii = eng.Vre_idx[bt.src[e]], eng.Vim_idx[bt.src[e]]
    jr, ji = eng.Vre_idx[bt.dst[e]], eng.Vim_idx[bt.dst[e]]
    status, X = eng.params[eng.status_pidx[e]], bt.X[e]
    sgn = _oriented(eng.model.branches[e], from) ? 1.0 : -1.0
    sol = eng.integrator.sol
    P = Vector{Float64}(undef, length(sol.u))
    @inbounds for k in eachindex(sol.u)
        u = sol.u[k]
        Vf = complex(u[ir], u[ii])
        Vt = complex(u[jr], u[ji])
        P[k] = sgn * real(Vf * conj(status * (Vf - Vt) / (im * X)))
    end
    return (t = copy(sol.t), P = P)
end

"""
    _reinitialise_algebraic!(eng)

Restore the algebraic states after a discontinuity — the failure mode D1 buys and
SPEC §6 predicted ("re-init algebraic state for the network tiers"). Stepping a
DAE from a point that does not satisfy its constraints is not a well-posed
problem, so `inject!` ends here.

Every machine's rotor angle **and transient flux** are PINNED at their current
values and the bus voltages are re-solved. That is exactly "hold the differential
states, restore the algebraic ones", and it needs no new solver: it is the same
static network the power flow used, in its third mode (`_PF_HOLD`).

**The third mode is what M5 step 2 had to add here.** Step 1 reused the
steady-state PIN mode, which is correct only while the machine's internal voltage
is a constant of the model — true for a classical machine, false for a two-axis
one the moment its flux has moved. `_PF_HOLD` evaluates the machine's actual
stator algebra at the held `(δ, E′q, E′d)` instead. At the frozen-flux
degeneration the two modes agree exactly, which is why step 1's version was not
wrong, only narrower than it looked.

**This is not validated by step 1's flat run.** That run has no event in it and
proves the initialisation only. The flat run *across* an event — trip a line on a
system whose post-trip equilibrium is known, assert no transient beyond the
physical one — is D8's check and belongs to the step that arms protection here.
What this function has today is the weaker guarantee that the re-solved point
satisfies the network's own residual, asserted below with a number.
"""
function _reinitialise_algebraic!(eng::DetailedEngine)
    u = eng.integrator.u
    for k in eachindex(eng.sδ_idx)
        eng.p_static[eng.smode_pidx[k]]    = _PF_HOLD
        eng.p_static[eng.sδtarget_pidx[k]] = u[eng.δ_idx[k]]
        eng.p_static[eng.sE′q_pidx[k]]     = u[eng.E′q_idx[k]]
        eng.p_static[eng.sE′d_pidx[k]]     = u[eng.E′d_idx[k]]
        eng.u_static[eng.sδ_idx[k]]        = u[eng.δ_idx[k]]
    end
    # M7 step 4 — a grid-forming inverter's differential states are its angle and the
    # two filters; the voltage it forms is a function of `Q_filt` alone, so holding
    # `(δ, E)` is exactly "hold the differential states". Its static vertex's
    # `_PF_HOLD` mode pins both.
    g = eng.gfm
    for j in eachindex(g.ids)
        E = _gfm_E(eng, u, j)
        eng.p_static[g.smode_pidx[j]]    = _PF_HOLD
        eng.p_static[g.sδtarget_pidx[j]] = u[g.δ_idx[j]]
        eng.p_static[g.sEheld_pidx[j]]   = E
        eng.u_static[g.sδ_idx[j]]        = u[g.δ_idx[j]]
        eng.u_static[g.sE_idx[j]]        = E
    end
    # M7 step 5 — a grid-following inverter's differential states are its PLL's; the
    # current it injects is its setpoint at the PLL angle, so `_PF_HOLD` holds exactly
    # that (constant current), where the steady-state modes hold constant power.
    f = eng.gfl
    for j in eachindex(f.ids)
        eng.p_static[f.smode_pidx[j]]  = _PF_HOLD
        eng.p_static[f.sθheld_pidx[j]] = u[f.θ_idx[j]]
    end
    # Seed from where the network is, never from flat — the spurious basin is
    # within 2.5 rad (see the header).
    for v in eachindex(eng.Vre_idx)
        eng.u_static[eng.sVre_idx[v]] = u[eng.Vre_idx[v]]
        eng.u_static[eng.sVim_idx[v]] = u[eng.Vim_idx[v]]
    end
    res = _run_static!(eng.nw_static, eng.u_static, eng.p_static)
    bt = branch_topology(eng.model)
    ma = machine_arrays(eng.model)
    V, _, _, _, flows = _read_static(eng.model, bt, eng.u_static, eng.p_static,
                                     eng.sVre_idx, eng.sVim_idx, eng.sδ_idx,
                                     eng.sstatus_pidx, ma)
    _check_power_flow(eng.model, V, flows, res,
                      "DetailedEngine re-initialisation at t = $(eng.integrator.t)")
    for v in eachindex(eng.Vre_idx)
        u[eng.Vre_idx[v]] = real(V[v])
        u[eng.Vim_idx[v]] = imag(V[v])
    end
    # THE DYNAMIC NETWORK'S OWN KIRCHHOFF ROWS, AT THE STATE JUST WRITTEN (M7 step 7).
    # Everything above checks the STATIC network's solve — a different set of
    # equations, kept equal to the dynamic one only by every event writing the same
    # change into both parameter vectors. A source trip writes FOUR such pairs (a
    # machine's status, an inverter's status, a grid-following setpoint in each
    # network), and one written on one side only would leave a static solve that
    # converges beautifully onto a network the integrator is not integrating. This is
    # the check that sees it: the algebraic rows of the right-hand side the solver
    # actually steps, evaluated where it is about to start.
    du = similar(u)
    eng.nw(du, u, eng.params, eng.integrator.t)
    kcl = 0.0
    for v in eachindex(eng.Vre_idx)
        kcl = max(kcl, abs(du[eng.Vre_idx[v]]), abs(du[eng.Vim_idx[v]]))
    end
    kcl < _PF_RESIDUAL || throw(ErrorException(
        "DetailedEngine re-initialisation at t = $(eng.integrator.t): the static solve " *
        "converged, but the DYNAMIC network's Kirchhoff rows are off by $kcl at the " *
        "re-solved voltages. The two networks hold different parameters — an event " *
        "wrote its change into one of them only."))
    # A STATE WRITTEN INTO THE INTEGRATOR IS DISCARDED BY THE NEXT STEP UNLESS THE
    # INTEGRATOR IS TOLD (the M3 finding, and the reason this is not a bare
    # assignment). `derivative_discontinuity!` invalidates the cached derivative
    # that a FSAL method would otherwise reuse across the discontinuity;
    # `auto_dt_reset!` stops the controller carrying a step size chosen for the
    # pre-event dynamics.
    SciMLBase.derivative_discontinuity!(eng.integrator, true)
    SciMLBase.auto_dt_reset!(eng.integrator)
    return nothing
end

"""
    inject!(eng::DetailedEngine, ev::TripLine)

Open the branch between `ev.from` and `ev.to`, then restore the algebraic states.

The line goes out through a `status` PARAMETER that multiplies its current, so an
out-of-service branch is an open circuit exactly — there is no `X = Inf` anywhere
near a denominator, and the network's structure never changes. Tripping a line
already out is a no-op, logged as such rather than silently re-applied.
"""
function inject!(eng::DetailedEngine, ev::TripLine)
    e = _detailed_branch_index(eng, ev.from, ev.to)
    e in eng.lines_online || return nothing
    delete!(eng.lines_online, e)
    eng.params[eng.status_pidx[e]] = 0.0
    eng.p_static[eng.sstatus_pidx[e]] = 0.0
    _reinitialise_algebraic!(eng)
    _log_event!(eng, :trip_line, ev.from, ev.to)
    return nothing
end

"""
    is_online(eng::DetailedEngine, id::Symbol) -> Bool

Whether source `id` — a machine or an inverter of either kind — is still in service.
An unknown id is `false`, the swing tier's contract.
"""
is_online(eng::DetailedEngine, id::Symbol) = id in eng.online

"""
    inject!(eng::DetailedEngine, ev::TripGenerator)

Take a source out of service (M7 step 7, `m7-context.md` D15): a machine, a
grid-forming inverter or a grid-following one, looked up by id.

**The bus becomes a passive node without the vertex changing shape.** A compiled
vertex model's state count is fixed, so the source is switched off through an
in-service flag that multiplies its CURRENT — `mstat` in `_stator`, `istat` in the
grid-forming vertex, and the current setpoint itself for a grid-following inverter
(which IS its current). The obvious shortcut, `E = 0`, is **wrong** and is not what
this does: it would leave `X′d` (or `X_c`) in place as a shunt reactance to ground —
a different network that converges and looks plausible. The flag is written into
BOTH networks, the one integrated and the one the re-initialisation solves, and the
re-initialisation checks that the two agree (`_reinitialise_algebraic!`).

What leaves with the unit, each for the swing tier's reason (`inject!(::SwingEngine,
::TripGenerator)` argues every one):

  - **its inertia weight** — `w[k]` for a machine, the virtual inertia `gfm.H[j]` for
    a grid-forming inverter; `Σw` is recomputed, so `f_coi` and `coi_rocof` average
    over the units still online (a grid-following inverter weighed nothing);
  - a machine's **mechanical power, governor, reserve and ramp** (`Pm`, `invR`,
    `headroom`, `rate` to zero), with `ΔPm` re-seated to zero at the boundary — an
    undriven rotor that kept its `Pm` would accelerate forever on a power nobody
    takes, and one that kept `rate` would go on ramping;
  - a grid-forming inverter's **setpoint** (`P_set` to zero), so its now-idle droop
    settles at zero frequency instead of drifting its angle at `K_p·P_set`;
  - every **shed ladder** on a tripped machine and every **out-of-step relay**
    watching a branch that ends at its bus, latched without firing.

**A trip that would leave no machine and no grid-forming inverter online is
refused** before anything moves: the centre-of-inertia weights would sum to zero,
and the grid-following inverters would be left with nothing to follow (Hurdle 10
claim 3, D5) — the aggregate engine's refusal, at this tier.

Then the algebraic states are re-solved with every differential state held (the
same `_PF_HOLD` path a line trip takes). Tripping a unit already out is a no-op; an
unknown id is a `KeyError`, and the lookup happens first so that error is reachable.
"""
function inject!(eng::DetailedEngine, ev::TripGenerator)
    id = ev.id
    k = findfirst(==(id), eng.ids)
    j = findfirst(==(id), eng.gfm.ids)
    f = findfirst(==(id), eng.gfl.ids)
    k === nothing && j === nothing && f === nothing && throw(KeyError(id))
    id in eng.online || return nothing
    # Refused BEFORE anything moves: is any voltage source left once this one goes?
    any(x -> x != id && x in eng.online, eng.ids) ||
        any(x -> x != id && x in eng.online, eng.gfm.ids) || throw(ArgumentError(
        "DetailedEngine: tripping $id would leave no machine and no grid-forming " *
        "inverter online — no inertia to weight a centre-of-inertia frequency, and " *
        "nothing for the grid-following inverters to follow (m7-context.md D5, " *
        "Hurdle 10 claim 3). Refused; nothing was changed."))
    delete!(eng.online, id)
    p, ps, u = eng.params, eng.p_static, eng.integrator.u
    bus = Symbol("")
    if k !== nothing
        p[eng.mstat_pidx[k]]   = 0.0
        ps[eng.smstat_pidx[k]] = 0.0
        p[eng.Pm_pidx[k]]      = 0.0
        p[eng.invR_pidx[k]]    = 0.0
        p[eng.hr_pidx[k]]      = 0.0
        p[eng.rate_pidx[k]]    = 0.0
        u[eng.ΔPm_idx[k]]      = 0.0
        eng.w[k] = 0.0
        for l in eng.ladders
            l.machine === id && disarm!(l)
        end
        bus = eng.model.machines[k].bus
    elseif j !== nothing
        g = eng.gfm
        p[g.stat_pidx[j]]   = 0.0
        ps[g.sstat_pidx[j]] = 0.0
        p[g.Pset_pidx[j]]   = 0.0
        g.H[j] = 0.0
        bus = eng.model.buses[g.bus[j]].id
    else
        h = eng.gfl
        p[h.id_pidx[f]]  = 0.0
        p[h.iq_pidx[f]]  = 0.0
        ps[h.sid_pidx[f]] = 0.0
        ps[h.siq_pidx[f]] = 0.0
        bus = eng.model.buses[h.bus[f]].id
    end
    for r in eng.relays
        (r.from === bus || r.to === bus) && disarm!(r)
    end
    eng.Σw = isempty(eng.gfm.ids) ? sum(eng.w) : sum(eng.w) + sum(eng.gfm.H)
    _reinitialise_algebraic!(eng)
    _log_event!(eng, :trip_generator, id, Symbol(""))
    return nothing
end

# M7 step 6. A machine's `ω` row and a grid-forming inverter's `P_filt` row both have
# unit mass, so `du` there IS the derivative. The inverter's speed is the droop law
# `_gfm_speed`, linear in `P_filt` with the setpoint a parameter, so its rate is the
# same law applied to the rate with the setpoint at zero — one copy of the law.
# Unreachable at zero weight on this tier — D5 refuses a model with no source at
# `init!`, and `inject!(::TripGenerator)` refuses the trip that would take the last
# one (M7 step 7) — guarded anyway so the method says what the others say. A tripped
# unit's weight is zeroed (`w[k]`, `gfm.H[j]`), so it drops out of the sum here.
function coi_rocof(eng::DetailedEngine)
    eng.Σw > 0 || throw(ArgumentError(
        "coi_rocof: the inertia weights sum to zero, so there is no centre-of-inertia " *
        "frequency to differentiate."))
    u, p = eng.integrator.u, eng.integrator.p
    du = similar(u)
    eng.nw(du, u, p, eng.integrator.t)
    acc = 0.0
    @inbounds for k in eachindex(eng.ω_idx)
        acc += eng.w[k] * du[eng.ω_idx[k]]
    end
    g = eng.gfm
    @inbounds for j in eachindex(g.ids)
        acc += g.H[j] * _gfm_speed(g.K_p[j], du[g.Pf_idx[j]], 0.0)
    end
    return eng.f0 * acc / eng.Σw
end
