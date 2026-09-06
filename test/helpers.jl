# Shared fixtures and helpers for the whole suite.
#
# INCLUDED AT TOP LEVEL, and that is the point of this file rather than a style
# choice. `include` evaluates its file in the MODULE's global scope, never in the
# local scope of the block the call appears in - so a helper left inside the outer
# `@testset` of runtests.jl would be invisible to every milestone file included
# from there (docs/plans/README.md, Structure notes). These moved out of that
# scope verbatim in M5 step 0b; the comments are the ones they were written with.
#
# Groups are in the order the definitions appeared in the single file, and each
# names the file that uses it.

# --- every guard testset in the suite (all files) ---
# Returns the ArgumentError message a thunk throws, or a marker string. Used
# instead of a bare `@test_throws ArgumentError` so a guard test cannot pass
# because a *different* guard fired first — several of the invalid models
# below violate more than one rule, and "it threw" would not distinguish them.
argerr_msg(f) = try
    f()
    "NO ERROR THROWN"
catch e
    e isa ArgumentError ? e.msg : "NOT-ArgumentError: $(typeof(e))"
end

# --- the recorder sweep (test/m1_frequency.jl) ---
# Both entry points are swept, not just one. `record!` has a varargs form (arity
# pinned by the type parameter) and a vector form for engines whose channel count
# is only known at construction — and `SwingEngine` records *exclusively* through
# the vector one, so a sweep of the varargs path alone would leave the newer
# engine's actual code path unasserted. They share one retention decision
# (`_accept!`), which is what this pair of sweeps is really checking stays true.
RECORD_ENTRY_POINTS = (("varargs", (rec, t, x) -> GridSim.record!(rec, t, x)),
                       ("vector",  (rec, t, x) -> GridSim.record!(rec, t, [x])))

# --- M1 validation sweeps (test/m1_frequency.jl) ---
#
# Two shared helpers, defined once for the block below.

# Rebuild a system with every unit's inertia scaled by `k` and *nothing else*
# touched. S_rated/P0/R/Pmax are carried through verbatim, so S_base, the
# disturbance size, R_eq, D and the aggregate headroom are all identical
# across scalings — which is what makes the comparison inertia-only rather
# than a confounded "different system" comparison.
scale_inertia(sys::SystemModel, k::Real) =
    SystemModel(sys.S_base, sys.f0, sys.D, sys.Tg,
                [GeneratingUnit(u.id, u.S_rated, u.H * k, u.P0, u.R, u.Pmax)
                 for u in sys.units])

# Trip one unit from a cold engine and run it out. Returns the readings the
# closed forms and the ordering checks are stated in.
function trip_and_run(sys::SystemModel, id::Symbol; dt = 0.02, T = 150.0)
    eng = init!(FrequencyResponseEngine, sys; dt = dt)
    inject!(eng, TripGenerator(id))
    RoCoF0 = current_state(eng).RoCoF        # read at the trip instant, un-stepped
    for _ in 1:round(Int, T / dt)
        step!(eng, dt)
    end
    s = current_state(eng)
    a = GridSim.aggregates(sys, eng.online)  # post-trip aggregates
    return (; RoCoF0, nadir = eng.nadir, Δω_end = s.Δω, f_end = s.f,
            ΔPm_end = s.ΔPm, ΔPm_max = maximum(state_series(eng).ΔPm), aggr = a)
end

P0_of(sys, id) = first(u.P0 for u in sys.units if u.id === id)

# --- M3 steps 1, 2, 5: the governed ring (test/m3_governors_protection.jl) ---
# The M2 ring with real droop on the two machines that survive a G1 trip.
# `hr2` is G2's up-reserve in MW, so the same shape serves both the
# "reserve is ample" and the "reserve runs out" cases.
function governed_ring(; hr2 = 200.0, hr3 = 60.0, Tg = 5.0)
    buses = [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)]
    machines = [
        Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05,   80.0),               # no governor
        Machine(:G2, :B2, 200.0, 3.0, 2.0, 0.20, 1.03,   30.0, 0.05,   30.0 + hr2, Tg),
        Machine(:G3, :B3, 500.0, 5.0, 2.0, 0.50, 1.04, -110.0, 0.05, -110.0 + hr3, Tg),
    ]
    branches = [Branch(:L12, :B1, :B2, 0.25, 500.0),
                Branch(:L23, :B2, :B3, 0.25, 500.0),
                Branch(:L31, :B3, :B1, 0.25, 500.0)]
    return NetworkModel(100.0, 50.0, buses, branches, machines)
end

# --- M3 step 3: the split-speed fixture (test/m3_governors_protection.jl) ---
#
# THE FIXTURE, and why it is shaped like this. D5's hazard is a ladder driven by
# `f_coi`: it runs, it produces a plausible trace, and it sheds at the wrong
# instants. A test in which the bound machine's frequency and the COI average
# cross the threshold at nearly the same moment CANNOT see that bug. So the two
# signals are separated by construction: a small area (`:A` with its local
# generation `:C`) hangs off a very large one (`:B`) through a deliberately weak
# tie. `:B` carries 30x the area's inertia, so it owns the COI outright. Trip
# `:C` and the small area loses all its generation with a tie that cannot import
# the shortfall, so it pulls out of step and its own frequency collapses — while
# the average, anchored to `:B`, never reaches the threshold at all.
#
# That the area separates is the point, not an accident: this is precisely the
# state in which `swing.jl`'s header calls the single `f_coi` read-out a weighted
# average of two unrelated numbers. Step 4 adds the protection that trips such a
# tie; step 3 only has to make sure the defence plan is not listening to the
# wrong number while it happens.
_split_speed_net() =
    NetworkModel(100.0, 50.0,
                 [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)],
                 [Branch(:L12, :B1, :B2, 0.05, 500.0),   # inside the area: stiff
                  Branch(:L13, :B1, :B3, 2.50, 500.0)],  # the tie: deliberately weak
                 #       id   bus   S_rated    H    D   Xd′    E′      P0
                 [Machine(:A, :B1,   500.0,  2.0, 0.5, 0.30, 1.03,  -35.0),
                  Machine(:C, :B2,   300.0,  2.0, 0.5, 0.30, 1.03,   45.0),
                  Machine(:B, :B3,  5000.0,  6.0, 0.5, 0.30, 1.05,  -10.0)])

# --- M3 step 4: the pole-slip fixture (test/m3_governors_protection.jl) ---
#
# THE FIXTURE, and why the step-3 one would not do. `_split_speed_net` above is
# built so a machine's own frequency and the COI average say different things.
# It is *useless* for this step, and it takes a measurement to see why: with the
# tie still in service its two ends already sit at their own islanded closed
# forms (A at −0.14 pu, B at −0.004), so "the trip leaves two islands each
# holding their own frequency" is true there **before the relay does anything**.
# That is step 3's own V5 trap in a new place — an assertion that passes for a
# reason unrelated to the mechanism under test.
#
# So this fixture is sized to the question instead. A generating area (`:ES` at
# B1, its local generation `:ESG` at B2 behind a stiff line) exports 10 MW to a
# larger area (`:FR`) across a tie deliberately weaker than the area's own load:
# the tie's maximum transfer is `K = 0.2704 pu` against the 0.40 pu that B1 must
# import once `:ESG` is gone. Below its own load, so after the trip the surviving
# network has **no equilibrium at all** — not a marginal one that a solver
# version could push either way. The angle across the tie therefore grows
# monotonically, the transfer peaks at 90°, falls back through zero at 180° and
# reverses: a pole slip, which is what this protection exists to catch.
_pole_slip_net() =
    NetworkModel(100.0, 50.0,
                 [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)],
                 [Branch(:L12, :B1, :B2, 0.05, 500.0),   # inside the area: stiff
                  Branch(:L13, :B1, :B3, 4.00, 500.0)],  # the tie: weaker than the load
                 #       id     bus   S_rated    H    D   Xd′    E′      P0
                 [Machine(:ES,  :B1, 2000.0, 4.0, 0.5, 0.30, 1.03, -40.0),
                  Machine(:ESG, :B2, 1000.0, 4.0, 0.5, 0.30, 1.03,  50.0),
                  Machine(:FR,  :B3, 4000.0, 5.0, 0.5, 0.30, 1.05, -10.0)])

# 120°, the low end of the range D6 records for the report's separation. It is a
# *scenario parameter, not a constant of the tier* — step 6's sweep varies it —
# so it is named here rather than defaulted anywhere in `src/`.
_SLIP_THR = 2π / 3

# --- M2 step 6: the COI cross-fidelity fixtures (test/m2_events_and_coi.jl) ---
# A ring shaped so the aggregate view's exactness condition can be switched on
# and off. See the V4 testsets for the derivation; in short, the aggregate is
# exact iff the tripped machine has `D = 0` (so the aggregate's fixed `D` does
# not keep damping a machine that has left) and the survivors share `D/H` (so
# `Σ Dᵢωᵢ = D_sys·ω_coi` even while they swing apart). `D/H` is base-independent
# — both scale by the same `S_rated/S_base` — so the ratio can be read straight
# off the machine data. Machines stay rated away from `S_base`, as everywhere
# else here, so a missing per-unit conversion changes the answer.
ratio_ring(; D1 = 0.0, D2 = 1.5, D3 = 2.5) = NetworkModel(100.0, 50.0,
    [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)],
    [Branch(:L12, :B1, :B2, 0.25, 500.0), Branch(:L23, :B2, :B3, 0.25, 500.0),
     Branch(:L31, :B3, :B1, 0.25, 500.0)],
    #        id    bus   S_rated    H    D   Xd′    E′      P0
    [Machine(:G1, :B1,    300.0,  4.0, D1,  0.30,  1.05,   80.0),
     Machine(:G2, :B2,    200.0,  3.0, D2,  0.20,  1.03,   30.0),
     Machine(:G3, :B3,    500.0,  5.0, D3,  0.50,  1.04, -110.0)])

# Drive both engines through the SAME trip in ONE lockstep loop, comparing the
# live reads rather than the recorded series: `state_series` has a different
# channel set per engine and both recorders decimate, so comparing trajectories
# would be comparing two differently-sampled histories. Returns the aggregate
# frequency gap and the *survivors'* speed spread (the tripped machine is
# excluded — it is decoupled, so its speed is not inter-machine swing).
function lockstep_coi(net, trip::Symbol; dt = 0.02, nsteps = 3000)
    sw = init!(SwingEngine, net; dt = dt)
    fr = init!(FrequencyResponseEngine, coi_model(net); dt = dt)
    inject!(sw, TripGenerator(trip))          # the same event, at the same t = 0
    inject!(fr, TripGenerator(trip))
    surv = [i for (i, id) in pairs(machine_ids(sw)) if id !== trip]
    s0 = current_state(sw); r0 = current_state(fr)
    t = [0.0]; gap = [abs(s0.f_coi - r0.f)]          # measured, not a seeded zero
    spread = [maximum(s0.ω[surv]) - minimum(s0.ω[surv])]; f_sw = [s0.f_coi]
    for _ in 1:nsteps
        s = step!(sw, dt); r = step!(fr, dt)
        push!(t, s.t); push!(gap, abs(s.f_coi - r.f)); push!(f_sw, s.f_coi)
        push!(spread, maximum(s.ω[surv]) - minimum(s.ω[surv]))
    end
    return (; t, gap, spread, f_sw, sw, fr)
end

# --- M4 step 1: the real-time/playback pair (test/m4_playback.jl) ---
# N output steps EXACTLY.
#
# `run_realtime!` stops on `t < t_stop`, so a `duration` that is an exact
# multiple of `dt` is decided by floating-point accumulation. Measured while
# writing this block: `duration = 1.0` at `dt = 0.1` ran ELEVEN steps, not ten,
# because ten accumulated `0.1`s fall a hair short of `1.0` — so the real-time
# event landed a whole output step away from where playback put it and the
# agreement check failed for a reason with nothing to do with playback. Half a
# step of slack cannot be decided by roundoff.
#
# Left as a property of `run_realtime!` rather than "fixed" here: `while t <
# t_stop` is a correct reading of "run for `duration` seconds of simulation
# time", and rounding instead would move the step count of every existing
# caller. Recorded in m4-tasks.md as a finding for a later step to weigh.
pb_steps!(eng, n, dt) = run_realtime!(eng, nothing; rtf = Inf,
                                      duration = (n - 0.5) * dt, dt = dt)
# A channel's own peak excursion from where it started — the scale the band is
# a fraction of.
pb_exc(v) = maximum(abs.(v .- v[1]))
# One scenario, run both ways. `mk` builds a fresh engine (so the two runs
# cannot share state), `N`/`M` are output steps before and after the event, and
# `t_pb` is where PLAYBACK is told to put it — normally `N*dt`, i.e. the same
# instant, and deliberately elsewhere for the two controls.
function pb_both(mk, ev, N, M, dt, t_pb)
    rt = mk()
    pb_steps!(rt, N, dt)
    inject!(rt, ev)
    pb_steps!(rt, M, dt)
    pb = mk()
    solve!(pb, (0.0, (N + M) * dt); perturbations = [t_pb => ev], saveat = dt)
    return state_series(rt), state_series(pb)
end

# --- M4 step 2: the overlay pair (test/m4_playback.jl) ---
# The overlay pair M4 is built on: the aggregate tier compiled down from the
# network tier (`coi_model`) against the network tier itself, ONE scenario,
# solved by `solve!` in BOTH engines onto ONE `saveat` grid. This is the
# comparison `lockstep_coi` above could not make on recorded series (its own
# comment says why: differently-sampled histories); with a shared grid it can.
function overlay_pair(net, ev, t_ev, horizon; dt = 0.02, reltol = 1e-3, abstol = 1e-6)
    sw = SwingEngine(net; reltol = reltol, abstol = abstol)
    fr = FrequencyResponseEngine(coi_model(net); reltol = reltol, abstol = abstol)
    solve!(sw, (0.0, horizon); perturbations = [t_ev => ev], saveat = dt)
    solve!(fr, (0.0, horizon); perturbations = [t_ev => ev], saveat = dt)
    return state_series(sw), state_series(fr)
end

# --- M5 step 2: the internal degeneration oracle (test/m5_detailed.jl) ---
#
# The same model with every branch reactance reduced by the transient reactance
# of the machine at each end — the number that makes the DETAILED tier the same
# electrical network as the CLASSICAL tier on the model it was handed.
#
# Ours-classical puts `E′` AT the bus, so its coupling denominator is `X_ij`
# outright. Ours-detailed puts `E′` BEHIND `X′d` on a terminal bus, so its
# internal-node-to-internal-node reactance is `X′d,i + X_line + X′d,j`. Handing the
# detailed side `X_ij` unreduced would make that sum `X_ij + X′d,i + X′d,j` and the
# resulting gap would be pure modelling error wearing a fidelity finding's clothes.
# This is `reference/src/oracle.jl`'s `reduced_line_reactance` applied to our own
# tier instead of to PowerDynamics', for the identical reason.
#
# **It exists only on a radial pair, and this helper THROWS rather than saying so.**
# A machine of branch degree 2 has one internal reactance to spend across two lines
# and subtracting it from each double-counts it. On `three_machine_ring()` every
# `X′d` converts to 0.10, so the arithmetic happily returns `X = 0.05 > 0` — a
# valid-LOOKING model built on a reduction that does not exist for it. That is
# exactly the failure `reference/src/oracle.jl` names in its own words: "a comment
# saying the ring is not a valid oracle case is exactly the thing that gets stepped
# over later; a thrown error is not". `_assert_radial` throws there; this throws
# here, and the ring is the test of the refusal rather than a caveat in a comment.
#
# Indexed through `machine_arrays(net).bus` rather than by assuming machine `k`
# sits on vertex `k`. That identity holds on every fixture here and `SwingEngine`
# asserts it — but this helper is handed models the classical tier never sees.
function terminal_bus_reduced(net::NetworkModel)
    ma = machine_arrays(net)
    degree = zeros(Int, length(net.buses))
    for br in net.branches
        degree[net.bus_index[br.from]] += 1
        degree[net.bus_index[br.to]] += 1
    end
    Xd′_at = zeros(Float64, length(net.buses))
    for k in eachindex(ma.bus)
        v = ma.bus[k]
        degree[v] == 1 || throw(ArgumentError(
            "terminal_bus_reduced: machine $(net.machines[k].id) has branch degree " *
            "$(degree[v]). `E′ at the bus` and `E′ behind X′d` coincide only on a " *
            "RADIAL pair — a machine on two lines has one internal reactance to " *
            "spend across both, and this reduction would count it twice. The result " *
            "would still be a positive reactance and a model that builds."))
        Xd′_at[v] += ma.Xd′[k]
    end
    # The positivity guard runs BEFORE `Branch` is constructed, not after. `Branch`
    # refuses `X ≤ 0` itself — but it refuses it as "the coupling denominator",
    # which sends the reader to the wrong question. Here the answer is that the
    # machines' internal reactances swallow the tie and the REDUCTION does not
    # exist, which is a statement about this comparison rather than about the data.
    Xr = [br.X - Xd′_at[net.bus_index[br.from]] - Xd′_at[net.bus_index[br.to]]
          for br in net.branches]
    for (e, br) in pairs(net.branches)
        Xr[e] > 0 || throw(ArgumentError(
            "terminal_bus_reduced: branch $(br.id) reduces to X = $(Xr[e]) ≤ 0 — the " *
            "machines' internal reactances exceed the tie, so there is no line left " *
            "to put between them and the reduction does not exist for this model."))
    end
    branches = [Branch(br.id, br.from, br.to, Xr[e], br.rating)
                for (e, br) in pairs(net.branches)]
    return NetworkModel(net.S_base, net.f0, net.buses, branches,
                        net.machines, net.loads)
end

# One disturbance, applied identically to a classical and a detailed engine, and
# both played back onto the SAME `saveat` grid.
#
# The disturbance is a STEP IN SCHEDULED MECHANICAL POWER, not a seeded rotor
# angle, and the reason is the detailed tier's algebraic constraint: `Pm` appears
# in no algebraic equation, so stepping it leaves the DAE's initial point
# consistent, where an angle written straight into `u` would not be. It is also
# the one perturbation both tiers express identically — `TripLine` islands a
# radial pair, and `inject!(::TripGenerator)` is refused at the detailed tier.
#
# `auto_dt_reset!` on both, symmetrically: the initial step size was chosen at
# `init` against the un-stepped RHS, and letting one side carry a stale one while
# the other does not would put an asymmetry into a comparison whose whole content
# is a symmetry.
function tier_pair(net, red; tspan = (0.0, 10.0), saveat = 0.02, ΔPm = 0.05,
                   reltol = 1.0e-6, abstol = 1.0e-9)
    sw = init!(SwingEngine, net; reltol = reltol, abstol = abstol)
    de = init!(DetailedEngine, red; reltol = reltol, abstol = abstol)
    for eng in (sw, de)
        eng.params[eng.Pm_pidx[1]] += ΔPm
        SciMLBase.auto_dt_reset!(eng.integrator)
    end
    return solve!(sw, tspan; saveat = saveat), solve!(de, tspan; saveat = saveat)
end

# The four channels the classical and detailed tiers may be compared on, and the
# one they may not.
#
# Rotor angles appear ONLY as a difference: the two engines fix the rotational
# gauge differently (the detailed tier pins its slack machine at zero, the
# classical tier's fixpoint lands wherever it lands), so an absolute angle is not
# a shared quantity. `f_coi` and the per-machine speeds are gauge-free as they
# stand.
#
# **There is deliberately no voltage channel.** `SwingEngine`'s bus voltage IS
# `E′` — constant by construction — while the detailed tier's is the TERMINAL
# voltage behind `X′d`, which genuinely moves during a swing. They are different
# physical quantities that happen to share a name, and a comparison between them
# would report the tier's entire reason for existing as a disagreement.
const TIER_CHANNELS = (("f_coi", system_frequency),
                       ("ω_G1", s -> s.ω_G1),
                       ("ω_G2", s -> s.ω_G2),
                       ("δ_G2−δ_G1", s -> s.δ_G2 .- s.δ_G1))


# ─────────────────────────────────────────────────────────────────────────────
# M5 step 4 — the flux equations
# ─────────────────────────────────────────────────────────────────────────────

"""
    flux_tau_pred(net) -> Float64

The Heffron-Phillips field-flux time constant `T′do·(X′d + Xe)/(Xd + Xe)` for an
`infinite_bus_system()`-shaped model: machine 1 on the infinite bus that machine
2's frozen internal node IS, through `Xe = X_tie + X′d₂`.

**Every reactance comes from `machine_arrays`**, i.e. on the SYSTEM base. The
`Machine` fields are on the MACHINE base and `G1` is rated 250 MVA against a 100
MVA system, so reading `net.machines[1].Xd` here would predict a time constant
wrong by 2.5x — and it would look entirely plausible, which is the trap this repo
keeps paying for.
"""
function flux_tau_pred(net::NetworkModel)
    ma = machine_arrays(net)
    Xe = net.branches[1].X + ma.Xd′[2]
    return ma.Td0′[1] * (ma.Xd′[1] + Xe) / (ma.Xd[1] + Xe)
end

"""
    flux_tau_fit(t, y; h, i1) -> (τ, n)

The decay constant of `y(t) = A + B·e^{−t/τ}`, fitted **without ever estimating
the asymptote `A`**: differencing the series against itself `h` samples later
kills the constant outright, since
`y(t) − y(t+h) = B·(1 − e^{−h/τ})·e^{−t/τ}`, so a straight line through the log of
`|y(t) − y(t+h)|` has slope `−1/τ`. An `A` read off the tail would be exactly the
quantity a wrong time constant also gets wrong, and the fit would absorb the error
it exists to measure.

Samples `i0 = 1` through `i1`; `h` is in samples, not seconds.
"""
function flux_tau_fit(t, y; h::Integer, i1::Integer)
    xs = Float64[]; ls = Float64[]
    for i in 1:i1
        d = y[i] - y[i + h]
        abs(d) < 1.0e-13 && continue          # below round-off: no information left
        push!(xs, t[i]); push!(ls, log(abs(d)))
    end
    length(xs) >= 10 || error("flux_tau_fit: only $(length(xs)) usable samples")
    n = length(xs); mx = sum(xs) / n; ml = sum(ls) / n
    slope = sum((xs .- mx) .* (ls .- ml)) / sum((xs .- mx) .^ 2)
    return -1 / slope, n
end

"""
    flux_limit_model(net) -> NetworkModel

`net` with every machine's transient reactances raised to its synchronous ones
(`X′d := Xd`, `X′q := Xq`) and its flux frozen — the `T′do, T′qo → 0` LIMIT
machine written as a model rather than as a limit.

**Why those two edits ARE the limit.** As `T′ → 0` the flux states reach their
quasi-steady values instantly, `E′q → Efd − (Xd − X′d)·Id` and
`E′d → (Xq − X′q)·Iq`; substitute those into the stator algebra and it collapses to
`Vq = Efd − Xd·Id − Ra·Iq`, `Vd = Xq·Iq − Ra·Id` — a constant q-axis source `Efd`
behind `(Ra + jXq)`, which is precisely a frozen machine whose transient
reactances are its synchronous ones. Nothing has to be matched by hand: the power
flow is bit-identical (`_machine_injection` reads only `E`, `Ra` and `Xq`, none of
which this touches), and the limit machine's back-substituted `E′q` is identically
the fast machine's `Efd`.

**`E′q` and `E′d` are NOT comparable channels between the two models**, and that
is by construction rather than by accident: they differ by `(Xd − X′d)·Id` and
`(Xq − X′q)·Iq`, an O(0.1) offset on `detailed_pair()`. Only `δ`, `ω`, the bus
voltages and `f_coi` mean the same quantity on both sides — which is why the
caller lists channels instead of looping over `keys`.
"""
flux_limit_model(net::NetworkModel) = NetworkModel(net.S_base, net.f0, net.buses,
    net.branches,
    [Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd, m.E′, m.P0, m.R, m.Pmax, m.Tg;
             Xd = m.Xd, Xq = m.Xq, Xq′ = m.Xq, Td0′ = Inf, Tq0′ = Inf, Ra = m.Ra)
     for m in net.machines])

# `net` with every finite flux time constant scaled by `λ`. `Inf·λ` is `Inf`, so a
# machine that was already frozen stays frozen and needs no special case.
scale_flux_time(net::NetworkModel, λ::Real) = NetworkModel(net.S_base, net.f0,
    net.buses, net.branches,
    [Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, m.P0, m.R, m.Pmax, m.Tg;
             Xd = m.Xd, Xq = m.Xq, Xq′ = m.Xq′, Td0′ = λ * m.Td0′,
             Tq0′ = λ * m.Tq0′, Ra = m.Ra) for m in net.machines])

# `net` with one machine's `Xd` scaled — the anti-vacuity mutation for both the
# closed form (the predicted τ moves) and the `T′ → 0` limit (the fast side
# converges to a DIFFERENT machine).
scale_Xd(net::NetworkModel, id::Symbol, f::Real) = NetworkModel(net.S_base, net.f0,
    net.buses, net.branches,
    [Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, m.P0, m.R, m.Pmax, m.Tg;
             Xd = m.id === id ? f * m.Xd : m.Xd, Xq = m.Xq, Xq′ = m.Xq′,
             Td0′ = m.Td0′, Tq0′ = m.Tq0′, Ra = m.Ra) for m in net.machines])

"""
    efd_step_run(net; ΔEfd, reltol, abstol, T, saveat, slack) -> NamedTuple

A step on machine 1's field voltage, and the trajectory it produces.

`Efd` is a PARAMETER at this tier until the plan's step 5 gives it a regulator, so
this is the sanctioned perturbation channel (SPEC §6 — `inject!` writes exactly
this vector) and needs no new event type. `auto_dt_reset!` follows the write for
the reason `tier_pair` does it: the integrator's cached step size was chosen for
the pre-step problem.
"""
function efd_step_run(net::NetworkModel; ΔEfd::Real = 0.05, reltol::Real = 1.0e-9,
                      abstol::Real = 1.0e-12, T::Real = 25.0, saveat::Real = 0.05,
                      slack::Symbol = :G_inf)
    eng = init!(DetailedEngine, net; slack = slack, reltol = reltol, abstol = abstol)
    eng.params[eng.Efd_pidx[1]] += ΔEfd
    SciMLBase.auto_dt_reset!(eng.integrator)
    return solve!(eng, (0.0, Float64(T)); saveat = saveat)
end

"""
    pm_step_run(net; ΔPm, reltol, abstol, T, saveat) -> NamedTuple

A step on machine 1's mechanical power — the disturbance the `T′ → 0` limit
comparison runs on, because a FLAT run makes the two models agree trivially.

The base value is read off the engine rather than from `Machine.P0`: at this tier
the dispatch comes from the power flow, and on a model carrying a load those are
not the same number.
"""
function pm_step_run(net::NetworkModel; ΔPm::Real = 0.05, reltol::Real = 1.0e-9,
                     abstol::Real = 1.0e-12, T::Real = 5.0, saveat::Real = 0.02)
    eng = init!(DetailedEngine, net; reltol = reltol, abstol = abstol)
    eng.params[eng.Pm_pidx[1]] += ΔPm
    SciMLBase.auto_dt_reset!(eng.integrator)
    return solve!(eng, (0.0, Float64(T)); saveat = saveat)
end

# The channels the fast machine and its `T′ → 0` limit may be compared on. The two
# flux channels are absent DELIBERATELY — see `flux_limit_model`.
const FLUX_LIMIT_CHANNELS = (:δ_G1, :δ_G2, :ω_G1, :ω_G2, :V_B1, :V_B2, :f_coi)
