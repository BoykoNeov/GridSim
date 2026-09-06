# Orchestration (docs/SPEC.md 7.5): the event queue, the real-time loop and its
# pacing, the UI accessors, and the core-is-UI-free dependency closure.

# --- orchestration: event queue + real-time loop (docs/SPEC.md §7.5) ------
#
# Every loop test below terminates on its own: either a finite `duration` with
# `rtf = Inf` (no sleeping, so it cannot outlive the assertion it supports), or
# an explicit stopper wired to a state callback plus a wall-clock watchdog. A
# `while running[]` loop with wall-clock pacing is the classic way to hang a
# suite, and a hung suite is worse than a failing one.

@testset "load shedding: latching, downward-only, root-found" begin
    # The ladder is an ARMED PROTECTION SCHEME, not a user-injected event: it
    # fires on the system's own state, at a root-found instant, once per stage.
    sys = example_system()
    stage = LoadShedStage(49.5, 0.02; label = :s1)
    eng = init!(FrequencyResponseEngine, sys; dt = 0.01, shed = [stage])
    @test isempty(shed_log(eng.ladder).t)            # nothing fires at build
    @test eng.ladder.armed == [true]
    inject!(eng, TripGenerator(:G4))                 # -60/550 pu => dips past 49.5
    for _ in 1:1500; step!(eng); end                 # 15 s
    lg = shed_log(eng.ladder)
    @test length(lg.t) == 1                          # fired exactly once
    @test lg.label == [:s1]
    @test eng.ladder.armed == [false]                # latched
    @test shed_total(eng.ladder) ≈ 0.02
    # Root-found, not step-quantised: the crossing instant is (almost surely)
    # NOT on the dt grid, and f at that instant is the threshold to solver tol.
    t_fire = lg.t[1]
    @test 0 < t_fire < 15
    @test !isapprox(t_fire / 0.01, round(t_fire / 0.01); atol = 1e-6)
    tr = state_series(eng)
    i = argmin(abs.(tr.t .- t_fire))
    @test isapprox(tr.f[i], 49.5; atol = 0.02)       # within one dt of the grid
    # And it actually helped: same scenario without the ladder settles lower.
    bare = init!(FrequencyResponseEngine, sys; dt = 0.01)
    inject!(bare, TripGenerator(:G4))
    for _ in 1:1500; step!(bare); end
    @test current_state(eng).f > current_state(bare).f
end

@testset "load shedding: downward crossings only (affect_neg! slot)" begin
    # Positional-argument hazard: `ContinuousCallback(cond, affect!, affect_neg!)`
    # — `affect!` is the UPcrossing, `affect_neg!` the DOWNcrossing. Wire the shed
    # into the wrong slot and it fires as frequency RISES through the threshold:
    # physically backwards, and silent. Assert both polarities, don't trust the
    # signature.
    #
    # `example_system` is underdamped (ζ ≈ 0.28), so a load shed sends frequency
    # up through a threshold and the swing brings it back down through the same
    # one ~6 s later. That gives both crossings in ONE run, in a known order.
    sys = example_system()
    eng = init!(FrequencyResponseEngine, sys; dt = 0.01,
                shed = [LoadShedStage(50.5, 0.02; label = :both_ways)])
    inject!(eng, StepLoad(-0.3))                     # shed load => f climbs
    for _ in 1:200; step!(eng); end                  # t = 2 s: f ≈ 52.8, well past 50.5
    @test current_state(eng).f > 50.5                # the UPcrossing really happened
    @test isempty(shed_log(eng.ladder).t)            # ...and it did NOT fire
    @test eng.ladder.armed == [true]
    for _ in 1:600; step!(eng); end                  # t = 8 s: the swing brings it back
    @test current_state(eng).f < 50.5                # now a DOWNcrossing
    @test length(shed_log(eng.ladder).t) == 1        # ...and it fired
    @test 2.0 < shed_log(eng.ladder).t[1] < 8.0      # on the way down, not the way up
end

@testset "load shedding: a fired stage never re-arms" begin
    # The latch sign is the subtle part: a disarmed stage's condition must keep
    # the sign it had just AFTER firing (negative). Return +1.0 instead and the
    # rootfinder sees a manufactured sign change at the disarm instant => double
    # shed. This drives frequency back up through the threshold and down again.
    sys = example_system()
    eng = init!(FrequencyResponseEngine, sys; dt = 0.01,
                shed = [LoadShedStage(49.5, 0.001; label = :once)])
    inject!(eng, TripGenerator(:G1))                 # deep dip => fires
    for _ in 1:500; step!(eng); end
    @test length(shed_log(eng.ladder).t) == 1
    inject!(eng, StepLoad(-0.6))                     # haul it back above 49.5
    for _ in 1:2000; step!(eng); end
    @test current_state(eng).f > 49.5
    inject!(eng, StepLoad(0.6))                      # and back down through it
    for _ in 1:2000; step!(eng); end
    @test current_state(eng).f < 49.5
    @test length(shed_log(eng.ladder).t) == 1        # still exactly one shed
    @test shed_total(eng.ladder) ≈ 0.001
end

@testset "shed sign == StepLoad(-dP): shedding load raises frequency" begin
    # Pins the convention against a future sign flip: `ΔP_dist += ΔP_pu` for a
    # shed must be the exact mirror of `StepLoad`'s `ΔP_dist -= ΔP_pu`.
    sys = example_system()
    shed_amt = 0.02
    # Fire the ladder at a threshold the trip is guaranteed to cross.
    a = init!(FrequencyResponseEngine, sys; dt = 0.005,
              shed = [LoadShedStage(49.9, shed_amt; label = :x)])
    inject!(a, TripGenerator(:G4))
    for _ in 1:16000; step!(a); end                  # 80 s — well past settling
    @test length(shed_log(a.ladder).t) == 1
    # Equivalent hand-injected version: same trip, same shed as a StepLoad at the
    # root-found instant. Compare the SETTLING point, which is instant-independent.
    b = init!(FrequencyResponseEngine, sys; dt = 0.005)
    inject!(b, TripGenerator(:G4))
    inject!(b, StepLoad(-shed_amt))
    for _ in 1:16000; step!(b); end
    @test isapprox(a.params.ΔP_dist, b.params.ΔP_dist; rtol = 1e-12)
    # 80 s is ~3.5 damped periods past settling, so the two runs' different shed
    # INSTANTS have decayed out and only the shared fixed point is left. A flipped
    # sign would move that fixed point by ~0.11 Hz — 10⁴x this tolerance.
    @test isapprox(current_state(a).f, current_state(b).f; atol = 1e-5)
end

@testset "shed event is integrated, not just recorded (dt refinement)" begin
    # The shed affect! mutates `p` while leaving `u` alone — the stale-FSAL hazard
    # `inject!` arms against by hand. On the callback path DiffEqBase already sets
    # `derivative_discontinuity` before invoking the affect, so no explicit call is
    # needed there; this test is what keeps that true. It matters because the error
    # would be INVISIBLE to any readout assertion: `current_state` recomputes RoCoF
    # algebraically from `_dΔω`, so it would report the right post-shed value while
    # the integration drifted. Only refining dt and demanding convergence
    # discriminates.
    sys = example_system()
    stage = LoadShedStage(49.8, 0.05; label = :fsal)
    function run_to(dt, tend)
        eng = init!(FrequencyResponseEngine, sys; dt = dt, shed = [stage])
        inject!(eng, TripGenerator(:G1))
        for _ in 1:round(Int, tend / dt); step!(eng); end
        return eng
    end
    coarse = run_to(0.01, 3.0)
    fine   = run_to(0.001, 3.0)
    @test length(shed_log(coarse.ladder).t) == 1
    @test length(shed_log(fine.ladder).t) == 1
    # Root-found instant is a property of the trajectory, not of the sampling.
    @test isapprox(shed_log(coarse.ladder).t[1], shed_log(fine.ladder).t[1];
                   atol = 1e-4)
    # 10x refinement must not move the state: a stale-derivative step biases the
    # coarse run by ~dt*ΔP_shed/(2*H_sys), which this rtol rejects.
    @test isapprox(current_state(coarse).Δω, current_state(fine).Δω; rtol = 2e-3)
end

@testset "cumulative tripped MW counts generation only" begin
    # The second axis of report Figs 1-3 / 3-7 / 3-9 is tripped GENERATION.
    # Shed load is not generation and must not leak into it.
    sys = example_system()
    eng = init!(FrequencyResponseEngine, sys; dt = 0.01,
                shed = [LoadShedStage(49.5, 0.02; label = :s)])
    @test eng.tripped_mw == 0.0
    step!(eng)
    @test state_series(eng).tripped_mw[end] == 0.0
    inject!(eng, TripGenerator(:G1))                 # 150 MW
    step!(eng)
    @test eng.tripped_mw ≈ 150.0
    @test state_series(eng).tripped_mw[end] ≈ 150.0
    inject!(eng, TripGenerator(:G1))                 # already offline => no double count
    @test eng.tripped_mw ≈ 150.0
    inject!(eng, StepLoad(0.05))                     # load, not generation
    @test eng.tripped_mw ≈ 150.0
    inject!(eng, TripGenerator(:G3))                 # +70 MW
    for _ in 1:1500; step!(eng); end
    @test eng.tripped_mw ≈ 220.0
    @test !isempty(shed_log(eng.ladder).t)           # the ladder did fire...
    @test eng.tripped_mw ≈ 220.0                     # ...and did not touch the tally
    # The recorded series is aligned with the trajectory and non-decreasing.
    s = state_series(eng)
    @test length(s.tripped_mw) == length(s.t)
    @test issorted(s.tripped_mw)
    @test s.tripped_mw[end] ≈ 220.0
end

@testset "windowed_rocof: 500 ms sliding window, actual elapsed divisor" begin
    # Every RoCoF number in the ENTSO-E report is a 500 ms window (p.116); the
    # engine's `current_state` RoCoF is instantaneous. Different quantities.
    t = collect(0.0:0.01:2.0)
    f = 50.0 .- 2.0 .* t                             # exact -2 Hz/s ramp
    w = windowed_rocof(t, f)
    @test length(w) == length(t)
    @test all(isnan, w[t .< 0.5 - 1e-9])             # window not full yet => NaN
    @test all(x -> isapprox(x, -2.0; atol = 1e-9), filter(!isnan, w))
    @test count(!isnan, w) == count(>=(0.5 - 1e-9), t)
    # Non-uniform samples: the divisor is the ACTUAL elapsed time, not the
    # nominal window. Here the lookback lands 0.7 s back, not 0.5 s.
    tn = [0.0, 0.3, 1.0]
    fn = [50.0, 50.0, 49.0]
    wn = windowed_rocof(tn, fn)
    @test isnan(wn[1]) && isnan(wn[2])
    @test isapprox(wn[3], -1.0 / 0.7; atol = 1e-12)  # -1.4286, not -2.0
    # Window length is a knob.
    @test count(!isnan, windowed_rocof(t, f; window = 1.0)) < count(!isnan, w)
    @test_throws ArgumentError windowed_rocof(t, f[1:end-1])
    @test_throws ArgumentError windowed_rocof(t, f; window = 0.0)
    # NamedTuple method over a real trajectory: the windowed peak is strictly
    # shallower than the instantaneous one during a fast transient.
    eng = init!(FrequencyResponseEngine, example_system(); dt = 0.01)
    inject!(eng, TripGenerator(:G1))
    for _ in 1:1000; step!(eng); end
    s = state_series(eng)
    ww = windowed_rocof(s)
    @test ww.t === s.t
    @test length(ww.RoCoF) == length(s.t)
    @test minimum(filter(!isnan, ww.RoCoF)) > minimum(s.RoCoF)
end

@testset "inverter-based resources (H=0, R=Inf) give finite aggregates" begin
    # The Iberian scenario models the tripping blocks as IBR: zero inertia, no
    # droop, no headroom. This must stay expressible with no data-model change,
    # and must not produce NaN/Inf where a finite number belongs.
    pv = GeneratingUnit(:PV, 900.0, 0.0, 900.0, Inf, 900.0)
    sync = GeneratingUnit(:SYNC, 1000.0, 4.0, 600.0, 0.05, 800.0)
    sys = SystemModel(2000.0, 50.0, 1.5, 8.0, [sync, pv])
    a = GridSim.aggregates(sys, Set([:SYNC, :PV]))
    @test isfinite(a.H_sys) && a.H_sys ≈ 4.0 * 1000 / 2000     # PV adds no inertia
    @test isfinite(a.R_eq) && a.R_eq > 0                        # 1/Inf = 0, no NaN
    @test a.R_eq ≈ 1 / ((1 / 0.05) * 1000 / 2000)
    @test isfinite(a.headroom) && a.headroom ≈ (800 - 600) / 2000  # PV: zero reserve
    # An all-IBR set is the degenerate corner: no inertia, no droop, no NaN.
    b = GridSim.aggregates(sys, Set([:PV]))
    @test b.H_sys == 0.0 && b.R_eq == Inf && b.headroom == 0.0
    @test !isnan(b.H_sys) && !isnan(b.headroom)
    # And the engine runs with one in the mix: trip the PV, get a finite dip.
    eng = init!(FrequencyResponseEngine, sys; dt = 0.01)
    inject!(eng, TripGenerator(:PV))
    for _ in 1:1000; step!(eng); end
    st = current_state(eng)
    @test isfinite(st.f) && st.f < sys.f0
    @test all(isfinite, state_series(eng).f)
    @test eng.tripped_mw ≈ 900.0
end

@testset "Iberia scenario: the two-window structure, asserted not banded" begin
    # The headless script is a deliverable, so its claims are pinned here. It is
    # included as a MODULE so the scenario stays single-sourced (no second copy of
    # the event times in the test) without leaking its constants into the suite;
    # `main()` is guarded by PROGRAM_FILE, so including it runs nothing.
    #
    # THE TOLERANCES ENCODE A STRUCTURE, NOT A BAND. The model errs in opposite
    # directions on either side of ~12:33:17, and one symmetric "close enough"
    # band would hide both halves. So each window is asserted with its own SIGN.
    eng = Iberia.replay()
    s = state_series(eng)
    at(tq) = s.f[argmin(abs.(s.t .- tq))]

    # Window 1 — before loss of synchronism the model runs TOO DEEP, because
    # Iberia was still synchronously inside Continental Europe behind a finite
    # tie and was therefore stiffer than the isolated system modelled here.
    for (tq, fref) in ((55.0, 49.98), (60.0, 49.94), (76.9, 49.90), (77.9, 49.80))
        fm = at(tq)
        @test fm < fref                              # the SIGN is the claim
        @test fref - fm < 0.15                       # …and it stays small
    end

    # Window 2 — 12:33:20 is DELIBERATELY NOT BANDED. The centre-of-inertia model
    # cannot reproduce the last 5 s (plan doc §2): ~5,000 MW of the imbalance was
    # export swing from loss of synchronism, which a two-state swing + governor
    # model has no state for. With the real defence plan armed the model recovers
    # while reality collapsed, so this row is asserted as a KNOWN STRUCTURAL
    # FAILURE. It is not a target: closing it requires the two-area model, and
    # doing so must come with a conscious edit to this assertion — never with a
    # parameter tuned until the number matches.
    @test at(80.0) > 48.50 + 0.5
    @test eng.nadir > 49.0                           # the ladder arrests the fall

    # The defence plan fired the stages the report annotates, in threshold order.
    lg = shed_log(eng.ladder)
    @test length(lg.t) == 4
    @test lg.threshold_hz == [49.8, 49.7, 49.6, 49.5]
    @test issorted(lg.t)                             # in time order too
    @test isapprox(shed_total(eng.ladder) * eng.model.S_base, 3907.0; atol = 1.0)
    # Root-found, so the crossing instants are not on the dt grid.
    @test all(t -> !isapprox(t / 0.01, round(t / 0.01); atol = 1e-6), lg.t)
    # Reality did not reach 49.5 Hz until 12:33:20.133 (report p.174), i.e. AFTER
    # the fidelity boundary; the model gets there ~1.7 s early, the same too-deep
    # error as the waypoints above. Two-sided on purpose: a one-sided "more than
    # 1 s early" would also be satisfied by a run firing at 60 s for unrelated
    # reasons, which is not the claim being made.
    @test 78.0 < lg.t[end] < 79.0

    # Disarming the ladder must make it worse — the mechanism has to be load-bearing.
    # The armed nadir is pinned at the 49.5 Hz threshold (that stage arrests the
    # fall), the disarmed one lands at ~48.73, so the gap is ~0.77 Hz; 0.5 is a
    # deliberate margin under it, not a number that happened to pass. If the
    # ladder's contents change, this is the assertion that moves.
    bare = Iberia.replay(; shed = false)
    @test bare.nadir < eng.nadir - 0.5
    @test isempty(shed_log(bare.ladder).t)

    # Cumulative tripped generation: the scripted sequence, and a lower bound by
    # construction (the report calls the last cluster a floor).
    @test issorted(s.tripped_mw)
    @test s.tripped_mw[end] ≈ 355 + 725 + 930 + 2600

    # The one RoCoF claim that lies INSIDE the faithful window: the report states
    # |RoCoF| stayed within 1 Hz/s until 12:33:20.560 (p.116), measured over a
    # 500 ms sliding window. Instantaneous RoCoF is a different quantity and is
    # steeper by construction — asserted, so the two cannot be conflated later.
    w = windowed_rocof(s)
    inwin = findall(t -> t <= Iberia.T_BOUNDARY, s.t)
    wv = filter(!isnan, w.RoCoF[inwin])
    @test !isempty(wv)
    @test maximum(abs, wv) < 1.0                     # the report's claim
    @test maximum(abs, wv) > 0.2                     # non-vacuous
    @test maximum(abs, wv) < maximum(abs, s.RoCoF[inwin])
end

@testset "Iberia scenario: keying the base off KE makes RoCoF0 H-independent" begin
    # The report's 2.21–2.71 s inertia band is uncertainty about how to SPLIT the
    # measured kinetic energy between machines and motor load. `S_base = KE/H_tot`
    # makes f0·ΔP/(2·H_sys) collapse to f0·ΔP_MW/(2·KE), so that split cancels out
    # of the initial RoCoF exactly. The script prints this; here it is pinned, so
    # nobody later reads the identical column as an empirical insensitivity result.
    r_lo  = Iberia.rocof0(Iberia.H_LO, :E6)
    r_mid = Iberia.rocof0(Iberia.H_MID, :E6)
    r_hi  = Iberia.rocof0(Iberia.H_HI, :E6)
    @test isapprox(r_lo, r_mid; rtol = 1e-12)
    @test isapprox(r_hi, r_mid; rtol = 1e-12)
    @test isapprox(r_mid, -50.0 * 2600.0 / (2 * Iberia.KE); rtol = 1e-12)
    @test r_mid < 0                                  # a trip lowers frequency
end

@testset "EventQueue" begin
    q = EventQueue()
    @test isempty(q) && length(q) == 0
    @test isempty(drain!(q))                        # draining an empty queue is fine

    push!(q, TripGenerator(:G1))
    push!(q, StepLoad(0.05))
    @test length(q) == 2 && !isempty(q)

    evs = drain!(q)                                 # submission order preserved
    @test evs == [TripGenerator(:G1), StepLoad(0.05)]
    @test isempty(q)                                # …and the queue is now empty
    @test isempty(drain!(q))                        # a second drain yields nothing

    # The swap must hand out a *fresh* vector each time, not alias the one the
    # caller is still holding — otherwise a later push! would mutate it.
    push!(q, TripGenerator(:G2))
    @test length(evs) == 2                          # the earlier batch is untouched
    empty!(q)
    @test isempty(q)
end

@testset "timestep is the engine's own dt" begin
    eng = init!(FrequencyResponseEngine, example_system(); dt = 0.05)
    @test timestep(eng) == 0.05                     # what run_realtime! defaults to
end

@testset "UI accessors: system_inertia falls on a trip, is_online tracks it" begin
    sys = example_system()
    eng = init!(FrequencyResponseEngine, sys)
    # The indicator must agree with the aggregate, not merely be non-zero.
    @test system_inertia(eng) ≈ GridSim.aggregates(sys, Set(u.id for u in sys.units)).H_sys
    @test all(is_online(eng, u.id) for u in sys.units)
    @test !is_online(eng, :nope)                    # a button for a ghost unit, not a bug

    H_before = system_inertia(eng)
    inject!(eng, TripGenerator(:G1))
    @test !is_online(eng, :G1)
    @test is_online(eng, :G2)
    # Losing a unit removes its kinetic energy from the pool: strictly less inertia.
    @test system_inertia(eng) < H_before
    @test system_inertia(eng) ≈
        GridSim.aggregates(sys, Set([:G2, :G3, :G4])).H_sys
end

@testset "run_realtime! headless (rtf = Inf) with a queued trip" begin
    sys = example_system()
    eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
    obs = Observables.Observable(current_state(eng))
    q = EventQueue()
    push!(q, TripGenerator(:G1))                    # applied at the first step boundary

    out = run_realtime!(eng, obs; rtf = Inf, queue = q, duration = 2.0)

    @test out.engine === eng                        # returns the handles it used
    @test out.queue === q
    @test out.control isa RealtimeControl
    @test isempty(q)                                # the loop drained it
    @test !(:G1 in eng.online)                      # …and injected it

    @test isapprox(current_state(eng).t, 2.0; atol = 0.021)   # ran the sim duration
    @test obs[] == current_state(eng)                # published the latest state
    s = state_series(eng)
    # Seed point + ~100 steps of 0.02. Deliberately a *range*: whether the loop
    # takes 100 or 101 steps turns on where 100 accumulated additions of 0.02
    # land relative to 2.0 in Float64 — not a property worth asserting, and an
    # exact count would fail mysteriously on an integrator bookkeeping change.
    @test 101 ≤ length(s.t) ≤ 102
    @test length(s.f) == length(s.t) == length(s.RoCoF) == length(s.ΔPm)
    @test minimum(s.f) < sys.f0 - 0.05               # losing 150 MW dips frequency
    @test eng.nadir == minimum(s.f)
end

@testset "run_realtime! stops when control.running[] is cleared" begin
    eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
    obs = Observables.Observable(current_state(eng))
    ctl = RealtimeControl(; rtf = Inf)
    # Stop from a state callback: deterministic (counts published states, so it
    # also proves one publish per step) and independent of wall-clock timing.
    published = Ref(0)
    Observables.on(obs) do _
        published[] += 1
        published[] == 10 && stop!(ctl)
    end
    # `duration = Inf` on purpose — the callback is what must end this loop.
    run_realtime!(eng, obs; control = ctl, duration = Inf)
    @test published[] == 10
    @test !ctl.running[]
    @test isapprox(current_state(eng).t, 0.2; atol = 1e-9)   # exactly 10 × dt
end

@testset "run_realtime! honours pause and resumes without catch-up sprint" begin
    eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
    ctl = RealtimeControl(; rtf = Inf, paused = true)
    task = @async run_realtime!(eng, nothing; control = ctl, duration = 1.0)
    # Watchdog: whatever happens, this loop is over within 10 s wall-clock, so a
    # regression in the pause branch fails the test instead of hanging the suite.
    @async (sleep(10.0); stop!(ctl))

    sleep(0.2)
    @test current_state(eng).t == 0.0               # frozen: sim time did not advance
    @test ctl.running[]                             # …but the loop is alive
    ctl.paused[] = false
    wait(task)
    @test isapprox(current_state(eng).t, 1.0; atol = 0.021)   # resumed and finished
end

@testset "run_realtime! paces to wall-clock at rtf = 1" begin
    eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
    t_wall = @elapsed run_realtime!(eng, nothing; rtf = 1.0, duration = 0.2)
    @test isapprox(current_state(eng).t, 0.2; atol = 0.021)
    # Lower bound is the real assertion (it did sleep rather than sprint); the
    # upper bound is deliberately loose — timer resolution and CI load are noisy.
    @test 0.15 < t_wall < 3.0
    # Twice the speed must take less wall-clock time for the same sim duration.
    eng2 = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
    t_wall2 = @elapsed run_realtime!(eng2, nothing; rtf = 4.0, duration = 0.2)
    @test t_wall2 < t_wall
end

@testset "run_realtime! picks up an rtf change mid-run" begin
    # The pacing reads control.rtf[] fresh on every pass precisely so the UI's
    # speed slider takes effect immediately. Pin that down: start paced (slow
    # enough to be unmistakably sleeping), then switch to Inf from a state
    # callback — if the loop had captured rtf once at entry, the remaining steps
    # would still crawl and the elapsed time would blow past the bound.
    eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
    obs = Observables.Observable(current_state(eng))
    ctl = RealtimeControl(; rtf = 0.1)               # 0.2 s of sim ⇒ 2 s wall-clock
    Observables.on(_ -> (ctl.rtf[] = Inf), obs)      # …unless the first step frees it
    t_wall = @elapsed run_realtime!(eng, obs; control = ctl, duration = 0.2)
    @test isapprox(current_state(eng).t, 0.2; atol = 0.021)
    @test t_wall < 1.0                               # ≫ the ~1.8 s a stale rtf would cost
end

@testset "core dependency closure is UI-free and oracle-free" begin
    # The structural invariant (docs/SPEC.md §3.1): the core may reach Observables
    # — that is the seam live state crosses — but never a plotting package. The
    # positive half matters as much as the negative: without it this testset
    # would pass vacuously if `Pkg.dependencies()` ever returned nothing useful.
    names = [d.name for d in values(Pkg.dependencies())]
    @test "Observables" in names                     # positive control
    # The M2 network deps are named explicitly as *further* positive controls:
    # they arrived with ~60 transitive packages, and this scan is only evidence
    # about that closure if the closure it read actually contains them.
    @test "NetworkDynamics" in names
    @test "Graphs" in names
    @test !any(n -> occursin("Makie", n), names)     # the actual invariant
    # Makie is the invariant the SPEC names, but it is not the only way a UI
    # package could enter — a transitive plotting dep would violate §3.1 just
    # as much, and would not contain the string "Makie".
    @test !any(n -> n in ("Plots", "GR", "PyPlot", "PlotlyJS", "UnicodePlots"),
               names)

    # M4 step 4 (D3): the external oracle gets the same structural treatment
    # as the UI. `reference/` depends on GridSim and on PowerDynamics, and
    # never the reverse — so core keeps its six dependencies, `Pkg.test()` at
    # the root does not resolve the ~49 extra packages PowerDynamics brings,
    # and PowerDynamics stays the CHECKER rather than becoming a tier the mode
    # router offers.
    #
    # The three names are listed separately rather than matched on a substring
    # because they are three distinct ways in: the oracle itself, the whole
    # ModelingToolkit symbolic stack it is built on (which is the expensive
    # half of that closure), and PSID, which the SPEC used to name and which
    # `m4-context.md` §The dependency probes established is unusable here.
    @test !("PowerDynamics" in names)
    @test !("PowerSimulationsDynamics" in names)
    @test !any(n -> startswith(n, "ModelingToolkit"), names)
end
