# M6 step 3 — the nonlinear ("AC") power flow.
#
# THE EQUATIONS ARE OURS; THE SOLVER IS NonlinearSolve's (m6-context.md D2). What
# power balance means at a bus, what a generator bus holds fixed, and when a
# reactive limit binds are *model* — they are written here, the same way every ODE
# right-hand side in `src/engines/` is written here and handed to an integrator.
# Newton, the Jacobian, the line search and the convergence control are not.
#
# WHAT IS SOLVED, AND WHAT IS HELD — the table `m6-plan.md` opens with:
#
#   slack bus      holds |V| (its machines' `V_set`) and angle 0; its machines'
#                  P and Q are whatever the network turns out to need
#   generator bus  holds its machines' scheduled P and their `V_set`; solves for
#                  the angle, and reports the reactive output that supports it
#   load bus       holds P and Q (the load's ZIP schedule); solves |V| and angle
#
# CONVERGENCE IS NOT VALIDATION, and this repo has the measurement rather than the
# folklore: M5 found the collapsed low-voltage solution converging to a residual of
# 5.0e-16 against the true solution's 1.8e-13 — 400x "better" by the number the
# solver reports. `_check_voltage_band` is the discriminator and the residual is
# not, so the checks here run band, then ratings, then residual last, and the band
# is INHERITED from `_check_power_flow` rather than re-derived (D6, D10).
#
# A PQ BUS HOLDS A ZIP SCHEDULE, NOT A CONSTANT COMPLEX POWER, and that is a
# deliberate departure from the textbook power flow (D11). `Load` in this repo is a
# ZIP load whose DEFAULT is constant impedance, and step 4's flat-run oracle only
# means anything if the power flow's load draw is the same arithmetic the DAE tier
# integrates — so the voltage scalar is `_zip_k`, shared with `_load_current`, and
# not a second copy of the same algebra. At `a_p = 1` a load bus is the textbook
# constant-power bus; at the default `a_z = 1` it is not, and a comparison against
# any external power flow has to say which it built.
#
# WHAT IS DELIBERATELY ABSENT, named rather than left to be read as a modelling
# choice: line charging and transformer taps (`Branch` says so too — there is no
# `B` and no tap ratio, so the pi-model here is a bare series impedance), bus
# shunts, phase shifters, and any area/distributed slack. And with `a_p > 0` the
# load current diverges as `|V| -> 0` exactly as it does in the DAE tier — M5 D23's
# decision, inherited here rather than re-taken: a bus that draws constant power
# from a collapsed node is a model with no solution, and the singularity is the
# model telling the truth.

# A generator bus is switched to its reactive limit only once the violation is
# bigger than this. Numerical noise on `Q` at a PV bus is at the residual's scale;
# switching on that would make the "limits so wide they cannot bind" control below
# non-exact, and it is exact by construction (D12).
const _AC_QLIM_TOL = 1.0e-9

# The switching loop's cap. Reached only if buses keep taking turns at their
# limits, which is the cycling that bind-only switching is supposed to preclude —
# so hitting it is a bug or a genuinely pathological case, and it throws with the
# bus list rather than returning a half-switched answer.
const _AC_MAX_SWITCH_ROUNDS = 20

"""
    _zip_scale(Vm, a_i, a_p) -> Float64

The ZIP load's power multiplier, `|V|^2 * k(|V|)` — algebraically
`a_z|V|^2 + a_i|V| + a_p`, the share-weighted draw at magnitude `Vm`.

Written as `Vm^2 * _zip_k(...)` rather than as the expanded polynomial so that it
is the **same function** `_load_current` applies to the current, evaluated through
the same grouping. `S_load = V * conj(I_load) = |V|^2 k (P0 + jQ0)` exactly, so
the two are one model and not two that happen to agree.

The `a_i = a_p = 0` early return matters for one reason: `_zip_k` divides by `Vm`,
so a zero-voltage bus with no voltage-dependent share would produce `NaN` from
`0 * Inf` instead of the perfectly well-defined `0`.
"""
@inline function _zip_scale(Vm, a_i, a_p)
    ((a_i == 0.0) & (a_p == 0.0)) && return Vm * Vm
    return Vm * Vm * _zip_k(Vm, a_i, a_p)
end

"""
    _ac_admittance(net::NetworkModel) -> SparseMatrixCSC{ComplexF64,Int}

The bus admittance matrix `Y`, `n x n` in vertex order, from the branch series
impedances `R + jX`: `Y[i,i] = sum y` over the branches at `i`, `Y[i,j] = -y_ij`.

**Sparse, and structurally so** — the same `sparse(I, J, V, n, n)` assembly and the
same stored-entry count `n + 2m` as `_dc_susceptance`, for the same three reasons
(no unbranched bus, no self-loop, no parallel circuit), and checked rather than
trusted. This is `CLAUDE.md`'s "never a dense Y-bus" binding our own code for the
second time.

`Y` is complex and symmetric (not Hermitian): a passive series branch contributes
`-y` to both off-diagonals. It carries **no shunt terms at all** — no line
charging, no taps — so `Y * 1 = 0` holds here exactly as `B * 1 = 0` does in the
DC assembly, and it is the same statement: with nothing to ground, a uniform
voltage draws no current.
"""
function _ac_admittance(net::NetworkModel)
    n = length(net.buses)
    m = length(net.branches)
    rows = Vector{Int}(undef, 4m)
    cols = Vector{Int}(undef, 4m)
    vals = Vector{ComplexF64}(undef, 4m)
    for (e, br) in pairs(net.branches)
        y = inv(complex(br.R, br.X))     # X > 0 is enforced by `Branch`, so never 1/0
        f, t = net.bus_index[br.from], net.bus_index[br.to]
        k = 4e - 3
        rows[k],   cols[k],   vals[k]   = f, f,  y
        rows[k+1], cols[k+1], vals[k+1] = t, t,  y
        rows[k+2], cols[k+2], vals[k+2] = f, t, -y
        rows[k+3], cols[k+3], vals[k+3] = t, f, -y
    end
    return SparseArrays.sparse(rows, cols, vals, n, n)
end

"""
    _ac_schedule(net::NetworkModel)

Everything the residual equations need about a bus, gathered per vertex:
generation, terminal setpoint, reactive limits and the load's ZIP schedule.

`Pgen` comes through `machine_arrays`, which is the one place `MW -> pu` happens;
`P`/`Q` of the load come through `load_arrays` for the same reason. `V_set`,
`Q_min` and `Q_max` are read straight off `Machine` and deliberately not added to
`machine_arrays`: they need **no** conversion (a voltage setpoint is a ratio, and
the limits are already declared on the system base), and putting power-flow-only
data into the view every engine builds would make three fields that no engine
reads travel with every integration.

**Machines on one bus sum**, in `P` and in both limits, and must agree on `V_set` —
a bus has one terminal voltage, so two machines asking for different ones is a
contradiction in the data and is refused by name rather than resolved by a rule
nobody chose.
"""
function _ac_schedule(net::NetworkModel)
    n = length(net.buses)
    Pgen  = zeros(Float64, n)
    V_set = fill(NaN, n)
    Q_min = zeros(Float64, n)
    Q_max = zeros(Float64, n)
    has_machine = falses(n)
    ma = machine_arrays(net)
    for k in eachindex(ma.bus)
        v = ma.bus[k]
        m = net.machines[k]
        if has_machine[v]
            m.V_set == V_set[v] || throw(ArgumentError(
                "ac_powerflow: bus $(net.buses[v].id) carries machines with different " *
                "V_set ($(V_set[v]) and $(m.V_set) pu, the latter on machine $(m.id)). " *
                "A bus has ONE terminal voltage; two setpoints on it is a contradiction " *
                "in the model, not a case for a tie-break rule."))
        else
            has_machine[v] = true
            V_set[v] = m.V_set
        end
        Pgen[v]  += ma.Pm[k]
        Q_min[v] += m.Q_min
        Q_max[v] += m.Q_max
    end
    Pl  = zeros(Float64, n)
    Ql  = zeros(Float64, n)
    a_i = zeros(Float64, n)
    a_p = zeros(Float64, n)
    la = load_arrays(net)
    for k in eachindex(la.bus)
        v = la.bus[k]
        Pl[v]  = la.P[k]
        Ql[v]  = la.Q[k]
        a_i[v] = la.a_i[k]
        a_p[v] = la.a_p[k]
    end
    return (; Pgen, V_set, Q_min, Q_max, has_machine, Pl, Ql, a_i, a_p)
end

"""
    _ACContext

One classification of the buses, plus the data the residual reads — rebuilt from
scratch for each round of reactive-limit switching rather than mutated, because
which equations exist changes when a bus switches and a mutated context would be a
different problem wearing the same object (M3's rebuild-per-cell rule).

  - `nonslack` — vertices with a real-power equation, in order; their angles are
    the first block of unknowns
  - `pq` — vertices with a reactive-power equation, i.e. load buses **and**
    generator buses currently held at a reactive limit; their magnitudes are the
    second block
  - `Vm_held` — the magnitude at the slack and at every unswitched generator bus
  - `Qgen_held` — the reactive injection from machines at a bus whose limit has
    bound (zero everywhere else, which is also the truth at a bus with no machine)
"""
struct _ACContext
    n::Int
    Y::SparseArrays.SparseMatrixCSC{ComplexF64,Int}
    v_slack::Int
    nonslack::Vector{Int}
    pq::Vector{Int}
    Vm_held::Vector{Float64}
    Pgen::Vector{Float64}
    Qgen_held::Vector{Float64}
    Pl::Vector{Float64}
    Ql::Vector{Float64}
    a_i::Vector{Float64}
    a_p::Vector{Float64}
end

# The bus voltages implied by an unknown vector: the held magnitudes and the pinned
# slack angle put back beside the solved ones. Generic in `eltype(x)` so the same
# code serves the residual under a dual number and the read-back under a Float64.
function _ac_expand(c::_ACContext, x::AbstractVector{T}) where {T}
    Vm = Vector{T}(undef, c.n)
    θ  = zeros(T, c.n)
    @inbounds for v in 1:c.n
        Vm[v] = c.Vm_held[v]
    end
    @inbounds for (i, v) in pairs(c.nonslack)
        θ[v] = x[i]
    end
    off = length(c.nonslack)
    @inbounds for (i, v) in pairs(c.pq)
        Vm[v] = x[off + i]
    end
    return Vm, θ
end

# The net complex power flowing from each bus INTO the network, `S = V conj(Y V)`,
# in rectangular arithmetic so that autodiff never meets a `Complex{Dual}`.
#
# `Y` is symmetric, so the sparse column `v` holds exactly the row `v` entries and
# the CSC traversal below reads `Y[k, v]` where the formula says `Y[v, k]`.
function _ac_flows(c::_ACContext, Vm::AbstractVector{T}, θ::AbstractVector{T}) where {T}
    n = c.n
    Vre = Vector{T}(undef, n)
    Vim = Vector{T}(undef, n)
    @inbounds for v in 1:n
        Vre[v] = Vm[v] * cos(θ[v])
        Vim[v] = Vm[v] * sin(θ[v])
    end
    P = Vector{T}(undef, n)
    Q = Vector{T}(undef, n)
    rv = SparseArrays.rowvals(c.Y)
    nz = SparseArrays.nonzeros(c.Y)
    @inbounds for v in 1:n
        Ire = zero(T)
        Iim = zero(T)
        for idx in SparseArrays.nzrange(c.Y, v)
            k = rv[idx]
            g, b = real(nz[idx]), imag(nz[idx])
            Ire += g * Vre[k] - b * Vim[k]
            Iim += g * Vim[k] + b * Vre[k]
        end
        P[v] = Vre[v] * Ire + Vim[v] * Iim
        Q[v] = Vim[v] * Ire - Vre[v] * Iim
    end
    return P, Q
end

"""
    _ac_residual!(F, x, c::_ACContext)

Real power balance at every non-slack bus and reactive balance at every PQ bus:

    P_network(v)  -  ( Pgen(v) - Pload(v, |V|) )  =  0
    Q_network(v)  -  ( Qgen(v) - Qload(v, |V|) )  =  0

with the loads' draw a function of the solved magnitude through `_zip_scale`. The
slack has neither equation — it is the bus whose P and Q are whatever is left over,
which is the same statement as "it picks up the losses".
"""
function _ac_residual!(F, x, c::_ACContext)
    Vm, θ = _ac_expand(c, x)
    P, Q = _ac_flows(c, Vm, θ)
    @inbounds for (i, v) in pairs(c.nonslack)
        z = _zip_scale(Vm[v], c.a_i[v], c.a_p[v])
        F[i] = P[v] - (c.Pgen[v] - c.Pl[v] * z)
    end
    off = length(c.nonslack)
    @inbounds for (i, v) in pairs(c.pq)
        z = _zip_scale(Vm[v], c.a_i[v], c.a_p[v])
        F[off + i] = Q[v] - (c.Qgen_held[v] - c.Ql[v] * z)
    end
    return nothing
end

"""
    _ac_assert_no_backoff(net, limited, at_max, Qheld, Vm, V_set)

The half of reactive-limit switching this solver does **not** do, made loud.

Switching here is bind-only: a bus that has been put on its limit never comes back
off it. That is deliberate — back-off is what makes the classical PV/PQ iteration
cycle — but it means there is one solved state this solver has no right to return:
a bus held at `Q_max` whose magnitude ended up *above* its setpoint (or held at
`Q_min` and below). It was capped because holding `V_set` cost more reactive power
than it had; if it is now on the other side of `V_set`, the cap is no longer what
is binding and the bus should have gone back to holding its voltage.

Taken out of `ac_powerflow` so it can be exercised directly, the way
`_check_power_flow` is: no fixture reaches a pathology by accident, and a guard
that never runs is decoration (`m6-context.md` D12).

`limited` and `at_max` are per switched bus and in step; `Qheld`, `Vm` and `V_set`
are per vertex.
"""
function _ac_assert_no_backoff(net::NetworkModel, limited::Vector{Int},
                               at_max::Vector{Bool}, Qheld::Vector{Float64},
                               Vm::Vector{Float64}, V_set::Vector{Float64})
    for (i, v) in pairs(limited)
        ok = at_max[i] ? Vm[v] <= V_set[v] + 1.0e-9 : Vm[v] >= V_set[v] - 1.0e-9
        ok || throw(ErrorException(
            "ac_powerflow: bus $(net.buses[v].id) was held at Q_$(at_max[i] ? "max" : "min") " *
            "= $(Qheld[v]) pu and then solved to |V| = $(Vm[v]) against a setpoint of " *
            "$(V_set[v]) — the wrong side, which means the bus should have come OFF " *
            "its limit and gone back to holding its voltage. Back-off is not " *
            "implemented (it is what makes the switching iteration cycle), so this " *
            "case is refused rather than answered wrongly."))
    end
    return nothing
end

"""
    ACPowerFlow

A solved nonlinear power flow — the answer detached from the model it came from,
the same contract `DCPowerFlow` has (its vectors are handed out live and the type
is immutable by convention).

  - `slack` — the reference bus: angle exactly `0.0`, magnitude its `V_set`
  - `buses`, `Vm`, `θ` — bus ids in vertex order, magnitudes in pu, angles in rad
  - `Pgen`, `Qgen` — per bus, pu on `S_base`, the machines' output; at the slack
    and at every generator bus these are **solved**, not scheduled
  - `Pload`, `Qload` — per bus, pu, what the loads actually draw at the solved
    magnitude. On a ZIP load that is not `P0` unless `|V| = 1`
  - `roles` — the role each bus had **in the solve**: a generator bus whose
    reactive limit bound reports `:load`, because that is what it became
  - `limited` — the ids of those buses, so the switch is legible rather than only
    implied by `roles`
  - `branches`, `from`, `to` — branch ids and their own orientation
  - `flow`, `qflow` — P and Q leaving `from` into the branch, pu
  - `flow_rev`, `qflow_rev` — P and Q leaving `to`. **Not the negatives of the
    above**: a lossy branch delivers less than it is given, and `flow + flow_rev`
    is exactly the branch's active loss
  - `loss` — that loss, per branch, pu
  - `residual` — the largest absolute residual of the converged equations

Read it with [`bus_voltage`](@ref), [`bus_angle`](@ref), [`bus_generation`](@ref),
[`branch_power`](@ref), [`branch_reactive`](@ref) and [`branch_loss`](@ref).
`bus_angle` and `branch_power` are methods on the generics `DCPowerFlow` and the
two dynamic tiers already answer to — the same physical quantity does not acquire
a new name because a new tier computes it (M5 step 7).
"""
struct ACPowerFlow
    slack::Symbol
    buses::Vector{Symbol}
    Vm::Vector{Float64}
    θ::Vector{Float64}
    Pgen::Vector{Float64}
    Qgen::Vector{Float64}
    Pload::Vector{Float64}
    Qload::Vector{Float64}
    roles::Vector{Symbol}
    limited::Vector{Symbol}
    branches::Vector{Symbol}
    from::Vector{Symbol}
    to::Vector{Symbol}
    flow::Vector{Float64}
    flow_rev::Vector{Float64}
    qflow::Vector{Float64}
    qflow_rev::Vector{Float64}
    loss::Vector{Float64}
    residual::Float64
end

# One Newton solve at a fixed bus classification. Returns the unknown vector and
# the residual RECOMPUTED from it rather than read off the solution object, so the
# number that is checked is a function of the answer that is returned.
function _ac_newton(c::_ACContext, x0::Vector{Float64}, abstol::Float64, maxiters::Int)
    isempty(x0) && return (x0, 0.0)     # one bus, and it is the slack: nothing to solve
    prob = SciMLBase.NonlinearProblem(SciMLBase.NonlinearFunction{true}(_ac_residual!), x0, c)
    sol = NonlinearSolve.solve(prob, NonlinearSolve.NewtonRaphson();
                               abstol = abstol, maxiters = maxiters)
    SciMLBase.successful_retcode(sol) || throw(ErrorException(
        "ac_powerflow: the Newton solve returned $(sol.retcode) after $maxiters " *
        "iterations. A power flow that does not converge is not a result; a case " *
        "with no solution at all looks exactly like this, and so does one seeded " *
        "into the wrong basin."))
    F = similar(sol.u)
    _ac_residual!(F, sol.u, c)
    return (Vector{Float64}(sol.u), maximum(abs, F))
end

"""
    ac_powerflow(net::NetworkModel; abstol = 1e-12, maxiters = 200,
                 max_switch_rounds = 20) -> ACPowerFlow

Solve the nonlinear power flow for `net` at its declared dispatch and declared
slack bus.

**The dispatch is read from the model and nowhere else**, exactly as in
[`dc_powerflow`](@ref) — no injection argument, because a second way to supply one
is a second source of truth about the same fact (`m6-context.md` D3).

The solved answer is **checked, not trusted**: `|V|` band first (the discriminator
— see D6 and the note at the head of this file), branch ratings second, the
residual last and least. A case that converges outside the band is refused by name.

## Reactive limits

A generator bus holds `V_set` only while its machines can supply the reactive power
that takes. When the solved `Q` runs past `Q_max` (or `Q_min`), the bus is switched
to a load bus **held at that limit** and the flow is re-solved; the loop repeats
until nothing more switches.

**Switching is bind-only: a limited bus never returns to holding its voltage.**
Back-off is what makes the classical iteration cycle, and a cycling power flow is
worse than one that says it cannot answer. The missing half is made loud rather
than silent — after convergence, a bus held at `Q_max` whose magnitude ended up
*above* its setpoint (or at `Q_min` and below) is exactly the case back-off exists
for, and it is refused by name rather than returned (D12).

**The slack's own reactive limits are not enforced.** The slack is the bus whose
injection is whatever the network needs; limiting it needs a distributed or area
slack, which no type in this repo expresses. Named here rather than discovered.

## What it refuses

  - a slack bus with no machine on it — the model allows this so a half-built
    editor draft stays constructible (M5 D3's precedent), and the tier that has to
    put a voltage source there refuses it by name;
  - two machines on one bus asking for different `V_set`;
  - a solve that does not converge, or converges outside the checks above.
"""
function ac_powerflow(net::NetworkModel;
                      abstol::Real = 1.0e-12,
                      maxiters::Integer = 200,
                      max_switch_rounds::Integer = _AC_MAX_SWITCH_ROUNDS)
    n = length(net.buses)
    v_slack = net.bus_index[net.slack]           # the constructor guarantees this resolves
    sch = _ac_schedule(net)
    sch.has_machine[v_slack] || throw(ArgumentError(
        "ac_powerflow: the declared slack bus :$(net.slack) carries no machine. " *
        "NetworkModel accepts that — a half-built model with buses placed and no " *
        "machines yet must stay constructible — but a power flow needs a voltage " *
        "source at the reference bus, and there is nothing there to be one."))

    Y = _ac_admittance(net)
    gen_buses = [v for v in 1:n if sch.has_machine[v] && v != v_slack]
    nonslack = [v for v in 1:n if v != v_slack]

    limited = Int[]                      # generator buses switched to a limit
    at_max = Bool[]                      # ...which end of the range each went to
    Qheld = zeros(Float64, n)            # ...and the value each is held at
    x = Float64[]
    res = 0.0
    local c::_ACContext, Vm::Vector{Float64}, θ::Vector{Float64}
    local Pnet::Vector{Float64}, Qnet::Vector{Float64}, Qgen::Vector{Float64}

    round = 0
    while true
        held = Set(limited)
        pq = [v for v in nonslack if !sch.has_machine[v] || v in held]
        Vm_held = [sch.has_machine[v] && !(v in held) ? sch.V_set[v] : 1.0 for v in 1:n]
        c = _ACContext(n, Y, v_slack, nonslack, pq, Vm_held,
                       sch.Pgen, Qheld, sch.Pl, sch.Ql, sch.a_i, sch.a_p)
        # Flat start on the first round; on a later one, the previous answer with
        # the newly freed magnitudes seeded at where they already were.
        x0 = zeros(Float64, length(nonslack) + length(pq))
        if round == 0
            for i in eachindex(pq)
                x0[length(nonslack) + i] = 1.0
            end
        else
            for (i, v) in pairs(nonslack)
                x0[i] = θ[v]
            end
            for (i, v) in pairs(pq)
                x0[length(nonslack) + i] = Vm[v]
            end
        end
        x, res = _ac_newton(c, x0, Float64(abstol), Int(maxiters))
        Vm, θ = _ac_expand(c, x)
        Pnet, Qnet = _ac_flows(c, Vm, θ)
        Qgen = [Qnet[v] + sch.Ql[v] * _zip_scale(Vm[v], sch.a_i[v], sch.a_p[v]) for v in 1:n]

        # Which unswitched generator buses cannot supply what they were asked for.
        newly = Int[]
        newly_at_max = Bool[]
        for v in gen_buses
            v in held && continue
            if Qgen[v] > sch.Q_max[v] + _AC_QLIM_TOL
                push!(newly, v); push!(newly_at_max, true)
                Qheld[v] = sch.Q_max[v]
            elseif Qgen[v] < sch.Q_min[v] - _AC_QLIM_TOL
                push!(newly, v); push!(newly_at_max, false)
                Qheld[v] = sch.Q_min[v]
            end
        end
        # NOTHING SWITCHED ON THE FIRST ROUND MEANS EXACTLY ONE SOLVE HAPPENED.
        # That is what makes "limits so wide they cannot bind reproduce the
        # unlimited answer" an `==` and not an `approx` (D12).
        isempty(newly) && break
        append!(limited, newly)
        append!(at_max, newly_at_max)
        round += 1
        round <= max_switch_rounds || throw(ErrorException(
            "ac_powerflow: reactive-limit switching did not settle in " *
            "$max_switch_rounds rounds; still switching " *
            join(("$(net.buses[v].id)" for v in newly), ", ") * ". Switching here is " *
            "bind-only and should therefore terminate, so this is a bug or a case " *
            "with no limited solution — either way a half-switched answer is not one."))
    end

    _ac_assert_no_backoff(net, limited, at_max, Qheld, Vm, sch.V_set)

    Pload = [sch.Pl[v] * _zip_scale(Vm[v], sch.a_i[v], sch.a_p[v]) for v in 1:n]
    Qload = [sch.Ql[v] * _zip_scale(Vm[v], sch.a_i[v], sch.a_p[v]) for v in 1:n]
    Pgen  = Pnet .+ Pload

    # Branch flows at BOTH ends, from the series admittance and the solved voltages
    # — not from `Y`, so that the losses identity in the tests compares two things
    # that were computed from different data (`m6-tasks.md` step 3).
    nb = length(net.branches)
    flow     = Vector{Float64}(undef, nb)
    flow_rev = Vector{Float64}(undef, nb)
    qflow     = Vector{Float64}(undef, nb)
    qflow_rev = Vector{Float64}(undef, nb)
    loss      = Vector{Float64}(undef, nb)
    mva       = Vector{Float64}(undef, nb)
    Vc = ComplexF64[Vm[v] * cis(θ[v]) for v in 1:n]
    for (e, br) in pairs(net.branches)
        f, t = net.bus_index[br.from], net.bus_index[br.to]
        y = inv(complex(br.R, br.X))
        I = y * (Vc[f] - Vc[t])
        Sf = Vc[f] * conj(I)
        St = Vc[t] * conj(-I)
        flow[e], qflow[e] = real(Sf), imag(Sf)
        flow_rev[e], qflow_rev[e] = real(St), imag(St)
        loss[e] = real(Sf) + real(St)
        # The rating is a property of the conductor, so it is the LARGER end that
        # has to fit — on a lossy branch the two differ, and taking the sending end
        # alone would pass a line whose receiving end is over its limit.
        mva[e] = max(abs(Sf), abs(St))
    end

    what = "ac_powerflow"
    _check_voltage_band(net, Vm, what)
    _check_branch_ratings(net, mva, what)
    _check_residual(res, what)

    held = Set(limited)
    roles = [v == v_slack ? :slack :
             (sch.has_machine[v] && !(v in held)) ? :generator : :load for v in 1:n]

    return ACPowerFlow(net.slack,
                       Symbol[b.id for b in net.buses], Vm, θ,
                       Pgen, Qgen, Pload, Qload,
                       roles, Symbol[net.buses[v].id for v in limited],
                       Symbol[b.id for b in net.branches],
                       Symbol[b.from for b in net.branches],
                       Symbol[b.to for b in net.branches],
                       flow, flow_rev, qflow, qflow_rev, loss, res)
end

# The vertex of a bus in a solved answer, or a throw naming it — a missing bus is a
# typo, the way `load_at`, `bus_role` and `bus_angle(::DCPowerFlow, …)` treat one.
function _ac_vertex(sol::ACPowerFlow, bus::Symbol)
    v = findfirst(==(bus), sol.buses)
    v === nothing && throw(ArgumentError(
        "ACPowerFlow: no bus :$bus (has $(join(sol.buses, ", ")))."))
    return v
end

"""
    bus_voltage(sol::ACPowerFlow, bus::Symbol) -> Float64

The solved voltage **magnitude** at `bus`, pu. At the slack and at any generator
bus still holding its setpoint this is exactly `V_set`; everywhere else it is
solved.
"""
bus_voltage(sol::ACPowerFlow, bus::Symbol) = sol.Vm[_ac_vertex(sol, bus)]

"""
    bus_angle(sol::ACPowerFlow, bus::Symbol) -> Float64

The solved voltage angle at `bus`, in radians, relative to the slack (which is
exactly `0.0`) — the same generic [`DCPowerFlow`](@ref) answers to.
"""
bus_angle(sol::ACPowerFlow, bus::Symbol) = sol.θ[_ac_vertex(sol, bus)]

"""
    bus_generation(sol::ACPowerFlow, bus::Symbol) -> (; P, Q)

The machines' active and reactive output at `bus`, pu on the model's `S_base`.

At a load bus both are zero. At a generator bus `P` is the schedule and `Q` is
solved; at the slack **both** are solved, and its `P` is where the network's losses
end up.
"""
function bus_generation(sol::ACPowerFlow, bus::Symbol)
    v = _ac_vertex(sol, bus)
    return (; P = sol.Pgen[v], Q = sol.Qgen[v])
end

# The branch joining two buses, and whether the caller named it in its own
# direction. Shared by the three reads below so the "argument order decides the
# sign" contract is implemented once.
function _ac_branch(sol::ACPowerFlow, from::Symbol, to::Symbol)
    for e in eachindex(sol.branches)
        if sol.from[e] === from && sol.to[e] === to
            return e, true
        elseif sol.from[e] === to && sol.to[e] === from
            return e, false
        end
    end
    throw(ArgumentError("ACPowerFlow: no branch between :$from and :$to."))
end

"""
    branch_power(sol::ACPowerFlow, from::Symbol, to::Symbol) -> Float64

Active power **leaving** bus `from` into the branch joining it to `to`, pu.

The same generic the two dynamic tiers and `DCPowerFlow` answer to, with one
difference that matters: the branch here can be lossy, so
`branch_power(sol, :A, :B) != -branch_power(sol, :B, :A)`. The two differ by
exactly the branch's loss, which is what [`branch_loss`](@ref) returns.
"""
function branch_power(sol::ACPowerFlow, from::Symbol, to::Symbol)
    e, fwd = _ac_branch(sol, from, to)
    return fwd ? sol.flow[e] : sol.flow_rev[e]
end

"""
    branch_power(sol::ACPowerFlow) -> Vector{Float64}

Every branch's active power in **model branch order**, leaving `from`, pu.
"""
branch_power(sol::ACPowerFlow) = copy(sol.flow)

"""
    branch_reactive(sol::ACPowerFlow, from::Symbol, to::Symbol) -> Float64
    branch_reactive(sol::ACPowerFlow) -> Vector{Float64}

Reactive power leaving `from` into the branch, pu — `branch_power`'s sibling, with
the same sign contract. A series reactance **absorbs** reactive power (`I^2 X`), so
both ends of a loaded branch normally send Q into it.
"""
function branch_reactive(sol::ACPowerFlow, from::Symbol, to::Symbol)
    e, fwd = _ac_branch(sol, from, to)
    return fwd ? sol.qflow[e] : sol.qflow_rev[e]
end

branch_reactive(sol::ACPowerFlow) = copy(sol.qflow)

"""
    branch_loss(sol::ACPowerFlow, from::Symbol, to::Symbol) -> Float64
    branch_loss(sol::ACPowerFlow) -> Vector{Float64}

The branch's active loss, pu — `I^2 R`, and therefore **orientation-free**: unlike
`branch_power` the argument order does not change the sign, because a loss has no
direction. Zero on a lossless branch, which is every branch in every pre-M6
fixture.
"""
function branch_loss(sol::ACPowerFlow, from::Symbol, to::Symbol)
    e, _ = _ac_branch(sol, from, to)
    return sol.loss[e]
end

branch_loss(sol::ACPowerFlow) = copy(sol.loss)
