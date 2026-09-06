# M1 - the aggregate frequency tier: the shared bounded recorder, the aggregates,
# `fr_rhs!`, `FrequencyResponseEngine`, load shedding, and the closed-form sweeps.

# --- the shared bounded trajectory recorder (src/engines/recorder.jl) -------
#
# Every engine records through this instead of growing its own vectors. The
# retention rule is: a sample whose 1-based push index is `n` is kept iff
# `(n-1) % keep_every == 0`, and `keep_every` doubles each time the buffer
# fills. So the retained samples are always an arithmetic progression that
# starts at the very first sample — which is the property these tests assert,
# rather than a hand-traced sequence that would only prove one capacity.

@testset "TrajectoryRecorder: retention invariant, via $label" for
        (label, push_sample) in RECORD_ENTRY_POINTS
    # Odd capacities are where the stride bookkeeping goes off by one, so they
    # are in the sweep deliberately. Each property is checked after *every* one
    # of the 200 pushes but reported as one assertion per capacity, with the
    # offending push indices in the failure output.
    for cap in (2, 3, 4, 5, 8, 9)
        rec = GridSim.TrajectoryRecorder(:x; capacity = cap)
        over_capacity, lost_first, not_progression, ragged, unevenly_spaced =
            Int[], Int[], Int[], Int[], Int[]
        for n in 1:200
            push_sample(rec, 0.1 * n, Float64(n))
            tr = GridSim.series(rec)
            k = rec.keep_every
            GridSim.n_kept(rec) <= cap || push!(over_capacity, n)
            # The first sample must survive every halving — that is the whole
            # reason for decimating instead of dropping the oldest: the nadir
            # and the initial RoCoF both live at the start of a disturbance.
            tr.x[1] == 1.0 || push!(lost_first, n)
            # Retained samples are exactly the progression 1, 1+k, 1+2k, ...
            tr.x == collect(1.0:k:Float64(n)) || push!(not_progression, n)
            length(tr.t) == length(tr.x) == GridSim.n_kept(rec) || push!(ragged, n)
            # ...hence evenly spaced in time, which is what any consumer that
            # finite-differences or plots the series depends on.
            length(tr.t) >= 2 && !all(≈(0.1 * k), diff(tr.t)) &&
                push!(unevenly_spaced, n)
        end
        @test over_capacity == Int[]
        @test lost_first == Int[]
        @test not_progression == Int[]
        @test ragged == Int[]
        @test unevenly_spaced == Int[]
        @test rec.n_seen == 200            # every sample was *offered*...
        @test GridSim.n_kept(rec) < 200    # ...and the buffer is bounded anyway
    end
end

@testset "TrajectoryRecorder: the capacity-4 trace, by hand" begin
    # The property test above generalises this, but a worked example pins the
    # intent: at capacity 4 the buffer halves at pushes 5, 9, 17, ...
    rec = GridSim.TrajectoryRecorder(:x; capacity = 4)
    got = Vector{Float64}[]
    for n in 1:9
        GridSim.record!(rec, Float64(n), Float64(n))
        push!(got, copy(GridSim.series(rec).x))
    end
    @test got[4] == [1.0, 2.0, 3.0, 4.0]      # full, stride still 1
    @test got[5] == [1.0, 3.0, 5.0]           # halved, stride 2, sample 5 kept
    @test got[7] == [1.0, 3.0, 5.0, 7.0]      # full again
    @test got[9] == [1.0, 5.0, 9.0]           # halved, stride 4, sample 9 kept
    @test rec.keep_every == 4
end

@testset "TrajectoryRecorder: shape, names, and guards" begin
    rec = GridSim.TrajectoryRecorder(:f, :RoCoF; capacity = 16)
    # `:t` is prepended by the recorder and comes first, so no consumer can be
    # handed data without the time base it needs to place the samples.
    @test propertynames(GridSim.series(rec)) == (:t, :f, :RoCoF)
    @test GridSim.n_kept(rec) == 0
    # Arity is pinned by the type parameter: a call with the wrong number of
    # channels fails at the call site, not as a length mismatch found later.
    @test_throws MethodError GridSim.record!(rec, 0.0, 1.0)
    @test_throws MethodError GridSim.record!(rec, 0.0, 1.0, 2.0, 3.0)
    @test occursin("prepended automatically",
                   argerr_msg(() -> GridSim.TrajectoryRecorder(:t, :f)))
    @test occursin("at least one channel",
                   argerr_msg(() -> GridSim.TrajectoryRecorder()))
    @test occursin("duplicate channel",
                   argerr_msg(() -> GridSim.TrajectoryRecorder(:f, :f)))
    @test occursin("capacity must be >= 2",
                   argerr_msg(() -> GridSim.TrajectoryRecorder(:f; capacity = 1)))
    # Concrete field types on the hot path (SPEC §4).
    @test isconcretetype(fieldtype(typeof(rec), :channels))
end

@testset "recorder: engine nadir survives decimation (summary ≠ buffer)" begin
    # The trap this guards: once the buffer decimates, `minimum(series.f)` is
    # the lowest *retained* sample, not the lowest that occurred. Running
    # summaries must therefore be tracked incrementally, outside the buffer.
    sys = example_system()
    run_engine(cap) = begin
        eng = init!(FrequencyResponseEngine, sys; dt = 0.02, capacity = cap)
        inject!(eng, TripGenerator(:G1))
        for _ in 1:3000; step!(eng, 0.02); end
        eng
    end
    small, big = run_engine(64), run_engine(200_000)
    @test GridSim.n_kept(small.traj) <= 64
    @test GridSim.n_kept(big.traj) == 3001          # nothing dropped at all
    # The nadir is identical either way — it is not read off the buffer.
    @test small.nadir ≈ big.nadir atol = 1e-12
    # And it had better not be, because the decimated buffer genuinely lost it:
    # the lowest retained sample is strictly above the true nadir.
    @test minimum(GridSim.series(small.traj).f) > small.nadir + 1e-9
    @test minimum(GridSim.series(big.traj).f) ≈ big.nadir atol = 1e-12
end

@testset "aggregates (COI, on system base) vs hand arithmetic" begin
    sys = example_system()   # S_base=550, D=1.5, Tg=8.0; all R=0.05
    all_ids = Set(u.id for u in sys.units)

    # All four online. H_sys = Σ Hᵢ·Sᵢ / S_base:
    #   (4.0·200 + 3.5·150 + 3.0·100 + 2.5·100)/550 = 1875/550.
    # 1/R_eq = Σ (1/Rᵢ)·(Sᵢ/S_base) = 20·(200+150+100+100)/550 = 20·1 = 20
    #   (ΣSᵢ == S_base here, so R_eq collapses to the common 0.05 droop).
    a = GridSim.aggregates(sys, all_ids)
    @test a.H_sys ≈ 1875 / 550
    @test a.R_eq ≈ 0.05
    @test a.D == 1.5            # system-wide pass-through
    @test a.Tg == 8.0
    # headroom = Σ(Pmaxᵢ−P0ᵢ)/S_base = (50+40+30+40)/550 = 160/550.
    @test a.headroom ≈ 160 / 550

    # Trip G1 (200 MVA, H=4): only G2,G3,G4 online.
    #   H_sys = (525+300+250)/550 = 1075/550.
    #   1/R_eq = 20·(150+100+100)/550 = 7000/550 → R_eq = 550/7000.
    b = GridSim.aggregates(sys, Set([:G2, :G3, :G4]))
    @test b.H_sys ≈ 1075 / 550
    @test b.R_eq ≈ 550 / 7000
    # Tripping G1 also takes G1's own 50 MW headroom out of the pool:
    #   headroom = (40+30+40)/550 = 110/550.
    @test b.headroom ≈ 110 / 550
    # Losing inertia lowers H_sys; losing a unit lowers droop gain ⇒ raises R_eq;
    # and removes that unit's reserve ⇒ lowers headroom.
    @test b.H_sys < a.H_sys
    @test b.R_eq > a.R_eq
    @test b.headroom < a.headroom

    # No units online ⇒ zero inertia, zero droop gain (R_eq = Inf, not NaN),
    # zero reserve.
    z = GridSim.aggregates(sys, Set{Symbol}())
    @test z.H_sys == 0.0
    @test z.R_eq == Inf
    @test z.headroom == 0.0
end

@testset "fr_rhs!: swing/governor RHS + headroom saturation in the derivative" begin
    # Hand-built params (not from a system) so each scenario is isolated.
    # H_sys=2, R_eq=0.05, D=1.5, Tg=8, a generation-loss imbalance, ceiling 0.2.
    mk(; ΔP_dist = -0.27, headroom = 0.2) =
        GridSim.FRParams(2.0, 0.05, 1.5, 8.0, ΔP_dist, headroom)
    du = zeros(2)

    # Initial RoCoF: at the trip instant the state is the origin, so the swing
    # equation collapses to dΔω/dt = ΔP_dist/(2·H_sys) (closed form, SPEC §7.6).
    p = mk()
    GridSim.fr_rhs!(du, [0.0, 0.0], p, 0.0)
    @test du[1] ≈ p.ΔP_dist / (2 * p.H_sys)
    @test du[2] == 0.0                      # −0/R_eq − 0 = 0
    # RHS is type-stable and non-allocating in the hot path.
    @test (@inferred GridSim.fr_rhs!(du, [0.0, 0.0], p, 0.0)) === nothing

    # Governor term below the ceiling, under-frequency (Δω<0) ⇒ ramp UP.
    #   dΔPm = (−(−0.02)/0.05 − 0.1)/8 = (0.4 − 0.1)/8 = 0.0375 > 0.
    GridSim.fr_rhs!(du, [-0.02, 0.1], mk(), 0.0)
    @test du[2] ≈ 0.0375
    @test du[2] > 0                         # not at the ceiling ⇒ free to rise

    # SATURATION BINDS: ΔPm already at headroom and the governor wants more.
    #   raw dΔPm = (0.4 − 0.2)/8 = 0.025 > 0 ⇒ zeroed.
    GridSim.fr_rhs!(du, [-0.02, 0.2], mk(), 0.0)
    @test du[2] == 0.0

    # RELEASE (the test a naive state-clamp fails): at the ceiling but Δω has
    # recovered (Δω>0), so the governor term is negative — ΔPm must be allowed
    # to come back DOWN. raw dΔPm = (−0.2 − 0.2)/8 = −0.05 < 0 ⇒ NOT zeroed.
    GridSim.fr_rhs!(du, [0.01, 0.2], mk(), 0.0)
    @test du[2] ≈ -0.05
    @test du[2] < 0

    # R_eq = Inf (no droop / no online droop) ⇒ −Δω/R_eq = 0, no NaN.
    q = GridSim.FRParams(2.0, Inf, 1.5, 8.0, -0.1, 0.2)
    GridSim.fr_rhs!(du, [-0.01, 0.0], q, 0.0)
    @test all(isfinite, du)
    @test du[2] == 0.0                      # (−0 − 0)/Tg = 0
end

@testset "FrequencyResponseEngine: build, step, trip, closed-form checks" begin
    sys = example_system()                  # S_base=550, f0=50, D=1.5, Tg=8

    # --- construction via the interface verb (Type dispatch ⇒ fresh engine) ---
    eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
    @test eng isa FrequencyResponseEngine
    # LOAD-BEARING: the integrator must hold the SAME params object the engine
    # mutates, or `inject!` would silently no-op the running integration.
    @test eng.integrator.p === eng.params
    @test eng.online == Set([:G1, :G2, :G3, :G4])

    # Pre-disturbance: sitting at the origin ⇒ f=f0, RoCoF=0, ΔPm=0.
    s0 = current_state(eng)
    @test s0.f ≈ sys.f0
    @test s0.Δω == 0.0
    @test s0.RoCoF == 0.0
    @test s0.ΔPm == 0.0
    # The parametric design pays off: `current_state` is type-stable.
    @inferred current_state(eng)

    # Stepping with no disturbance keeps us at the origin (ΔP_dist still 0).
    step!(eng, 0.02)
    @test current_state(eng).f ≈ sys.f0

    # --- trip G1 (P0=150) live: only G2,G3,G4 remain online ----------------
    inject!(eng, TripGenerator(:G1))
    @test eng.online == Set([:G2, :G3, :G4])
    a1 = GridSim.aggregates(sys, eng.online)
    @test eng.params.ΔP_dist ≈ -150 / 550          # lost generation, pu
    @test eng.params.H_sys ≈ a1.H_sys              # aggregates refreshed
    @test eng.params.headroom ≈ 110 / 550

    # Closed-form INITIAL RoCoF at the trip instant (state still the origin):
    #   RoCoF0 = f0·ΔP_dist/(2·H_sys) = 50·(−150/550)/(2·1075/550) = −7500/2150.
    s_trip = current_state(eng)
    @test s_trip.RoCoF ≈ 50 * (-150 / 550) / (2 * a1.H_sys)
    @test s_trip.RoCoF ≈ -7500 / 2150
    @test s_trip.RoCoF < 0                          # losing gen ⇒ frequency falls

    # Run it out and check the saturation invariant: G1's trip leaves only
    # 0.2 pu of headroom, which the droop demand exceeds — so ΔPm must pin at
    # the ceiling and NEVER cross it (the post-hoc-clamp landmine).
    for _ in 1:5000                                 # 100 s at dt=0.02
        step!(eng, 0.02)
    end
    @test maximum(state_series(eng).ΔPm) ≤ eng.params.headroom + 1e-6
    @test eng.nadir < sys.f0                         # frequency dipped
    @test current_state(eng).f < sys.f0              # and settles below nominal
    # Trajectory recorded one point per step (+ the seeded origin).
    traj = state_series(eng)
    @test length(traj.t) == length(traj.f) == length(traj.ΔPm)
    @test issorted(traj.t)

    # Tripping an already-offline unit is a no-op.
    d_before = eng.params.ΔP_dist
    inject!(eng, TripGenerator(:G1))
    @test eng.params.ΔP_dist == d_before

    # --- separate engine: a SMALL trip whose droop stays below headroom, so
    # the unsaturated settling closed form applies: Δω_ss = ΔP_dist/(D+1/R_eq).
    eng2 = init!(FrequencyResponseEngine, sys; dt = 0.02)
    inject!(eng2, TripGenerator(:G4))               # P0=60, small
    a2 = GridSim.aggregates(sys, eng2.online)
    for _ in 1:4000                                  # 80 s — well past settling
        step!(eng2, 0.02)
    end
    Δω_ss = (-60 / 550) / (a2.D + 1 / a2.R_eq)
    f_ss = sys.f0 * (1 + Δω_ss)
    @test isapprox(current_state(eng2).f, f_ss; atol = 0.02)
    @test current_state(eng2).ΔPm < a2.headroom      # never bound ⇒ clean settle
end

@testset "GeneratingUnit rejects negative headroom (Pmax < P0)" begin
    # A unit whose ceiling is below its output is negative reserve — it must
    # fail loud at construction, not silently poison the aggregate headroom.
    @test_throws ArgumentError GeneratingUnit(:bad, 100.0, 3.0, 80.0, 0.05, 50.0)
    # Pmax == P0 (zero headroom) is allowed.
    @test GeneratingUnit(:ok, 100.0, 3.0, 80.0, 0.05, 80.0) isa GeneratingUnit
end

@testset "inject!: tripping a non-existent unit throws (caller bug)" begin
    sys = example_system()
    eng = init!(FrequencyResponseEngine, sys)
    # The lookup runs BEFORE the online check, so an unknown id is reachable
    # and loud rather than a silent no-op.
    @test_throws KeyError inject!(eng, TripGenerator(:NOPE))
end

@testset "StepLoad sign: positive load lowers frequency" begin
    sys = example_system()
    eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
    # StepLoad is named for LOAD: +0.1 pu adds load ⇒ negative imbalance ⇒ dip.
    inject!(eng, StepLoad(0.1))
    @test eng.params.ΔP_dist ≈ -0.1
    for _ in 1:3000                                  # 60 s — well past settling
        step!(eng, 0.02)
    end
    @test current_state(eng).f < sys.f0              # added load ⇒ frequency falls
    # And shedding load raises it (mirror check on a fresh engine).
    eng2 = init!(FrequencyResponseEngine, sys; dt = 0.02)
    inject!(eng2, StepLoad(-0.1))
    for _ in 1:3000
        step!(eng2, 0.02)
    end
    @test current_state(eng2).f > sys.f0
end

@testset "inject! invalidates the FSAL cache (no stale-derivative first step)" begin
    # Bug: Tsit5 is FSAL — it reuses the cached RHS at the current state as the
    # next step's first stage. If inject! mutates params without u_modified!, the
    # first post-trip step integrates from the stale (pre-trip, ==0) derivative.
    sys = example_system()
    eng = init!(FrequencyResponseEngine, sys; dt = 0.001)
    step!(eng, 0.001)                                # seed a live (zero) FSAL cache
    @test current_state(eng).Δω == 0.0
    inject!(eng, TripGenerator(:G1))                 # true dΔω/dt jumps off zero
    a = GridSim.aggregates(sys, eng.online)
    dΔω0 = (-150 / 550) / (2 * a.H_sys)              # closed-form derivative at trip
    Δω0 = current_state(eng).Δω                      # still exactly 0 (state untouched)
    step!(eng, 0.001)
    # Realized average rate over the first post-trip step must match the true
    # derivative to O(dt); a stale-zero cache biases it low by ~10%, which this
    # tight rtol catches (the old atol=0.02 settling check absorbed it).
    rate = (current_state(eng).Δω - Δω0) / 0.001
    @test isapprox(rate, dΔω0; rtol = 2e-3)
end

@testset "second trip after saturation does not freeze the integrator" begin
    # Bug: inject! shrank headroom while leaving ΔPm pinned to the OLD ceiling,
    # so the isoutofdomain guard rejected every step until dt collapsed to an
    # abort — and step! then silently flatlined. The event-boundary re-init
    # (cap ΔPm to the new ceiling) plus the loud retcode check fix both halves.
    sys = example_system()
    eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
    inject!(eng, TripGenerator(:G1))                 # big trip ⇒ ΔPm rides the ceiling
    for _ in 1:3000                                  # 60 s ⇒ ΔPm pins at headroom
        step!(eng, 0.02)
    end
    @test isapprox(current_state(eng).ΔPm, eng.params.headroom; atol = 1e-3)

    # Second trip: new headroom (110/550 → 80/550) is BELOW the pinned ΔPm.
    inject!(eng, TripGenerator(:G3))
    @test eng.params.headroom ≈ 80 / 550
    # Re-init'd down to the new ceiling at the event boundary (not left stranded).
    @test current_state(eng).ΔPm ≤ eng.params.headroom + 1e-9
    n = length(state_series(eng).ΔPm)
    t0 = eng.integrator.t
    for _ in 1:2000                                  # must keep advancing, not abort
        step!(eng, 0.02)
    end
    @test eng.integrator.t > t0 + 39.0               # ~40 s of real progress, no freeze
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    # Post-trip trajectory never crosses the new (shrunken) ceiling.
    @test all(≤(eng.params.headroom + 1e-6), @view state_series(eng).ΔPm[n+1:end])
end

# --- M1 validation: closed forms + the low-inertia lesson (SPEC §7.6, §7.8)
#
# The engine-level testsets above prove the *mechanics* on one instance each.
# These sweep the same closed forms across every unit, and add the acceptance
# criterion the earlier tests do not touch at all: less online inertia ⇒
# steeper RoCoF and deeper nadir (SPEC §7.8 AC #6).
@testset "closed form: initial RoCoF, swept over every single-unit trip" begin
    # SPEC §7.6 / §7.8 AC #4. RoCoF0 = −f0·(P_k/S_base)/(2·H_sys), where H_sys
    # is the POST-trip aggregate — the tripped unit's inertia is gone the
    # instant it goes offline, which is the whole reason the number is
    # interesting. The state is still exactly the origin (Δω=0, ΔPm=0), so the
    # swing equation collapses to this with no transient contribution; read it
    # with no intervening step! or the state has already moved off the origin.
    sys = example_system()
    for u in sys.units
        eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
        inject!(eng, TripGenerator(u.id))
        a = GridSim.aggregates(sys, eng.online)
        @test a.H_sys > 0                     # never the all-offline edge (RoCoF → ∓Inf)
        expected = -sys.f0 * (u.P0 / sys.S_base) / (2 * a.H_sys)
        s = current_state(eng)
        @test s.RoCoF ≈ expected              # exact closed form, default rtol
        @test s.RoCoF < 0                     # losing generation ⇒ frequency falls
        @test s.Δω == 0.0                     # still at the origin: no state jump
        @test s.ΔPm == 0.0                    # governors have not moved yet
    end
end

@testset "closed form: settling deviation, swept over every trip" begin
    # SPEC §7.6 / §7.8 AC #5. Δω_ss = ΔP_dist/(D + 1/R_eq) — but ONLY while the
    # governors are unsaturated; the formula assumes ΔPm can reach the droop
    # demand *at the fixed point*. G2/G3/G4 do, so they get a tolerance that
    # bites: rtol = 1e-6, ~4 orders tighter than the ±0.02 Hz used in the
    # engine testset above. (That looseness is what once absorbed the stale-
    # derivative bug — a closed-form check with a tolerance looser than the
    # physics deserves is where the next bug hides.)
    sys = example_system()
    for id in (:G2, :G3, :G4)
        r = trip_and_run(sys, id)
        Δω_ss = (-P0_of(sys, id) / sys.S_base) / (r.aggr.D + 1 / r.aggr.R_eq)
        # Precondition, asserted not assumed — and stated on the *equilibrium*,
        # which is what the closed form is about: at the fixed point the droop
        # demand ΔPm_ss = −Δω_ss/R_eq must sit strictly under the ceiling, so
        # the saturation branch is inactive there. G2's overshoot does briefly
        # touch the ceiling on the way (measured, not assumed: its ΔPm_max sits
        # exactly at headroom), which clips the transient but cannot move the
        # equilibrium — the saturation is switched off again by the time the
        # trajectory settles. Hence the transient peak is checked against the
        # ceiling, not against the precondition.
        @test r.ΔPm_end < r.aggr.headroom - 1e-3
        @test r.ΔPm_max ≤ r.aggr.headroom + 1e-9
        @test isapprox(r.Δω_end, Δω_ss; rtol = 1e-6)
        @test isapprox(r.f_end, sys.f0 * (1 + Δω_ss); rtol = 1e-6)
    end

    # G1 is the counter-case that proves the precondition is load-bearing, not
    # decoration: its droop demand exceeds the surviving reserve, ΔPm pins at
    # the ceiling, and the system settles *below* the unsaturated formula. A
    # test suite that only ever checked the formula would call this a failure;
    # it is the physics (reserve exhaustion), and the ceiling still holds.
    r1 = trip_and_run(sys, :G1)
    Δω_ss_unsat = (-P0_of(sys, :G1) / sys.S_base) / (r1.aggr.D + 1 / r1.aggr.R_eq)
    @test isapprox(r1.ΔPm_end, r1.aggr.headroom; atol = 1e-6)   # pinned
    @test r1.Δω_end < Δω_ss_unsat                               # deeper than the formula
    @test r1.ΔPm_max ≤ r1.aggr.headroom + 1e-9                  # ceiling never crossed
end

@testset "less inertia ⇒ steeper RoCoF and deeper nadir (inertia-only)" begin
    # SPEC §7.8 AC #6 — the low-inertia/renewables lesson, isolated. Only the
    # inertia moves; the disturbance, droop gain, damping and reserve are
    # identical across all four systems, so any difference in the response is
    # attributable to inertia and nothing else.
    base = example_system()
    ks = (2.0, 1.0, 0.5, 0.25)                   # decreasing inertia
    rs = [trip_and_run(scale_inertia(base, k), :G4) for k in ks]

    # Settling is inertia-FREE: Δω_ss = ΔP_dist/(D + 1/R_eq) has no H in it.
    # So every config must land on the SAME frequency and differ only in how
    # far it dipped on the way. Asserting the equality alongside the ordering
    # is a much sharper statement of the lesson than the ordering alone.
    # Mixing sources here is deliberate and safe: the disturbance comes from
    # `base` while D/R_eq come from the k=2.0 config's aggregates — legal
    # *because* droop, damping and reserve are invariant under inertia
    # scaling, which is the very premise this testset rests on. If
    # `scale_inertia` ever grows to touch a second field, that invariance is
    # gone and this line silently compares against the wrong baseline instead
    # of failing, so the two must move together.
    a = rs[1].aggr
    Δω_ss = (-P0_of(base, :G4) / base.S_base) / (a.D + 1 / a.R_eq)
    f_ss = base.f0 * (1 + Δω_ss)
    for r in rs
        @test isapprox(r.Δω_end, Δω_ss; rtol = 1e-4)
        # No confound: if the ceiling bound in the low-inertia configs but not
        # the high-inertia ones, the "deeper nadir" would be partly reserve
        # exhaustion rather than inertia. Fail loudly instead of quietly.
        @test r.ΔPm_max < r.aggr.headroom - 1e-3
        # Not a vacuous ordering: each config must genuinely undershoot its
        # settling value. If a future parameter edit overdamped the system the
        # nadir would collapse onto f_ss in every config and the ordering below
        # would start passing on floating-point noise with nothing behind it.
        @test r.nadir < f_ss - 0.1
    end

    # Initial RoCoF: strictly steeper as inertia falls, and exactly inversely
    # proportional to it (halving H doubles RoCoF0 — same ΔP over half the
    # inertia). The exact ratio is a stronger check than the ordering.
    @test issorted([r.RoCoF0 for r in rs]; rev = true)   # increasingly negative
    for i in 2:length(ks)
        @test isapprox(rs[i].RoCoF0 / rs[1].RoCoF0, ks[1] / ks[i]; rtol = 1e-9)
    end

    # Nadir: strictly deeper as inertia falls. Physically — with a slow
    # governor (Tg = 8 s) the early fall is governed by inertia alone, so a
    # lighter system plunges further toward the damping-only asymptote before
    # the governors arrive to arrest it.
    @test issorted([r.nadir for r in rs]; rev = true)     # monotonically lower
    @test rs[end].nadir < rs[1].nadir - 0.5               # a visible gap, not noise
end

@testset "fewer units online ⇒ steeper RoCoF and deeper dip (SPEC AC #6)" begin
    # The literal wording of AC #6 ("fewer/less-inertia units online"). This is
    # the DEMONSTRATION, not the isolation: taking a unit offline moves inertia
    # and droop gain and reserve together, so unlike the inertia-only testset
    # above the two configs do NOT settle to the same frequency. Both effects
    # push the same way, which is exactly the operational point.
    sys = example_system()

    # Same disturbance (trip G4) in a full system vs one already missing G3.
    # Measure the dip relative to the pre-trip frequency, since the depleted
    # system is already below nominal when the second trip lands.
    function dip_after(pretrips, id; dt = 0.02, T = 150.0)
        eng = init!(FrequencyResponseEngine, sys; dt = dt)
        for p in pretrips
            inject!(eng, TripGenerator(p))
            for _ in 1:round(Int, T / dt)      # let the pre-trip fully settle
                step!(eng, dt)
            end
        end
        f_before = current_state(eng).f
        mark = length(state_series(eng).f)
        inject!(eng, TripGenerator(id))
        RoCoF0 = current_state(eng).RoCoF
        for _ in 1:round(Int, T / dt)
            step!(eng, dt)
        end
        tr = state_series(eng)
        tail = mark:length(tr.f)
        return (; RoCoF0, dip = f_before - minimum(@view tr.f[tail]),
                ΔPm_max = maximum(@view tr.ΔPm[tail]),
                headroom = GridSim.aggregates(sys, eng.online).headroom)
    end

    full = dip_after(Symbol[], :G4)
    thin = dip_after([:G3], :G4)

    @test thin.RoCoF0 < full.RoCoF0            # steeper (both negative)
    @test thin.dip > full.dip                  # deeper dip below the pre-trip point
    # And the second mechanism the depleted system exposes: its surviving
    # reserve is smaller, so the same trip now exhausts it. Ceiling still holds.
    @test full.ΔPm_max < full.headroom - 1e-3        # full system: reserve to spare
    @test isapprox(thin.ΔPm_max, thin.headroom; atol = 1e-6)   # depleted: pinned
    @test thin.ΔPm_max ≤ thin.headroom + 1e-9
end
