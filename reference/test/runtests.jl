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
