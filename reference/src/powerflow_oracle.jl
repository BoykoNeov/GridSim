# The `NetworkModel → PowerSystems` builder, the `PowerFlows` solve, and the band
# that judges the gap. M6 step 4, oracle B.
#
# Same claim as `oracle.jl`, one milestone later and for a different physics: a
# `PowerSystems.System` for one of our models is DERIVED, and the derivation is
# short enough to read. Everything long in here is a precondition, or a convention
# ANSWERED FROM THEIR SOURCE rather than assumed.
#
# ============================================================================
# WHAT THIS ORACLE IS FOR, AND WHAT ORACLE A COULD NOT REACH
# ============================================================================
#
# Oracle A (`m6-tasks.md` step 4) feeds a solved power flow into `DetailedEngine`
# and checks the run does nothing. It is sharp, it needs no dependency, and it has
# two structural blind spots that no amount of care removes:
#
#   1. **A lossy branch.** Our dynamic tiers refuse `R ≠ 0` by name
#      (`_assert_lossless_branches`), so with `R = 0` everywhere our loss channel
#      is identically zero and `flow + flow_rev` vanishes. The resistive half of
#      `ac_powerflow` — the only thing `Branch.R` was added for — has no internal
#      check at all. Only an outside solve on a lossy case can say it is right.
#   2. **A bus wrongly switched to a reactive limit.** A bus held at a `Q` nobody
#      scheduled is still a perfectly good fixpoint, so the flat run stays flat
#      (D13). Only an external solve on the same case can say the WRONG bus was
#      limited.
#
# Those two are why this file exists. Everything else it checks is a bonus.
#
# ============================================================================
# THE CASE IS COMPILED FROM `NetworkModel`, NEVER TYPED BESIDE IT
# ============================================================================
#
# `oracle.jl`'s header argues this at length and the argument is unchanged: a
# hand-written PowerSystems case next to `three_machine_ring()` would be exactly
# the forked parallel data SPEC §3.2 forbids, and it would drift silently.
#
# **But the bound is NOT the same bound as `oracle.jl`'s, and the difference is
# deliberate.** The transient oracle reads `machine_arrays` / `branch_arrays` /
# `_coupling`, so both sides are handed the same per-unit conversion and the
# comparison is blind to a bug in it. This builder reads the **raw `Machine`,
# `Branch` and `Load` structs** and does its own conversion — in the case of a
# machine's power, by handing PowerSystems the number on the machine's OWN base
# and letting PowerSystems rebase it. So:
#
#   | quantity            | our path                | their path                  |
#   |---------------------|-------------------------|-----------------------------|
#   | machine P           | `machine_arrays.Pm`     | `P0/S_rated` × their rebase |
#   | load P, Q           | `load_arrays.P`, `.Q`   | `P0/S_base` written here    |
#   | ZIP shares          | `load_arrays.a_*`       | read off `Load` here        |
#   | `V_set`, `Q_min/max`| read off `Machine`      | read off `Machine` here     |
#   | branch `X`, `R`     | `branch_arrays`         | read off `Branch` here      |
#
# Nothing in the right column goes through a view the left column also reads, so a
# bug in `machine_arrays` or `load_arrays` moves ONE side and the comparison goes
# red. The `S_rated ≠ S_base` fixture is what makes the first row's independence
# testable at all — with every machine rated at the system base, the rebase is the
# identity and a wrong one is invisible.
#
# Branch `X` and `R` are system per-unit on BOTH sides by construction (measured:
# a `Line`'s device base IS the system base, `get_x` returns 0.1 under
# `DEVICE_BASE` and under `SYSTEM_BASE` alike), so that row is a genuinely shared
# number and no oracle can check it. Said here rather than left implied.
#
# ============================================================================
# CONVENTIONS, ANSWERED FROM THEIR SOURCE BEFORE THE FIRST COMPARISON RAN
# ============================================================================
#
# M4 D13/D14's lesson, scheduled rather than discovered. Every line below is a
# measurement taken on 2026-09-08 against PowerSystems 5.12.3 / PowerFlows 0.25.2,
# with the probe scripts kept in `W:\temp\claude\gridsim-m6-oracleb\`.
#
# **Per-unit bases.** A `System`'s default unit setting is `SYSTEM_BASE`. But a
# component CONSTRUCTOR takes its arguments in **DEVICE BASE regardless of the
# system setting** — a `ThermalStandard` built with `active_power = 0.4` and
# `base_power = 250.0` on a 100 MVA system reads back as `0.4` under `DEVICE_BASE`,
# `1.0` under `SYSTEM_BASE` and `100.0` under `NATURAL_UNITS`. That is the whole
# reason the machine row above can be independent: we write `P0/S_rated`, they
# multiply by `S_rated/S_base`, and the two conversions never meet.
#
# **Result units.** `solve_power_flow` exports voltages in per-unit and **powers in
# MW/MVAr**, not per-unit — it says so in a log line and the numbers confirm it.
# Every power read back here is divided by `net.S_base` at the boundary.
#
# **Angle reference.** The REF bus's `angle` field is honoured, not pinned: set it
# to 0.3 and the solved `θ₁` comes back 0.3 with every other angle shifted with it.
# Our slack angle is zero by construction (the deleted row and column of `B`), so
# this builder pins `angle = 0.0` on every bus and a test holds it there.
#
# **Load sign.** A `StandardLoad`'s powers are positive for consumption, as ours
# are. Its ZIP law was measured on all four share combinations and is exactly ours:
# `a_z·V² + a_i·V + a_p`, agreeing to six decimals on a case whose voltage lands at
# 0.90 pu. See `_pf_load` for what that buys and what it does not.
#
# **Shunts.** Our `Branch` has no line charging (its docstring says so), so `b` is
# written as zero at both ends and no shunt is booked anywhere.
#
# **Their DC solve carries no losses and uses `1/x`.** Measured directly: `θ₂` on a
# two-bus case is exactly `−0.05` at `R = 0` and at `R = 0.05`, i.e. `P·x`, and
# `P_from_to` equals the injection with no loss term. Ours is the same formula, so
# the DC channel compares like against like. Their DC path does go through
# `PowerNetworkMatrices.solve_w_refinement` — an ITERATIVE refinement with its own
# tolerance — which is what produced a 4.8e-9 wobble in `θ₂` at `R = 0.02` where
# the exact answer is unchanged. That is why the DC channel gets its own band and
# not the AC one's.
#
# **Reactive limits are OFF by default.** `ACPowerFlow()` carries
# `check_reactive_power_limits = false`, and with it off a generator held 126.7
# MVAr against a 25 MVAr ceiling without complaint. It is passed explicitly here.
# With it on, their bus bound at exactly 25.0 MVAr and its magnitude fell to
# 0.9435 — bind-and-hold, which is what ours does. **Whether they BACK OFF a bus
# that should be released was not measured**, and ours refuses back-off cases by
# name (D12), so the comparison domain is "cases our side accepts" and back-off
# stays `un-oracled`. Stated rather than implied.
#
# **Their Newton tolerance defaults to 1e-9** (`DEFAULT_NR_TOL`), which is looser
# than our `abstol = 1e-12`. It is set explicitly through `solver_settings`.
#
# ============================================================================
# THE ONE COLUMN THAT IS WRONG, AND WHY THIS FILE REFUSES TO READ IT
# ============================================================================
#
# Their per-bus `P_load` / `Q_load` / `P_net` columns DO NOT BOOK a
# constant-impedance or constant-current load. On a fixture drawing 200 MW at
# `a_z = 1` the solve is right — `Vm₂ = 0.9104` and the line delivers 165.78 MW,
# which is `200 × 0.9104²` to six decimals — but `bus_results.P_load` comes back
# `0.0` and `P_net` comes back `0.0`, which is not merely absent, it is wrong.
#
# The channels that ARE booked (`Vm`, `θ`, both ends of every branch flow, and the
# slack's `P_gen`/`Q_gen`) carry the ZIP answer correctly, so the full ZIP is
# oracled through them. `_pf_bus_column` refuses the three bad columns BY NAME
# rather than a comment asking the next reader not to touch them — oracle A found
# three pieces of dead code in one batch, every one of them a comment or a guard
# written without checking what actually runs on that path.

# `Q_min`/`Q_max` of `Inf` have no PowerSystems spelling — a limit of `Inf` inside
# their `reactive_power_limits` would propagate into arithmetic. A wide finite
# number says the same thing, on the `_AVR_VR_LIM` precedent in `oracle.jl`, and
# `to_powersystems` ASSERTS it cannot bind on the case it was handed rather than
# hoping. Per-unit on the system base.
const _PF_Q_WIDE = 1.0e3
# Likewise for a machine's real-power range, which PowerSystems validates against
# `active_power` and warns about. Nothing in a power flow reads it: the slack's
# output is whatever the network needs and every other machine's is scheduled.
const _PF_P_WIDE = 1.0e3
# Their Newton tolerance, set explicitly. Their default is 1e-9; ours is 1e-12.
const _PF_TOL = 1.0e-12
# The bus columns that are wrong for a non-constant-power load — see the header.
const _PF_BAD_COLUMNS = (:P_load, :Q_load, :P_net, :Q_net)

"""
    to_powersystems(net::NetworkModel) -> PowerSystems.System

Compile `net` into a `PowerSystems.System` carrying the same case.

The mapping, one line each:

  - a `Bus` becomes an `ACBus` numbered by its **vertex index**, named by its id,
    typed from [`bus_roles`](@ref) (`:slack → REF`, `:generator → PV`,
    `:load → PQ`) and pinned to `angle = 0.0`;
  - a `Branch` becomes a `Line` on an `Arc` in the branch's **declared**
    direction, with `r`/`x` straight off the struct (both are already system
    per-unit on both sides) and no charging;
  - a `Machine` becomes a `ThermalStandard` on **its own base** — `active_power =
    P0/S_rated` with `base_power = S_rated`, so PowerSystems does the rebase and
    our `machine_arrays` is not in the path;
  - a `Load` becomes ONE `StandardLoad` whose three field pairs carry the ZIP
    shares. One component type for every load: a `StandardLoad` with all its
    weight in `constant_*` was measured to reproduce a `PowerLoad` exactly, so
    there is no branch here and no second path to keep in step.

## What it refuses

  - a slack bus with no machine on it, exactly as [`ac_powerflow`](@ref) does and
    for the same reason: PowerSystems needs a source at the REF bus;
  - a machine whose reactive limits are wider than `_PF_Q_WIDE` can stand in for.
"""
function to_powersystems(net::GridSim.NetworkModel)
    S_base = net.S_base
    roles = GridSim.bus_roles(net)
    v_slack = net.bus_index[net.slack]
    isempty(net.machines_at_bus[v_slack]) && throw(ArgumentError(
        "to_powersystems: the declared slack bus :$(net.slack) carries no machine. " *
        "NetworkModel accepts that and ac_powerflow refuses it; so does this, for " *
        "the same reason — a REF bus with no source is not a case PowerSystems can " *
        "solve either."))

    sys = PSY.System(S_base; frequency = net.f0)

    # Buses. The magnitude a generator bus starts at is its own setpoint, which is
    # also the value their solve HOLDS there; a load bus starts flat.
    acbuses = Vector{PSY.ACBus}(undef, length(net.buses))
    for (v, b) in pairs(net.buses)
        role = roles[v]
        Vm = role === :load ? 1.0 : _pf_bus_vset(net, v)
        acbuses[v] = PSY.ACBus(;
            number = v,
            name = String(b.id),
            available = true,
            bustype = role === :slack ? PSY.ACBusTypes.REF :
                      role === :generator ? PSY.ACBusTypes.PV : PSY.ACBusTypes.PQ,
            # PINNED, not copied from anywhere: their REF angle is honoured, ours
            # is zero by construction. A test holds this at 0.0.
            angle = 0.0,
            magnitude = Vm,
            # Wide on purpose. Whether a solved magnitude is acceptable is
            # `ac_powerflow`'s `_check_voltage_band` to judge, not a validation
            # warning here — and a case deliberately pushed out of band is one of
            # the things this oracle is for.
            voltage_limits = (min = 0.5, max = 1.5),
            base_voltage = b.V_base)
    end
    PSY.add_components!(sys, acbuses)

    for br in net.branches
        f = net.bus_index[br.from]
        t = net.bus_index[br.to]
        PSY.add_component!(sys, PSY.Line(;
            name = String(br.id),
            available = true,
            active_power_flow = 0.0,
            reactive_power_flow = 0.0,
            # The arc runs in the branch's DECLARED direction, so their
            # `P_from_to` is our `flow` and no sign has to be argued about.
            arc = PSY.Arc(; from = acbuses[f], to = acbuses[t]),
            r = br.R,
            x = br.X,
            b = (from = 0.0, to = 0.0),          # no line charging in our model
            rating = br.rating / S_base,
            angle_limits = (min = -1.5, max = 1.5)))
    end

    for m in net.machines
        w = S_base / m.S_rated                   # system pu -> the machine's own base
        qmin = isfinite(m.Q_min) ? m.Q_min : -_PF_Q_WIDE
        qmax = isfinite(m.Q_max) ? m.Q_max : _PF_Q_WIDE
        (abs(qmin) <= _PF_Q_WIDE && abs(qmax) <= _PF_Q_WIDE) || throw(ArgumentError(
            "to_powersystems: machine $(m.id) has reactive limits ($(m.Q_min), " *
            "$(m.Q_max)) pu that a stand-in of ±$(_PF_Q_WIDE) pu cannot represent. " *
            "The stand-in exists because `Inf` has no PowerSystems spelling; a real " *
            "limit larger than it would be silently tightened."))
        PSY.add_component!(sys, PSY.ThermalStandard(;
            name = String(m.id),
            available = true,
            status = true,
            bus = acbuses[net.bus_index[m.bus]],
            # ON THE MACHINE'S OWN BASE. This is the independent conversion — see
            # the table in the header.
            active_power = m.P0 / m.S_rated,
            reactive_power = 0.0,
            rating = _PF_P_WIDE,
            active_power_limits = (min = -_PF_P_WIDE, max = _PF_P_WIDE),
            reactive_power_limits = (min = qmin * w, max = qmax * w),
            ramp_limits = nothing,
            operation_cost = PSY.ThermalGenerationCost(nothing),
            base_power = m.S_rated,
            time_limits = nothing,
            prime_mover_type = PSY.PrimeMovers.ST,
            fuel = PSY.ThermalFuels.COAL))
    end

    for l in net.loads
        PSY.add_component!(sys, _pf_load(net, l, acbuses))
    end
    return sys
end

# The terminal setpoint a bus holds, and the refusal that keeps two machines from
# asking for two of them. Deliberately the SAME rule `_ac_schedule` applies, and
# deliberately not a call into it: reading their answer out of the function under
# test is how step 3 shipped two checks that could not fail (`m6-tasks.md` step 3).
function _pf_bus_vset(net::GridSim.NetworkModel, v::Integer)
    idx = net.machines_at_bus[v]
    Vset = net.machines[first(idx)].V_set
    for k in idx
        net.machines[k].V_set == Vset || throw(ArgumentError(
            "to_powersystems: bus $(net.buses[v].id) carries machines with " *
            "different V_set ($Vset and $(net.machines[k].V_set) pu). A bus has " *
            "ONE terminal voltage; ac_powerflow refuses this too."))
    end
    return Vset
end

# One `StandardLoad` carrying the ZIP split.
#
# THEIR ZIP LAW IS OURS, MEASURED RATHER THAN ASSUMED. On a two-bus case loaded
# hard enough to pull the voltage to 0.90 pu, the delivered power matched
# `P0·(a_z·V² + a_i·V + a_p)` to six decimals at (1,0,0), (0,1,0), (0,0,1) and
# (0.5,0.3,0.2). The last of those is why a mixed-share fixture ships: with
# `a_i = 0` a constant-current term that had been dropped entirely would be
# invisible.
#
# `P0/S_base` is written HERE and not read from `load_arrays`, which computes the
# same quotient. That is the point — a bug in `load_arrays` moves our side alone.
function _pf_load(net::GridSim.NetworkModel, l::GridSim.Load,
                  acbuses::Vector{PSY.ACBus})
    S_base = net.S_base
    P = l.P0 / S_base
    Q = l.Q0 / S_base
    big = _PF_P_WIDE
    return PSY.StandardLoad(;
        name = String(l.id),
        available = true,
        bus = acbuses[net.bus_index[l.bus]],
        base_power = S_base,
        constant_active_power    = l.a_p * P,
        constant_reactive_power  = l.a_p * Q,
        impedance_active_power   = l.a_z * P,
        impedance_reactive_power = l.a_z * Q,
        current_active_power     = l.a_i * P,
        current_reactive_power   = l.a_i * Q,
        max_constant_active_power    = big, max_constant_reactive_power  = big,
        max_impedance_active_power   = big, max_impedance_reactive_power = big,
        max_current_active_power     = big, max_current_reactive_power   = big)
end

"""
    _pf_bus_column(df, name) -> Vector{Float64}

One column of their `bus_results`, with the four unreadable ones refused BY NAME.

`P_load`, `Q_load`, `P_net` and `Q_net` do not book a constant-impedance or
constant-current load — measured, on a case where the solve itself is right (see
the header). This is a guard and not a comment because a comment is what the next
reader ignores; oracle A deleted three pieces of dead code in one batch that were
each a note written without checking the path it described.
"""
function _pf_bus_column(df, name::Symbol)
    name in _PF_BAD_COLUMNS && throw(ArgumentError(
        "oracle B: bus_results.$name is not readable. PowerFlows does not book a " *
        "constant-impedance or constant-current load into the per-bus load " *
        "columns — on an `a_z = 1` case drawing 200 MW it returns P_load = 0.0 and " *
        "P_net = 0.0 while solving the case correctly. Read the flow columns and " *
        "the slack's P_gen/Q_gen instead; those carry the ZIP answer."))
    return Vector{Float64}(df[!, name])
end

"""
    oracle_powerflow(net::NetworkModel; tol = 1e-12, check_limits = true)

Solve `net`'s power flow with `PowerFlows.jl` and read the answer back **in our
terms**: our bus order, our branch order, per-unit on `net.S_base`.

Returns a NamedTuple with `Vm`, `θ`, `Pgen`, `Qgen` (per bus) and `flow`,
`flow_rev`, `qflow`, `qflow_rev` (per branch, at the branch's declared `from` end
and its `to` end), named to match `GridSim.ACPowerFlow`'s own fields EXACTLY, so one
`channel` function reads the same on both sides — `powerflow_band` applies the
same closure to our result and to theirs, and a field named `P_gen` here against
`Pgen` there would make every generation band an error rather than a comparison.

`check_limits` is passed explicitly because **their default is `false`** and a
default-off limit check silently returns the unlimited answer.
"""
function oracle_powerflow(net::GridSim.NetworkModel; tol::Real = _PF_TOL,
                          check_limits::Bool = true)
    sys = to_powersystems(net)
    pf = PF.ACPowerFlow(; check_reactive_power_limits = check_limits,
                        solver_settings = Dict{Symbol,Any}(:tol => Float64(tol)))
    res = PF.solve_power_flow(pf, sys)
    return _pf_read(net, res["bus_results"], res["flow_results"])
end

"""
    oracle_dc_powerflow(net::NetworkModel)

Their linear (DC) solve, read back in our terms. Same shape as
[`oracle_powerflow`](@ref) minus the reactive channels, which a DC solve does not
have.

Their DC result is keyed by time step (`Dict{String,Dict{String,DataFrame}}`), and
this repo's cases are single-period, so the one key is `"1"` and anything else is
refused rather than guessed at.
"""
function oracle_dc_powerflow(net::GridSim.NetworkModel)
    sys = to_powersystems(net)
    res = PF.solve_power_flow(PF.DCPowerFlow(), sys)
    ks = collect(keys(res))
    ks == ["1"] || throw(ErrorException(
        "oracle_dc_powerflow: their DC result carries time-step keys $ks; this " *
        "repo's cases are single-period and the reader indexes \"1\" deliberately " *
        "rather than taking whatever `first` returns."))
    return _pf_read(net, res["1"]["bus_results"], res["1"]["flow_results"])
end

# Their two DataFrames -> our ordering and our per-unit. The ONLY place their
# MW/MVAr export is divided by `S_base`, and the only place their row order is
# turned into ours.
function _pf_read(net::GridSim.NetworkModel, bus_df, flow_df)
    S_base = net.S_base
    n = length(net.buses)
    nb = length(net.branches)
    number = Vector{Int}(bus_df[!, :bus_number])
    row = Dict(number[i] => i for i in eachindex(number))
    length(row) == n || throw(ErrorException(
        "oracle B: their bus_results has $(length(row)) distinct buses where the " *
        "model has $n."))
    Vm = _pf_bus_column(bus_df, :Vm)
    θ  = _pf_bus_column(bus_df, :θ)
    Pg = _pf_bus_column(bus_df, :P_gen)
    Qg = _pf_bus_column(bus_df, :Q_gen)

    ord = [row[v] for v in 1:n]                  # their row for our vertex v
    fb = Vector{Int}(flow_df[!, :bus_from])
    tb = Vector{Int}(flow_df[!, :bus_to])
    frow = Dict((fb[i], tb[i]) => i for i in eachindex(fb))
    flow      = Vector{Float64}(undef, nb)
    flow_rev  = Vector{Float64}(undef, nb)
    qflow     = Vector{Float64}(undef, nb)
    qflow_rev = Vector{Float64}(undef, nb)
    P_ft = Vector{Float64}(flow_df[!, :P_from_to]); P_tf = Vector{Float64}(flow_df[!, :P_to_from])
    Q_ft = Vector{Float64}(flow_df[!, :Q_from_to]); Q_tf = Vector{Float64}(flow_df[!, :Q_to_from])
    for (e, br) in pairs(net.branches)
        key = (net.bus_index[br.from], net.bus_index[br.to])
        i = get(frow, key, 0)
        i == 0 && throw(ErrorException(
            "oracle B: no flow row for branch $(br.id) ($(br.from) -> $(br.to)). " *
            "The arc is built in the branch's declared direction, so their " *
            "bus_from/bus_to should be ours; a miss here is a mapping bug, not a " *
            "reason to search the reversed pair."))
        flow[e]      = P_ft[i] / S_base
        flow_rev[e]  = P_tf[i] / S_base
        qflow[e]     = Q_ft[i] / S_base
        qflow_rev[e] = Q_tf[i] / S_base
    end
    return (; Vm  = Vm[ord], θ = θ[ord],
              Pgen = Pg[ord] ./ S_base, Qgen = Qg[ord] ./ S_base,
              flow, flow_rev, qflow, qflow_rev)
end


# ============================================================================
# THE ACCURACY CEILING THE ORACLE ITSELF HAS, AND WHAT THE BAND CAN THEREFORE BE
# ============================================================================
#
# **`PowerFlows` stores its admittance matrix in SINGLE precision.**
# `PowerNetworkMatrices/src/definitions.jl` line 1 reads
# `const YBUS_ELTYPE = ComplexF32` — a compile-time constant with no setting
# behind it. One `grep` confirms it; the path is here so the next reader does not
# have to re-derive it from a residual mismatch, which is how this was found.
#
# **It is the admittance and nothing else.** `PowerFlows/src/PowerFlowData.jl`
# declares every injection, withdrawal, magnitude and angle matrix as
# `Matrix{Float64}` — checked, because "their data is single precision" and "their
# ADMITTANCE is single precision" are different claims and only the second is true.
#
# What it costs, measured on the three-bus radial fixture: their Newton reports a
# final ∞-norm residual of **4.4e-16** and it is telling the truth — about the
# Float32-rounded network. Evaluated in double precision against an admittance
# matrix built by hand from the branch list, the same answer leaves a mismatch of
# **3.8e-8 pu**, where ours on the same independent check leaves **4.4e-16**. Their
# Y differs from the exact one by up to 6.4e-7 in absolute terms, which is
# single-precision resolution on an entry of 16.67. None of it is convergence:
# their answer stops moving once `tol` passes 1e-10 and never improves again.
#
# **THIS IS M4's D7 ARRIVING A SECOND TIME BY A DIFFERENT MECHANISM.** There,
# PowerDynamics was measured at 3.5–18x further from the truth than us, through
# integration error. Here PowerFlows is roughly SEVEN ORDERS further, through a
# fixed-width admittance. Both say the same thing and it is worth saying twice: the
# oracle is a **floor, not a ceiling**.
#
# **WHY THE BAND IS A PRECISION STATEMENT AND NOT A SENSITIVITY CALCULATION.**
# The obvious move is to predict their error: perturb our branch admittances onto
# the single-precision grid, re-solve with our own code, and use the difference.
# Two versions of that were built and measured, and **neither is a bound**:
#
#   * one twin with every branch rounded at once under-predicts on meshed cases
#     (it realises ONE rounding pattern where their assembly rounds each entry
#     independently);
#   * the first-order sum over single-branch perturbations covers three fixtures
#     and is **saturated at 2.94x on the off-base one**.
#
# The reason no factor rescues either is structural, and it is worth stating
# because it decides the shape of everything below. Our model has no shunts, so
# `Y_vv = −Σ_u Y_vu` holds by construction. **Their rounded diagonal breaks that
# identity**: rounding the assembled sum leaves an implicit shunt at every bus,
# which is a perturbation our model *cannot express at all*. It is not a term with
# an unknown coefficient waiting for a factor — it is a different kind of object,
# and multiplying a branch-sensitivity sum by 3 or by 4 to cover it would be
# fitting a constant to the very gap it is meant to judge. M4 refused that move for
# the `tolerance_band` ratio that ran 5.2 → 15.3 and did not settle; the same
# refusal applies here.
#
# So the agreement band says only what can be said without a model of their error:
# **their admittance is stored to single-precision RELATIVE accuracy, so no channel
# derived from it can agree with a double-precision solve more closely than that
# relative accuracy times the channel's own magnitude.** One sentence, no factor,
# stated before any gap was seen — and the measured ratios go in `m6-tasks.md`
# rather than into a threshold, so a fixture that lands above 1.0 reads as a
# finding rather than as a broken band.
#
# **The sharp check is elsewhere, and it needs no band at all**: evaluate each
# side's answer in an independently built double-precision admittance and report
# the mismatch. That is a fact about each side alone. See the suite's
# "each side's answer in an independent admittance" testset — it is what carries
# this round, and the banded comparisons are secondary to it.

"""
    float32_admittance_twin(net::NetworkModel) -> NetworkModel

`net` with every branch impedance replaced by the one whose **admittance** lands
on the single-precision grid — the grid `PowerFlows` stores its `Ybus` on.

**This is how the mechanism was identified and confirmed, and it is deliberately
NOT how the band is derived.** Solving this twin with our own solver moves the
answer the same way and by a comparable amount as theirs moves — which is what
turned "their answer is mysteriously 4e-9 off" into "their admittance is
`ComplexF32`". As a *predictor* it is not a bound: it realises one rounding
pattern where their assembly rounds each entry independently, and it cannot
represent the implicit shunt their rounded diagonal leaves behind. The header
above says why no factor fixes that, and [`powerflow_band`](@ref) does not use
this function.

`R` is clamped at zero and only where rounding pushed a zero resistance slightly
negative: `Branch` requires `R >= 0`, and a lossless branch must stay lossless
rather than fail construction. A resistance that comes back negative by more than
rounding could be is refused, so the clamp can never quietly hide one.
"""
function float32_admittance_twin(net::GridSim.NetworkModel)
    branches = map(net.branches) do br
        z = 1 / ComplexF32(1 / complex(br.R, br.X))
        R = Float64(real(z))
        if R < 0
            abs(R) < 1.0e-9 || throw(ErrorException(
                "float32_admittance_twin: branch $(br.id) came back with R = $R after " *
                "the single-precision round trip. Rounding a non-negative resistance " *
                "can only push it negative by the width of the grid; this is far " *
                "larger, so it is not a rounding artefact to clamp away."))
            R = 0.0
        end
        GridSim.Branch(br.id, br.from, br.to, Float64(imag(z)), br.rating; R = R)
    end
    return GridSim.NetworkModel(net.S_base, net.f0, net.buses, branches,
                                net.machines, net.loads; slack = net.slack)
end

"""
    powerflow_band(net; channel, abstol = 1e-12, tol = 1e-12,
                   check_limits = true, dc = false)

The agreement band for one channel of the AC (or DC) comparison on `net`, and the
three terms it is made of.

Returns `(; band, ours, theirs, precision)`:

  - `ours`      — our solver's own convergence, `|ours(abstol) - ours(abstol_fine)|`;
  - `theirs`    — their solver's own convergence, `|theirs(tol) - theirs(1000*tol)|`;
  - `precision` — `eps(Float32) * scale`: their admittance is stored to
    single-precision relative accuracy, so nothing derived from it can agree with
    a double-precision solve more closely than that relative accuracy times the
    size of the quantities it was computed from. The header says why this is a
    *statement about their storage* rather than a prediction of their error, and
    why every attempt at the latter was refused.

**`scale` defaults to the channel's own magnitude, and for a BRANCH FLOW that
default is wrong.** A solved unknown (`Vm`, `θ`) is its own scale. A branch flow is
not: it is a difference of products of admittance entries and voltages, so its
absolute error is set by the size of those intermediate terms — `|y|·|V|²`, see
[`flow_scale`](@ref) — and not by the size of a result they may largely cancel
into. Measured rather than assumed: with the channel's own magnitude as the scale,
`qflow` lands at **3.17x, 3.22x and 6.12x** the band on the meshed, lossy and
off-base fixtures, and `flow` at **0.94x** on the off-base one — saturated. The
first of those is what showed the scale was wrong; both sets of ratios are in
`m6-tasks.md` so the revision is visible rather than absorbed.

`band = ours + theirs + precision`, with **no factor**. Each term is a property of
one side alone and none looks at the cross gap, so "state the band before you see
the gap" is a property of the arithmetic rather than a discipline anyone keeps.

`channel` picks the quantity: `s -> s.Vm`, `s -> s.θ`, `s -> s.flow`. **One band
per channel** — M4 measured what an aggregate band costs on a per-machine read.

**`Pgen` and `Qgen` are NOT channels for this.** At a generator bus our `Pgen` is
the schedule exactly — not a solved quantity, so a convergence term for it is
meaningless — and at the slack theirs passes through `post_processing.jl`'s
redistribution loop, whose own `ISAPPROX_ZERO_TOLERANCE` is `1e-6` and has nothing
to do with admittance precision. Generation is checked by identity instead (the
schedule on our side, the loss pickup at the slack), which is what those numbers
actually assert.

**`abstol_fine` is a keyword because the 1000x-tighter probe is not always
attainable, and that is a measurement rather than a caution.** On the
reactive-limit fixture our solve reaches a residual of 1.804e-15 and can go no
further — the problem's own floor — so asking for `1e-15` makes Newton run its 200
iterations and report `Stalled`. The band refuses that by name and says to pass an
attainable `abstol_fine`, rather than swallowing the stall or quietly falling back
to a tolerance nobody chose. A silent fallback would make the convergence term a
different quantity on different fixtures without anything in the output saying so.

`dc = true` bands the linear solve. It gets its own band for its own reason: their
DC path runs through `PowerNetworkMatrices.solve_w_refinement`, an iterative
refinement with a separate tolerance, which is a different mechanism from the
Ybus quantization even where it lands at a similar size.
"""
function powerflow_band(net::GridSim.NetworkModel; channel,
                        scale::Union{Real,Nothing} = nothing,
                        abstol::Real = 1.0e-12,
                        abstol_fine::Real = abstol / 1000,
                        tol::Real = _PF_TOL,
                        check_limits::Bool = true, dc::Bool = false)
    gap(x, y) = maximum(abs, channel(x) .- channel(y))
    if dc
        ours_c = GridSim.dc_powerflow(net)
        ours_f = ours_c                              # linear: one factorisation, no tolerance
        theirs_c = oracle_dc_powerflow(net)
        theirs_f = theirs_c                          # their DC takes no tolerance argument
    else
        ours_c = GridSim.ac_powerflow(net; abstol = abstol)
        ours_f = try
            GridSim.ac_powerflow(net; abstol = abstol_fine)
        catch err
            throw(ErrorException(
                "powerflow_band: the convergence probe at abstol = $abstol_fine did " *
                "not converge on this model, while the run at $abstol did (residual " *
                "$(ours_c.residual)). That is the problem's own residual floor, not " *
                "a bug — the reactive-limit fixture bottoms out at 1.8e-15 — so pass " *
                "an attainable `abstol_fine` rather than letting the band fall back " *
                "to a tolerance nobody chose. Original: $(sprint(showerror, err))"))
        end
        theirs_c = oracle_powerflow(net; tol = tol, check_limits = check_limits)
        theirs_f = oracle_powerflow(net; tol = tol * 1000, check_limits = check_limits)
    end
    ours_term  = gap(ours_c, ours_f)
    their_term = gap(theirs_c, theirs_f)
    sc = scale === nothing ? maximum(abs, channel(ours_c)) : Float64(scale)
    sc > 0 || throw(ArgumentError(
        "powerflow_band: scale must be > 0, got $sc."))
    prec_term = eps(Float32) * sc
    band = ours_term + their_term + prec_term
    band > 0 || throw(ArgumentError(
        "powerflow_band: the derived band is $band, because the channel is " *
        "identically zero and neither side moved. A band derived from nothing is " *
        "not a band; compare an identically-zero channel with `==`."))
    return (; band, ours = ours_term, theirs = their_term, precision = prec_term)
end

"""
    independent_mismatch(net::NetworkModel, sol) -> Float64

The largest power-flow mismatch `sol` leaves, evaluated against an admittance
matrix **built here, by hand, in double precision** — four lines of
`y = 1/(R + jX)` scattered into a dense matrix, reading `Branch` directly.

This is the round's sharp instrument and it needs no band, because it is a
statement about ONE answer rather than about the gap between two. It is also the
only check here that touches neither `_ac_admittance` nor `PowerNetworkMatrices`:
handing either side its own admittance back would be the mistake step 3 shipped
twice, where a check read its answer from the source it was checking.

Buses whose injection is not scheduled are skipped and named as such: the slack's
real and reactive injection and a generator bus's reactive injection are outputs
of the solve, so there is no scheduled value to difference against. Every other
equation the solve claims to have satisfied is evaluated.

The hand-built matrix is an *instrument*, not a second model of the network — it
computes no solution, it only evaluates one — so SPEC §3.2's ban on parallel
hand-maintained copies is not in play.
"""
function independent_mismatch(net::GridSim.NetworkModel, sol)
    n = length(net.buses)
    Y = zeros(ComplexF64, n, n)
    for br in net.branches
        f = net.bus_index[br.from]; t = net.bus_index[br.to]
        y = 1 / complex(br.R, br.X)
        Y[f, f] += y; Y[t, t] += y; Y[f, t] -= y; Y[t, f] -= y
    end
    V = sol.Vm .* cis.(sol.θ)
    S = V .* conj.(Y * V)

    # The scheduled injection at each bus, assembled from the model rather than
    # from `_ac_schedule`: machines' P0 minus the load's ZIP draw at the solved
    # magnitude, written out here in the expanded form on purpose (D11's `_zip_k`
    # grouping is the thing under test elsewhere, and a check must not evaluate the
    # model it is checking — `m6-tasks.md` step 3, F10).
    v_slack = net.bus_index[net.slack]
    worst = 0.0
    for v in 1:n
        v == v_slack && continue
        Pgen = sum((m.P0 for m in net.machines if net.bus_index[m.bus] == v); init = 0.0) /
               net.S_base
        k = net.load_at_bus[v]
        Vm = sol.Vm[v]
        Pl, Ql = 0.0, 0.0
        if k != 0
            l = net.loads[k]
            zip = l.a_z * Vm^2 + l.a_i * Vm + l.a_p
            Pl = l.P0 / net.S_base * zip
            Ql = l.Q0 / net.S_base * zip
        end
        worst = max(worst, abs(real(S[v]) - (Pgen - Pl)))
        # The reactive equation exists only where Q is scheduled, i.e. at a bus with
        # no machine holding a voltage.
        isempty(net.machines_at_bus[v]) && (worst = max(worst, abs(imag(S[v]) + Ql)))
    end
    return worst
end

"""
    flow_scale(net::NetworkModel, sol) -> Float64

The scale a **branch-flow** channel's precision term must be built from:
`max|y| · max|V|²` over the model's branches and the solved magnitudes.

A branch flow is `V·conj(y·(V_from − V_to))` — a difference of terms each of order
`|y|·|V|²`. Where those terms largely cancel, the flow that comes out is small
while the arithmetic that produced it was not, so the absolute error the
single-precision admittance leaves behind is set by the ingredients and not by the
answer. On the meshed fixture `max|y|` is 10 against a `qflow` of 0.41, and that
ratio of 24 is exactly the factor by which a band scaled on the result alone came
out too small.

This is a statement about cancellation, not a correction fitted to a run — but it
was written *after* the naive scale was measured to fail, and `m6-tasks.md` records
that order of events rather than presenting it as foresight.
"""
function flow_scale(net::GridSim.NetworkModel, sol)
    ymax = maximum(abs(1 / complex(br.R, br.X)) for br in net.branches)
    return ymax * maximum(sol.Vm)^2
end
