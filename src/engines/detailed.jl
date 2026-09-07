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
# saturations in the DERIVATIVE, backed by an `isoutofdomain` guard which this tier
# had none of at all before step 5.
#
# WHAT IS DELIBERATELY NOT HERE YET, each named rather than discovered later:
#   - `inject!(::TripGenerator)` — a tripped machine turns its bus into a passive
#     node, which changes that vertex's EQUATIONS, and a vertex model cannot
#     change shape at run time. It needs a machine status that zeroes the injected
#     current without turning `X′d` into a shunt to ground;
#   - more than one machine on a bus. The canonical model expresses it (M5 step 1
#     made sure of that); this engine's vertex models do not yet, and say so;
#   - the ZIP `a_i`/`a_p` shares (plan step 6). Only constant impedance is solved.
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
rotor states drift harmlessly. It is carried for symmetry with the branch flag and
is **not exercised** — `inject!(::TripGenerator)` still refuses by name below.
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

"""
    _load_current(Vre, Vim, G, B) -> (Ire, Iim)

A constant-impedance load's drawn current, `I = (G + jB)·V`.

The admittance comes from the scheduled draw at nominal voltage: `Y = conj(S)/|V₀|²`
with `|V₀| = 1`, i.e. `G = P₀` and `B = −Q₀` (per unit). A bus with no load carries
`G = B = 0`, which is arithmetically no load at all rather than a special case.
"""
@inline _load_current(Vre, Vim, G, B) = (G * Vre - B * Vim, G * Vim + B * Vre)

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
    G, B, mstat         = p[15], p[16], p[17]
    K_A, T_E            = p[18], p[19]
    Efd_min, Efd_max, Vref = p[20], p[21], p[22]
    Id, Iq, Ire, Iim, Pe = _stator(Vre, Vim, δ, E′q, E′d, Ra, Xd′, Xq′, mstat)
    Lre, Lim = _load_current(Vre, Vim, G, B)
    dv[1] = Ire - Lre + esum[1]                 # KCL, real
    dv[2] = Iim - Lim + esum[2]                 # KCL, imaginary
    dv[3] = ω₀ * ω
    dv[4] = (Pm + ΔPm - Pe - D * ω) / (2 * H)
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
    Lre, Lim = _load_current(v[1], v[2], p[1], p[2])
    dv[1] = -Lre + esum[1]
    dv[2] = -Lim + esum[2]
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
    Pset, E, Xq, Ra, G, B = p[1], p[2], p[3], p[4], p[5], p[6]
    mode, δ_target, mstat = p[7], p[8], p[9]
    Xd′, Xq′, E′q, E′d    = p[10], p[11], p[12], p[13]
    if mode > 1.5
        _, _, Ire, Iim, _ = _stator(Vre, Vim, δ, E′q, E′d, Ra, Xd′, Xq′, mstat)
        Pe = zero(Ire)                          # unused in this mode; see below
    else
        Ire, Iim, Pe = _machine_injection(Vre, Vim, δ, E, Ra, Xq, mstat)
    end
    Lre, Lim = _load_current(Vre, Vim, G, B)
    dv[1] = Ire - Lre + esum[1]
    dv[2] = Iim - Lim + esum[2]
    dv[3] = mode > 0.5 ? (δ - δ_target) : (Pe - Pset)
    return nothing
end

# ─────────────────────────────────────────────────────────────────────────────
# Preconditions
# ─────────────────────────────────────────────────────────────────────────────

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
    for (v, ks) in pairs(net.machines_at_bus)
        length(ks) <= 1 || throw(ArgumentError(
            "DetailedEngine: bus $(net.buses[v].id) carries $(length(ks)) machines " *
            "($(join([net.machines[k].id for k in ks], ", "))). The canonical model " *
            "expresses this and this engine does not yet: a vertex model's state " *
            "count is fixed at compile time, so a second machine on a bus needs a " *
            "second vertex model rather than a wider one. Not a tier boundary — " *
            "unbuilt work, and named here so it cannot be mistaken for one."))
    end
    for l in net.loads
        (l.a_i == 0.0 && l.a_p == 0.0) || throw(ArgumentError(
            "DetailedEngine: load $(l.id) has ZIP shares (a_z, a_i, a_p) = " *
            "($(l.a_z), $(l.a_i), $(l.a_p)). Step 1 solves the constant-impedance " *
            "term only — it is the case that folds into the admittance and the case " *
            "with a closed form. The constant-current and constant-power terms are " *
            "plan step 6, and are refused rather than silently ignored, because a " *
            "load quietly drawing the wrong power is the failure this whole tier " *
            "exists to see."))
    end
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

# The load admittance seen at each VERTEX, `Y = conj(S)/|V₀|²` with `|V₀| = 1`.
# Zero where a bus carries no load, which is arithmetically no load rather than a
# branch in the RHS. Converted through `load_arrays`, the one place loads convert.
function _bus_admittance(net::NetworkModel)
    la = load_arrays(net)
    G = zeros(Float64, length(net.buses))
    B = zeros(Float64, length(net.buses))
    for k in eachindex(la.bus)
        G[la.bus[k]] =  la.P[k]
        B[la.bus[k]] = -la.Q[k]
    end
    return G, B
end

# The dynamic (DAE) network: a machine vertex where there is a machine, a passive
# vertex where there is not. Heterogeneous vertex vectors and zero mass-matrix
# rows were both measured to work before any of this was written.
function _dynamic_network(net::NetworkModel, g)
    vmachine = NetworkDynamics.VertexModel(
        f = _detailed_machine_bus!, g = NetworkDynamics.StateMask(1:2),
        sym = [:V_re, :V_im, :δ, :ω, :ΔPm, :E′q, :E′d, :Efd],
        psym = [:Pm, :Xd, :Xq, :Xd′, :Xq′, :Td0′, :Tq0′, :Ra,
                :H, :D, :ω₀, :invR, :headroom, :Tg, :G, :B, :mstat,
                :K_A, :T_E, :Efd_min, :Efd_max, :Vref],
        mass_matrix = LinearAlgebra.Diagonal([0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]),
        name = :machine_bus)
    vpassive = NetworkDynamics.VertexModel(
        f = _detailed_passive_bus!, g = NetworkDynamics.StateMask(1:2),
        sym = [:V_re, :V_im], psym = [:G, :B],
        mass_matrix = LinearAlgebra.Diagonal([0.0, 0.0]), name = :passive_bus)
    verts = [isempty(net.machines_at_bus[v]) ? vpassive : vmachine
             for v in 1:length(net.buses)]
    return NetworkDynamics.Network(g, verts, [_detailed_edge() for _ in 1:Graphs.ne(g)])
end

# The static network: same graph, same edges, same Kirchhoff residual, machines
# reduced to `(V_re, V_im, δ)` with the switchable third equation.
function _static_network(net::NetworkModel, g)
    vmachine = NetworkDynamics.VertexModel(
        f = _static_machine_bus!, g = NetworkDynamics.StateMask(1:2),
        sym = [:V_re, :V_im, :δ],
        psym = [:Pset, :E, :Xq, :Ra, :G, :B, :mode, :δ_target, :mstat,
                :Xd′, :Xq′, :E′q, :E′d],
        mass_matrix = LinearAlgebra.Diagonal(zeros(3)), name = :pf_machine_bus)
    vpassive = NetworkDynamics.VertexModel(
        f = _detailed_passive_bus!, g = NetworkDynamics.StateMask(1:2),
        sym = [:V_re, :V_im], psym = [:G, :B],
        mass_matrix = LinearAlgebra.Diagonal(zeros(2)), name = :pf_passive_bus)
    verts = [isempty(net.machines_at_bus[v]) ? vpassive : vmachine
             for v in 1:length(net.buses)]
    return NetworkDynamics.Network(g, verts, [_detailed_edge() for _ in 1:Graphs.ne(g)])
end

# `isoutofdomain` predicate, built per engine because it has to close over the
# resolved flat indices — `SwingEngine`'s construction, and for its reasons.
#
# THIS TIER HAD NO PREDICATE AT ALL UNTIL M5 STEP 5, and that is a gap being closed
# rather than a feature being extended. `ΔPm`'s headroom has had its derivative
# saturation here since step 1, but nothing absorbed an adaptive step that overshot
# the ceiling between two derivative evaluations — the guard `SwingEngine` grew in
# M3 was simply never copied across. The regulator is what made it worth writing (a
# limit that BINDS is the case where overshoot happens), so the predicate arrives
# with three indices per machine rather than the plan's two.
#
# It touches only `ΔPm` and `Efd`. `δ` and `ω` are deliberately unbounded — post-trip
# the angles drift forever by design — and so are the flux states and every bus
# voltage: an algebraic unknown has no box to be outside of, and a predicate that
# rejected a proposed voltage would reject every step of a correct run and collapse
# `dt` to an abort.
#
# Rejecting a step is not the forbidden post-hoc clamp: the step is retried, never
# written. The derivative saturations in `_detailed_machine_bus!` do the physical
# work; this only absorbs overshoot on top of them, and it cannot stall, because at
# a limit the saturated derivative already puts the solution *at* the limit rather
# than beyond it. The `1e-10` slack is roundoff tolerance for exactly that landing.
function _detailed_outofdomain(ΔPm_idx::Vector{Int}, hr_pidx::Vector{Int},
                               Efd_idx::Vector{Int}, lo_pidx::Vector{Int},
                               hi_pidx::Vector{Int})
    return function (u, p, t)
        @inbounds for k in eachindex(ΔPm_idx)
            u[ΔPm_idx[k]] > p[hr_pidx[k]] + 1e-10 && return true
            u[Efd_idx[k]]  > p[hi_pidx[k]]  + 1e-10 && return true
            u[Efd_idx[k]]  < p[lo_pidx[k]]  - 1e-10 && return true
        end
        return false
    end
end


# ─────────────────────────────────────────────────────────────────────────────
# The power flow, and the checks that make it a result rather than a fixpoint
# ─────────────────────────────────────────────────────────────────────────────

"""
    _check_power_flow(net, V, flows, residual, what)

The solution is CHECKED, NOT TRUSTED (m5-prestudy.md §4, D7). Three tests, and
the first one is the one that matters:

  1. `|V| ∈ [0.9, 1.1]` at every bus. This is not a comfort check on voltage
     quality — it is the **only** thing that separates the true solution from the
     collapsed spurious one, whose residual is 400× tighter (see the header).
  2. Every branch flow within its rating, so a "converged" answer that needs a
     line to carry three times its thermal limit is refused rather than reported.
  3. The residual below `1e-10`. Listed third deliberately: it is necessary and
     conspicuously not sufficient.
"""
function _check_power_flow(net::NetworkModel, V::Vector{ComplexF64},
                           flows::Vector{Float64}, residual::Float64,
                           what::AbstractString)
    residual < _PF_RESIDUAL || throw(ErrorException(
        "$what: the network solve converged to a residual of $residual, above the " *
        "$_PF_RESIDUAL threshold. This is necessary and not sufficient — see the " *
        "band check below, which is what actually separates the true solution from " *
        "a self-consistent collapsed one."))
    for (v, b) in pairs(net.buses)
        Vm = abs(V[v])
        _PF_VMIN <= Vm <= _PF_VMAX || throw(ErrorException(
            "$what: bus $(b.id) solved to |V| = $Vm pu, outside [$_PF_VMIN, $_PF_VMAX]. " *
            "A collapsed-voltage solution is SELF-CONSISTENT and converges to a " *
            "TIGHTER residual than the true one (measured: 5.0e-16 against 1.8e-13), " *
            "so this band is the discriminator and the residual is not. Either the " *
            "case is genuinely infeasible, or the solve fell into the spurious basin."))
    end
    for (e, br) in pairs(net.branches)
        mva = flows[e] * net.S_base
        mva <= br.rating || throw(ErrorException(
            "$what: branch $(br.id) carries $mva MVA against a rating of " *
            "$(br.rating) MVA. The solve converged, but onto a dispatch the network " *
            "cannot physically run."))
    end
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
    for k in 1:nm
        v = ma.bus[k]
        δ[k] = u[sδ[k]]
        # Meaningful in the two STEADY modes only: it evaluates the steady-state
        # source, whose magnitude `ma.E[k]` is a statement about a machine at rest.
        # `_reinitialise_algebraic!` (mode `_PF_HOLD`) discards it for that reason.
        _, _, pe = _machine_injection(real(V[v]), imag(V[v]), δ[k],
                                      ma.E[k], ma.Ra[k], ma.Xq[k], 1.0)
        Pe[k] = pe
    end
    status = Float64[p[sstatus[e]] for e in eachindex(net.branches)]
    flows = _branch_flows(net, bt, V, status)
    return V, δ, Pe, flows
end

"""
    init!(DetailedEngine, net::NetworkModel; t0=0.0, dt=0.02, slack=first machine,
          solver=Rodas5P(), reltol, abstol, capacity)

Build the detailed tier's engine: compile both networks, solve the power flow,
back-substitute every machine state, and place a stiff integrator on the result.

`slack` names the machine whose rotor angle is the reference, and whose mechanical
power is therefore free while every other machine holds its schedule. It is a
keyword rather than model data because it is a decision about a *case*, not a
property of the network — but it is **not** merely a gauge choice, and the header
carries the measurement that says so: with a voltage-dependent load anywhere in
the model, two slacks give two different (both correct) dispatches.

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
               capacity::Integer = _TRAJ_CAPACITY)
    _assert_detailed_tier(net)
    isempty(net.machines) && throw(ArgumentError(
        "DetailedEngine: the model has no machines, so there is no angle reference " *
        "and no differential state at all."))

    ma = machine_arrays(net)
    g, bt = _detailed_graph(net)
    nb, nm, ne = length(net.buses), length(net.machines), length(net.branches)
    ids = Symbol[m.id for m in net.machines]
    G, B = _bus_admittance(net)
    ω₀ = 2π * net.f0
    t0f = Float64(t0)

    slack_id = slack === nothing ? ids[1] : slack
    k_slack = findfirst(==(slack_id), ids)
    k_slack === nothing && throw(ArgumentError(
        "DetailedEngine: slack = :$slack_id is not a machine in this model " *
        "(machines: $(join(ids, ", "))). The slack supplies the angle reference; " *
        "it must be a machine, because a passive bus has no rotor angle to pin."))

    nw  = _dynamic_network(net, g)
    nws = _static_network(net, g)
    SII = NetworkDynamics.SII

    # Flat indices, resolved once through the symbolic interface — nothing here
    # assumes a stride or an ordering, the discipline `SwingEngine` established.
    Vre_idx = [SII.variable_index(nw, NetworkDynamics.VIndex(v, :V_re)) for v in 1:nb]
    Vim_idx = [SII.variable_index(nw, NetworkDynamics.VIndex(v, :V_im)) for v in 1:nb]
    δ_idx   = [SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :δ)) for k in 1:nm]
    ω_idx   = [SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :ω)) for k in 1:nm]
    ΔPm_idx = [SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :ΔPm)) for k in 1:nm]
    E′q_idx = [SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :E′q)) for k in 1:nm]
    E′d_idx = [SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :E′d)) for k in 1:nm]
    Efd_idx = [SII.variable_index(nw, NetworkDynamics.VIndex(ma.bus[k], :Efd)) for k in 1:nm]
    Pm_pidx = [SII.parameter_index(nw, NetworkDynamics.VPIndex(ma.bus[k], :Pm)) for k in 1:nm]
    Vref_pidx = [SII.parameter_index(nw, NetworkDynamics.VPIndex(ma.bus[k], :Vref)) for k in 1:nm]
    hr_pidx   = [SII.parameter_index(nw, NetworkDynamics.VPIndex(ma.bus[k], :headroom)) for k in 1:nm]
    lo_pidx   = [SII.parameter_index(nw, NetworkDynamics.VPIndex(ma.bus[k], :Efd_min)) for k in 1:nm]
    hi_pidx   = [SII.parameter_index(nw, NetworkDynamics.VPIndex(ma.bus[k], :Efd_max)) for k in 1:nm]

    sVre_idx = [SII.variable_index(nws, NetworkDynamics.VIndex(v, :V_re)) for v in 1:nb]
    sVim_idx = [SII.variable_index(nws, NetworkDynamics.VIndex(v, :V_im)) for v in 1:nb]
    sδ_idx   = [SII.variable_index(nws, NetworkDynamics.VIndex(ma.bus[k], :δ)) for k in 1:nm]
    sPset_pidx    = [SII.parameter_index(nws, NetworkDynamics.VPIndex(ma.bus[k], :Pset)) for k in 1:nm]
    smode_pidx    = [SII.parameter_index(nws, NetworkDynamics.VPIndex(ma.bus[k], :mode)) for k in 1:nm]
    sδtarget_pidx = [SII.parameter_index(nws, NetworkDynamics.VPIndex(ma.bus[k], :δ_target)) for k in 1:nm]
    sE′q_pidx     = [SII.parameter_index(nws, NetworkDynamics.VPIndex(ma.bus[k], :E′q)) for k in 1:nm]
    sE′d_pidx     = [SII.parameter_index(nws, NetworkDynamics.VPIndex(ma.bus[k], :E′d)) for k in 1:nm]

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
        sp[SII.parameter_index(nws, NetworkDynamics.VPIndex(v, :G))] = G[v]
        sp[SII.parameter_index(nws, NetworkDynamics.VPIndex(v, :B))] = B[v]
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
    for e in 1:ne
        sp[sX_pidx[e]]      = bt.X[e]
        sp[sstatus_pidx[e]] = 1.0
    end

    res = _run_static!(nws, su, sp)
    V, δ0, Pe, flows = _read_static(net, bt, su, sp, sVre_idx, sVim_idx, sδ_idx,
                                    sstatus_pidx, ma)
    _check_power_flow(net, V, flows, res, "DetailedEngine power flow")

    # --- back-substitution ----------------------------------------------------
    # `Pm` from the POWER FLOW, not from `Machine.P0` — see the header. On a model
    # with no load this is `P0` to the bit for every non-slack machine, which is
    # exactly why the fixture that exercises it has a load on it.
    u0 = zeros(Float64, NetworkDynamics.dim(nw))
    p0 = zeros(Float64, NetworkDynamics.pdim(nw))
    for v in 1:nb
        u0[Vre_idx[v]] = real(V[v])
        u0[Vim_idx[v]] = imag(V[v])
        p0[SII.parameter_index(nw, NetworkDynamics.VPIndex(v, :G))] = G[v]
        p0[SII.parameter_index(nw, NetworkDynamics.VPIndex(v, :B))] = B[v]
    end
    # EVERY MACHINE STATE IN CLOSED FORM (`m5-prestudy.md` §4). `δ` is never
    # *seeded*, only computed from a converged network solution, which is what
    # sidesteps the spurious-equilibrium basin the header measures.
    worst_pm = 0.0
    for k in 1:nm
        vb = ma.bus[k]
        Vre, Vim = real(V[vb]), imag(V[vb])
        δ = δ0[k]
        Ire, Iim, _ = _machine_injection(Vre, Vim, δ, ma.E[k], ma.Ra[k], ma.Xq[k], 1.0)
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
                           (:Efd_min, ma.Efd_min[k]), (:Efd_max, ma.Efd_max[k]))
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

    prob = OrdinaryDiffEq.ODEProblem(nw, u0, (t0f, t0f + 1.0e6), p0)
    integrator = OrdinaryDiffEq.init(prob, solver; dt = Float64(dt),
                                     reltol = Float64(reltol), abstol = Float64(abstol),
                                     dtmax = Float64(dtmax),
                                     isoutofdomain = _detailed_outofdomain(
                                         ΔPm_idx, hr_pidx, Efd_idx, lo_pidx, hi_pidx),
                                     save_everystep = false, dense = false,
                                     calck = _ENGINE_CALCK)

    channels = vcat([Symbol("δ_", id) for id in ids],
                    [Symbol("ω_", id) for id in ids],
                    [Symbol("E′q_", id) for id in ids],
                    [Symbol("E′d_", id) for id in ids],
                    [Symbol("Efd_", id) for id in ids],
                    [Symbol("V_", b.id) for b in net.buses], [:δ_coi, :f_coi])
    traj = TrajectoryRecorder(channels...; capacity = capacity)
    branch_of_buses = Dict{Tuple{Symbol,Symbol},Int}(
        _bus_pair(br.from, br.to) => e for (e, br) in pairs(net.branches))

    eng = DetailedEngine(net, nw, nws, slack_id, Set(1:ne), integrator.p, sp, su,
                         Float64(dt), integrator, net.f0, ω₀, ids, copy(ma.bus),
                         δ_idx, ω_idx, ΔPm_idx, E′q_idx, E′d_idx, Efd_idx,
                         Vre_idx, Vim_idx, Pm_pidx, Vref_pidx, status_pidx,
                         sVre_idx, sVim_idx, sδ_idx, sPset_pidx, smode_pidx,
                         sδtarget_pidx, sstatus_pidx, sE′q_pidx, sE′d_pidx,
                         branch_to_edge, branch_of_buses,
                         copy(ma.H), copy(ma.H), sum(ma.H), traj,
                         Vector{Float64}(undef, length(channels)),
                         EngineEvent[], 0, net.f0)
    _record!(eng)                                 # seed the pre-disturbance point
    return eng
end

# ─────────────────────────────────────────────────────────────────────────────
# Read-out
# ─────────────────────────────────────────────────────────────────────────────

# Inertia-weighted aggregate over the machines, the same gauge-fixing device
# `SwingEngine` uses: an individual rotor angle means nothing on its own, only its
# difference from the aggregate does.
@inline function _coi(eng::DetailedEngine, u, idx::Vector{Int})
    acc = 0.0
    @inbounds for k in eachindex(idx)
        acc += eng.w[k] * u[idx[k]]
    end
    return acc / eng.Σw
end
@inline _ω_coi(eng::DetailedEngine, u) = _coi(eng, u, eng.ω_idx)
@inline _δ_coi(eng::DetailedEngine, u) = _coi(eng, u, eng.δ_idx)

"""
    current_state(eng::DetailedEngine) -> NamedTuple

`(; t, δ, ω, ΔPm, E′q, E′d, Efd, V, δ_coi, ω_coi, f_coi)`. `V` is the vector of bus
voltage MAGNITUDES in per unit, indexed by vertex — the quantity this whole tier
exists to produce, and the one `SwingEngine` cannot report at all because it does
not carry a bus voltage as an unknown.

`E′q`/`E′d` are the transient flux states, machine-indexed. At the classical
degeneration they are constants (`E′q = Machine.E′`, `E′d = 0`) and reading them is
how a test tells that the degeneration actually took.
"""
function current_state(eng::DetailedEngine)
    u = eng.integrator.u
    ω_coi = _ω_coi(eng, u)
    V = Float64[hypot(u[eng.Vre_idx[v]], u[eng.Vim_idx[v]]) for v in eachindex(eng.Vre_idx)]
    return (t = eng.integrator.t, δ = u[eng.δ_idx], ω = u[eng.ω_idx],
            ΔPm = u[eng.ΔPm_idx], E′q = u[eng.E′q_idx], E′d = u[eng.E′d_idx],
            Efd = u[eng.Efd_idx], V = V,
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
    @inbounds for v in 1:nb
        eng.sample[5n + v] = hypot(u[eng.Vre_idx[v]], u[eng.Vim_idx[v]])
    end
    f_coi = eng.f0 * (1 + _ω_coi(eng, u))
    eng.sample[5n + nb + 1] = _δ_coi(eng, u)
    eng.sample[5n + nb + 2] = f_coi
    record!(eng.traj, t, eng.sample)
    f_coi < eng.nadir && (eng.nadir = f_coi)
    return nothing
end

_record!(eng::DetailedEngine) = _record_at!(eng, eng.integrator.t, eng.integrator.u)

"""
    state_series(eng::DetailedEngine) -> NamedTuple

`(; t, δ_<id>..., ω_<id>..., E′q_<id>..., E′d_<id>..., Efd_<id>..., V_<bus>...,
δ_coi, f_coi)`. Bounded and decimating, like every recorder in the repo.

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
    # Seed from where the network is, never from flat — the spurious basin is
    # within 2.5 rad (see the header).
    for v in eachindex(eng.Vre_idx)
        eng.u_static[eng.sVre_idx[v]] = u[eng.Vre_idx[v]]
        eng.u_static[eng.sVim_idx[v]] = u[eng.Vim_idx[v]]
    end
    res = _run_static!(eng.nw_static, eng.u_static, eng.p_static)
    bt = branch_topology(eng.model)
    ma = machine_arrays(eng.model)
    V, _, _, flows = _read_static(eng.model, bt, eng.u_static, eng.p_static,
                                  eng.sVre_idx, eng.sVim_idx, eng.sδ_idx,
                                  eng.sstatus_pidx, ma)
    _check_power_flow(eng.model, V, flows, res,
                      "DetailedEngine re-initialisation at t = $(eng.integrator.t)")
    for v in eachindex(eng.Vre_idx)
        u[eng.Vre_idx[v]] = real(V[v])
        u[eng.Vim_idx[v]] = imag(V[v])
    end
    # A STATE WRITTEN INTO THE INTEGRATOR IS DISCARDED BY THE NEXT STEP UNLESS THE
    # INTEGRATOR IS TOLD (the M3 finding, and the reason this is not a bare
    # assignment). `u_modified!` invalidates the cached derivative that a FSAL
    # method would otherwise reuse across the discontinuity; `auto_dt_reset!` stops
    # the controller carrying a step size chosen for the pre-event dynamics.
    SciMLBase.u_modified!(eng.integrator, true)
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
    inject!(eng::DetailedEngine, ev::TripGenerator)

Not built yet, and refused by name rather than approximated.

A tripped machine turns its bus into a passive node, which changes that vertex's
EQUATIONS — and a `VertexModel`'s state count is fixed when the network compiles.
The obvious shortcut, setting `E = 0`, is **wrong**: it leaves `X′d` in place as a
shunt reactance to ground rather than removing the machine, which is a different
network and a plausible-looking wrong answer. What it needs is a machine status
that zeroes the injected current while leaving the rotor's own states to drift
harmlessly, plus the swing equation released from a power it no longer produces.
"""
function inject!(eng::DetailedEngine, ev::TripGenerator)
    throw(ArgumentError(
        "DetailedEngine: inject!(::TripGenerator) is not built at this tier yet " *
        "(machine $(ev.id)). A tripped machine makes its bus a passive node, which " *
        "changes the vertex's equations, and a compiled vertex model cannot change " *
        "shape at run time. Setting E = 0 would leave X′d as a shunt to ground — a " *
        "different network that converges and looks plausible. Use TripLine, or " *
        "SwingEngine, until the machine-status path exists."))
end
