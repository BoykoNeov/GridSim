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
# M6 step 4, oracle B. Same aliases the module itself uses and for the same reason:
# `ACPowerFlow` and `DCPowerFlow` are names GridSim already owns, and a `using` on
# either package would make both ambiguous here.
import PowerSystems as PSY
import PowerFlows as PF

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

    # Loads and machine-free buses were STEP 6 and are BUILT as of step 6, so what
    # stands here is the lifted form: this tier now takes both. The checks that
    # they are mapped CORRECTLY live in step 6's own block at the bottom of this
    # file; what is asserted here is only that the refusal is gone, because a
    # lifted precondition nothing asserts is one that can come back by accident.
    @test build_oracle(load_bus_system(); tier = :sauer_pai) isa OracleCase

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

# ===========================================================================
# M5 step 4 — the same two implementations, with the flux equations LIVE
# ===========================================================================
#
# WHAT THIS ADDS TO STEP 3, IN ONE SENTENCE: step 3 ran with `T′ = Inf` on both
# sides, where `(Xd − X′d)` and `(Xq − X′q)` are multiplied by a zero derivative
# and reach nothing — and it ASSERTED that blindness (a ×4 `Xd` left every channel
# bit-identical). Here the same comparison runs on a machine whose flux moves, so
# the flux equations get an external check with the mechanism switched on, and the
# CHANGE from step 3 is the flux term by construction (`m5-context.md` D6).
#
# The fixture is `detailed_pair()`, which step 3 built and never ran dynamically:
# `Xd = 1.8`, `Xq = 1.7` and `T′do = 8 s`, `T′qo = 0.4 s` on `G1`, against a
# frozen-flux `G2`. Its `E′d = 0.184` at the solved point, so the saliency and the
# q-axis flux are live rather than decorative.
#
# THE PREDICTION FOR THE RESIDUAL, WRITTEN BEFORE IT WAS MEASURED. Switching the
# flux on adds a SECOND route by which their stator `ω` reaches the comparison:
# their `I_d` differs from ours by O(slip), and `I_d` drives the flux equation. So
# the coefficient need not be step 3's 0.995 — but the residual must still be
# FIRST ORDER IN SLIP with a coefficient of order one, because both routes are.
# ===========================================================================

@testset "M5 step 4 — PowerDynamics with the flux LIVE" begin

# ===========================================================================
@testset "the flat run, on a fixture whose flux fixpoint is a real condition" begin
    # Step 3's flat run was on the ring, where every flux derivative is
    # identically zero and the fixpoint's flux part reads `0 = 0`. Here it does
    # not: `E′d = (Xq − X′q)·Iq` is a condition the initialisation has to satisfy,
    # and it is satisfied on OUR side by construction and on theirs by their own
    # equations agreeing with it.
    net  = detailed_pair()
    grid = collect(0.0:0.02:5.0)
    for (rt, at) in ((1.0e-9, 1.0e-12), (1.0e-6, 1.0e-9))
        o, t = both_detailed(net, (0.0, 5.0), grid; reltol = rt, abstol = at)
        @test keys(o) == keys(t)
        for k in keys(o)
            k === :t && continue
            a, b = getproperty(o, k), getproperty(t, k)
            @test maximum(abs, a .- a[1]) < 1.0e-8      # ours is flat
            @test maximum(abs, b .- b[1]) < 1.0e-8      # so is theirs
            @test maximum(abs, a .- b)    < 1.0e-8      # …at the same place
        end
        # …and the fixture is not a frozen machine wearing detailed data.
        @test abs(o.E′d_G1[1]) > 0.15                   # measured 0.184
    end
end

# ===========================================================================
@testset "the transient: the flux channel is now READABLE, and the residual keeps its signature" begin
    net  = detailed_pair()
    grid = collect(0.0:0.02:5.0)
    ids  = [m.id for m in net.machines]
    slips = Float64[]; gapsV = Float64[]; gapsE = Float64[]; flux = Float64[]
    for ΔP in (0.02, 0.04, 0.08)
        o9, t9 = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, ΔP))
        o5, t5 = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, ΔP),
                               reltol = 1.0e-5, abstol = 1.0e-8)
        push!(slips, peak_slip(o9, ids))
        push!(gapsV, gap(o9, t9, :V_B1))
        push!(gapsE, gap(o9, t9, :E′q_G1))
        push!(flux,  maximum(abs, o9.E′q_G1 .- o9.E′q_G1[1]))
        # THE FLUX CHANNEL CARRIES A RESOLVED COMPARISON, which is the whole point
        # of the step. In step 3 this same channel's gap was 2.2e-16 — round-off,
        # a number with no information in it. Here it is 191-424 bands.
        @test gapsE[end] > 100 * convergence_band(o5, o9, t5, t9; channel = chan(:E′q_G1))
        @test gapsV[end] > 100 * convergence_band(o5, o9, t5, t9; channel = chan(:V_B1))
    end
    # OUR OWN SIDE'S LINEARITY CONTROL, RUN FIRST. If the gap ratios below failed,
    # this is what says whether the residual went nonlinear or the physics did.
    @test slips[2] / slips[1] ≈ 2.0 rtol = 0.01
    @test slips[3] / slips[2] ≈ 2.0 rtol = 0.01
    # …and the flux is genuinely moving, so "the flux equations are checked here"
    # is a measurement rather than a hope.
    @test all(f -> f > 2.0e-3, flux)                    # measured 2.3e-3 … 9.7e-3

    # THE RESIDUAL, still first order in slip and still order one.
    @test gapsV[2] / gapsV[1] ≈ 2.0 rtol = 0.02
    @test gapsV[3] / gapsV[2] ≈ 2.0 rtol = 0.02
    for (s, g) in zip(slips, gapsV)
        @test g / s ≈ 1.0 rtol = 0.05                   # measured 1.0067, 1.0065, 1.0060
    end
    # The flux-channel gap scales the same way, which is what says it comes from
    # the same `ω` and not from a second, unidentified difference.
    @test gapsE[2] / gapsE[1] ≈ 2.0 rtol = 0.02
    @test gapsE[3] / gapsE[2] ≈ 2.0 rtol = 0.02
    # WHAT IS NOT CLAIMED. The coefficient here (1.006) is not step 3's (0.995),
    # and the difference is NOT attributed to the flux: this is a different fixture
    # as well as a different fidelity, and one number cannot be told from the other
    # by a run that changes both. What IS asserted is that both are order one and
    # that this one is stable to 7e-4 across a factor of four in disturbance size.
    @test maximum(gapsV ./ slips) - minimum(gapsV ./ slips) < 2.0e-3  # measured 7e-4
end

# ===========================================================================
@testset "the step-3 mirror: Xd reached NOTHING frozen, and reaches something now" begin
    # STEP 3 ASSERTED `all(t9 .=== tb)` FOR A ×4 `Xd`, and closed that testset with
    # "step 4 is what makes `(X_d − X′_d)` live". This is the same assertion with
    # the flux switched on, on ONE fixture with `T′` as the only difference — so
    # the `===` turning into a measured move is attributable to the flux equation
    # and to nothing else.
    net  = detailed_pair()
    grid = collect(0.0:0.02:5.0)
    frozen = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
        [Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, m.P0, m.R, m.Pmax,
                 m.Tg; Xd = m.Xd, Xq = m.Xq, Xq′ = m.Xq′, Td0′ = Inf, Tq0′ = Inf,
                 Ra = m.Ra) for m in net.machines])
    mutXd(nm, f) = NetworkModel(nm.S_base, nm.f0, nm.buses, nm.branches,
        [Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, m.P0, m.R, m.Pmax,
                 m.Tg; Xd = m.id === :G1 ? f * m.Xd : m.Xd, Xq = m.Xq, Xq′ = m.Xq′,
                 Td0′ = m.Td0′, Tq0′ = m.Tq0′, Ra = m.Ra) for m in nm.machines])

    # FROZEN: bit-identical, on THEIR side, at 1 % — the same claim step 3 made at
    # ×4 and on the ring, re-made here so the two halves share a fixture.
    _, tf  = both_detailed(frozen, (0.0, 5.0), grid; ΔPm = (:G1, 0.04))
    _, tfm = both_detailed(mutXd(frozen, 0.99), (0.0, 5.0), grid; ΔPm = (:G1, 0.04))
    for k in (:V_B1, :ω_G1, :f_coi)
        @test all(getproperty(tf, k) .=== getproperty(tfm, k))
    end

    # LIVE: it moves, and by 12.7 bands on the voltage channel.
    o5, t5 = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04),
                           reltol = 1.0e-5, abstol = 1.0e-8)
    o9, t9 = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04))
    _, tm  = both_detailed(mutXd(net, 0.99), (0.0, 5.0), grid; ΔPm = (:G1, 0.04))
    bandV = convergence_band(o5, o9, t5, t9; channel = chan(:V_B1))
    @test maximum(abs, t9.V_B1 .- tm.V_B1) > 10 * bandV     # measured 12.7 bands
    @test !all(t9.V_B1 .=== tm.V_B1)

    # AND THE CHANNEL THAT HIDES IT, asserted rather than left to be discovered.
    # A 1 % `Xd` error is 12.7 bands on the bus voltage and BELOW the band on
    # `f_coi` — a hundredth of it. This is the third distinct shape of the same
    # lesson: step 3 found `V` hiding a stator error that `E′q` showed; here it is
    # the aggregate frequency hiding a flux error that `V` shows. "Assert per
    # state" is not a style preference in this tier.
    bandF = convergence_band(o5, o9, t5, t9; channel = chan(:f_coi))
    @test maximum(abs, t9.f_coi .- tm.f_coi) < bandF        # measured 0.01 bands
end

# ===========================================================================
@testset "the degeneration still took, with the flux live" begin
    # `X_ls` IS THE FREE POSITIVE CONTROL, and switching the flux on is exactly the
    # kind of change that could quietly break the `X″ = X′` reduction it tests:
    # `γ_d2` multiplies `ψ″_d` INSIDE the `E′q` equation, which step 3 ran with a
    # zero derivative in front of it. It is zero for reasons independent of `T′`,
    # and that is now measured rather than argued.
    net  = detailed_pair()
    grid = collect(0.0:0.02:5.0)
    o5, t5 = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04),
                           reltol = 1.0e-5, abstol = 1.0e-8)
    o9, t9 = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04))
    for frac in (0.1, 0.9)
        _, alt = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04),
                               X_ls_frac = frac)
        for k in (:V_B1, :E′q_G1, :f_coi)
            band = convergence_band(o5, o9, t5, t9; channel = chan(k))
            @test maximum(abs, getproperty(t9, k) .- getproperty(alt, k)) < band
        end
    end
    # …and their two sub-transient states still drive nothing, seeded ×2 and
    # shifted — the sharp form, re-run because "decoupled" was established with a
    # frozen `E′` equation and the coupling that would break it is in that equation.
    _, wrong = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04), ψ_scale = 2.0)
    for k in (:V_B1, :E′q_G1, :f_coi)
        band = convergence_band(o5, o9, t5, t9; channel = chan(k))
        @test maximum(abs, getproperty(t9, k) .- getproperty(wrong, k)) < band
    end
end

# ===========================================================================
@testset "anti-vacuity: a flux datum wrong on our side only, and the axis it lands on" begin
    # THE MEASURED RESULT OF THIS TESTSET IS A TABLE, AND THE TABLE IS THE FINDING.
    # Three flux data are perturbed on OUR side only (the oracle is always built
    # from the unmutated model), and each lands on ONE channel:
    #
    #   mutation      V_B1   E′q_G1   E′d_G1   f_coi        honest gap = ×1.0
    #   Td0′ × 1.10   ×0.9   ×14.8    ×2.8     ×1.0
    #   Xd   × 0.90   ×0.9   ×27.0    ×4.6     ×1.0
    #   Tq0′ × 1.10   ×1.0   ×1.9     ×13.6    ×1.0
    #
    # Two things follow, and neither was on the plan's list. The d-axis and the
    # q-axis flux errors are told apart BY CHANNEL — `E′q` for one, `E′d` for the
    # other — so a per-state comparison does not merely catch more, it says which
    # equation is wrong. And the terminal voltage sees NONE of them, because the
    # stator-`ω` residual on that channel (2.0e-3) is a hundred times larger than
    # anything a flux error does to it. The aggregate frequency sees nothing at all.
    net  = detailed_pair()
    grid = collect(0.0:0.02:5.0)
    remach(n, f) = NetworkModel(n.S_base, n.f0, n.buses, n.branches,
                                [f(m) for m in n.machines])
    tweak(; Xd = 1.0, Td = 1.0, Tq = 1.0) = m ->
        Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, m.P0, m.R, m.Pmax,
                m.Tg; Xd = m.id === :G1 ? Xd * m.Xd : m.Xd, Xq = m.Xq, Xq′ = m.Xq′,
                Td0′ = m.id === :G1 ? Td * m.Td0′ : m.Td0′,
                Tq0′ = m.id === :G1 ? Tq * m.Tq0′ : m.Tq0′, Ra = m.Ra)

    o0, t0 = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04))
    honest = Dict(k => gap(o0, t0, k) for k in (:V_B1, :E′q_G1, :E′d_G1, :f_coi))

    # `mutate` puts the error on the ENGINE's model and leaves the oracle's alone —
    # `both_detailed`'s own channel for exactly this, unchanged since step 3.
    run_mut(mk) = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G1, 0.04),
                                mutate = nm -> remach(nm, mk))

    for (mk, chan_hit, hit, name) in ((tweak(Td = 1.10), :E′q_G1, 8.0,  "Td0′"),
                                      (tweak(Xd = 0.90), :E′q_G1, 10.0, "Xd"),
                                      (tweak(Tq = 1.10), :E′d_G1, 8.0,  "Tq0′"))
        o, t = run_mut(mk)
        # It goes red, on the axis it belongs to.
        @test gap(o, t, chan_hit) > hit * honest[chan_hit]
        # It does NOT go red on the terminal voltage or on the aggregate — measured,
        # so "the comparison is blind here" is a number rather than a caveat.
        @test gap(o, t, :V_B1)  < 1.2 * honest[:V_B1]
        @test gap(o, t, :f_coi) < 1.05 * honest[:f_coi]
        # THE CONTROL THAT SEPARATES "INVISIBLE" FROM "NOT APPLIED". Without this
        # line the two assertions above would also pass if the mutation had quietly
        # stopped being built. Our own trajectory moves in every case.
        @test maximum(abs, o.V_B1 .- o0.V_B1) > 1.0e-5
    end
    # …and the two axes are separated rather than merely both visible: the q-axis
    # time constant is 13.6 bands-worth on `E′d` and under two on `E′q`.
    oq, tq = run_mut(tweak(Tq = 1.10))
    @test gap(oq, tq, :E′q_G1) < 3.0 * honest[:E′q_G1]

    # THE RESOLUTION OF THIS ORACLE ON THE FLUX EQUATIONS, STATED AS A NUMBER. At
    # 1 % the same mutation is only twice the honest gap, because the honest gap on
    # `E′q` is not solver noise — it is the stator-`ω` residual arriving through
    # `I_d`. So the external check pins the flux data to roughly ten per cent, and
    # what pins them to 1e-4 is the CLOSED FORM in `test/m5_detailed.jl`. Three
    # oracles, three different resolutions, none of them redundant.
    o1, t1 = run_mut(tweak(Xd = 0.99))
    @test gap(o1, t1, :E′q_G1) > 1.5 * honest[:E′q_G1]      # measured 2.1×
    @test gap(o1, t1, :E′q_G1) < 5.0 * honest[:E′q_G1]
end

end # M5 step 4

# ===========================================================================
# M5 step 5 — the UNLIMITED exciter against PowerDynamics' AVRTypeI
# ===========================================================================
#
# WHAT IS COMPARED, AND WHAT DELIBERATELY IS NOT. Our exciter is one lag with hard
# limits on the field voltage. `AVRTypeI` degenerates onto the lag exactly
# (`Kf = 0`, `Se1 = Se2 = 0`, `Ke = 1`, `tmeas_lag = false`, `Ta → 0`) and does NOT
# have our limits: theirs sit on the regulator output `vr`, one block upstream. So
# the LIMITED exciter is refused by `build_oracle(tier = :sauer_pai_avr)` by name,
# and gets its check from a closed form in the core suite instead — which is four
# orders sharper than this comparison anyway. This is the unlimited loop only.
#
# THE FIXTURE IS `infinite_bus_system`, NOT `regulator_bus_system`, and the reason
# is structural rather than a preference: `_assert_sauer_pai_tier` refuses a
# machine-free bus, and the three-path fixture's junctions are exactly that. Two
# buses, two machines, no load — which also means a line trip would island the
# machine, so the disturbance is a **setpoint step**: a parameter on our side
# (`Vref_pidx`) and a parameter on theirs (`gen₊avr₊vref`), needing no event type.
#
# AND IT MAKES THE COMPARISON UNUSUALLY CLEAN. At zero loading `ω ≡ 1` exactly on
# both sides, so the stator-`ω` residual that held M5 step 4's external oracle to
# ~10 % vanishes IDENTICALLY here. The only difference left between the two models
# is the exciter's own extra lag.
#
# THE BAND, DERIVED AND WRITTEN BEFORE THE GAP WAS SEEN. `Ta → 0` is a LIMIT, not a
# setting — their `Ta` multiplies a derivative, so zero would change the structure
# of their model — which means this comparison is one lag richer than ours by
# construction. To first order the extra lag delays the amplifier by `Ta`, so the
# field-voltage gap is `≈ Ta·dEfd/dt ≈ Ta·K_A·ΔVref/T_E`, and against the
# excursion itself (`≈ K_A·ΔVref/(1 + G)`, with `G` the DC loop gain) the
# RELATIVE gap is
#
#     Ta·(1 + G)/T_E
#
# That is a prediction with `Ta` in it, so the check that matters is not its size
# but its SIGNATURE: halve `Ta` and the gap halves. A tolerance cannot be wrong in
# a way a signature cannot.
# ===========================================================================

# One GridSim run and one PowerDynamics run of the same setpoint step, on one grid.
function both_avr(net, tspan, grid; ΔVref = 0.02, avr_Ta = 0.001,
                  reltol = 1.0e-9, abstol = 1.0e-12)
    eng  = init!(DetailedEngine, net; slack = :G_inf, reltol = reltol, abstol = abstol)
    case = build_oracle(net; tier = :sauer_pai_avr, avr_Ta = avr_Ta)
    # THE STEP GOES IN ON BOTH SIDES FROM THE SAME NUMBER. `Vref` is DERIVED at
    # initialisation on our side, so it is read off the engine rather than
    # recomputed here — the two sides cannot come to disagree about what the
    # pre-disturbance setpoint was.
    k, v = 1, case.mach_bus[1]
    Vref = eng.params[eng.Vref_pidx[k]] + ΔVref
    eng.params[eng.Vref_pidx[k]] = Vref
    case.s0.p.v[v, :gen₊avr₊vref] = Vref
    ours   = solve!(eng, tspan; saveat = grid)
    theirs = oracle_solve(case, tspan; saveat = grid, reltol = reltol, abstol = abstol)
    return ours, theirs, case
end

@testset "M5 step 5 — the unlimited exciter against AVRTypeI" begin

# ===========================================================================
@testset "the flat run: two exciters at rest at the same point" begin
    # Before anything moves, the seeding has to be right: their `vfout` and `vr`
    # both sit at OUR dispatched field voltage, and their `vref` is OUR derived
    # setpoint. If any of the three were off, this run would show a startup
    # transient on one side only — which is exactly what a supplied (rather than
    # derived) setpoint would produce, and the reason ours is derived.
    net  = infinite_bus_system(; K_A = 20.0, T_E = 0.5)
    grid = collect(0.0:0.05:10.0)
    for (rt, at) in ((1.0e-9, 1.0e-12), (1.0e-6, 1.0e-9))
        o, t, _ = both_avr(net, (0.0, 10.0), grid; ΔVref = 0.0, reltol = rt, abstol = at)
        @test keys(o) == keys(t)
        for k in keys(o)
            k === :t && continue
            a, b = getproperty(o, k), getproperty(t, k)
            @test maximum(abs, a .- a[1]) < 1.0e-8       # ours is flat
            @test maximum(abs, b .- b[1]) < 1.0e-8       # so is theirs
            @test maximum(abs, a .- b)    < 1.0e-8       # …at the same place
        end
        # …and the exciter is actually armed, not a fixed field wearing its name.
        @test machine_arrays(net).K_A[1] == 20.0
        @test machine_arrays(net).T_E[1] == 0.5
    end
end

# ===========================================================================
@testset "the setpoint step: the gap is FIRST ORDER IN Ta, and halves with it" begin
    net  = infinite_bus_system(; K_A = 20.0, T_E = 0.5)
    grid = collect(0.0:0.02:10.0)
    ma   = machine_arrays(net)
    Xe   = net.branches[1].X + ma.Xd′[2]
    G    = ma.K_A[1] * Xe / (Xe + ma.Xd[1])
    @test Xe ≈ 0.25 atol = 1.0e-12
    @test G ≈ 5.1546 rtol = 1.0e-4

    ΔV = 0.02
    excursion = ma.K_A[1] * ΔV / (1 + G)                 # the closed-loop DC move
    gaps = Float64[]
    for Ta in (0.001, 0.0005)
        o, t, case = both_avr(net, (0.0, 10.0), grid; ΔVref = ΔV, avr_Ta = Ta)
        @test case.avr_Ta == Ta
        @test case.regulated == [true, false]            # G_inf got an AVRFixed
        # The machine really did move, on both sides, by the predicted amount.
        @test o.Efd_G1[end] - o.Efd_G1[1] ≈ excursion rtol = 1.0e-3
        @test t.Efd_G1[end] - t.Efd_G1[1] ≈ excursion rtol = 1.0e-3
        push!(gaps, gap(o, t, :Efd_G1))
        # THE BAND, from the formula above and not from the gap.
        @test gaps[end] < 3 * Ta * (1 + G) / ma.T_E[1] * excursion
    end
    # ── THE SIGNATURE. Halving `Ta` halves the gap; a difference that behaved
    #    otherwise would not be the missing amplifier lag.
    @test gaps[2] / gaps[1] ≈ 0.5 rtol = 0.15
    # …and it is a resolved comparison rather than round-off: the gap is far above
    # what either side's own convergence would explain.
    @test gaps[1] > 1.0e-6

    # ── THE STATOR-ω RESIDUAL IS ABSENT HERE, AND THAT IS ASSERTED, NOT ASSUMED.
    #    It is the term that held step 4's external oracle to ~10 %, it is first
    #    order in slip, and at zero loading the rotor does not move at all.
    o, t, _ = both_avr(net, (0.0, 10.0), grid; ΔVref = ΔV, avr_Ta = 0.001)
    @test maximum(abs, o.ω_G1) < 1.0e-12
    @test maximum(abs, t.ω_G1) < 1.0e-12
    @test maximum(abs, o.δ_G1 .- o.δ_G1[1]) < 1.0e-9
end

# ===========================================================================
@testset "the tier refuses what it cannot compare, by name" begin
    # A LIMITED exciter has no counterpart: their limits are on `vr`, ours on
    # `Efd`. Refused rather than compared, because the gap would be read as a
    # fidelity finding.
    lim = infinite_bus_system(; K_A = 20.0, T_E = 0.5)
    lim2 = NetworkModel(lim.S_base, lim.f0, lim.buses, lim.branches,
        [Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, m.P0, m.R, m.Pmax,
                 m.Tg; Xd = m.Xd, Xq = m.Xq, Xq′ = m.Xq′, Td0′ = m.Td0′,
                 Tq0′ = m.Tq0′, Ra = m.Ra, K_A = m.K_A, T_E = m.T_E,
                 Efd_min = m.Efd_min, Efd_max = m.id === :G1 ? 2.0 : m.Efd_max)
         for m in lim.machines])
    @test_throws ArgumentError build_oracle(lim2; tier = :sauer_pai_avr)
    # A case with no live regulator anywhere is `:sauer_pai` wearing a costume.
    @test_throws ArgumentError build_oracle(infinite_bus_system(); tier = :sauer_pai_avr)
    # `Ta` is their amplifier's denominator, and zero would restructure their model.
    @test_throws ArgumentError build_oracle(infinite_bus_system(; K_A = 20.0, T_E = 0.5);
                                            tier = :sauer_pai_avr, avr_Ta = 0.0)
    # And the HELD-field tier refuses a machine carrying a regulator, so an exciter
    # cannot be silently dropped by picking the wrong tier.
    @test_throws ArgumentError build_oracle(infinite_bus_system(; K_A = 20.0, T_E = 0.5);
                                            tier = :sauer_pai)
end

# ===========================================================================
@testset "anti-vacuity: the comparison can see the exciter at all" begin
    # If the AVR were not actually wired to the machine's field input, every check
    # above would still pass — their machine would hold its seeded `vf` and ours
    # would move, but a small enough step makes that look like agreement. So the
    # GAIN is mutated on one side and the two must come apart by the predicted
    # amount: doubling `K_A` doubles the excursion, which is a different number
    # from the one a disconnected exciter would produce (zero).
    net  = infinite_bus_system(; K_A = 20.0, T_E = 0.5)
    big  = infinite_bus_system(; K_A = 40.0, T_E = 0.5)
    grid = collect(0.0:0.02:10.0)
    o1, t1, _ = both_avr(net, (0.0, 10.0), grid; ΔVref = 0.02)
    o2, t2, _ = both_avr(big, (0.0, 10.0), grid; ΔVref = 0.02)
    ma  = machine_arrays(net)
    Xe  = net.branches[1].X + ma.Xd′[2]
    G1  = 20.0 * Xe / (Xe + ma.Xd[1])
    G2  = 40.0 * Xe / (Xe + ma.Xd[1])
    # Both sides move, and both land on the closed-loop DC gain for their OWN K_A.
    @test o2.Efd_G1[end] - o2.Efd_G1[1] ≈ 40.0 * 0.02 / (1 + G2) rtol = 1.0e-3
    @test t2.Efd_G1[end] - t2.Efd_G1[1] ≈ 40.0 * 0.02 / (1 + G2) rtol = 1.0e-3
    # …and the two gains give a different answer on THEIR side too — which is what
    # says their exciter is connected rather than seeded and idle.
    #
    # THE SIZE OF THAT DIFFERENCE IS NOT THE OBVIOUS ONE, and the threshold written
    # here first (`> 0.05`, i.e. "doubling the gain should roughly double the move")
    # was wrong by an order of magnitude. Doubling `K_A` doubles `G` too, and the
    # closed-loop gain `K_A/(1 + G)` is already near its ceiling: 0.06499 against
    # 0.07074, a difference of **0.00575**. Asserting the predicted difference is
    # both sharper and correct where a threshold picked by eye was neither.
    @test abs(t2.Efd_G1[end] - t1.Efd_G1[end]) ≈
          abs(40.0 * 0.02 / (1 + G2) - 20.0 * 0.02 / (1 + G1)) rtol = 5.0e-3
    @test abs(t2.Efd_G1[end] - t1.Efd_G1[end]) > 1.0e-3      # …and not a null move
    @test abs(t2.V_B1[end] - t1.V_B1[end]) > 1.0e-3
end

end # M5 step 5


# ===========================================================================
# M5 STEP 6 — THE ZIP LOAD, AGAINST POWERDYNAMICS' `ZIPLoad`
# ===========================================================================
#
# The two rejections `_assert_sauer_pai_tier` carried through step 5 — no loads,
# no machine-free buses — are lifted here, and this is the first time a load of
# any kind has crossed the oracle seam at all.
#
# WHAT MAKES THIS COMPARISON DIFFERENT FROM STEP 5'S. The exciter comparison is
# one lag richer on their side by construction (`Ta → 0` is a limit, not a
# setting), so its band could never be round-off. `ZIPLoad` carries NO state: every
# equation in it is algebraic, and with `Vset = 1` its polynomial is ours term for
# term. So there is no structural gap to allow for, and the flat run below is a
# round-off comparison rather than a banded one.
#
# WHAT IS STILL IN THE WAY IS STEP 3'S RESIDUAL, NOT A NEW ONE. Their static stator
# carries the rotor speed on the flux terms and ours does not, so on any run with
# real slip the two sides differ at first order in it. That residual has nothing to
# do with loads, and the transient testset below is written to SHOW that rather
# than to assume it: the gap is measured at four ZIP splits and three disturbance
# sizes, and what is asserted is the SCALING, not a magnitude.

@testset "M5 step 6 — the ZIP load against PowerDynamics' ZIPLoad" begin

# The four splits every testset here runs. Named once: a split that appears in one
# check and not another is the kind of hole this suite exists to close. (Not
# `const` — a `@testset` body is a local scope, and `const` is illegal in one.)
ZIP_SPLITS = (("Z",   (a_z = 1.0, a_i = 0.0, a_p = 0.0)),
              ("I",   (a_z = 0.0, a_i = 1.0, a_p = 0.0)),
              ("P",   (a_z = 0.0, a_i = 0.0, a_p = 1.0)),
              ("mix", (a_z = 0.2, a_i = 0.3, a_p = 0.5)))

# ===========================================================================
@testset "the rejections are lifted, and the one that replaced them is real" begin
    # A LOAD AND A MACHINE-FREE BUS BOTH CROSS THE SEAM NOW. `load_bus_system` has
    # both — three buses, two machines, and a 110 MW / 30 MVAr load on the bus with
    # no rotating mass — and it is the fixture this whole step runs on.
    for (_, sh) in ZIP_SPLITS
        @test build_oracle(load_bus_system(; sh...); tier = :sauer_pai) isa OracleCase
    end
    # A bare junction — a bus with neither machine nor load — is `MTKBus()` on
    # their side, and it is worth one case of its own because it is the only
    # configuration with NO injector at all.
    junction = NetworkModel(100.0, 50.0,
        [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)],
        [Branch(:L12, :B1, :B2, 0.25, 500.0), Branch(:L23, :B2, :B3, 0.25, 500.0)],
        [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05,  40.0),
         Machine(:G3, :B3, 400.0, 5.0, 2.0, 0.30, 1.04, -40.0)])
    @test build_oracle(junction; tier = :sauer_pai) isa OracleCase

    # …AND THE CLASSICAL TIERS NOW REFUSE A LOAD BY NAME, which they did not before.
    # This is a tier boundary rather than unbuilt work — `SwingEngine` refuses the
    # same model, because a constant-magnitude `E` behind a reactance holds the
    # voltage up by construction and a voltage-dependent draw has nothing to bite
    # on. Without this the builder would construct a PowerDynamics network with the
    # load silently absent and fail several hundred lines later inside the seed.
    for tier in (:swing, :classical)
        msg = argerr_msg(() -> build_oracle(load_bus_system(); tier = tier))
        @test occursin("load", msg)
        @test occursin("tier boundary", msg)
    end
end

# ===========================================================================
@testset "the flat run: their ZIPLoad agrees with ours at round-off" begin
    # THIS IS WHERE THE LOAD MODEL IS ACTUALLY CHECKED, and the reason is the same
    # argument step 5's D22 used one mechanism along: the stator-ω residual is
    # `(ω − 1)·V` and vanishes IDENTICALLY at synchronous speed. On a flat run
    # `ω ≡ 1`, so nothing is left between the two sides except the load equation
    # and round-off — which makes this a `1e-12` comparison rather than a banded
    # one, and makes it the sharpest check in this file by four orders.
    #
    # It is also not a soft check. The seed comes from OUR fixpoint, so if their
    # polynomial differed from ours in sign, in normalisation, or in which share
    # multiplies which power of `|V|`, our equilibrium would not be one of theirs
    # and their bus voltages would move off it. The mutation testset below measures
    # exactly how far, and the answer is ten orders above this threshold.
    grid = collect(0.0:0.02:5.0)
    for (nm, sh) in ZIP_SPLITS
        net = load_bus_system(; sh...)
        for (rtol, atol) in ((1.0e-9, 1.0e-12), (1.0e-6, 1.0e-9))
            o, t = both_detailed(net, (0.0, 5.0), grid; reltol = rtol, abstol = atol)
            @test keys(o) == keys(t)
            for k in keys(o)
                k === :t && continue
                a, b = getproperty(o, k), getproperty(t, k)
                @test maximum(abs, a .- a[1]) < 1.0e-10     # ours is flat
                @test maximum(abs, b .- b[1]) < 1.0e-10     # so is theirs
                # worst measured across all four splits and both tolerances: 1.1e-13
                @test maximum(abs, a .- b) < 1.0e-11        # …at the same place
            end
        end
    end
end

# ===========================================================================
@testset "the transient: the residual is step 3's, and the load adds none" begin
    # THE QUESTION THIS ANSWERS. On any run with real slip the two sides differ,
    # and step 3 identified that difference as the stator-ω residual: first order
    # in slip, coefficient of order one, zero at synchronous speed. The load model
    # could hide a second residual inside it — one that does NOT vanish at ω = 1 —
    # and a magnitude bound could never tell the two apart. Only the scaling can.
    #
    # So the same measurement runs at every ZIP split: three disturbance sizes, and
    # what is asserted is that `gap / (slip × |V|)` is CONSTANT across them and of
    # order one. A load-model error would put a slip-independent offset into the
    # gap, and the ratio would then fall as the disturbance grows instead of
    # holding. Measured, the ratio holds to three digits over a fourfold change in
    # disturbance, at every split:
    #
    #     Z    0.962  0.962  0.962        P    1.234  1.233  1.232
    #     I    1.078  1.077  1.077        mix  1.121  1.121  1.121
    #
    # The coefficient differs slightly BETWEEN splits, and it should: the splits are
    # different trajectories through the same residual, not the same trajectory.
    grid = collect(0.0:0.02:5.0)
    for (nm, sh) in ZIP_SPLITS
        net = load_bus_system(; sh...)
        ratios = Float64[]
        for ΔP in (0.02, 0.04, 0.08)
            o, t = both_detailed(net, (0.0, 5.0), grid; ΔPm = (:G2, ΔP))
            slip = maximum(abs, o.ω_G2)
            @test slip > 1.0e-4                       # the disturbance is real
            push!(ratios, gap(o, t, :V_B3) / (slip * o.V_B3[1]))
        end
        # FIRST ORDER IN SLIP: the ratio holds over a 4x change in disturbance.
        @test maximum(ratios) - minimum(ratios) < 3.0e-3
        # …AND OF ORDER ONE, which is what says it is the predicted residual rather
        # than an unknown one. A load-model error would not land here.
        @test 0.5 < minimum(ratios) < 2.0
    end
end

# ===========================================================================
@testset "anti-vacuity: the two sides disagreeing about the load, and the channel that cannot see it" begin
    # THE MUTATION. Our engine is built on a constant-IMPEDANCE load and theirs on
    # a constant-POWER one, on a fixture whose load bus solves at |V| = 0.975. Both
    # runs are still perfectly flat — each side sits at its OWN equilibrium — so
    # what the comparison has to see is that the two equilibria are different
    # PLACES. Measured: 8.1e-3 on a rotor angle and 4.0e-3 on the load bus voltage,
    # against the 1e-13 the unmutated comparison agrees to. Ten orders.
    grid = collect(0.0:0.02:5.0)
    o, t = both_detailed(load_bus_system(; a_z = 0.0, a_i = 0.0, a_p = 1.0),
                         (0.0, 5.0), grid; mutate = _ -> load_bus_system())
    @test gap(o, t, :δ_G2) > 1.0e-3
    @test gap(o, t, :V_B3) > 1.0e-3
    @test gap(o, t, :V_B1) > 1.0e-4

    # AND THE FINDING THAT RUNNING IT PRODUCED, WHICH IS ABOUT WHERE THE RECORDER
    # LOOKS RATHER THAN ABOUT THE LOAD. Every RATE-like channel is at round-off
    # through this mutation — `f_coi` is 1.4e-14, identical to its value in the
    # unmutated run, and so are `ω`, `E′q`, `E′d` and `Efd`. Nothing is moving on
    # either side, so a channel that can only report motion reports agreement, and
    # a load model that is wrong by 4 % in drawn power reads GREEN on it.
    #
    # This is step 5's lesson turned around: there, a settled observable could not
    # carry a rate. Here, a settled system's frequency cannot carry a difference of
    # equilibria. The consequence is a rule rather than an observation — **the
    # oracle's load check must name a POSITION channel**, and `f_coi`, which is the
    # default channel everywhere else in this file, is the one channel that must
    # not be used for it.
    @test gap(o, t, :f_coi) < 1.0e-12
    @test gap(o, t, :ω_G2) < 1.0e-12
    @test gap(o, t, :E′q_G2) < 1.0e-12
    # …and not even every position channel: `δ_G1` is the SLACK, pinned at zero on
    # both sides by construction, so it cannot carry it either (measured 7.8e-14).
    @test gap(o, t, :δ_G1) < 1.0e-12

    # THE MUTATION IS SEEN AT EVERY SPLIT, not only the pair above — otherwise the
    # check would rest on one lucky combination.
    for (nm, sh) in ZIP_SPLITS
        nm == "Z" && continue                       # the mutation target itself
        om, tm = both_detailed(load_bus_system(; sh...), (0.0, 5.0), grid;
                               mutate = _ -> load_bus_system())
        @test gap(om, tm, :V_B3) > 1.0e-4
    end
end

# ===========================================================================
@testset "the mapping's conventions, asserted rather than described" begin
    # THE SIGN. Their `Pset` is an INJECTION and our `Load.P0` is a draw, so the
    # builder negates. Read back off the constructed case: a load drawing 110 MW on
    # a 100 MVA base must appear as `Pset = −1.1`, and getting this backwards would
    # turn a load into a generator of the same size.
    net  = load_bus_system(; a_z = 0.2, a_i = 0.3, a_p = 0.5)
    case = build_oracle(net; tier = :sauer_pai)
    la   = load_arrays(net)
    v    = la.bus[1]
    @test case.s0.p.v[v, :load₊Pset] ≈ -la.P[1] atol = 1.0e-12
    @test case.s0.p.v[v, :load₊Qset] ≈ -la.Q[1] atol = 1.0e-12
    @test case.s0.p.v[v, :load₊Pset] < 0                      # …and it is negative

    # THE NORMALISATION. `Vset = 1` is what makes their `Vrel` our `|V|`; anywhere
    # else and their `Pset` would denominate a different quantity from our `P₀`,
    # and the comparison would be measuring the normalisation.
    @test case.s0.p.v[v, :load₊Vset] == 1.0

    # THE SHARES, INCLUDING THE RESTRICTION. Ours is ONE triple applied to both
    # `P` and `Q`; theirs is two independent triples. The mapping sends ours to
    # both of theirs, so a `ZIPLoad` whose two triples differ is a model we cannot
    # express — a real restriction on our side, asserted here so it is a fact about
    # the code rather than a sentence in a docstring.
    for (p, q, ours) in ((:load₊KpZ, :load₊KqZ, la.a_z[1]),
                         (:load₊KpI, :load₊KqI, la.a_i[1]),
                         (:load₊KpC, :load₊KqC, la.a_p[1]))
        @test case.s0.p.v[v, p] ≈ ours atol = 1.0e-12
        @test case.s0.p.v[v, q] ≈ ours atol = 1.0e-12
    end
    # `KpC`/`KqC` have DEFAULT EXPRESSIONS on their side (`1 - KpZ - KpI`) that
    # would compute the right value. They are passed explicitly anyway, and this is
    # the assertion that says so: the default and the passed value agree, so if the
    # default were ever removed nothing here changes.
    @test case.s0.p.v[v, :load₊KpC] ≈ 1 - la.a_z[1] - la.a_i[1] atol = 1.0e-12
end

end # M5 step 6

# ============================================================================
# M6 step 4, oracle B — PowerFlows.jl against `ac_powerflow` / `dc_powerflow`
# ============================================================================
#
# The three rules at the head of this file are unchanged, but rule 1 changes its
# MECHANISM here and the change is the round's headline. M4's band came from each
# side's own convergence. That is four orders too small for this pair, because
# `PowerFlows` stores its admittance in `ComplexF32` and its error is a
# QUANTIZATION rather than a convergence: it converges to 4.4e-16 on its own
# residual and still sits 7.6e-9 away from us in angle. `powerflow_band`'s third
# term measures that, on our side of the comparison, and its docstring carries the
# derivation.
#
# WHAT THIS ORACLE REACHES THAT ORACLE A COULD NOT — the two boxes M6's task list
# wrote as boxes rather than prose:
#
#   * a LOSSY branch. Our dynamic tiers refuse `R != 0`, so oracle A's flat run can
#     never see one and the resistive half of `ac_powerflow` has no internal check.
#   * a BINDING reactive limit. A bus held at a `Q` nobody scheduled is still a
#     fixpoint, so the flat run stays flat whichever bus was limited (D13).

# The five fixtures. Each exists for one reason and the reason is on its line;
# a fixture without a reason is a fixture nobody notices has stopped testing
# anything (oracle A: two of ten mutations were no-ops on the case they were run
# against, and the first reading of that table was wrong because of it).

# 1. RADIAL, lossless, pure constant power. The simplest case that has a PV bus,
#    a load bus and a slack all at once.
pf_radial() = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.15, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.0, 0.0, 1.0)]; slack = :B1)

# 2. MESHED, lossless, MIXED ZIP shares. Meshed because a radial fixes every flow
#    by conservation alone and cannot see a wrong off-diagonal; mixed shares
#    because with `a_i = 0` a constant-current term dropped entirely is invisible.
pf_meshed() = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.15, 400.0),
     Branch(:L13, :B1, :B3, 0.30, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.5, 0.3, 0.2)]; slack = :B1)

# 3. LOSSY. The only fixture in the repo on which `Branch.R` reaches a residual
#    equation and produces a number anyone can check.
pf_lossy() = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0; R = 0.010),
     Branch(:L23, :B2, :B3, 0.15, 400.0; R = 0.020),
     Branch(:L13, :B1, :B3, 0.30, 400.0; R = 0.030)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 100.0; V_set = 1.01)],
    [Load(:D3, :B3, 160.0, 40.0, 0.5, 0.3, 0.2)]; slack = :B1)

# 4. OFF-BASE: `S_base = 250` and no machine rated at it. With every machine on the
#    system base the rebase PowerSystems performs is the identity and a wrong one
#    cannot be seen — the independence claimed in `powerflow_oracle.jl`'s header
#    table is untestable without this fixture.
pf_offbase() = NetworkModel(250.0, 60.0,
    [Bus(:B1, 345.0), Bus(:B2, 345.0), Bus(:B3, 345.0)],
    [Branch(:L12, :B1, :B2, 0.08, 900.0; R = 0.008),
     Branch(:L23, :B2, :B3, 0.12, 900.0; R = 0.012),
     Branch(:L13, :B1, :B3, 0.25, 900.0; R = 0.025)],
    [Machine(:G1, :B1, 400.0, 5.0, 1.0, 0.2, 1.05, 150.0; V_set = 1.02),
     Machine(:G2, :B2, 150.0, 4.0, 1.0, 0.2, 1.03, 120.0; V_set = 1.01)],
    [Load(:D3, :B3, 270.0, 70.0, 0.4, 0.2, 0.4)]; slack = :B1)

# 5. A BINDING reactive limit at B2. `Q_max` is set below what the unlimited solve
#    asks for, so the bus must give up its voltage and hold the limit instead.
#    Tuned on OUR side alone before anything was compared: the first draft pulled
#    B3 down to 0.819 pu and `ac_powerflow`'s own voltage band refused it — the
#    guard doing its job, and cheaper to find here than in a suite run.
pf_qlimit(; Q_max = 0.10) = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0), Bus(:B3, 230.0)],
    [Branch(:L12, :B1, :B2, 0.10, 400.0), Branch(:L23, :B2, :B3, 0.10, 400.0)],
    [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 20.0; V_set = 1.00),
     Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 70.0; V_set = 1.05,
             Q_min = -Q_max, Q_max = Q_max)],
    [Load(:D3, :B3, 90.0, 25.0, 0.0, 0.0, 1.0)]; slack = :B1)

# The gap on one channel. Deliberately NOT a function of the band: a check that
# computes its own threshold from the numbers it is judging is the shape step 3
# shipped twice and had to fix (`m6-tasks.md` step 3).
pf_gap(a, b, channel) = maximum(abs, channel(a) .- channel(b))

@testset "M6 step 4 oracle B — PowerFlows as an external power-flow oracle" begin

@testset "the case is compiled, and its conventions are the measured ones" begin
    net = pf_meshed()
    sys = to_powersystems(net)

    # Every bus angle PINNED to zero. Their REF angle is honoured, not ignored —
    # setting it to 0.3 shifts the whole solved answer by 0.3 — and our slack angle
    # is zero by construction, so this is a claim that has to be held, not assumed.
    for b in PSY.get_components(PSY.ACBus, sys)
        @test PSY.get_angle(b) == 0.0
    end

    # Bus types come from `bus_roles`, which is the model's own derivation.
    byname = Dict(PSY.get_name(b) => b for b in PSY.get_components(PSY.ACBus, sys))
    @test PSY.get_bustype(byname["B1"]) == PSY.ACBusTypes.REF
    @test PSY.get_bustype(byname["B2"]) == PSY.ACBusTypes.PV
    @test PSY.get_bustype(byname["B3"]) == PSY.ACBusTypes.PQ
    @test GridSim.bus_roles(net) == [:slack, :generator, :load]

    # A generator bus starts at ITS OWN setpoint, not at 1.0 and not at `E'`.
    # M5 step 8 measured what one number serving two denominations costs.
    @test PSY.get_magnitude(byname["B2"]) == 1.01
    @test PSY.get_magnitude(byname["B3"]) == 1.0

    # The arc runs in the branch's DECLARED direction, so their `bus_from` is ours
    # and no sign convention has to be argued about anywhere else in this file.
    for l in PSY.get_components(PSY.Line, sys)
        br = net.branches[findfirst(b -> String(b.id) == PSY.get_name(l), net.branches)]
        arc = PSY.get_arc(l)
        @test PSY.get_number(PSY.get_from(arc)) == net.bus_index[br.from]
        @test PSY.get_number(PSY.get_to(arc)) == net.bus_index[br.to]
        @test PSY.get_x(l) == br.X
        @test PSY.get_r(l) == br.R
        @test PSY.get_b(l) == (from = 0.0, to = 0.0)   # our model has no charging
    end

    # The load is ONE `StandardLoad` carrying the ZIP split, and the shares land in
    # the three field pairs the way their law reads them.
    sl = only(PSY.get_components(PSY.StandardLoad, sys))
    l = only(net.loads)
    @test PSY.get_impedance_active_power(sl) ≈ l.a_z * l.P0 / net.S_base atol = 1e-15
    @test PSY.get_current_active_power(sl)   ≈ l.a_i * l.P0 / net.S_base atol = 1e-15
    @test PSY.get_constant_active_power(sl)  ≈ l.a_p * l.P0 / net.S_base atol = 1e-15
end

@testset "the machine's per-unit conversion is INDEPENDENT of machine_arrays" begin
    # The point of the off-base fixture. `to_powersystems` writes `P0/S_rated` on
    # the machine's own base and PowerSystems rebases; `machine_arrays` writes
    # `P0/S_base`. The two never meet, so this is a real cross-check — but only on
    # a model where the rebase is not the identity.
    net = pf_offbase()
    @test all(m -> m.S_rated != net.S_base, net.machines)   # the fixture's whole job
    sys = to_powersystems(net)
    ma = machine_arrays(net)
    for (k, m) in pairs(net.machines)
        g = PSY.get_component(PSY.ThermalStandard, sys, String(m.id))
        @test PSY.get_base_power(g) == m.S_rated
        # Constructor arguments are DEVICE base regardless of the system setting —
        # measured, and the reason the two paths are independent.
        @test PSY.get_active_power(g) ≈ ma.Pm[k] atol = 1e-15   # read back in SYSTEM base
        @test PSY.get_active_power(g) != m.P0 / m.S_rated       # ...and it was NOT stored so
    end
end

@testset "what the builder refuses, by name" begin
    # A slack with no machine: the MODEL accepts it (a half-built editor draft must
    # stay constructible, M5 D3) and both power-flow paths refuse it.
    headless = NetworkModel(100.0, 50.0,
        [Bus(:B1, 230.0), Bus(:B2, 230.0)],
        [Branch(:L12, :B1, :B2, 0.10, 400.0)],
        [Machine(:G2, :B2, 100.0, 4.0, 1.0, 0.2, 1.03, 60.0)],
        [Load(:D1, :B1, 60.0, 20.0)]; slack = :B1)
    @test bus_role(headless, :B1) === :slack
    @test_throws ArgumentError to_powersystems(headless)
    @test_throws ArgumentError ac_powerflow(headless)

    # Two machines on one bus asking for two terminal voltages.
    clash = NetworkModel(100.0, 50.0,
        [Bus(:B1, 230.0), Bus(:B2, 230.0)],
        [Branch(:L12, :B1, :B2, 0.10, 400.0)],
        [Machine(:G1, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 60.0; V_set = 1.02),
         Machine(:G1b, :B1, 100.0, 5.0, 1.0, 0.2, 1.05, 0.0; V_set = 1.04)],
        [Load(:D2, :B2, 60.0, 20.0)]; slack = :B2)
    @test_throws ArgumentError to_powersystems(clash)

    # The bus columns that do not book a ZIP load are refused rather than read.
    # This is a GUARD and not a comment: oracle A deleted three pieces of dead code
    # in one batch, each a note written without checking the path it described.
    res = oracle_powerflow(pf_meshed())
    @test haskey(res, :Vm) && haskey(res, :Pgen)
    for bad in (:P_load, :Q_load, :P_net, :Q_net)
        @test !haskey(res, bad)
    end
    df = (; P_load = [1.0], Vm = [1.0])
    @test_throws ArgumentError GridSimReference._pf_bus_column(df, :P_load)
end

@testset "the band's three terms, and which one dominates" begin
    net = pf_radial()
    b = powerflow_band(net; channel = s -> s.Vm)
    @test b.band > 0
    @test b.band == b.ours + b.theirs + b.precision          # no factor anywhere
    # THE FINDING, as an inequality rather than as a number: what limits the
    # agreement is their single-precision ADMITTANCE, not either side's Newton.
    # Both convergence terms together are orders below the precision term. The
    # measured multiples live in `m6-tasks.md`; asserting one here would turn a
    # measurement into a threshold.
    @test b.precision > b.ours + b.theirs
    @test b.ours < 1.0e-12
    @test b.precision ≈ eps(Float32) * maximum(abs, ac_powerflow(net).Vm)

    ours = ac_powerflow(net)
    theirs = oracle_powerflow(net)
    @test pf_gap(ours, theirs, s -> s.Vm) < b.band
    # NOTE the check that is deliberately absent: there is no lower bound on the
    # gap. A channel that agrees far better than the band — `flow` on this fixture
    # agrees to 7.8e-16 — is two solvers agreeing to the bit on a quantity the
    # quantization happens not to reach, not a vacuous check, and asserting a floor
    # under it would make an accident load-bearing.

    # An identically-zero channel has no band and says so rather than returning 0.
    @test_throws ArgumentError powerflow_band(net; channel = s -> zeros(3))
    @test_throws ArgumentError powerflow_band(net; channel = s -> s.Vm, scale = 0.0)
    # `flow_scale` is the admittance-sized number, not the flow-sized one — the
    # whole point, and the ratio between them is what a naive band gets wrong.
    ymax = maximum(abs(1 / complex(b.R, b.X)) for b in net.branches)
    @test flow_scale(net, ours) == ymax * maximum(ours.Vm)^2
    @test flow_scale(net, ours) > maximum(abs, ours.qflow)
end

@testset "the single-precision twin is the explanation, not a fitted constant" begin
    net = pf_radial()
    twin = float32_admittance_twin(net)
    # The twin is a different network, and only in the last bits.
    @test twin.branches[1].X != net.branches[1].X
    @test twin.branches[1].X ≈ net.branches[1].X rtol = 1e-6
    # Round-tripping a LOSSLESS branch must leave it lossless: `Branch` requires
    # `R >= 0` and a clamp that fired on anything larger would be hiding a bug.
    @test all(b -> b.R == 0.0, twin.branches)
    @test all(b -> b.R > 0.0, float32_admittance_twin(pf_lossy()).branches)

    # Their Ybus really is where the error lives: our solve on the twin lands on
    # the same side of ours as theirs does, and by a comparable amount.
    ours = ac_powerflow(net; abstol = 1e-14)
    ontwin = ac_powerflow(twin; abstol = 1e-14)
    theirs = oracle_powerflow(net)
    @test pf_gap(ours, ontwin, s -> s.Vm) > pf_gap(ours, theirs, s -> s.Vm)
    @test pf_gap(ours, theirs, s -> s.Vm) > 1.0e-10   # not solver noise
end

@testset "each side's answer in an INDEPENDENT admittance — the round's finding" begin
    # The sharp instrument, and the one check here that needs no band at all: a
    # mismatch is a statement about ONE answer, not about the gap between two.
    # `independent_mismatch` builds its own double-precision Y from `Branch` and
    # touches neither `_ac_admittance` nor `PowerNetworkMatrices`.
    #
    # The thresholds are stated as ORDERS, not as measured numbers, and they are
    # stated from the mechanism rather than from the run: ours solves in double
    # precision to `abstol = 1e-12`, so it must land near machine epsilon; theirs
    # solves in double precision against a matrix stored to single-precision
    # relative accuracy (eps(Float32) = 1.19e-7), so it cannot.
    for (name, net) in (("radial", pf_radial()), ("meshed", pf_meshed()),
                        ("lossy", pf_lossy()), ("offbase", pf_offbase()))
        ours = independent_mismatch(net, ac_powerflow(net))
        theirs = independent_mismatch(net, oracle_powerflow(net))
        @test ours < 1.0e-13                    # a double-precision solve of the real network
        @test theirs > 1.0e-9                   # a double-precision solve of a rounded one
        @test theirs / ours > 1.0e4             # ...and the two are not the same kind of number
        @test name isa String
    end

    # POSITIVE CONTROL: the instrument can read a small mismatch, so the large one
    # it reports for their answer is not an artefact of the instrument. Our answer
    # on the SAME code path is the control, and it is already above; here is the
    # anti-vacuity half — bend our answer and the mismatch must follow.
    net = pf_meshed()
    good = ac_powerflow(net)
    bent = (; Vm = good.Vm .+ 1.0e-6, θ = good.θ)
    @test independent_mismatch(net, bent) > 1.0e-7
    @test independent_mismatch(net, good) < 1.0e-13

    # And it reads the LOAD MODEL, which is what makes it independent of `_zip_scale`:
    # a fixture with mixed ZIP shares evaluated as though it were constant power
    # leaves a mismatch, so a check built on this cannot be blind the way step 3's
    # losses identity was (F10).
    flat = NetworkModel(net.S_base, net.f0, net.buses, net.branches, net.machines,
                        [Load(l.id, l.bus, l.P0, l.Q0, 0.0, 0.0, 1.0) for l in net.loads];
                        slack = net.slack)
    @test independent_mismatch(flat, good) > 1.0e-3      # same voltages, different load law
end

@testset "AC: radial and meshed agree, per channel and within a stated band" begin
    for (name, net) in (("radial", pf_radial()), ("meshed", pf_meshed()))
        ours = ac_powerflow(net)
        theirs = oracle_powerflow(net)
        for ch in (s -> s.Vm, s -> s.θ)
            b = powerflow_band(net; channel = ch)
            @test pf_gap(ours, theirs, ch) <= b.band
        end
        # A branch flow is a DIFFERENCE of |y|.|V|^2-sized products, so its precision
        # term is built from those and not from the (partly cancelled) result — see
        # `flow_scale`. Measured: on the channel's own magnitude, `qflow` runs 3.2x
        # over on this pair of fixtures and `flow` saturates at 0.94x on the
        # off-base one.
        fs = flow_scale(net, ours)
        for ch in (s -> s.flow, s -> s.flow_rev, s -> s.qflow)
            b = powerflow_band(net; channel = ch, scale = fs)
            @test pf_gap(ours, theirs, ch) <= b.band
        end
        # Generation is checked by IDENTITY, never banded — see `powerflow_band`'s
        # docstring. At a generator bus our `Pgen` IS the schedule, exactly, and a
        # band derived from a convergence that never happened would be meaningless.
        ma = machine_arrays(net)
        for (k, m) in pairs(net.machines)
            v = net.bus_index[m.bus]
            v == net.bus_index[net.slack] && continue
            @test ours.Pgen[v] ≈ ma.Pm[k] atol = 1e-12
        end
        # The slack angle is a constraint on both sides, not a solved quantity, so
        # it is compared EXACTLY — `powerflow_band` refuses to band it and says why.
        @test ours.θ[1] == 0.0 && theirs.θ[1] == 0.0
        # ...and the held generator magnitudes likewise.
        for v in eachindex(net.buses)
            GridSim.bus_role(net, net.buses[v].id) === :load && continue
            @test ours.Vm[v] == theirs.Vm[v]
        end
        @test name isa String
    end
end

@testset "AC: the LOSSY case — the half of ac_powerflow oracle A cannot reach" begin
    net = pf_lossy()
    ours = ac_powerflow(net)
    theirs = oracle_powerflow(net)
    # The loss channel exists at all only here: with `R = 0` every branch's
    # `flow + flow_rev` is identically zero and this compares nothing.
    ourloss = ours.flow .+ ours.flow_rev
    theirloss = theirs.flow .+ theirs.flow_rev
    @test all(>(0.0), ourloss)                       # a resistive branch dissipates
    @test maximum(ourloss) > 1.0e-4                  # ...by an amount worth checking
    fs = flow_scale(net, ours)
    for ch in (s -> s.Vm, s -> s.θ)
        b = powerflow_band(net; channel = ch)
        @test pf_gap(ours, theirs, ch) <= b.band
    end
    for ch in (s -> s.flow, s -> s.flow_rev, s -> s.qflow)
        b = powerflow_band(net; channel = ch, scale = fs)
        @test pf_gap(ours, theirs, ch) <= b.band
    end
    bl = powerflow_band(net; channel = s -> s.flow .+ s.flow_rev, scale = fs)
    @test maximum(abs, ourloss .- theirloss) <= bl.band

    # The slack picks the losses up, and BOTH sides say the same amount. This is
    # the identity `NetworkModel`'s sigma-balance guard stopped being able to make
    # once `Branch.R` existed (step 1, F3) — checked here, against an outside
    # solver, which is where that guard's annotation points.
    la = load_arrays(net)
    drawn = sum(la.P[k] * (la.a_z[k] * ours.Vm[la.bus[k]]^2 +
                           la.a_i[k] * ours.Vm[la.bus[k]] + la.a_p[k])
                for k in eachindex(la.bus))
    @test sum(ours.Pgen) ≈ drawn + sum(ourloss) atol = 1e-10
    # Their generation is compared on THEIR OWN constant, read from their source:
    # `post_processing.jl` redistributes generator set points until the residual is
    # within `ISAPPROX_ZERO_TOLERANCE = 1e-6` (per unit on the system base). That
    # is the honest tolerance for any cross-comparison of their generation numbers,
    # and it has nothing to do with admittance precision.
    @test sum(theirs.Pgen) ≈ sum(ours.Pgen) atol = 1.0e-6
end

@testset "AC: the off-base fixture, where their rebase is not the identity" begin
    net = pf_offbase()
    @test net.S_base == 250.0                        # and not the 100.0 every probe used
    ours = ac_powerflow(net)
    theirs = oracle_powerflow(net)
    for ch in (s -> s.Vm, s -> s.θ)
        b = powerflow_band(net; channel = ch)
        @test pf_gap(ours, theirs, ch) <= b.band
    end
    bf = powerflow_band(net; channel = s -> s.flow, scale = flow_scale(net, ours))
    @test pf_gap(ours, theirs, s -> s.flow) <= bf.band
    # Their export is in MW, ours in per-unit on `S_base`. On a 250 MVA base a
    # reader that had assumed per-unit would be out by 250x, so the scale is
    # asserted rather than trusted: the slack's pickup in MW is our pu times 250.
    sys = to_powersystems(net)
    raw = PF.solve_power_flow(PF.ACPowerFlow(; check_reactive_power_limits = true,
              solver_settings = Dict{Symbol,Any}(:tol => 1.0e-12)), sys)
    @test raw["bus_results"].P_gen[1] ≈ ours.Pgen[1] * net.S_base atol = 1e-6 * net.S_base
    @test abs(raw["bus_results"].P_gen[1]) > 10.0    # ...and it is MW-sized, not pu-sized
end

@testset "the BINDING reactive limit, and the default that would have hidden it" begin
    net = pf_qlimit()
    ours = ac_powerflow(net)
    # Ours switched B2 off its setpoint and holds it at the ceiling.
    @test ours.limited == [:B2]
    @test ours.Qgen[2] ≈ 0.10 atol = 1e-10
    @test ours.Vm[2] < 1.05

    theirs = oracle_powerflow(net; check_limits = true)
    @test theirs.Qgen[2] ≈ 0.10 atol = 1e-6          # the SAME bus, at the SAME limit
    @test theirs.Vm[2] < 1.05
    # `abstol_fine` is passed, and the reason is a MEASUREMENT: this model's own
    # residual floor is 1.804e-15, so the band's default 1000x-tighter probe
    # (1e-15) makes Newton stall. `powerflow_band` refuses that by name rather than
    # falling back silently, which is why the number appears here at the call site.
    for ch in (s -> s.Vm, s -> s.θ)
        b = powerflow_band(net; channel = ch, check_limits = true, abstol_fine = 1e-14)
        @test pf_gap(ours, theirs, ch) <= b.band
    end
    @test_throws ErrorException powerflow_band(net; channel = s -> s.Vm,
                                               check_limits = true)
    bf = powerflow_band(net; channel = s -> s.flow, check_limits = true,
                        abstol_fine = 1e-14, scale = flow_scale(net, ours))
    @test pf_gap(ours, theirs, s -> s.flow) <= bf.band

    # ANTI-VACUITY, and it is their own default. `ACPowerFlow()` ships with
    # `check_reactive_power_limits = false`; with it off they hold the setpoint and
    # blow straight through the ceiling, and the comparison must SEE that. A test
    # that passed either way would be reading nothing.
    unlimited = oracle_powerflow(net; check_limits = false)
    @test unlimited.Vm[2] == 1.05
    @test unlimited.Qgen[2] > 0.10 + 0.01            # measured: it asks for 0.860
    bV = powerflow_band(net; channel = s -> s.Vm, check_limits = true,
                        abstol_fine = 1e-14)
    @test pf_gap(ours, unlimited, s -> s.Vm) > bV.band

    # A limit so wide it cannot bind must reproduce the unlimited answer, on both
    # sides. Ours does it EXACTLY (nothing switched means exactly one solve ran);
    # theirs within the band.
    wide = pf_qlimit(Q_max = 50.0)
    ours_wide = ac_powerflow(wide)
    @test isempty(ours_wide.limited)
    @test ours_wide.Vm[2] == 1.05
    theirs_wide = oracle_powerflow(wide; check_limits = true)
    @test theirs_wide.Vm[2] == 1.05
end

@testset "DC: their linear solve against ours, on its own band" begin
    for net in (pf_radial(), pf_meshed())
        ours = dc_powerflow(net)
        theirs = oracle_dc_powerflow(net)
        b = powerflow_band(net; channel = s -> s.θ, dc = true)
        @test pf_gap(ours, theirs, s -> s.θ) <= b.band
        bf = powerflow_band(net; channel = s -> s.flow, dc = true,
                            scale = flow_scale(net, ac_powerflow(net)))
        @test pf_gap(ours, theirs, s -> s.flow) <= bf.band
        @test ours.θ[1] == 0.0 && theirs.θ[1] == 0.0
    end
    # Their DC ignores resistance and uses `1/x`, measured; ours does the same, so
    # the lossy model and its lossless twin must give BOTH sides the same angles.
    lossy = pf_lossy()
    lossless = NetworkModel(lossy.S_base, lossy.f0, lossy.buses,
        [Branch(b.id, b.from, b.to, b.X, b.rating) for b in lossy.branches],
        lossy.machines, lossy.loads; slack = lossy.slack)
    @test dc_powerflow(lossy).θ == dc_powerflow(lossless).θ
    bθ = powerflow_band(lossy; channel = s -> s.θ, dc = true)
    @test pf_gap(oracle_dc_powerflow(lossy), oracle_dc_powerflow(lossless), s -> s.θ) <= bθ.band
end

@testset "anti-vacuity: the comparison can read a disagreement" begin
    # The mutation that matters goes in `_ac_admittance` / `_ac_residual!` /
    # `_ac_flows` / `_zip_scale` and is executed by hand — it cannot live in a test
    # file, because a test cannot edit the source it is testing. The record of that
    # run is in `docs/plans/m6-tasks.md`. What IS testable here is that the
    # arithmetic these checks are built from is not vacuous: perturb one side by a
    # multiple of the band and every channel check must fail.
    net = pf_meshed()
    ours = ac_powerflow(net)
    theirs = oracle_powerflow(net)
    for ch in (s -> s.Vm, s -> s.θ, s -> s.flow)
        b = powerflow_band(net; channel = ch)
        @test pf_gap(ours, theirs, ch) <= b.band                      # positive control
        bent = (; Vm = ours.Vm .+ 10 * b.band, θ = ours.θ .+ 10 * b.band,
                  flow = ours.flow .+ 10 * b.band)
        @test pf_gap(bent, theirs, ch) > b.band                       # anti-vacuity
    end
end

end # M6 step 4 oracle B
