# M4 - `solve!` and the playback half of the engine interface (step 1), and the
# divergence read over a matched pair of series (step 2).

# ======================= M4 step 1: `solve!` ================================
#
# THE AGREEMENT BAND, WRITTEN DOWN BEFORE ANY OF THE COMPARISONS BELOW RAN.
# Real-time and playback integrate the SAME equations under the SAME error
# control; they differ only in where the solver's steps are allowed to land.
# `run_realtime!` truncates the adaptive step at every output sample
# (`step!(integ, dt, true)`); `solve!` lets the solver choose its steps and
# reads the output grid off each step's interpolant. So the two trajectories
# differ by the sum of two independently controlled errors, and there is no
# reason whatever to expect agreement better than the tolerance itself.
#
#     band = 3 · reltol · (that channel's own peak excursion over the run)
#
# Three because two paths contribute two errors and neither is exact at the
# final time; the channel's excursion because a relative tolerance is relative
# to the signal the solver is resolving, not to zero. At the default
# `reltol = 1e-3` that is 0.3% of the swing. Asserting anything tighter than
# this would be asserting a fact about roundoff, not about the two modes
# agreeing — and a tolerance picked after seeing the gap tests nothing
# (m4-tasks.md step 4's rule, which applies here for the same reason).
#
# The band alone is still only half a check, so two controls sit beside it: an
# event placed where the real-time grid CANNOT represent it must land outside
# the band, and the same event deliberately delayed by one output step must
# too. Without those, "inside the band" cannot be told apart from "this
# comparison is always inside the band".
@testset "M4 step 1: solve! exists, for both engines" begin
    # The whole point of the step: until now `solve!` was a docstring. It is
    # still CommonSolve's generic (asserted at the top of this file); what is
    # new is that GridSim engines answer to it.
    @test hasmethod(solve!, Tuple{SwingEngine,Tuple{Float64,Float64}})
    @test hasmethod(solve!, Tuple{FrequencyResponseEngine,Tuple{Float64,Float64}})
    # And it returns the trajectory, which is the same object `state_series`
    # hands back — playback does not invent a second history format.
    eng = SwingEngine(two_machine_system())
    out = solve!(eng, (0.0, 0.5))
    @test out === state_series(eng)
    @test out.t[1] == 0.0
    @test out.t[end] ≈ 0.5
    @test issorted(out.t)
end

@testset "M4 step 1: real-time and playback agree, and the gap tracks the tolerance" begin
    net = two_machine_system()
    sys = example_system()
    dt, N, M = 0.02, 50, 200

    # --- the network tier ------------------------------------------------
    function swing_gap(rtol, atol)
        a, b = pb_both(() -> SwingEngine(net; reltol = rtol, abstol = atol),
                       TripGenerator(:G2), N, M, dt, N * dt)
        # Same number of samples and the same time base. NOT bit-identical:
        # real-time accumulates `t` by repeated addition of `dt` while the
        # playback grid is `t0 + k*dt`, which is a different roundoff path.
        @test length(a.t) == length(b.t) == N + M + 1
        @test maximum(abs.(a.t .- b.t)) < 1e-12
        return (f = maximum(abs.(a.f_coi .- b.f_coi)),
                δ = maximum(abs.((a.δ_G1 .- a.δ_G2) .- (b.δ_G1 .- b.δ_G2))),
                ω = maximum(abs.(a.ω_G1 .- b.ω_G1)),
                band_f = 3e-3 * pb_exc(b.f_coi),
                band_δ = 3e-3 * pb_exc(b.δ_G1 .- b.δ_G2),
                band_ω = 3e-3 * pb_exc(b.ω_G1))
    end
    loose = swing_gap(1e-3, 1e-6)
    @test loose.f <= loose.band_f
    @test loose.δ <= loose.band_δ
    @test loose.ω <= loose.band_ω
    # The gauge-free angle is checked, not the raw angles: `find_fixpoint`
    # picks an arbitrary common offset, so only differences mean anything (the
    # lesson M2 spent four names learning).

    # THE SECOND TOLERANCE, AND WHAT IT IS FOR. M3's standing rule is not "run
    # it twice" — it is that a number this small is only a result if it MOVES
    # when the tolerance moves. Tighten `reltol` by 1000× and the gap must
    # collapse; a gap that sat still would be a fixed disagreement (a
    # misplaced event, a wrong weight) wearing a small number as a disguise.
    tight = swing_gap(1e-6, 1e-9)
    @test tight.f <= tight.band_f
    @test tight.f * 10 < loose.f
    @test tight.δ * 10 < loose.δ
    @test tight.ω * 10 < loose.ω

    # --- the aggregate tier ----------------------------------------------
    # Both engines, because `solve!` is one shared driver and a bug in it
    # would not be visible in only one of them — but the channel sets differ,
    # so the assertion has to be written twice however shared the code is.
    function fr_gap(rtol, atol)
        a, b = pb_both(() -> FrequencyResponseEngine(sys; reltol = rtol, abstol = atol),
                       TripGenerator(:G3), N, M, dt, N * dt)
        @test length(a.t) == length(b.t) == N + M + 1
        @test maximum(abs.(a.t .- b.t)) < 1e-12
        return (f = maximum(abs.(a.f .- b.f)),
                P = maximum(abs.(a.ΔPm .- b.ΔPm)),
                band_f = 3e-3 * pb_exc(b.f), band_P = 3e-3 * pb_exc(b.ΔPm))
    end
    floose = fr_gap(1e-3, 1e-6)
    @test floose.f <= floose.band_f
    @test floose.P <= floose.band_P
    ftight = fr_gap(1e-6, 1e-9)
    @test ftight.f <= ftight.band_f
    @test ftight.f * 10 < floose.f
    @test ftight.P * 10 < floose.P
end

@testset "M4 step 1: the two controls — an event the real-time grid cannot place" begin
    # POSITIVE CONTROL. The agreement above says the comparison reads "same"
    # when the two runs are the same run. This says it reads "different" when
    # they are not — and it picks the difference playback exists to make
    # possible: an event at an instant the real-time grid cannot represent.
    # Real-time can only inject at a step boundary; `solve!` lands the
    # integrator on the exact instant with a tstop. Half an output step apart.
    #
    # `dt = 0.1` rather than 0.02 deliberately: the size of the discrepancy IS
    # the offset, so a coarse output grid makes the control separate cleanly
    # instead of hovering at the band's edge. This is the honest way to
    # strengthen a control — make the effect bigger, not the band tighter.
    net = two_machine_system()
    sys = example_system()
    dt, N, M = 0.1, 10, 40

    a, b = pb_both(() -> SwingEngine(net), TripGenerator(:G2), N, M, dt,
                   (N + 0.5) * dt)
    band = 3e-3 * pb_exc(b.f_coi)
    @test maximum(abs.(a.f_coi .- b.f_coi)) > 3 * band
    a, b = pb_both(() -> FrequencyResponseEngine(sys), TripGenerator(:G3), N, M, dt,
                   (N + 0.5) * dt)
    @test maximum(abs.(a.f .- b.f)) > 3 * (3e-3 * pb_exc(b.f))

    # ANTI-VACUITY CONTROL. The mechanism that makes the agreement real is the
    # `add_tstop!` that lands the integrator exactly on the event instant. Put
    # the event one whole output step late — what a broken schedule compilation
    # would do — and the agreement check must go red. Run here on the SAME
    # 0.02 s grid the agreement check uses, so it is that check being falsified
    # and not a different one.
    dt2, N2, M2 = 0.02, 50, 200
    a, b = pb_both(() -> SwingEngine(net), TripGenerator(:G2), N2, M2, dt2,
                   (N2 + 1) * dt2)
    @test maximum(abs.(a.f_coi .- b.f_coi)) > 3e-3 * pb_exc(b.f_coi)
    a, b = pb_both(() -> FrequencyResponseEngine(sys), TripGenerator(:G3), N2, M2, dt2,
                   (N2 + 1) * dt2)
    @test maximum(abs.(a.f .- b.f)) > 3e-3 * pb_exc(b.f)
end

@testset "M4 step 1: the sample AT an event is the pre-event one, in both modes" begin
    # The record-then-apply ordering inside `_playback!`, asserted from outside
    # it. `inject!` writes through the integrator in place, so the moment it
    # runs the finished step's interpolant is void — every sample inside that
    # step has to be recorded first. Nothing in the loop's shape says that, so
    # a later edit could reorder the two halves and only this test would notice.
    #
    # `tripped_mw` is the cleanest witness: it is a step function that moves
    # exactly when `inject!` runs, so "which side of the event is this sample
    # on" is readable straight off the trajectory.
    sys = example_system()
    dt, N, M = 0.02, 50, 200
    a, b = pb_both(() -> FrequencyResponseEngine(sys), TripGenerator(:G3), N, M, dt,
                   N * dt)
    i = N + 1                                  # the sample at t = 1.0 (t0 is #1)
    @test a.t[i] ≈ N * dt && b.t[i] ≈ N * dt
    @test a.tripped_mw[i] == 0.0               # real-time: pre-event…
    @test b.tripped_mw[i] == 0.0               # …and playback agrees
    @test a.tripped_mw[i + 1] > 0.0            # the NEXT sample is post-event
    @test b.tripped_mw[i + 1] > 0.0
    @test a.tripped_mw[i + 1] == b.tripped_mw[i + 1]
end

@testset "M4 step 1: protection stays a callback in playback (D4)" begin
    # The decision that makes every comparison in M4 mean anything: scheduled
    # events go through `perturbations=`, state-triggered protection does NOT.
    # A ladder root-finds its own firing instant off the system's own state, in
    # BOTH modes, from the callback the constructor built. If playback had
    # flattened it into a preset time, the two modes would be different systems.
    net = two_machine_system()
    stages = [LoadShedStage(49.0, 0.10), LoadShedStage(48.5, 0.10)]
    mk() = SwingEngine(net; shed = [:G2 => stages])
    dt, N, M = 0.02, 50, 200
    # Trip the GENERATOR (G1, +60 MW): the load machine G2 is left undriven and
    # its own frequency falls, which is the condition its ladder exists for.
    a, b = pb_both(mk, TripGenerator(:G1), N, M, dt, N * dt)

    # Rebuild each side once more to reach the ladders themselves (pb_both
    # returns trajectories, and the ladder's log is not a trajectory channel).
    rt = mk(); pb_steps!(rt, N, dt); inject!(rt, TripGenerator(:G1)); pb_steps!(rt, M, dt)
    pb = mk(); solve!(pb, (0.0, (N + M) * dt);
                      perturbations = [N * dt => TripGenerator(:G1)], saveat = dt)
    lr = shed_log(shed_ladder(rt, :G2))
    lp = shed_log(shed_ladder(pb, :G2))
    @test !isempty(lr.t)                      # it fires at all — the premise
    @test length(lr.t) == length(lp.t)        # …the same number of times…
    @test lr.ΔP_pu == lp.ΔP_pu                # …shedding the same blocks…
    @test lr.threshold_hz == lp.threshold_hz
    # …at the same instants. These are ROOT-FOUND, not grid points: the two
    # modes reach them through completely different step sequences, so their
    # agreeing to well inside an output step is the actual claim.
    @test maximum(abs.(lr.t .- lp.t)) < dt / 10
    @test shed_total(shed_ladder(rt, :G2)) == shed_total(shed_ladder(pb, :G2))

    # AND THE TRAJECTORIES AGREE THROUGH THE FIRINGS. This line is the
    # regression test for the bug that writing this step found, and it is
    # worth naming because a reader will otherwise see a line that looks like
    # a duplicate of the agreement check above.
    #
    # The first implementation of playback stepped freely and read each output
    # sample off the finished step's interpolant. That is wrong for exactly one
    # step per callback firing: the framework shortens the step to the root,
    # runs the affect, and recomputes the end-of-step derivative against the
    # NEW parameters, which bends the interpolant back across the interval that
    # has just closed. Every sample inside that one step came out wrong by up
    # to 3.4e-2 Hz — SIX TIMES the band — while its neighbours on either side
    # were right to 1e-9, and the error did not shrink cleanly with the
    # tolerance because its size is set by the step length. No scenario without
    # protection could see it; this one is the only place it shows.
    @test maximum(abs.(a.f_coi .- b.f_coi)) <= 3e-3 * pb_exc(b.f_coi)
    # Firing two stages must not degrade the agreement at all — the same
    # comparison on the same network with no ladder armed reaches ~1e-6, and a
    # scenario that root-finds twice on the way has no business being worse.
    # Stated as an absolute number rather than as a ratio to the band, because
    # the band is 1e4 times looser than either run and would hide the bug.
    @test maximum(abs.(a.f_coi .- b.f_coi)) < 1e-4
end

@testset "M4 step 1: the RELAY path too, not just the ladder (D9 generalised)" begin
    # The bug D9 records was measured on a shed ladder, whose affect steps a
    # parameter. An out-of-step relay's affect does strictly more: it calls
    # `inject!(::TripLine)`, which zeroes a coupling, logs an event, drops the
    # FSAL cache AND calls `auto_dt_reset!`. That is the affect M3 built for the
    # Iberian case, so "playback and real-time agree through a callback firing"
    # has to be shown on it and not only on the cheaper one — otherwise a
    # disagreement in step 4 would have two candidate causes.
    net = _pole_slip_net()
    dt, N, M = 0.01, 100, 500
    mk() = init!(SwingEngine, net; dt = dt,
                 out_of_step = [(:B1, :B3) => OutOfStepTrip(_SLIP_THR; label = :tie)])
    a, b = pb_both(mk, TripGenerator(:ESG), N, M, dt, N * dt)

    rt = mk(); pb_steps!(rt, N, dt); inject!(rt, TripGenerator(:ESG)); pb_steps!(rt, M, dt)
    pb = mk(); solve!(pb, (0.0, (N + M) * dt);
                      perturbations = [N * dt => TripGenerator(:ESG)], saveat = dt)
    gr = out_of_step_log(out_of_step_relay(rt, :B1, :B3))
    gp = out_of_step_log(out_of_step_relay(pb, :B1, :B3))
    @test gr.tripped && gp.tripped            # it fires at all — the premise
    @test !is_online(rt, :B1, :B3) && !is_online(pb, :B1, :B3)
    # The root-found instant, reached through two completely different step
    # sequences, and the angle it was found on.
    @test abs(gr.t - gp.t) < dt / 100
    @test abs(gr.δ - gp.δ) < 1e-9
    # Both event logs say the same two things happened, in the same order.
    @test [e.kind for e in event_log(rt)] == [e.kind for e in event_log(pb)]
    # And the trajectories agree through the firing. Absolute, not a fraction of
    # the band: after a pole slip the angles drift without bound, so the band
    # would be enormous and would hide anything.
    @test maximum(abs.(a.f_coi .- b.f_coi)) < 1e-4
end

@testset "M4 step 1: what `sol` does across chained solves, pinned not assumed" begin
    # `add_saveat!` puts the output grid into the integrator's own solution
    # object, which — unlike the `TrajectoryRecorder` behind `state_series` —
    # never decimates. That is accepted (see the note in `engines/playback.jl`)
    # because it is one entry per sample the CALLER ASKED FOR, which is a
    # different thing from the unbounded live history both constructors refuse.
    # Accepted is not the same as unmeasured, so it is asserted here: if a later
    # change makes `sol` grow faster than the grid, this says so.
    eng = SwingEngine(two_machine_system())
    base = length(eng.integrator.sol.t)
    @test base == 1                            # just the initial point
    for k in 1:4
        t = current_state(eng).t
        solve!(eng, (t, t + 1.0); saveat = 0.02)
        @test length(eng.integrator.sol.t) == base + 50k
        @test length(state_series(eng).t) == 1 + 50k
    end
end

@testset "M4 step 1: the mid-step weight guard watches a live quantity" begin
    # `_playback!` errors if the aggregate COI weight moves DURING a step,
    # because every sample the framework saved inside that step would then be
    # weighted by a machine set from the wrong side of the change. Nothing can
    # trip it today — a shed steps a power parameter, a relay opens a line, and
    # only a scheduled trip changes who is online, which the driver applies
    # after draining. That makes it a guard against a future change rather than
    # against a present bug, and an unexercised guard is one refactor away from
    # watching the wrong thing.
    #
    # So what is asserted is that the quantity is LIVE: it is the divisor
    # `_record_at!` actually uses, and it moves when the online set moves. (The
    # comparison itself is known live for a duller reason — it fired while this
    # step was being written, on a baseline that had not been refreshed after a
    # scheduled trip.)
    eng = SwingEngine(two_machine_system())
    @test GridSim._aggregate_weight(eng) == system_inertia(eng)
    before = GridSim._aggregate_weight(eng)
    inject!(eng, TripGenerator(:G2))
    @test GridSim._aggregate_weight(eng) < before        # the trip moves it…
    @test GridSim._aggregate_weight(eng) == system_inertia(eng)   # …and it is the read-out

    fr = FrequencyResponseEngine(example_system())
    @test GridSim._aggregate_weight(fr) == system_inertia(fr)
    b2 = GridSim._aggregate_weight(fr)
    # A load step is exactly the event that must NOT move it: it changes the
    # imbalance, not the online set. This is the half that makes the guard
    # usable rather than a tripwire on every event.
    inject!(fr, StepLoad(0.05))
    @test GridSim._aggregate_weight(fr) == b2
    inject!(fr, TripGenerator(:G3))
    @test GridSim._aggregate_weight(fr) < b2
end

@testset "M4 step 1: the interpolant is the solver's own, armed or not" begin
    # THE TRAP THIS TEST EXISTS FOR. OrdinaryDiffEq decides for itself whether
    # to keep each step's interpolation coefficients, and with `dense=false`,
    # `save_everystep=false` and no `saveat` it decides NO — unless a
    # root-finding callback happens to be present, which flips it back on.
    # Measured on this repo before the fix: a bare `SwingEngine` came out with
    # `calck = false` and the same engine with one relay armed came out `true`.
    # Playback reads samples from INSIDE a step, so that would have made the
    # accuracy of a recorded trajectory depend on whether the scenario happened
    # to arm a relay — quietly, and only in the third decimal.
    net = two_machine_system()
    bare = SwingEngine(net)
    armed = SwingEngine(net; out_of_step = [(:B1, :B2) => OutOfStepTrip(2π / 3)])
    fr = FrequencyResponseEngine(example_system())
    @test bare.integrator.opts.calck
    @test armed.integrator.opts.calck
    @test fr.integrator.opts.calck
    # Still off, so the fix is `calck` and not the unbounded-history one both
    # constructors refuse.
    @test !bare.integrator.opts.dense
    @test !bare.integrator.opts.save_everystep

    # And the behavioural half, ON A TRANSIENT — at the flat start every state
    # is ~1e-20 and a correct interpolant, a linear fallback and a stale cache
    # all return the same number, so a check there proves only that the call
    # does not throw. Two runs of one scenario: one reads t* off an
    # interpolant, the other is forced to land on t* exactly.
    tstar = 1.337
    free = SwingEngine(net)
    solve!(free, (0.0, 1.0); perturbations = [1.0 => TripGenerator(:G2)], saveat = 0.5)
    solve!(free, (1.0, 3.0); saveat = [tstar])
    forced = SwingEngine(net)
    solve!(forced, (0.0, 1.0); perturbations = [1.0 => TripGenerator(:G2)], saveat = 0.5)
    solve!(forced, (1.0, tstar); saveat = tstar - 1.0)
    s_free, s_forced = state_series(free), state_series(forced)
    @test s_free.t[end] ≈ tstar
    @test s_forced.t[end] ≈ tstar
    @test s_free.f_coi[end] ≈ s_forced.f_coi[end] rtol = 1e-6
    @test s_free.δ_G1[end] - s_free.δ_G2[end] ≈
          s_forced.δ_G1[end] - s_forced.δ_G2[end] rtol = 1e-6
end

@testset "M4 step 1: playback guards, one message each" begin
    net = two_machine_system()
    eng = SwingEngine(net)
    # The horizon must start where the engine actually is: an engine carries
    # its integrator's position, so solving "from 0" one already stepped to 3 s
    # would produce a trajectory whose time base is a lie.
    @test occursin("the engine is at t", argerr_msg(() -> solve!(eng, (1.0, 2.0))))
    @test occursin("must run forwards", argerr_msg(() -> solve!(eng, (0.0, 0.0))))
    @test occursin("must be (t_start, t_end)", argerr_msg(() -> solve!(eng, (0.0, 1.0, 2.0))))
    @test occursin("time => event", argerr_msg(
        () -> solve!(eng, (0.0, 1.0); perturbations = [TripGenerator(:G1)])))
    @test occursin("not a PerturbationEvent", argerr_msg(
        () -> solve!(eng, (0.0, 1.0); perturbations = [0.5 => :trip])))
    # Matched on the whole clause, not on "outside the horizon" alone: the
    # `saveat` guard below uses the same phrase, and two guards that a test
    # cannot tell apart is one guard that could be routed through the other.
    @test occursin("event scheduled at t = 2.0 lies outside the horizon", argerr_msg(
        () -> solve!(eng, (0.0, 1.0); perturbations = [2.0 => TripGenerator(:G1)])))
    @test occursin("saveat must be a positive", argerr_msg(
        () -> solve!(eng, (0.0, 1.0); saveat = 0.0)))
    @test occursin("strictly increasing", argerr_msg(
        () -> solve!(eng, (0.0, 1.0); saveat = [0.3, 0.2])))
    @test occursin("saveat[2] = 1.5 lies outside the horizon", argerr_msg(
        () -> solve!(eng, (0.0, 1.0); saveat = [0.3, 1.5])))
    # None of the above may have advanced the engine.
    @test current_state(eng).t == 0.0
    @test length(state_series(eng).t) == 1
end

@testset "M4 step 1: an explicit saveat grid, and continuing a solve" begin
    net = two_machine_system()
    eng = SwingEngine(net)
    grid = [0.0, 0.15, 0.4, 0.41, 1.0]     # irregular, and containing t0
    solve!(eng, (0.0, 1.0); saveat = grid)
    s = state_series(eng)
    # `t0` appears ONCE: the constructor already seeded it, so an explicit grid
    # naming it does not record it twice.
    @test s.t == [0.0, 0.15, 0.4, 0.41, 1.0]
    # Playback continues from where the engine is, so a run can be built in
    # pieces — which is what the interpolant test above relies on.
    solve!(eng, (1.0, 1.5); saveat = 0.25)
    @test state_series(eng).t ≈ [0.0, 0.15, 0.4, 0.41, 1.0, 1.25, 1.5]
    @test current_state(eng).t ≈ 1.5
end

@testset "M4 step 1: playback self-terminates on a step count" begin
    # Standing rule since M3: a long-running loop stops on a fixed step count,
    # never on a condition. Here it is in the driver itself, so a collapsed step
    # size surfaces as a named error instead of a hung session — asserted by
    # setting the cap absurdly low rather than by engineering a collapse.
    eng = SwingEngine(two_machine_system())
    msg = try
        solve!(eng, (0.0, 100.0); saveat = 0.1, maxiters = 3)
        "NO ERROR THROWN"
    catch e
        e isa ErrorException ? e.msg : "NOT-ErrorException: $(typeof(e))"
    end
    @test occursin("exceeded 3 solver steps", msg)
    @test occursin("SwingEngine", msg)
end


# ------------------------------------------------------------------------
# M4 step 2 — the divergence read (analysis/postprocess.jl).
#
# The step's finding is structural: both engines are built `dense = false`, so
# after `solve!` there is no interpolant left to resample with, and the read
# therefore REFUSES two grids rather than drawing lines between samples. The
# last testset below measures what that refusal is worth, on a real swing.
# ------------------------------------------------------------------------

@testset "M4 step 2: divergence by hand arithmetic" begin
    t = [0.0, 1.0, 2.0]
    a = [0.0, 0.0, 0.0]
    b = [0.0, 1.0, 0.0]
    d = divergence(t, a, b; band = 0.5)
    @test d.max == 1.0
    @test d.t_max == 1.0
    @test d.rms ≈ sqrt(0.5)                 # trapezoid of gap² = [0, 1, 0] over 2 s
    @test d.t_depart == 1.0
    @test d.n == 3
    # Symmetric in its two series.
    d2 = divergence(t, b, a; band = 0.5)
    @test d2.max == d.max && d2.rms == d.rms && d2.t_depart == d.t_depart
    # A band never crossed reads NaN for the departure and still reports the gap.
    d3 = divergence(t, a, b; band = 2.0)
    @test isnan(d3.t_depart)
    @test d3.max == 1.0
    # The RMS is TIME-weighted, not sample-weighted — a decimated tail has fewer
    # samples per second and must not be under-counted for it.
    t4 = [0.0, 1.0, 3.0]
    a4 = [0.0, 0.0, 0.0]
    b4 = [1.0, 1.0, 0.0]                    # gap² = [1, 1, 0]: ∫ = 1 + 1 = 2 over 3 s
    @test divergence(t4, a4, b4; band = 10.0).rms ≈ sqrt(2 / 3)
    # Non-finite samples (a windowed RoCoF's unfilled head) are skipped, not
    # propagated, and the RMS is over the spans actually compared.
    t5 = [0.0, 1.0, 2.0, 3.0]
    a5 = [NaN, 0.0, 0.0, 0.0]
    b5 = [NaN, 0.0, 2.0, 0.0]
    d5 = divergence(t5, a5, b5; band = 1.0)
    @test d5.n == 3
    @test d5.max == 2.0 && d5.t_max == 2.0 && d5.t_depart == 2.0
    @test d5.rms ≈ sqrt(2.0)                # gap² = [4] between two zeros, over 2 s
    # One compared sample: no span to average, the gap is the RMS.
    @test divergence([0.0], [1.0], [3.0]; band = 1.0).rms == 2.0
    # `tolerance_band`: factor · reltol · excursion, excursion from the FIRST
    # finite sample, level ignored (50 Hz with a 0.1 Hz swing is a 0.1 Hz signal).
    @test tolerance_band([50.0, 49.95, 49.9, 49.97]; reltol = 1e-3) ≈ 3e-4
    @test tolerance_band([NaN, 50.0, 49.9]; reltol = 1e-3, factor = 1) ≈ 1e-4
end

@testset "M4 step 2: divergence guards, one message each" begin
    t = [0.0, 1.0]
    z = [0.0, 0.0]
    @test_throws ArgumentError divergence(t, [0.0], z; band = 1.0)
    @test_throws ArgumentError divergence(t, z, z; band = 0.0)
    @test_throws ArgumentError divergence(t, z, z; band = -1.0)
    @test_throws ArgumentError divergence(t, z, z; band = Inf)
    @test_throws ArgumentError divergence([1.0, 0.0], z, z; band = 1.0)
    @test_throws ArgumentError divergence(t, [NaN, NaN], z; band = 1.0)
    @test_throws ArgumentError divergence(Float64[], Float64[], Float64[]; band = 1.0)
    @test_throws ArgumentError tolerance_band(z; reltol = 0.0)
    @test_throws ArgumentError tolerance_band([NaN, NaN]; reltol = 1e-3)
    # Two series on different grids are REFUSED, never resampled — the
    # structural half of "never straight-line between decimated samples".
    sa = (; t = [0.0, 0.5, 1.0], f = [50.0, 50.0, 50.0])
    sb = (; t = [0.0, 0.5],      f = [50.0, 50.0])
    sc = (; t = [0.0, 0.6, 1.0], f = [50.0, 50.0, 50.0])
    @test_throws ArgumentError divergence(sa, sb; band = 1.0)
    @test_throws ArgumentError divergence(sa, sc; band = 1.0)
    msg = try
        divergence(sa, sc; band = 1.0)
        "NO ERROR THROWN"
    catch e
        e isa ArgumentError ? e.msg : "NOT-ArgumentError: $(typeof(e))"
    end
    @test occursin("different grids", msg)
    @test occursin("nothing here resamples", msg)
    # …while the roundoff between two ways of building ONE grid (M4 step 1
    # measured it below 1e-12 s) is not a different grid.
    sd = (; t = [0.0, 0.5 + 1e-12, 1.0], f = [50.0, 50.0, 50.0])
    @test divergence(sa, sd; band = 1.0).max == 0.0
    # The cross-tier channel: `f_coi` first, then `f`, never a per-machine one.
    @test system_frequency((; t = [0.0], f_coi = [49.0])) == [49.0]
    @test system_frequency((; t = [0.0], f = [49.5])) == [49.5]
    @test system_frequency((; t = [0.0], f = [1.0], f_coi = [2.0])) == [2.0]
    @test_throws ArgumentError system_frequency((; t = [0.0], ω_G1 = [0.0]))
    # An explicit selector is how anything else gets compared, deliberately.
    se = (; t = [0.0, 1.0], δ_G1 = [0.0, 0.2], δ_G2 = [0.0, 0.1])
    sf = (; t = [0.0, 1.0], δ_G1 = [0.0, 0.3], δ_G2 = [0.0, 0.1])
    @test divergence(se, sf; band = 0.05, channel = s -> s.δ_G1 .- s.δ_G2).max ≈ 0.1
end

@testset "M4 step 2: same series twice reads zero; the exact pair reads inside the band" begin
    # ANTI-VACUITY: the read must say "identical" when it is handed one run
    # twice, exactly, with no departure.
    net = ratio_ring()                          # V4a's fixture: the aggregate is EXACT here
    a, b = overlay_pair(net, TripGenerator(:G1), 0.0, 20.0)
    same = divergence(a, a; band = 1e-12)
    @test same.max == 0.0 && same.rms == 0.0 && isnan(same.t_depart)
    @test same.n == length(a.t)

    # POSITIVE CONTROL FOR AGREEMENT: where the two tiers are the same scalar
    # ODE (V4a's derivation), two separately error-controlled solves must agree
    # inside the band stated up front, and the band tracks the tolerance.
    band = tolerance_band(a.f_coi; reltol = 1e-3)
    d = divergence(a, b; band = band)
    @test d.n == length(a.t) == 1001
    @test d.max <= band
    @test isnan(d.t_depart)
    # Not vacuous: this is a real 2.5 Hz disturbance, not two flat lines.
    @test a.f_coi[end] < 47.5
    # Tightening the tolerance 1000× must shrink the gap at least 10× — a gap
    # that sat still would be a fixed disagreement wearing a small number.
    a2, b2 = overlay_pair(net, TripGenerator(:G1), 0.0, 20.0; reltol = 1e-6, abstol = 1e-9)
    d2 = divergence(a2, b2; band = tolerance_band(a2.f_coi; reltol = 1e-6))
    @test d2.max <= tolerance_band(a2.f_coi; reltol = 1e-6)
    @test d2.max * 10 < d.max
end

@testset "M4 step 2: the departure is located, sized, and never before the event" begin
    # POSITIVE CONTROL FOR DIVERGENCE: on the shipped ring the aggregate keeps
    # the damping of the tripped machine and settles elsewhere (V4c, a derived
    # number, not a band). The read must find that departure, place it AFTER
    # the trip (both tiers start flat on their fixpoints), and size it.
    net = three_machine_ring()
    ma = machine_arrays(net)
    t_trip = 1.0
    a, b = overlay_pair(net, TripGenerator(:G1), t_trip, 60.0)
    band = tolerance_band(a.f_coi; reltol = 1e-3)
    d = divergence(a, b; band = band)
    @test d.n == length(a.t) == 3001
    @test !isnan(d.t_depart)
    @test d.t_depart >= t_trip                 # nothing diverges before anything happens
    @test d.t_depart > t_trip + 0.1            # …and they track early (V4c: < 5e-4 Hz at 0.1 s)
    @test d.max > 0.8                          # ~0.86 Hz on this ring (V4c)
    @test d.max > 3 * band                     # clearly outside the band, not at its edge
    # The end gap is V4c's derived number, now read off two PLAYBACK series.
    ΣPm_online = sum(ma.Pm) - ma.Pm[1]
    f_swing = 50.0 * (1 + ΣPm_online / (sum(ma.D) - ma.D[1]))
    f_coi   = 50.0 * (1 + ΣPm_online / sum(ma.D))
    @test abs(a.f_coi[end] - b.f[end]) ≈ f_coi - f_swing atol = 1e-4
    # Before the trip both sit on their own flat starts, so the gap there is
    # fixpoint-solver residual, far inside the band.
    pre = a.t .< t_trip
    @test maximum(abs.(a.f_coi[pre] .- b.f[pre])) < 1e-6
end

@testset "M4 step 2: a physical residual below the band is invisible until the band moves" begin
    # V4b isolated a 4.4325 µHz peak at t ≈ 0.26 s — the inter-machine swing
    # content the aggregate averages away, stable to 8 figures across
    # tolerances. That number sits BELOW the default-tolerance band, so the
    # read must call it "indistinguishable" there, and must find it — located
    # and sized — once the stated band drops beneath it. The read is only as
    # sharp as the band it is handed; this is that fact, asserted.
    net = ratio_ring(; D3 = 2.0)
    a, b = overlay_pair(net, TripGenerator(:G1), 0.0, 3.0)
    loose = divergence(a, b; band = tolerance_band(a.f_coi; reltol = 1e-3))
    @test isnan(loose.t_depart)
    a2, b2 = overlay_pair(net, TripGenerator(:G1), 0.0, 3.0; reltol = 1e-9, abstol = 1e-12)
    band2 = tolerance_band(a2.f_coi; reltol = 1e-9)
    @test band2 < 4.4325e-6                    # the band really is below the physics now
    tight = divergence(a2, b2; band = band2)
    @test !isnan(tight.t_depart)
    @test tight.t_depart <= tight.t_max
    @test tight.max ≈ 4.4325e-6 rtol = 5e-2
    @test 0.2 < tight.t_max < 0.35
end

@testset "M4 step 2: what straight-line resampling would have cost (the second control)" begin
    # THE ANTI-VACUITY CONTROL FOR THE REFUSAL. The read refuses two grids. Had
    # it instead drawn straight lines between a coarser run's samples to land
    # them on the finer grid — the obvious implementation — the line's own error
    # would sit in the answer. Measure it: the SAME engine, the SAME scenario,
    # once at the fine grid and once at a 10× coarser one, the coarse run
    # interpolated linearly onto the fine grid. On a gauge-free angle difference
    # swinging at ~1–2 Hz the interpolation error must sit far outside the band.
    net = three_machine_ring()
    ev = TripLine(:B3, :B1)                    # V6: an equilibrium survives, so it RINGS
    solve_at(dt) = (eng = SwingEngine(net);
                    solve!(eng, (0.0, 10.0); perturbations = [0.5 => ev], saveat = dt);
                    state_series(eng))
    fine, coarse = solve_at(0.02), solve_at(0.2)
    @test length(fine.t) == 501 && length(coarse.t) == 51
    chan(s) = s.δ_G1 .- s.δ_G2
    band = tolerance_band(chan(fine); reltol = 1e-3)
    # Control of the control: at the instants the two grids SHARE, the two runs
    # agree inside the band — so whatever the next read finds is the resampling.
    shared = (; t = fine.t[1:10:end], y = chan(fine)[1:10:end])
    @test isnan(divergence(shared, (; t = coarse.t, y = chan(coarse));
                           band = band, channel = s -> s.y).t_depart)
    # Now the thing the read refuses to do, done by hand.
    lerp(tq, tc, yc) = map(tq) do τ
        j = clamp(searchsortedlast(tc, τ), 1, length(tc) - 1)
        yc[j] + (yc[j + 1] - yc[j]) * (τ - tc[j]) / (tc[j + 1] - tc[j])
    end
    resampled = lerp(fine.t, coarse.t, chan(coarse))
    d = divergence(fine.t, chan(fine), resampled; band = band)
    @test !isnan(d.t_depart)
    # Flat before the trip, so nothing to mis-draw — until the coarse span that
    # STRADDLES the trip (0.4–0.6 s), where a straight line from a flat sample to
    # a moved one is already wrong at 0.42 s. That is the mechanism, not slack.
    @test d.t_depart > 0.4
    @test d.max > 3 * band                     # far outside, not at the edge
end
