# GridSimReference — the external-oracle suite (docs/plans/m4-tasks.md step 4).
#
# Every check here is ours against SOMEBODY ELSE'S implementation. That is the
# one thing no earlier milestone could do: M1's closed forms, M2's cross-fidelity
# overlay and M3's degeneration checks are all ours against ours, and they cannot
# tell "the simple model drops swings" apart from "our model has a bug" (D2).
#
# THREE RULES THIS FILE KEEPS, INHERITED FROM M1–M3 AND NOT RE-ARGUED:
#
#   1. Every band is stated before the gap is seen. Here that is structural
#      rather than disciplinary: `oracle_band` is computed from each side's OWN
#      convergence and never looks at the other side (see its docstring).
#   2. Every check ships with a positive control (it can read agreement when
#      agreement is real) AND an anti-vacuity control (it can read disagreement).
#      Five planned checks in M3 would each have passed against the very bug they
#      targeted; this is what that cost bought.
#   3. A number below the solver's own tolerance is not a result until it survives
#      the tolerance changing.
#
# WHAT THIS SUITE CANNOT CATCH, SAID ONCE AND TESTED FOR AT THE BOTTOM. The case
# is COMPILED from `NetworkModel` (D5), so both sides read the same
# `machine_arrays` / `branch_arrays` / `_coupling`. A bug in those is handed
# identically to both and every check here goes green. That is the price of not
# hand-maintaining a parallel model, it is the right price, and it is why the
# anti-vacuity mutation must be made in `swing_vertex!` and never in the shared
# data path.

using Test
using GridSim
using GridSimReference
using PowerDynamics: set_fbase!, set_Sbase!

# ---------------------------------------------------------------------------
# Fixtures and helpers
# ---------------------------------------------------------------------------

# A model on NEITHER of the repo's two fixture bases. `two_machine_system()` and
# `three_machine_ring()` are both 100 MVA / 50 Hz, so any check that the builder
# takes the bases FROM THE MODEL — rather than from whatever PowerDynamics'
# process-global state happens to hold — is vacuous against them.
#
# It doubles as the fixture for the negative-reduction guard: `X′d` comes to
# 0.2333 + 0.1600 = 0.3933 pu on the system base against a 0.20 pu tie, so there
# is no line left to put between the two internal nodes.
function base_250_60()
    NetworkModel(250.0, 60.0,
                 [Bus(:BA, 230.0), Bus(:BB, 230.0)],
                 [Branch(:LAB, :BA, :BB, 0.20, 800.0)],
                 [Machine(:GA, :BA, 300.0, 3.5, 1.5, 0.28, 1.04,  150.0),
                  Machine(:GB, :BB, 500.0, 6.0, 2.5, 0.32, 1.01, -150.0)])
end

# A radial pair at a chosen loading, so the `ClassicalMachine` residual can be
# read against the one thing it is supposed to scale with.
function loaded_pair(P0_MW)
    NetworkModel(100.0, 50.0,
                 [Bus(:B1, 400.0), Bus(:B2, 400.0)],
                 [Branch(:L12, :B1, :B2, 0.25, 500.0)],
                 [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05,  P0_MW),
                  Machine(:G2, :B2, 400.0, 5.0, 2.0, 0.30, 1.02, -P0_MW)])
end

# The message of an `ArgumentError` a call is expected to throw. Defined here
# rather than imported: `test/helpers.jl` belongs to the core suite, and neither
# `reference/test/` nor `ui/test/` reaches into it (checked in M5 step 0b, and
# the reason a hoisted helper could break a suite nobody ran).
function argerr_msg(f)
    try
        f()
    catch e
        e isa ArgumentError && return e.msg
        rethrow()
    end
    error("expected an ArgumentError, but the call returned normally")
end

# The gauge-free channel: an angle DIFFERENCE. A raw `δ` is arbitrary up to a
# common shift on both sides, so it is never the thing compared.
δ12(s) = s.δ_G1 .- s.δ_G2

# One GridSim run and one PowerDynamics run of the same scenario on ONE grid.
# The grid is fixed before either solve because `divergence` refuses two grids
# and nothing anywhere resamples (M4 step 2, D10).
function both(net, tspan, grid; tier = :swing, perturbations = (),
              reltol = 1.0e-9, abstol = 1.0e-12, step_power = nothing)
    eng = SwingEngine(net; reltol = reltol, abstol = abstol)
    case = build_oracle(net; tier = tier, perturbations = perturbations)
    if step_power !== nothing
        id, Pm = step_power
        # Reaching past the engine's own interface, deliberately and for a stated
        # reason: a mechanical-power step is bus-local, works on any topology and
        # needs no new event type, and PARAMETERS are the sanctioned perturbation
        # channel (SPEC §6 — `inject!` writes exactly this vector). Seeding a
        # non-equilibrium STATE instead would be a second way to place an
        # engine's initial condition, which is the shape D4 and D8 forbid.
        v = findfirst(m -> m.id === id, net.machines)::Int
        eng.params[eng.Pm_pidx[v]] = Pm
        set_mechanical_power!(case, id, Pm)
    end
    ours = solve!(eng, tspan; perturbations = perturbations, saveat = grid)
    theirs = oracle_solve(case, tspan; saveat = grid, reltol = reltol, abstol = abstol)
    return ours, theirs
end

@testset "M4 step 4 — PowerDynamics as an external oracle" begin

# ===========================================================================
@testset "the preconditions are structural, not documented" begin
    # `m5-prestudy.md` §7 says the ring "must not be used" as a ClassicalMachine
    # oracle case. A sentence saying so is exactly what gets stepped over later.
    err = try build_oracle(three_machine_ring(); tier = :classical); nothing
          catch e; e end
    @test err isa ArgumentError
    @test occursin("degree 2", err.msg)
    @test occursin("radial", err.msg)
    # …and the ring IS accepted for `:swing`, which is the positive half: the
    # rejection has to be about the reduction, not about rings in general.
    @test build_oracle(three_machine_ring()) isa OracleCase

    # The reduction can also fail to exist on a perfectly good radial pair.
    err = try build_oracle(base_250_60(); tier = :classical); nothing
          catch e; e end
    @test err isa ArgumentError
    @test occursin("X_line", err.msg)
    @test occursin("≤ 0", err.msg)
    @test build_oracle(base_250_60()) isa OracleCase          # …but `:swing` is fine

    # A governed model has no `ΔPm` counterpart in either PowerDynamics tier.
    # The two clauses are exercised separately so a test cannot pass by reaching
    # the wrong one.
    governed = NetworkModel(100.0, 50.0,
        [Bus(:B1, 400.0), Bus(:B2, 400.0)],
        [Branch(:L12, :B1, :B2, 0.25, 500.0)],
        [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05,  60.0, 0.05, 60.0, 5.0),
         Machine(:G2, :B2, 400.0, 5.0, 2.0, 0.30, 1.02, -60.0)])
    err = try build_oracle(governed); nothing catch e; e end
    @test err isa ArgumentError
    @test occursin("droop", err.msg)

    reserved = NetworkModel(100.0, 50.0,
        [Bus(:B1, 400.0), Bus(:B2, 400.0)],
        [Branch(:L12, :B1, :B2, 0.25, 500.0)],
        [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05,  60.0, Inf, 90.0, 1.0),
         Machine(:G2, :B2, 400.0, 5.0, 2.0, 0.30, 1.02, -60.0)])
    err = try build_oracle(reserved); nothing catch e; e end
    @test err isa ArgumentError
    @test occursin("headroom", err.msg)

    # An event with no mapping is refused rather than silently dropped — a
    # perturbation that reached one side only is the worst failure this
    # comparison has, because it looks exactly like a physics finding.
    err = try build_oracle(two_machine_system();
                           perturbations = [1.0 => StepLoad(0.1)]); nothing
          catch e; e end
    @test err isa ArgumentError
    @test occursin("no PowerDynamics mapping", err.msg)

    @test_throws ArgumentError build_oracle(two_machine_system(); tier = :detailed)
    @test_throws ArgumentError build_oracle(two_machine_system();
                                            perturbations = [TripLine(:B1, :B2)])
    @test_throws ArgumentError build_oracle(two_machine_system();
                                            perturbations = [1.0 => TripLine(:B1, :B9)])

    # The one number the `:classical` comparison turns on, checked against the
    # model's own arrays and round-tripped rather than written out by hand.
    net = two_machine_system()
    ma, ba = machine_arrays(net), branch_arrays(net)
    Xr = reduced_line_reactance(net, 1)
    @test Xr ≈ 0.075
    @test Xr + ma.Xd′[1] + ma.Xd′[2] ≈ ba.X[1]    # internal node to internal node
    @test ma.Xd′[1] ≈ 0.25 * 100 / 250            # …and the weight is the INVERSE one
    @test ma.Xd′[2] ≈ 0.30 * 100 / 400           # (0.1 and 0.075, not 0.625 and 1.2)
end

# ===========================================================================
@testset "the flat run: PowerDynamics says our fixpoint is one" begin
    # No disturbance at all. PowerDynamics reaches equilibrium through complex
    # bus voltages, a pi-line admittance and a current balance; ours is a
    # closed-form `K·sin(δᵢ−δⱼ)`. If our steady state is not a steady state of
    # that formulation, this says so immediately — and no overlay would.
    net = two_machine_system()
    grid = collect(0.0:0.05:5.0)
    case = build_oracle(net)
    flat = oracle_solve(case, (0.0, 5.0); saveat = grid)
    @test maximum(abs, flat.ω_G1) < 1.0e-10
    @test maximum(abs, flat.ω_G2) < 1.0e-10
    @test maximum(abs, flat.f_coi .- net.f0) < 1.0e-8
    @test maximum(abs, δ12(flat) .- δ12(flat)[1]) < 1.0e-10
    # …and the angle it holds is the closed form, to the digit.
    @test δ12(flat)[1] ≈ asin(0.6 / branch_arrays(net).K[1]) atol = 1e-12

    # POSITIVE CONTROL — the flat run can read NOT-flat. Without this, "PD agrees
    # our fixpoint is one" is indistinguishable from "this check always passes".
    bumped = build_oracle(net)
    bumped.s0.v[1, bumped.angsym] += 0.01
    moved = oracle_solve(bumped, (0.0, 5.0); saveat = grid)
    @test maximum(abs, moved.ω_G1) > 1.0e-5
    @test maximum(abs, δ12(moved) .- δ12(moved)[1]) > 1.0e-3
end

# ===========================================================================
@testset "the band is derived, and it is derived from the right thing" begin
    net = two_machine_system()
    grid = collect(0.0:0.05:2.0)
    # A DISTURBED run, deliberately: on an undisturbed pair every run is flat and
    # every difference is exactly zero, so `b3 > 0` would fail and `b6 ≈ 2·b3`
    # would pass vacuously. A band derived from a scenario with no dynamics in it
    # is not a band.
    step = (:G1, machine_arrays(net).Pm[1] - 0.01)
    o, t = both(net, (0.0, 2.0), grid; step_power = step)
    # A series against itself contributes no error, so a band built only from
    # self-comparisons is exactly zero. `oracle_band` cannot manufacture room.
    @test oracle_band(o, o, t, t) == 0.0
    @test divergence(o, o; band = 1.0).max == 0.0
    @test isnan(divergence(o, o; band = 1.0).t_depart)
    # …and it is linear in the stated factor, so the factor is visible arithmetic
    # rather than something buried.
    o2, t2 = both(net, (0.0, 2.0), grid; step_power = step,
                  reltol = 1.0e-6, abstol = 1.0e-9)
    b3 = oracle_band(o2, o, t2, t)
    b6 = oracle_band(o2, o, t2, t; factor = 6)
    @test b3 > 0
    @test b6 ≈ 2 * b3
    # The two contributions are each side's OWN convergence — neither term ever
    # sees the other implementation. That is what makes "state the band before
    # you see the gap" arithmetic instead of discipline.
    @test b3 ≈ 3 * (maximum(abs, system_frequency(o2) .- system_frequency(o)) +
                    maximum(abs, system_frequency(t2) .- system_frequency(t)))
end

# ===========================================================================
@testset "agreement on the scenario the playback window ships" begin
    # `TripLine(:B3, :B1)` on the ring is M4 step 3's shipped default — the case
    # where the tier gap IS the inter-machine swing rather than damping
    # bookkeeping. Putting the external oracle on exactly that run is the point:
    # the window's caption claims a physics lesson, and this is what says the
    # physics underneath it is not our own arithmetic agreeing with itself.
    net = three_machine_ring()
    grid = collect(0.0:0.02:10.0)
    pert = [1.0 => TripLine(:B3, :B1)]
    o, t = both(net, (0.0, 10.0), grid; perturbations = pert)
    of, tf = both(net, (0.0, 10.0), grid; perturbations = pert,
                  reltol = 1.0e-12, abstol = 1.0e-15)
    band = oracle_band(o, of, t, tf)

    d = divergence(o, t; band = band)
    @test band > 0
    @test d.max < band
    @test isnan(d.t_depart)                       # never leaves the band
    @test d.n == length(grid)

    # The run really is the one step 3 draws — otherwise this is a tight
    # agreement on some other trajectory.
    @test maximum(abs, system_frequency(o) .- net.f0) ≈ 1.076e-3 rtol = 1e-2
    @test (maximum(δ12(o)) - minimum(δ12(o))) ≈ 0.2815 rtol = 1e-2

    # The per-machine speeds agree too, not only the aggregate — an aggregate can
    # hide two machines wrong in opposite directions.
    for id in machine_ids(SwingEngine(net))
        ch = s -> getproperty(s, Symbol(:ω_, id))
        # Its OWN band, derived on its own channel. The COI band scaled by `f0` is
        # NOT it: `f_coi` is an inertia-weighted mean, so the machines' errors
        # partly cancel inside it and its band comes out ~20x tighter than any
        # single machine's. Reusing it here would fail on a correct run — which is
        # exactly the mistake of judging one quantity by another's tolerance.
        cband = oracle_band(o, of, t, tf; channel = ch)
        @test cband > 0
        @test divergence(o, t; band = cband, channel = ch).max < cband
    end
    # …and the gauge-free angle difference, on its own band.
    aband = oracle_band(o, of, t, tf; channel = δ12)
    @test divergence(o, t; band = aband, channel = δ12).max < aband
end

# ===========================================================================
@testset "convergence: the gap is solver error, not a disagreement" begin
    # The standing rule (M3, restated in playback.jl): a number below the
    # solver's own tolerance is not a result until it survives the tolerance
    # changing. A fixed disagreement between two models would NOT shrink.
    net = three_machine_ring()
    grid = collect(0.0:0.02:10.0)
    pert = [1.0 => TripLine(:B3, :B1)]
    gap(rt) = divergence(both(net, (0.0, 10.0), grid;
                              perturbations = pert, reltol = rt, abstol = rt * 1e-3)...;
                         band = 1.0).max
    coarse, fine = gap(1.0e-6), gap(1.0e-9)
    @test coarse > 0
    @test fine > 0
    @test fine < coarse / 10                      # 1000x tighter, >=10x smaller
end

# ===========================================================================
@testset "a generator trip: the aggregate drops the machine on both sides" begin
    # The read-out, not just the trajectory. Our engine zeroes the tripped
    # machine's COI weight; the oracle has to do the same, at the same instant,
    # or the two `f_coi` channels are different quantities and would disagree
    # for a reason that has nothing to do with either implementation.
    net = three_machine_ring()
    grid = collect(0.0:0.02:10.0)
    pert = [1.0 => TripGenerator(:G2)]
    o, t = both(net, (0.0, 10.0), grid; perturbations = pert)
    of, tf = both(net, (0.0, 10.0), grid; perturbations = pert,
                  reltol = 1.0e-12, abstol = 1.0e-15)
    band = oracle_band(o, of, t, tf)
    @test divergence(o, t; band = band).max < band

    # ANTI-VACUITY: the weight really did move. Recomputing `f_coi` from the
    # oracle's own per-machine speeds with the PRE-trip weights gives a
    # different answer — so a version of `oracle_solve` that forgot to drop the
    # weight would not have passed the check above by accident.
    ma = machine_arrays(net)
    ΣH = sum(ma.H)
    stale = [net.f0 * (1 + (ma.H[1]*t.ω_G1[k] + ma.H[2]*t.ω_G2[k] +
                            ma.H[3]*t.ω_G3[k]) / ΣH) for k in eachindex(grid)]
    @test maximum(abs, stale .- t.f_coi) > 100 * band
    # …and the sample AT the trip instant is still the pre-event one, on both
    # sides, which is the ordering the playback driver asserts from outside.
    k = findfirst(==(1.0), grid)::Int
    @test t.f_coi[k] ≈ stale[k] atol = 1e-12
end

# ===========================================================================
@testset "the model's own bases reach PowerDynamics, not a stale global" begin
    # PowerDynamics reads `Sbase`/`fbase` from PROCESS-GLOBAL state at component
    # construction time and bakes them in. Both repo fixtures are 100 MVA /
    # 50 Hz, so a check that the builder sets them from the model it was handed
    # is vacuous against either. This one poisons the global first, on purpose.
    set_Sbase!(100.0)
    set_fbase!(50.0)

    net = base_250_60()
    @test net.f0 == 60.0
    grid = collect(0.0:0.02:4.0)
    ma = machine_arrays(net)
    o, t = both(net, (0.0, 4.0), grid; step_power = (:GA, ma.Pm[1] - 0.01))
    of, tf = both(net, (0.0, 4.0), grid; step_power = (:GA, ma.Pm[1] - 0.01),
                  reltol = 1.0e-12, abstol = 1.0e-15)
    band = oracle_band(of, o, tf, t; channel = s -> s.δ_GA .- s.δ_GB)
    ch = s -> s.δ_GA .- s.δ_GB
    @test divergence(o, t; band = band, channel = ch).max < band

    # ANTI-VACUITY: a stale 50 Hz base would put `dθ/dt = 314·ω` where the model
    # says 377, a 20 % error in every angle rate. Reproduce that error on OUR
    # side by compiling the same machines at 50 Hz and confirm the check would
    # have caught it — so the agreement above is evidence about the base and not
    # a band wide enough to swallow it.
    wrong = NetworkModel(net.S_base, 50.0, net.buses, net.branches, net.machines)
    ew = SwingEngine(wrong; reltol = 1.0e-9, abstol = 1.0e-12)
    ew.params[ew.Pm_pidx[1]] = ma.Pm[1] - 0.01
    ow = solve!(ew, (0.0, 4.0); saveat = grid)
    @test maximum(abs, ch(ow) .- ch(t)) > 100 * band
end

# ===========================================================================
@testset "ClassicalMachine is NOT our tier, and the residual has a signature" begin
    # `m5-prestudy.md` §7 lists three convention questions for this tier
    # (reactance placement, damping form, `H` base) and all three come out our
    # way. There is a FOURTH, which nothing on the plan had: PowerDynamics'
    # classical machine takes a mechanical TORQUE, `τ_m/ω`, where ours takes a
    # POWER. The difference is `τ_m(1/ω − 1) ≈ −Pm·Δω` — it acts like a change in
    # damping, is proportional to the machine's loading, and is invisible at
    # ω = 1, so no flat run and no steady-state check can see it (D14).

    # --- the closed form, which is the sharpest form the finding takes --------
    # After `TripGenerator(:G1)` on a radial pair the survivor is alone: no
    # coupling, constant mechanical input, first-order in ω. Both sides then have
    # a closed-form settling speed, and they are DIFFERENT closed forms.
    net = loaded_pair(60.0)
    ma = machine_arrays(net)
    D, τ = ma.D[2], ma.Pm[2]
    ours_ss   = τ / D                                       # Pm = D·Δω
    torque_ss = (D + sqrt(D^2 + 4 * D * τ)) / (2 * D) - 1   # τ/ω = D·(ω−1)
    @test ours_ss ≈ -0.075
    @test torque_ss < ours_ss                                # the torque form sags further
    # …by a factor (1 − Pm/D), which is the FIRST-order term: the exact ratio
    # here is 1.0132 against 1.075 − 1, i.e. 1.3 % of second-order correction.
    @test torque_ss ≈ ours_ss * (1 - τ / D) rtol = 2e-2

    grid = collect(0.0:0.05:60.0)
    pert = [1.0 => TripGenerator(:G1)]
    o, t_swing = both(net, (0.0, 60.0), grid; perturbations = pert)
    _, t_class = both(net, (0.0, 60.0), grid; tier = :classical, perturbations = pert)
    # Each side lands on ITS OWN closed form — which is what makes this an
    # attribution and not merely a disagreement.
    @test o.ω_G2[end]       ≈ ours_ss   rtol = 1e-3
    @test t_swing.ω_G2[end] ≈ ours_ss   rtol = 1e-3
    @test t_class.ω_G2[end] ≈ torque_ss rtol = 1e-3
    # …and the `Swing` tier tracks us to far better than the difference it is
    # being used to measure.
    @test maximum(abs, o.ω_G2 .- t_swing.ω_G2) < 1e-3 * abs(torque_ss - ours_ss)

    # --- the coupled comparison, and the signature ---------------------------
    # A mechanical-power step keeps the pair COUPLED, so this run exercises the
    # `X_line = X − X′d,ᵢ − X′d,ⱼ` reduction rather than two isolated rotors.
    grid2 = collect(0.0:0.02:5.0)
    residual = Dict{Float64,Float64}()
    for P in (60.0, 6.0, 0.6)
        n = loaded_pair(P)
        Pm = machine_arrays(n).Pm[1] - 0.001
        o, ts = both(n, (0.0, 5.0), grid2; step_power = (:G1, Pm))
        of, tsf = both(n, (0.0, 5.0), grid2; step_power = (:G1, Pm),
                       reltol = 1.0e-12, abstol = 1.0e-15)
        _, tc = both(n, (0.0, 5.0), grid2; tier = :classical, step_power = (:G1, Pm))
        band = oracle_band(o, of, ts, tsf; channel = δ12)
        gs = maximum(abs, δ12(o) .- δ12(ts))
        gc = maximum(abs, δ12(o) .- δ12(tc))
        # Same machinery, same band, opposite verdicts — and the verdict flips
        # for a reason that was derived from PowerDynamics' source, not fitted.
        @test gs < band
        @test gc > 5 * band
        residual[P] = gc
    end
    # THE SIGNATURE: linear in loading over two decades. This is asserted instead
    # of a magnitude, because a magnitude fitted to these three runs would be a
    # constant fitted to the very thing it claims to judge (M3's rule).
    @test residual[60.0] / residual[6.0] ≈ 10 rtol = 0.2
    @test residual[6.0] / residual[0.6]  ≈ 10 rtol = 0.2
    # …and the reduction is therefore EXACT: a wrong `X_line` would leave a
    # residual that does not vanish with loading, so the ratios would flatten
    # toward 1 as the torque term shrank beneath it. Extrapolated to zero
    # loading the residual goes to zero, which is the claim.
    @test residual[0.6] < residual[60.0] / 50
end

# ===========================================================================
@testset "what this oracle cannot check (D7's label list, as a test)" begin
    # The case is compiled from the canonical model, so both sides read the SAME
    # per-unit conversion. Pinned here so nobody later reads a green suite as
    # evidence about `machine_arrays`: the numbers PowerDynamics integrates are
    # literally the ones our engine integrates.
    net = two_machine_system()
    ma = machine_arrays(net)
    case = build_oracle(net)
    for v in 1:2
        @test case.s0.p.v[v, :mach₊M]  ≈ 2 * ma.H[v]
        @test case.s0.p.v[v, :mach₊D]  ≈ ma.D[v]
        @test case.s0.p.v[v, :mach₊Pm] ≈ ma.Pm[v]
        @test case.s0.p.v[v, :mach₊V]  ≈ ma.E[v]
    end
    # So `H`, `D` and `Pm` are NOT externally checked — invert a weight in
    # `machine_arrays` and both sides integrate the same wrong number. They stay
    # checked by M1/M2's closed forms. The anti-vacuity mutation for this step
    # therefore belongs in `swing_vertex!`, and scaling `D` is the one to make:
    # the equilibrium is at ω = 0 either way, so the flat run still passes and
    # only the transient diverges — which proves the transient check is the one
    # doing the work.
    #
    # `X′d` is the exception, and it is externally checked, by the `:classical`
    # residual's signature above: a wrong inverse weight there would leave a
    # loading-independent floor, and none survives.
    @test ma.Xd′[1] ≈ 0.25 * 100 / 250

    # The COI weights the oracle reports with are OURS, not PowerDynamics'.
    @test case.H == ma.H
end

end # M4 step 4

# ---------------------------------------------------------------------------
# Fixtures and helpers for the detailed tier (M5 steps 3 and 4)
# ---------------------------------------------------------------------------
#
# These four sat INSIDE the step-3 testset until step 4 needed them too, and a
# `@testset` block is a scope: a function defined in one is invisible to its
# sibling. Hoisting rather than copying is M5 step 0b's rule applied to this file —
# the alternative is two copies of the one helper that decides what "the same
# scenario on both sides" means. Nothing in them changed in the move; step 3's
# testsets below still call them and its counts are unchanged.

# `detailed_pair()` — the machine carrying REAL detailed data — was a local here
# until M5 step 4, and it MOVED INTO `GridSim` itself (`src/model/network_model.jl`,
# beside `two_machine_system` and friends). Step 4's core suite needs the same
# fixture for the `T′ → 0` limit and for the first flat run whose flux fixpoint is
# a real condition, and a fixture maintained in two files is the forked-data hazard
# SPEC §3.2 forbids. Its numbers, its scanned `|V|` and the reason they were scanned
# are in its docstring; nothing about the fixture changed in the move.

# One GridSim run and one PowerDynamics run of the same scenario on ONE grid, at
# the detailed tier. Same shape as `both` above and for the same reasons; it is
# separate because the engine, the tier and the perturbation channel all differ.
function both_detailed(net, tspan, grid; perturbations = (), reltol = 1.0e-9,
                       abstol = 1.0e-12, ΔPm = nothing, X_ls_frac = 0.5,
                       ψ_scale = 1.0, mutate = identity)
    eng  = init!(DetailedEngine, mutate(net); reltol = reltol, abstol = abstol)
    case = build_oracle(net; tier = :sauer_pai, perturbations = perturbations,
                        X_ls_frac = X_ls_frac)
    if ψ_scale != 1.0
        # Their two sub-transient states, seeded DELIBERATELY WRONG. See the
        # "drives nothing" testset: this is the sharp form of that claim.
        for k in eachindex(case.mach_bus)
            v = case.mach_bus[k]
            case.s0.v[v, :mach₊ψ″_d] *= ψ_scale
            case.s0.v[v, :mach₊ψ″_q] = case.s0.v[v, :mach₊ψ″_q] * ψ_scale - 0.1
        end
    end
    if ΔPm !== nothing
        # A mechanical-power step: bus-local, valid on any topology, no new event
        # type, and PARAMETERS are the sanctioned perturbation channel (SPEC §6).
        # The base value is read off the engine rather than from `Machine.P0`,
        # because at this tier the dispatch comes from the POWER FLOW.
        id, ΔP = ΔPm
        k = findfirst(m -> m.id === id, net.machines)::Int
        Pm = eng.params[eng.Pm_pidx[k]] + ΔP
        eng.params[eng.Pm_pidx[k]] = Pm
        set_mechanical_power!(case, id, Pm)
    end
    ours   = solve!(eng, tspan; perturbations = perturbations, saveat = grid)
    theirs = oracle_solve(case, tspan; saveat = grid, reltol = reltol, abstol = abstol)
    return ours, theirs
end

gap(a, b, k) = maximum(abs, getproperty(a, k) .- getproperty(b, k))
peak_slip(s, ids) = maximum(abs, vcat((getproperty(s, Symbol(:ω_, i)) for i in ids)...))
chan(k) = s -> getproperty(s, k)

# ===========================================================================
# M5 step 3 — the detailed tier against PowerDynamics, flux frozen on BOTH sides
# ===========================================================================
#
# WHY A SEPARATE STEP FROM "FLUX ON". `m5-prestudy.md` §2a establishes that
# `SauerPaiMachine` at `X″ = X′` IS our two-axis machine, line for line, with ONE
# exception: their static stator carries the rotor speed on the flux terms and
# ours does not. With `R_s = 0` their internal voltage is exactly `ω ×` ours, so
# at equal states the two terminal voltages differ by `(ω − 1)·V` — first order in
# the slip, identically zero at synchronous speed, and therefore invisible to the
# flat run, to the fixpoint residual and to every steady-state identity.
#
# That residual is IDENTIFIED BY ITS SIGNATURE, not absorbed into a band. A band
# wide enough to hide it would hide a real error of the same size. Freezing the
# flux on both sides is what makes the identification clean: it is the only
# residual left, so its linearity in slip can be measured against nothing else.
# Step 4 switches the flux on, and the CHANGE is the flux term by construction.
#
# THE ORDER MATTERS AND IT IS NOT THE PRE-STUDY'S FIRST GUESS. §7 proposed
# separating the two candidate effects by running at low loading. That does not
# separate them — flux decay scales with loading too, so both move together. The
# separator is fidelity, not loading.

@testset "M5 step 3 — PowerDynamics with the flux frozen on both sides" begin


# ===========================================================================
@testset "the detailed tier's preconditions are structural, not documented" begin
    ring = three_machine_ring()

    # Loads and machine-free buses are STEP 6, and each says so. A load quietly
    # absent from one side of a comparison is a physics disagreement that is not
    # one, which is the failure this whole tier exists to see.
    lb = load_bus_system()
    msg = argerr_msg(() -> build_oracle(lb; tier = :sauer_pai))
    @test occursin("load", msg)
    @test occursin("step 6", msg)

    # An unusable `X_ls` is refused rather than divided by. `γ_d1` divides by
    # `X′_d − X_ls` INSIDE PowerDynamics' component, so the failure mode without
    # this guard is a NaN trajectory, not an error.
    @test occursin("X_ls", argerr_msg(() -> build_oracle(ring; tier = :sauer_pai,
                                                         X_ls_frac = 1.0)))
    @test occursin("X_ls", argerr_msg(() -> build_oracle(ring; tier = :sauer_pai,
                                                         X_ls_frac = 0.0)))
    # …and the guard reaches BOTH axes: the limit is min(X′d, X′q), not X′d.
    @test all(build_oracle(ring; tier = :sauer_pai).X_ls .<
              min.(machine_arrays(ring).Xd′, machine_arrays(ring).Xq′))

    # `TripGenerator` has no counterpart our own engine can run, so a case
    # carrying one is refused at build time. An oracle case GridSim cannot run is
    # worse than no case: the missing side would be read as a fidelity finding.
    @test occursin("TripGenerator",
                   argerr_msg(() -> build_oracle(ring; tier = :sauer_pai,
                                                 perturbations = [1.0 => TripGenerator(:G1)])))

    # THE HOLE M5 STEP 2 NAMED AND LEFT OPEN. `SwingEngine` and `coi_model` refuse
    # a machine carrying detailed data; this builder — a third consumer of the same
    # frozen-flux assumption — did not, so it would have silently simulated a
    # different machine than the data describes. Core's own guard is called rather
    # than copied, which is why the message is core's.
    dp = detailed_pair()
    for tier in (:swing, :classical)
        m = argerr_msg(() -> build_oracle(dp; tier = tier))
        @test occursin("carries detailed-tier data", m)
        @test occursin("build_oracle(tier = :$tier)", m)
    end
    # …and the detailed tier accepts exactly that model. The guard is a tier
    # boundary, not a rejection of the data.
    @test build_oracle(dp; tier = :sauer_pai).tier === :sauer_pai

    @test occursin("tier must be", argerr_msg(() -> build_oracle(ring; tier = :nope)))
end

# ===========================================================================
@testset "the mapping is the X″ = X′ degeneration, and it is passed explicitly" begin
    net  = detailed_pair()
    case = build_oracle(net; tier = :sauer_pai)
    ma   = machine_arrays(net)
    for k in 1:2
        v = case.mach_bus[k]
        # Their sixth-order machine reduced to our fourth: X″ = X′ EXACTLY, in
        # both axes, which is what makes γ_1 = 1 and γ_2 = 0 exactly.
        @test case.s0.p.v[v, :mach₊X″_d] === ma.Xd′[k]
        @test case.s0.p.v[v, :mach₊X″_q] === ma.Xq′[k]
        @test case.s0.p.v[v, :mach₊X′_d] === ma.Xd′[k]
        @test case.s0.p.v[v, :mach₊X′_q] === ma.Xq′[k]
        # …and the data our tier carries reaches theirs unchanged.
        @test case.s0.p.v[v, :mach₊X_d] === ma.Xd[k]
        @test case.s0.p.v[v, :mach₊X_q] === ma.Xq[k]
        @test case.s0.p.v[v, :mach₊R_s] === ma.Ra[k]
        @test case.s0.p.v[v, :mach₊H]   === ma.H[k]
        @test case.s0.p.v[v, :mach₊D]   === ma.D[k]
    end
    # SPIKE S1, AS AN ASSERTION. They write the MULTIPLIED form
    # `T′_d0 · Dt(E′q) ~ rhs`, so `T′ = Inf` is `Inf·ẋ ~ finite` — which the
    # pre-study flagged as possibly inexpressible, with a large-but-finite
    # fallback and a `1/T′` convergence check planned instead. It IS expressible:
    # `mtkcompile` accepts it, and the frozen run below freezes `E′q` bit-exactly.
    # The fallback is not needed and the exactness assertion is available.
    frozen = build_oracle(three_machine_ring(); tier = :sauer_pai)
    for v in 1:3
        @test frozen.s0.p.v[v, :mach₊T′_d0] === Inf
        @test frozen.s0.p.v[v, :mach₊T′_q0] === Inf
    end
end

# ===========================================================================
@testset "the flat run: PowerDynamics says our detailed fixpoint is one" begin
    # THE RING, which the `:classical` tier must refuse (`_assert_radial`) and
    # this one takes: both sides put the machine behind its reactance on an
    # algebraic terminal bus, so they are handed the SAME line reactance and there
    # is no reduction to be wrong about (`m5-prestudy.md` §2a).
    net  = three_machine_ring()
    grid = collect(0.0:0.02:5.0)
    ids  = [m.id for m in net.machines]
    for (rtol, atol) in ((1.0e-9, 1.0e-12), (1.0e-6, 1.0e-9))
        o, t = both_detailed(net, (0.0, 5.0), grid; reltol = rtol, abstol = atol)
        # The channel sets must be the SAME NAMES IN THE SAME ORDER: `divergence`
        # matches two NamedTuples by key, so a channel present on one side only is
        # a silent omission rather than an error.
        @test keys(o) == keys(t)
        # ASSERTED PER STATE, never on `f_coi`. A wrong `E′d` leaves the frequency
        # flat and the voltage wrong, which is the whole reason this tier exists.
        for k in keys(o)
            k === :t && continue
            a, b = getproperty(o, k), getproperty(t, k)
            @test maximum(abs, a .- a[1]) < 1.0e-8      # ours is flat
            @test maximum(abs, b .- b[1]) < 1.0e-8      # so is theirs
            @test maximum(abs, a .- b)    < 1.0e-8      # …at the same place
        end
    end

    # POSITIVE CONTROL: the flat run can read a fixpoint that is not one. One
    # machine's seeded internal voltage is moved off ours by 1 %, so their run
    # starts away from equilibrium and leaves it.
    #
    # THE FIRST CHOICE OF CONTROL WAS VACUOUS AND THE SUITE SAID SO. Perturbing
    # `vf_set` by 1 % moves the trajectory by 8.9e-16 — nothing — because the field
    # voltage enters ONLY the flux derivative, and with `T′ = Inf` that derivative
    # is zero whatever `vf` is. A control has to act through a path the tier under
    # test actually has, and at the frozen limit the excitation is not one; `vf_set`
    # belongs on the list of parameters that reach nothing here, alongside `X_d`
    # and `X_ls`.
    case = build_oracle(net; tier = :sauer_pai)
    case.s0.v[1, :mach₊E′_q] *= 1.01
    eng  = init!(DetailedEngine, net; reltol = 1.0e-9, abstol = 1.0e-12)
    o    = solve!(eng, (0.0, 5.0); saveat = grid)
    t    = oracle_solve(case, (0.0, 5.0); saveat = grid, reltol = 1.0e-9, abstol = 1.0e-12)
    @test gap(o, t, :V_B1) > 1.0e-3                  # measured 6.9e-3
    @test maximum(abs, t.V_B1 .- t.V_B1[1]) > 1.0e-4 # measured 2.3e-4
    # …and the inert one is asserted rather than described, so the next reader does
    # not have to take "the excitation reaches nothing" on trust.
    inert = build_oracle(net; tier = :sauer_pai)
    inert.s0.p.v[1, :mach₊vf_set] *= 1.01
    ti = oracle_solve(inert, (0.0, 5.0); saveat = grid, reltol = 1.0e-9, abstol = 1.0e-12)
    @test gap(o, ti, :V_B1) < 1.0e-12
end

# ===========================================================================
@testset "the bases come from the model, at the new tier too" begin
    # PowerDynamics reads `set_Sbase!`/`set_fbase!` at COMPONENT CONSTRUCTION and
    # bakes the values in; they are process-global. A new tier is a new place for
    # that to go stale silently, so the check is re-run on a model that is on
    # NEITHER of the repo's fixture bases — against which it would be vacuous.
    net  = base_250_60()
    grid = collect(0.0:0.02:2.0)
    set_Sbase!(1.0); set_fbase!(1.0)            # deliberately wrong, before building
    o, t = both_detailed(net, (0.0, 2.0), grid)
    for k in keys(o)
        k === :t && continue
        @test maximum(abs, getproperty(o, k) .- getproperty(t, k)) < 1.0e-8
    end
    @test o.f_coi[1] ≈ 60.0
end

# ===========================================================================
@testset "the transient: the ring, and the residual that is left" begin
    net  = three_machine_ring()
    grid = collect(0.0:0.02:5.0)
    pert = [1.0 => TripLine(:B3, :B1)]
    o9, t9 = both_detailed(net, (0.0, 5.0), grid; perturbations = pert,
                           reltol = 1.0e-9, abstol = 1.0e-12)
    o5, t5 = both_detailed(net, (0.0, 5.0), grid; perturbations = pert,
                           reltol = 1.0e-5, abstol = 1.0e-8)

    # The band is derived from each side's OWN convergence and never looks at the
    # gap it judges — the structural version of "state the band before you see the
    # gap", unchanged from M4 and now with a third caller.
    for k in (:δ_G1, :ω_G1, :V_B1, :f_coi)
        band = convergence_band(o5, o9, t5, t9; channel = chan(k))
        @test band > 0
        # The gap EXCEEDS the band, and that is the expected result rather than a
        # failure: the stator-ω residual is a real modelling difference, predicted
        # from their source before it was measured. The next testset is what turns
        # that from an excuse into an identification.
        @test gap(o9, t9, k) > band
    end

    # THE DOCUMENTED INTERFACE CLAIM, EXERCISED RATHER THAN ASSERTED IN PROSE.
    # `oracle_solve`'s docstring says the output is shaped so `divergence` applies
    # across the two sides with no adapter and no resampling — and this tier adds
    # three new channel families to that shape. Matching key sets is necessary and
    # is not the same claim: `divergence` refuses two grids and reads a channel by
    # name, and neither path was touched anywhere until here.
    band = convergence_band(o5, o9, t5, t9; channel = chan(:V_B1))
    d = divergence(o9, t9; band = band, channel = chan(:V_B1))
    @test isfinite(d.max)
    @test d.max ≈ gap(o9, t9, :V_B1)
    # …and it departs, which is the expected reading here: the stator-ω residual
    # is a real difference, so a `divergence` that reported no departure would mean
    # the band had been derived from the gap it judges.
    @test isfinite(d.t_depart)
    # The grid refusal is the other half of the claim. Two runs on different grids
    # have no interpolant left to resample with, so it must throw rather than
    # quietly compare index by index.
    coarse = collect(0.0:0.04:5.0)
    o_c, _ = both_detailed(net, (0.0, 5.0), coarse; perturbations = pert,
                           reltol = 1.0e-9, abstol = 1.0e-12)
    @test_throws ArgumentError divergence(o_c, t9; band = band, channel = chan(:V_B1))

    # FROZEN MEANS FROZEN — TO ROUND-OFF, NOT TO THE BIT, AND THE DIFFERENCE IS A
    # FINDING RATHER THAN A TOLERANCE. Spike S1 showed `T′ = Inf` on their
    # MULTIPLIED form (`Inf·ẋ ~ rhs`) makes the derivative exactly zero, and on a
    # two-bus case the trajectory came back bit-identical. On the ring it does not:
    # both sides drift by one ulp (2.2e-16 on a state near 1). The cause is not the
    # equation, it is the linear algebra — `E′q` is a DIFFERENTIAL state, so it sits
    # in the implicit solver's Newton system with a zero Jacobian row, and the LU
    # that solves the coupled system mixes the other rows into it at round-off.
    #
    # The same mechanism explains why the two "reaches nothing" controls below are
    # bands rather than `===`, and why taking the adaptive error norm out of it
    # (fixed `dt`) tightens them to ~1e-15 without reaching zero. One cause, three
    # places. Measured on both sides: OURS drifts by the identical 2.2e-16, so this
    # is a property of stiff integration, not of PowerDynamics.
    for i in (m.id for m in net.machines)
        tq = getproperty(t9, Symbol("E′q_", i))
        oq = getproperty(o9, Symbol("E′q_", i))
        @test maximum(abs, tq .- tq[1]) < 1.0e-14
        @test maximum(abs, oq .- oq[1]) < 1.0e-14
        @test maximum(abs, getproperty(t9, Symbol("E′d_", i))) < 1.0e-14
        @test maximum(abs, getproperty(o9, Symbol("E′d_", i))) < 1.0e-14
    end
end

# ===========================================================================
@testset "the stator-ω residual, identified by its signature" begin
    # THE PREDICTION, WRITTEN BEFORE THE MEASUREMENT. Their static stator carries
    # the rotor speed on the flux terms and ours does not, so with `R_s = 0` their
    # internal voltage is exactly `ω ×` ours and the terminal-voltage residual is
    # `(ω − 1)·V` — FIRST ORDER IN SLIP, coefficient of order one, zero at
    # synchronous speed. So: double the disturbance, double the gap; and the gap
    # divided by (peak slip × |V|) is ≈ 1 and not ≈ 0.01 or ≈ 100.
    #
    # A MAGNITUDE BOUND WOULD BE VACUOUS HERE and that is the point of doing it
    # this way. The residual vanishes identically at ω = 1, so a gentle enough
    # scenario makes any "the gap is small" assertion pass against a bug of the
    # same size. Only the SCALING can tell the predicted residual from an unknown
    # one — the shape M4's D14 already proved works on this pair.
    net  = three_machine_ring()
    grid = collect(0.0:0.02:5.0)
    ids  = [m.id for m in net.machines]
    slips = Float64[]
    gaps  = Float64[]
    for ΔP in (0.02, 0.04, 0.08)
        o, t = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, ΔP))
        push!(slips, peak_slip(o, ids))
        push!(gaps,  gap(o, t, :V_B1))
    end
    # Linear in slip over a factor of four in disturbance size.
    @test gaps[2] / gaps[1] ≈ slips[2] / slips[1] rtol = 0.02
    @test gaps[3] / gaps[2] ≈ slips[3] / slips[2] rtol = 0.02
    @test gaps[2] / gaps[1] ≈ 2.0 rtol = 0.02
    # …and the COEFFICIENT is the predicted one, not merely proportional. `|V|` is
    # within a per cent of 1 pu here, so the ratio is the coefficient itself.
    for (s, g) in zip(slips, gaps)
        @test g / s ≈ 1.0 rtol = 0.05
    end
    # The residual is a VOLTAGE residual, which is why `V` is the channel it is
    # read on: on the speed channel it is three orders smaller, because a stator
    # voltage error reaches the rotor only through the power balance.
    o, t = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.08))
    @test gap(o, t, :ω_G1) < gap(o, t, :V_B1) / 100
end

# ===========================================================================
@testset "the degeneration took: two parameters that must reach nothing" begin
    # THE FREE POSITIVE CONTROL (`m5-prestudy.md` §2a). `X_ls` is a parameter of
    # THEIR component that survives nowhere in the degeneration: γ_1 = 1 and
    # γ_2 = 0 are independent of it, the `E′` brackets reduce to `I_d`/`I_q`, and
    # the flux linkages lose their `ψ″` terms. So varying it across a run must
    # change nothing — and if anything moves, γ_d1 ≠ 1 and the degeneration did
    # not take. It costs one extra solve and it tests the assumption every flux
    # oracle in this milestone rests on.
    #
    # WHY THIS IS A BAND AND NOT `===`. The pre-study asked for bit-identity. It
    # is not available, and the reason is worth more than the assertion would
    # have been: their two `ψ″` states are DIFFERENTIAL, so they sit in the
    # implicit solver's Newton system even though nothing reads them. Changing
    # `X_ls` changes their trajectory, and the LU that solves the coupled system
    # mixes those rows into every other component at round-off. Measured both
    # ways: adaptive stepping gives ~1e-10 on `V`, and taking the adaptive error
    # norm out of it entirely (fixed `dt`) still gives ~1e-15 rather than zero.
    # So the coupling is floating-point, not physical, and the honest statement of
    # that is "below the band", derived as every other band here is.
    net  = three_machine_ring()
    grid = collect(0.0:0.02:5.0)
    o5, t5 = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04),
                           reltol = 1.0e-5, abstol = 1.0e-8)
    o9, t9 = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04),
                           reltol = 1.0e-9, abstol = 1.0e-12)
    for frac in (0.1, 0.9)
        _, alt = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04),
                               X_ls_frac = frac)
        for k in (:ω_G1, :V_B1, :f_coi, :E′q_G1)
            band = convergence_band(o5, o9, t5, t9; channel = chan(k))
            @test maximum(abs, getproperty(t9, k) .- getproperty(alt, k)) < band
        end
    end

    # THE SHARPER FORM OF THE SAME CLAIM. Varying `X_ls` moves the seed and the
    # equation consistently, so `ψ″` may barely leave equilibrium and the control
    # above can pass without exercising much. Seeding those two states DELIBERATELY
    # WRONG — doubled, and one of them shifted off zero — is the maximum-signal
    # version: if they drove anything at all, this would move it.
    _, wrong = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04), ψ_scale = 2.0)
    for k in (:ω_G1, :V_B1, :f_coi, :E′q_G1)
        band = convergence_band(o5, o9, t5, t9; channel = chan(k))
        @test maximum(abs, getproperty(t9, k) .- getproperty(wrong, k)) < band
    end

    # AND WHAT STEP 3 THEREFORE DOES NOT CHECK, asserted rather than implied.
    # With the flux frozen, `(X_d − X′_d)` is multiplied by a zero derivative on
    # our side and divided by `Inf` on theirs, so the synchronous reactances reach
    # nothing. Step 4 is where they become live, and this is the statement of what
    # step 4 has left to earn.
    ring = three_machine_ring()
    big  = NetworkModel(ring.S_base, ring.f0, ring.buses, ring.branches,
                        [Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, m.P0,
                                 m.R, m.Pmax, m.Tg; Xd = 4 * m.Xd′, Xq = m.Xq,
                                 Xq′ = m.Xq′, Td0′ = m.Td0′, Tq0′ = m.Tq0′, Ra = m.Ra)
                         for m in ring.machines])
    _, tb = both_detailed(big, (0.0, 5.0), grid; ΔPm = (:G1, 0.04))
    for k in (:ω_G1, :V_B1, :f_coi)
        @test all(getproperty(t9, k) .=== getproperty(tb, k))
    end
end

# ===========================================================================
@testset "the sample-row mapping refuses what it says it refuses" begin
    # THREE THROWS THAT NOTHING ELSE REACHES. `_sample_rows` is the guard against a
    # future solver option silently reintroducing interpolation — the M4 step 3
    # failure it was written for — and a guard nobody has seen fire is a guard
    # nobody knows fires. Called directly with hand-built sample times, because
    # provoking these through a solve would mean deliberately misconfiguring one.
    f = GridSimReference._sample_rows
    grid = [0.0, 0.1, 0.2]
    # The ordinary case, and the duplicate an event instant produces: the FIRST row
    # at a repeated time is taken, which is the pre-event sample.
    @test f([0.0, 0.1, 0.2], grid) == [1, 2, 3]
    @test f([0.0, 0.1, 0.1, 0.2], grid) == [1, 2, 4]
    # A stored time nobody asked for — what a `tstop` that also saves, or
    # `save_everystep`, would produce.
    @test_throws ErrorException f([0.0, 0.05, 0.1, 0.2], grid)
    # A solve that stopped early.
    @test_throws ErrorException f([0.0, 0.1], grid)
    # Samples beyond the end of the grid.
    @test_throws ErrorException f([0.0, 0.1, 0.2, 0.3], grid)
end

# ===========================================================================
@testset "anti-vacuity: the external check can go red, and where" begin
    # THIS TESTSET CHANGED SHAPE TWICE UNDER MEASUREMENT, AND THAT IS THE RESULT.
    # The plan asked for "perturb one coefficient in our stator algebra; the
    # external check must go red". Two candidate mutations turned out to be
    # invisible on the channel they were aimed at, and finding out WHY is worth
    # more than the assertion would have been:
    #
    #   * A 1 % error in `X′q` does almost nothing, because at this degeneration
    #     `X′q = X′d` and the initialisation re-derives `E′d`/`E′q` consistently —
    #     so the terminal current at t = 0 is unchanged and only a second-order
    #     saliency term moves.
    #   * A 1 % error in `X′d` does nothing to the VOLTAGE at all (1.6e-15, i.e.
    #     the honest gap), for the same reason: `E′q = Vq + X′d·I_d` is computed
    #     FROM the power flow, so a different `X′d` buys a compensating `E′q` and
    #     the same terminal behaviour.
    #
    # The mutation is caught — on the state that absorbed it. That is the measured
    # justification for the plan's rule "assert per state, never on an aggregate":
    # here it is not `f_coi` that hides the error, it is `V`.
    net  = three_machine_ring()
    grid = collect(0.0:0.02:5.0)
    flat(nm) = begin
        e = init!(DetailedEngine, nm; reltol = 1.0e-9, abstol = 1.0e-12)
        c = build_oracle(net; tier = :sauer_pai)   # ALWAYS the unmutated model
        (solve!(e, (0.0, 5.0); saveat = grid),
         oracle_solve(c, (0.0, 5.0); saveat = grid, reltol = 1.0e-9, abstol = 1.0e-12))
    end
    remach(n, f) = NetworkModel(n.S_base, n.f0, n.buses, n.branches,
        [f(m) for m in n.machines])

    o0, t0 = flat(net)                              # the honest flat run

    # (1) A STATOR COEFFICIENT: `X′d` 1 % low on our side only. Invisible on `V`
    # and on `δ`; caught on `E′q` by twelve orders of magnitude.
    Xd′_low = remach(net, m -> Machine(m.id, m.bus, m.S_rated, m.H, m.D, 0.99 * m.Xd′,
                                       m.E′, m.P0, m.R, m.Pmax, m.Tg;
                                       Xd = m.Xd, Xq = m.Xq, Xq′ = m.Xq′,
                                       Td0′ = m.Td0′, Tq0′ = m.Tq0′, Ra = m.Ra))
    o1, t1 = flat(Xd′_low)
    @test gap(o1, t1, :E′q_G1) > 1.0e-5             # measured 1.6e-4
    @test gap(o1, t1, :E′q_G1) > 1.0e10 * gap(o0, t0, :E′q_G1)
    @test gap(o1, t1, :V_B1)   < 1.0e-12            # …and V cannot see it at all
    # Linear in the error, which is what says the channel is reading the mutation
    # rather than something that happens to move with it.
    Xd′_lower = remach(net, m -> Machine(m.id, m.bus, m.S_rated, m.H, m.D, 0.80 * m.Xd′,
                                         m.E′, m.P0, m.R, m.Pmax, m.Tg;
                                         Xd = m.Xd, Xq = m.Xq, Xq′ = m.Xq′,
                                         Td0′ = m.Td0′, Tq0′ = m.Tq0′, Ra = m.Ra))
    o2, t2 = flat(Xd′_lower)
    @test gap(o2, t2, :E′q_G1) / gap(o1, t1, :E′q_G1) ≈ 20.0 rtol = 0.05

    # (2) A MAPPING ERROR: one branch reactance 1 % high on our side only. This is
    # the class the oracle exists for — the graph, the per-branch mapping, the
    # sign of an edge — and it lands on `V`, by ten orders.
    Xline = NetworkModel(net.S_base, net.f0, net.buses,
                         [Branch(b.id, b.from, b.to, 1.01 * b.X, b.rating)
                          for b in net.branches], net.machines)
    o3, t3 = flat(Xline)
    @test gap(o3, t3, :V_B1) > 1.0e-6               # measured 2.5e-5
    @test gap(o3, t3, :V_B1) > 1.0e9 * gap(o0, t0, :V_B1)
    # A tenth of that error is still eight orders clear of the honest gap, so the
    # sensitivity is not a cliff sitting just under 1 %.
    Xline10 = NetworkModel(net.S_base, net.f0, net.buses,
                           [Branch(b.id, b.from, b.to, 1.001 * b.X, b.rating)
                            for b in net.branches], net.machines)
    o4, t4 = flat(Xline10)
    @test gap(o4, t4, :V_B1) > 1.0e8 * gap(o0, t0, :V_B1)

    # (3) THE RESOLUTION LIMIT OF THE TRANSIENT COMPARISON, ASSERTED RATHER THAN
    # CAVEATED. On the transient voltage channel the predicted stator-ω residual is
    # ~2.8e-3, and a TWENTY per cent error in `X′d` moves our own trajectory by only
    # ~4.8e-4 — so the transient `V` gap genuinely cannot see it, and any test that
    # claimed otherwise would be reading noise. This is the honest boundary of what
    # step 3 establishes: with the flux frozen, the synchronous and transient
    # reactances are pinned by the FLAT run's per-state comparison and by nothing
    # else. Step 4 switches the flux on, which is what makes `(X_d − X′_d)` live and
    # gives those reactances a transient check.
    trans(nm) = begin
        e = init!(DetailedEngine, nm; reltol = 1.0e-9, abstol = 1.0e-12)
        c = build_oracle(net; tier = :sauer_pai)
        Pm = e.params[e.Pm_pidx[1]] + 0.08
        e.params[e.Pm_pidx[1]] = Pm
        set_mechanical_power!(c, :G1, Pm)
        (solve!(e, (0.0, 5.0); saveat = grid),
         oracle_solve(c, (0.0, 5.0); saveat = grid, reltol = 1.0e-9, abstol = 1.0e-12))
    end
    oh, th = trans(net)
    om, tm = trans(Xd′_lower)
    # The mutation IS applied — our own trajectory moves by ~4.8e-4. Without this
    # line the assertion below would also pass if the mutation had silently stopped
    # being applied, which would make "the comparison cannot see it" a coincidence
    # rather than a measurement.
    @test maximum(abs, om.V_B1 .- oh.V_B1) > 1.0e-4
    # …and the transient comparison still cannot see it.
    @test gap(om, tm, :V_B1) ≈ gap(oh, th, :V_B1) rtol = 0.1
end

end # M5 step 3
