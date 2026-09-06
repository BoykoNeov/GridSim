# M2 (second half) - line trips and the equilibrium they leave, the event log,
# the gauge-free angle reference, the UI prerequisites (step 7), and the COI view
# compiled down from the network model with its cross-fidelity checks (step 6).

@testset "SwingEngine V6: a line trip settles on the closed-form equilibrium" begin
    # The sharper half of step 5, and why it leads. A GENERATOR trip breaks
    # `Σ Pm = 0` and this tier has no governors, so nothing settles (see the
    # test above). A LINE trip changes no `Pm` at all, so the surviving network
    # still has an equilibrium — and on the ring, cutting one line leaves a
    # radial path B1–B2–B3 whose steady state is a chain of `asin`s:
    #   L12 must carry everything machine 1 injects           → asin(Pm₁ / K₁₂)
    #   L23 must carry that plus machine 2's                  → asin((Pm₁+Pm₂) / K₂₃)
    # Both couplings are read from `branch_arrays`, i.e. through the same code
    # path the engine integrates against — copying a hand-computed number is
    # exactly how the D8 coupling error survived its first sitting.
    net = three_machine_ring()
    ma, ba = machine_arrays(net), branch_arrays(net)
    bidx(id) = findfirst(b -> b.id === id, net.branches)
    K12, K23, K31 = ba.K[bidx(:L12)], ba.K[bidx(:L23)], ba.K[bidx(:L31)]
    pred12 = asin(ma.Pm[1] / K12)
    pred23 = asin((ma.Pm[1] + ma.Pm[2]) / K23)

    eng = init!(SwingEngine, net; dt = 0.05)
    n_state = length(eng.integrator.u)
    Pm_before = [eng.params[i] for i in eng.Pm_pidx]
    @test is_online(eng, :B3, :B1)
    inject!(eng, TripLine(:B3, :B1))

    @test !is_online(eng, :B3, :B1)
    @test is_online(eng, :B1, :B2) && is_online(eng, :B2, :B3)
    @test length(eng.integrator.u) == n_state              # never resized
    # No mechanical power moved — which is *why* an equilibrium survives.
    @test [eng.params[i] for i in eng.Pm_pidx] == Pm_before
    # Exactly one coupling died, and it is the one that used to be K31. (The
    # parameter vector is in GRAPH edge order, which is not branch order — so
    # this also re-checks the mapping the header warns about.)
    live = [eng.params[i] for i in eng.K_pidx]
    @test count(iszero, live) == 1
    @test sort(filter(!iszero, live)) ≈ sort([K12, K23])

    for _ in 1:4800; step!(eng, 0.05); end              # 240 s, finite by construction
    st = current_state(eng)
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    # Every machine back at rest — not merely the aggregate, which can sit at
    # zero while the machines run in opposite directions (see the split test).
    @test maximum(abs, st.ω) < 1e-9
    @test abs(st.ω_coi) < 1e-9
    # Angle DIFFERENCES only: absolute angles are gauge-dependent.
    @test st.δ[1] - st.δ[2] ≈ pred12 atol = 1e-9
    @test st.δ[2] - st.δ[3] ≈ pred23 atol = 1e-9
    # ...and the near misses, so the tolerance is doing work. Charging L23 with
    # machine 2's own injection instead of the cumulative flow lands 0.19 rad
    # out; using the wrong branch's coupling for the L12 leg lands 1.8e-3 out,
    # and that near one is what makes a loose tolerance a real risk.
    @test !isapprox(st.δ[2] - st.δ[3], asin(ma.Pm[2] / K23); atol = 1e-3)
    @test !isapprox(st.δ[1] - st.δ[2], asin(ma.Pm[1] / K31); atol = 1e-4)

    # Naming the line the other way round names the same line.
    other = init!(SwingEngine, net; dt = 0.05)
    inject!(other, TripLine(:B1, :B3))
    @test [other.params[i] for i in other.K_pidx] == live
    # Tripping it again is a no-op; a bus pair no branch joins is a caller bug;
    # a self-loop cannot be a branch and is refused by the event itself.
    @test inject!(eng, TripLine(:B3, :B1)) === eng
    @test_throws KeyError inject!(eng, TripLine(:B1, :B9))
    @test_throws ArgumentError TripLine(:B1, :B1)
end

@testset "SwingEngine: a line trip accelerates only its own two ends" begin
    # The second independent bite on the edge-ordering hazard, and one V2
    # cannot deliver: at the instant L31 opens, the machines at ITS ends jump by
    # ∓P₃₁/2H while the third machine's acceleration is exactly zero. Zero the
    # wrong edge and machine 2 moves. `P₃₁` is read off the fixpoint the engine
    # actually reached, so it comes through the real code path.
    net = three_machine_ring()
    ma, ba = machine_arrays(net), branch_arrays(net)
    b31 = findfirst(b -> b.id === :L31, net.branches)
    eng = init!(SwingEngine, net; dt = 0.01)
    δ0 = current_state(eng).δ
    src, dst = ba.src[b31], ba.dst[b31]                 # vertex indices, B3 → B1
    P31 = ba.K[b31] * sin(δ0[src] - δ0[dst])
    @test abs(P31) > 0.5                                # control: it carried real power

    inject!(eng, TripLine(:B3, :B1))
    du = similar(eng.integrator.u)
    eng.integrator.f(du, eng.integrator.u, eng.integrator.p, eng.integrator.t)
    acc = [du[i] for i in eng.ω_idx]
    # The end that was exporting P₃₁ keeps that power and speeds up; the end that
    # was receiving it loses it and slows down.
    @test acc[src] ≈ P31 / (2 * ma.H[src]) atol = 1e-12
    @test acc[dst] ≈ -P31 / (2 * ma.H[dst]) atol = 1e-12
    untouched = only(setdiff(1:3, [src, dst]))
    @test abs(acc[untouched]) < 1e-12
    # ...and that zero is not trivially small: the two ends jumped by ~1e-2.
    @test minimum(abs, acc[[src, dst]]) > 1e-3
end

@testset "SwingEngine: the event boundary drops the stale derivative" begin
    # Tsit5 is FSAL — it reuses the cached RHS at the current state as the next
    # step's first stage. Sitting on the fixpoint that cached derivative is
    # exactly zero, so an event that changes the system without telling the
    # integrator makes the first post-trip step start from a stale zero. The M1
    # version of this test is at "inject! invalidates the FSAL cache"; this is
    # the M2 pair of it, run over BOTH trip paths.
    #
    # MEASURED, so the tolerance is calibrated rather than guessed: with both
    # `derivative_discontinuity!` and `auto_dt_reset!` removed the realized first
    # step comes out 9.7% low (9.66% at dt=1e-3, 10.1% at dt=0.02) on every
    # machine that moves — so rtol 2e-3 separates them by a factor of ~50.
    #
    # RECORDED, not patched: the two calls are NOT separably observable here.
    # `auto_dt_reset!` re-evaluates the RHS as a side effect of re-estimating the
    # step, so either call alone suppresses the whole bias and only removing both
    # shows up. The test therefore asserts what is measurable and both calls stay
    # in `inject!` — see docs/plans/m2-context.md.
    net = three_machine_ring()
    for ev in (TripGenerator(:G1), TripLine(:B3, :B1))
        eng = init!(SwingEngine, net; dt = 0.001)
        step!(eng, 0.001)                       # seed a live (zero) FSAL cache
        @test maximum(abs, current_state(eng).ω) < 1e-12
        ω0 = copy(current_state(eng).ω)
        inject!(eng, ev)
        du = similar(eng.integrator.u)
        eng.integrator.f(du, eng.integrator.u, eng.integrator.p, eng.integrator.t)
        truth = [du[i] for i in eng.ω_idx]
        step!(eng, 0.001)
        rate = (current_state(eng).ω .- ω0) ./ 0.001
        moving = findall(a -> abs(a) > 1e-3, truth)
        @test length(moving) >= 2               # control: something has to move
        for i in moving
            @test isapprox(rate[i], truth[i]; rtol = 2e-3)
            # ...and the stale-cache answer is outside that band, so the
            # assertion above is not passing on slack.
            @test !isapprox(0.9034 * truth[i], truth[i]; rtol = 2e-3)
        end
    end
end

@testset "SwingEngine: a line trip may split the grid, and the aggregate lies" begin
    # Cutting the only line of the two-machine system leaves two islands. This
    # tier does not refuse that — it is a real event — but the single COI
    # read-out stops meaning anything: each island holds its own frequency, and
    # `ω_coi` is an inertia-weighted average of two unrelated numbers.
    net = two_machine_system()
    ma = machine_arrays(net)
    eng = init!(SwingEngine, net; dt = 0.02)
    br = only(net.branches)
    inject!(eng, TripLine(br.from, br.to))
    @test !is_online(eng, br.from, br.to)
    @test all(id -> is_online(eng, id), machine_ids(eng))   # no machine tripped
    @test all(iszero, [eng.params[i] for i in eng.K_pidx])

    for _ in 1:5000; step!(eng, 0.02); end                  # 100 s
    st = current_state(eng)
    # Decoupled and undriven, each machine runs until its own damping absorbs
    # its own injection: ωᵢ → Pmᵢ/Dᵢ. Opposite signs — one island speeds up by
    # 6% and the other slows by 3.75%, which is nothing like a power system and
    # everything like what this tier says happens.
    @test st.ω ≈ ma.Pm ./ ma.D atol = 1e-7
    @test st.ω[1] > 0.05 && st.ω[2] < -0.03
    # The aggregate is the inertia-weighted mean of those two, which is NOT zero
    # (it would be only if both machines shared an H/D ratio) and is NOT the
    # frequency of either island. Assert the derived value, and assert it is far
    # from both islands, because "≈ 0" would read as "nothing happened".
    pred = sum(ma.H .* (ma.Pm ./ ma.D)) / sum(ma.H)
    @test st.ω_coi ≈ pred atol = 1e-7
    @test abs(pred) > 1e-3
    @test abs(st.ω_coi - st.ω[1]) > 0.05 && abs(st.ω_coi - st.ω[2]) > 0.05
end

@testset "SwingEngine: a dead generator does not take its lines out of service" begin
    # `is_online` for a line is tracked, not inferred from "is K zero?" — because
    # a generator trip zeroes the coupling of every branch at its bus, and those
    # lines are still in service; they simply have nothing left to carry.
    net = three_machine_ring()
    eng = init!(SwingEngine, net; dt = 0.02)
    inject!(eng, TripGenerator(:G1))
    @test count(iszero, [eng.params[i] for i in eng.K_pidx]) == 2
    @test is_online(eng, :B1, :B2) && is_online(eng, :B3, :B1)
    @test !is_online(eng, :B1, :B9)          # unknown pair is false, not a throw
    # Tripping one of those lines afterwards is still a real state change.
    @test !is_online(inject!(eng, TripLine(:B1, :B2)), :B1, :B2)
end

@testset "SwingEngine: recording is bounded and the nadir is not read from it" begin
    net = two_machine_system()
    eng = init!(SwingEngine, net; dt = 0.02)
    # Pinned deliberately: the channel set of a running engine cannot be
    # changed afterwards, so it is a decision (step 7) rather than a detail.
    @test propertynames(state_series(eng)) ==
          (:t, :δ_G1, :δ_G2, :ω_G1, :ω_G2, :δ_coi, :f_coi)
    @test length(state_series(eng).t) == 1          # seeded pre-disturbance point
    inject!(eng, TripGenerator(:G1))
    for _ in 1:1000; step!(eng, 0.02); end
    @test length(state_series(eng).t) == 1001

    small = init!(SwingEngine, net; dt = 0.02, capacity = 64)
    inject!(small, TripGenerator(:G1))
    for _ in 1:1000; step!(small, 0.02); end
    @test GridSim.n_kept(small.traj) <= 64
    @test small.nadir ≈ eng.nadir atol = 1e-12      # summary, not a buffer read
    @test minimum(state_series(small).f_coi) > small.nadir + 1e-9
    # Wrong channel count is a named error, not a silent length mismatch.
    @test occursin("expected", argerr_msg(() ->
        GridSim.record!(small.traj, 0.0, [1.0, 2.0])))
end

# --- M2 step 7: what the UI needs before a line of drawing code -----------
#
# Three decisions the window depends on, asserted here rather than in `ui/`,
# because they are core behaviour and the core suite is what would catch a
# regression in them.

@testset "SwingEngine: applied events are logged, the trajectory cannot say it" begin
    net = three_machine_ring()
    eng = init!(SwingEngine, net; dt = 0.02)
    @test isempty(event_log(eng))
    @test n_events_dropped(eng) == 0

    for _ in 1:50; step!(eng); end
    t_line = eng.integrator.t
    inject!(eng, TripLine(:B1, :B2))
    for _ in 1:50; step!(eng); end
    t_gen = eng.integrator.t
    inject!(eng, TripGenerator(:G2))

    log = event_log(eng)
    @test length(log) == 2
    # The cheap question a redraw asks every frame, answered without copying.
    @test n_events(eng) == length(log)
    # The timestamp is the integrator's own clock at the moment of injection —
    # not a wall clock, and not a time the caller supplied.
    @test log[1].t == t_line
    @test log[2].t == t_gen
    @test log[1].kind === :trip_line
    # Logged by the branch's bus names, so the argument order a caller happened
    # to use does not change what the record says happened.
    @test (log[1].a, log[1].b) == (:B1, :B2)
    @test log[2].kind === :trip_generator && log[2].a === :G2
    @test describe_event(log[1]) == "trip line B1–B2"
    @test describe_event(log[2]) == "trip G2"

    # The log records what CHANGED the system, not what was asked for: the
    # no-op paths of both `inject!` methods leave no entry behind.
    inject!(eng, TripLine(:B2, :B1))         # already open, either order
    inject!(eng, TripGenerator(:G2))         # already offline
    @test length(event_log(eng)) == 2
    # ...and neither does an event that throws before it applies anything.
    @test_throws KeyError inject!(eng, TripGenerator(:G9))
    @test_throws KeyError inject!(eng, TripLine(:B1, :B9))
    @test length(event_log(eng)) == 2

    # It is a copy: a caller may keep it without holding a handle on the engine.
    keep = event_log(eng)
    inject!(eng, TripLine(:B2, :B3))
    @test length(keep) == 2 && length(event_log(eng)) == 3

    # And the point of the whole thing: nothing in the recorded channels says a
    # line opened. Every channel is a smooth per-machine or aggregate quantity,
    # and none of them is the event marker a played-back run would need.
    @test !any(n -> occursin("trip", String(n)) || occursin("event", String(n)),
               propertynames(state_series(eng)))
end

@testset "SwingEngine: the event log is bounded and says so" begin
    # Events are user clicks, so the cap is far above any session — but a
    # scripted driver must not turn this into the one vector that grows
    # forever. At the cap the EARLIEST events are kept (the same
    # start-is-what-matters choice the recorder makes when it decimates) and
    # the rest are counted rather than silently dropped.
    net = two_machine_system()
    eng = init!(SwingEngine, net; dt = 0.02)
    cap = GridSim._EVENT_LOG_CAP
    for k in 1:(cap + 10)
        # Straight at the log: a real trip is a no-op the second time, so the
        # cap is unreachable through `inject!` on a two-machine system.
        GridSim._log_event!(eng, :trip_generator, Symbol("G", k), Symbol(""))
    end
    log = event_log(eng)
    @test length(log) == cap
    @test n_events(eng) == cap               # the count stops at the cap too
    @test n_events_dropped(eng) == 10
    @test log[1].a === :G1                   # the start survives...
    @test log[end].a === Symbol("G", cap)    # ...and the tail is what was cut
end

@testset "SwingEngine: δ_coi is the gauge-free reference the angle traces need" begin
    net = three_machine_ring()
    eng = init!(SwingEngine, net; dt = 0.02)
    s = current_state(eng)

    # It is the same inertia-weighted mean as ω_coi, over the same live weights.
    @test s.δ_coi ≈ sum(eng.w .* s.δ) / sum(eng.w) atol = 1e-14

    # THE PROPERTY THAT MAKES IT THE RIGHT REFERENCE. `find_fixpoint` picks an
    # arbitrary gauge — shifting every angle by a constant is still the same
    # physical state — so an absolute angle is not a plottable quantity. Shift
    # the whole state and the aggregate shifts with it, leaving every machine's
    # angle *relative to it* untouched.
    rel_before = s.δ .- s.δ_coi
    for i in eng.δ_idx; eng.integrator.u[i] += 0.75; end
    s2 = current_state(eng)
    @test s2.δ_coi ≈ s.δ_coi + 0.75 atol = 1e-12
    @test s2.δ .- s2.δ_coi ≈ rel_before atol = 1e-12
    for i in eng.δ_idx; eng.integrator.u[i] -= 0.75; end   # put the gauge back

    # The recorded channel is the same number as the live read-out.
    step!(eng)
    tr = state_series(eng)
    @test tr.δ_coi[end] ≈ current_state(eng).δ_coi atol = 1e-14

    # A tripped machine leaves the reference, exactly as it leaves ω_coi: the
    # aggregate is the weighted mean over SURVIVORS, so it tracks the cluster
    # that is still running rather than being dragged by a decoupled rotor.
    inject!(eng, TripGenerator(:G1))
    for _ in 1:400; step!(eng); end
    s3 = current_state(eng)
    surv = [2, 3]
    @test s3.δ_coi ≈ sum(eng.w[surv] .* s3.δ[surv]) / sum(eng.w[surv]) atol = 1e-12
    # ...which is what keeps the picture readable: the survivors sit close to
    # the reference while the tripped machine visibly separates from it. Both
    # halves matter — a reference that drifted with the dead machine would push
    # the survivors off the axis instead.
    rel = s3.δ .- s3.δ_coi
    @test maximum(abs, rel[surv]) < 0.5           # survivors: on-screen
    @test abs(rel[1]) > 10 * maximum(abs, rel[surv])   # the tripped one: gone
end

@testset "SwingEngine: the bus-pair lookup is indexed, and both callers share it" begin
    net = three_machine_ring()
    eng = init!(SwingEngine, net; dt = 0.02)
    # One entry per branch, keyed by the unordered pair — so a branch cannot be
    # reachable under one bus order and missing under the other.
    @test length(eng.branch_of_buses) == length(net.branches)
    for (b, br) in pairs(net.branches)
        @test GridSim._find_branch(eng, br.from, br.to) == b
        @test GridSim._find_branch(eng, br.to, br.from) == b
        @test is_online(eng, br.from, br.to) && is_online(eng, br.to, br.from)
    end
    # The two callers still disagree only where they are meant to: a read-out
    # for a line that does not exist is `false`, injecting into one is a bug.
    @test GridSim._find_branch(eng, :B1, :B9) === nothing
    @test !is_online(eng, :B1, :B9)
    @test_throws KeyError inject!(eng, TripLine(:B1, :B9))
    # And the index still resolves the branch a trip must actually open.
    inject!(eng, TripLine(:B3, :B1))
    @test !is_online(eng, :B1, :B3)
    @test iszero(eng.params[eng.K_pidx[eng.branch_to_edge[3]]])   # L31, not another
end



# --- M2 step 6: the COI view, compiled down from the network model ---------
#
# `coi_model(net)` is what makes SPEC §3.2 true rather than aspirational: the
# aggregate model M1's engine runs on is *derived* from M2's network model, not
# hand-maintained beside it. The tests below are the cross-fidelity validation
# (V4) and the no-dense-network claim (V5), plus a direct assertion on the
# mapping itself — V4 alone lets a partially-wrong mapping through, because a
# model wrong in both H and D can still track early and diverge late.

@testset "coi_model: the mapping, and the wrong conversions by name" begin
    net = three_machine_ring()
    cm  = coi_model(net)
    ma  = machine_arrays(net)
    @test cm isa SystemModel
    @test (cm.S_base, cm.f0) == (net.S_base, net.f0)
    @test [u.id for u in cm.units] == machine_ids(init!(SwingEngine, net))  # bus order

    # H and S_rated go through RAW (on the machine's own base) because
    # `aggregates` applies `S_rated/S_base` itself; D is summed AFTER conversion
    # because `SystemModel.D` is already a system-base scalar. That asymmetry is
    # the trap in this function, so both halves are asserted against the wrong
    # conversions by name and not merely against the right one.
    a = GridSim.aggregates(cm, Set(u.id for u in cm.units))
    @test a.H_sys ≈ sum(ma.H) atol = 1e-12                  # = 43.0 s
    @test !isapprox(a.H_sys, sum(m.H for m in net.machines))            # unweighted: 12.0
    @test !isapprox(a.H_sys, sum(m.H * net.S_base / m.S_rated for m in net.machines))  # inverted: 3.83
    @test cm.D ≈ sum(ma.D) atol = 1e-12                     # = 20.0 pu/pu
    @test !isapprox(cm.D, sum(m.D for m in net.machines))               # unweighted: 6.0
    @test !isapprox(cm.D, sum(m.D * net.S_base / m.S_rated for m in net.machines))     # inverted: 2.07
    @test a.D == cm.D                                       # passed through, not re-weighted

    # Governor-free, because `three_machine_ring`'s machines are — NOT because
    # `coi_model` hard-codes it any more (M3 step 1). The distinction matters:
    # M2 deleted the governor on the way through so the two tiers differed by
    # inter-machine dynamics alone, and a view that deletes a property of the
    # canonical model is not a compiled view of it (SPEC §3.2). Now the droop
    # comes through and this fixture simply has none.
    @test all(u -> u.R == Inf, cm.units)
    @test a.R_eq == Inf
    @test all(u -> u.Pmax == u.P0, cm.units)
    @test a.headroom == 0.0
    @test cm.Tg == 1.0                                      # the no-droop fallback

    # …and with real droop it is passed through rather than discarded, on both
    # bases: `R` raw on the machine base (`aggregates` applies the weight) and
    # `Pmax` in MW. G2 alone has a governor here, so the aggregate gain is its
    # gain and the aggregate lag is its lag — the weighted mean's one case with
    # an unambiguous answer.
    one_gov = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
        [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05,   80.0),
         Machine(:G2, :B2, 200.0, 3.0, 2.0, 0.20, 1.03,   30.0, 0.05, 130.0, 7.0),
         Machine(:G3, :B3, 500.0, 5.0, 2.0, 0.50, 1.04, -110.0)])
    cg = coi_model(one_gov)
    ag = GridSim.aggregates(cg, Set(u.id for u in cg.units))
    @test [u.R for u in cg.units] == [Inf, 0.05, Inf]        # raw, machine base
    @test [u.Pmax for u in cg.units] == [80.0, 130.0, -110.0]
    @test 1 / ag.R_eq ≈ (1 / 0.05) * (200.0 / 100.0) ≈ 40.0  # gain carries the weight
    @test ag.headroom ≈ (130.0 - 30.0) / 100 ≈ 1.0
    @test cg.Tg == 7.0                                       # only voter, so it wins
    # The lag is weighted by droop GAIN, not by MVA and not unweighted: a machine
    # that does not respond gets no say in how fast the aggregate responds. With
    # two governors of unequal gain the three answers are different numbers, and
    # this is the one that ships (a choice with no oracle — see `coi_model`).
    two_gov = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
        [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05,   80.0),
         Machine(:G2, :B2, 200.0, 3.0, 2.0, 0.20, 1.03,   30.0, 0.05, 130.0,  2.0),
         Machine(:G3, :B3, 500.0, 5.0, 2.0, 0.50, 1.04, -110.0, 0.10, -10.0, 10.0)])
    g2, g3 = (1 / 0.05) * 2.0, (1 / 0.10) * 5.0              # 40.0 and 50.0
    @test coi_model(two_gov).Tg ≈ (g2 * 2.0 + g3 * 10.0) / (g2 + g3)
    @test coi_model(two_gov).Tg ≉ (2.0 + 10.0) / 2           # unweighted
    @test coi_model(two_gov).Tg ≉ (200.0 * 2.0 + 500.0 * 10.0) / 700.0   # MVA-weighted

    # P0 stays in engineering units (MW) and keeps its sign: a load is a machine
    # with negative P0, and it compiles to a unit with negative P0 *and* negative
    # Pmax (which `GeneratingUnit`'s headroom guard accepts, since Pmax ≥ P0).
    @test [u.P0 for u in cm.units] == [m.P0 for m in net.machines] == [80.0, 30.0, -110.0]
    @test [u.S_rated for u in cm.units] == [m.S_rated for m in net.machines]

    # The compiled units carry the *rotating* inertia of every machine, load
    # buses included — so the aggregate H is over all three, not over the two
    # net generators.
    @test a.H_sys ≈ 43.0 && a.H_sys > sum(ma.H[1:2])

    # Two machines is a different shape, same rules.
    cm2 = coi_model(two_machine_system())
    @test length(cm2.units) == 2
    @test cm2.D ≈ sum(machine_arrays(two_machine_system()).D) ≈ 13.0
end

@testset "coi_model: Tg is unobservable, and both reasons are asserted" begin
    # `Tg = 1.0` is arbitrary only because the governor state is identically
    # zero, which needs BOTH `R_eq = Inf` (no droop command) and `ΔPm(0) = 0`
    # (M1's state is a deviation).
    #
    # Scope, after M3 step 1: this is a property of a GOVERNOR-FREE model, not of
    # `coi_model` in general. `three_machine_ring` has no droop, so the fallback
    # fires and `Tg` is genuinely unobservable here. Compile a governed network
    # and `Tg` becomes load-bearing — and the aggregation that produces it is a
    # modelling choice nothing in this suite can distinguish (see `coi_model`).
    #
    # Assert the invariance rather than the comment:
    # a second model differing ONLY in Tg must give the same trajectory.
    net = three_machine_ring()
    cm  = coi_model(net)
    slow = SystemModel(cm.S_base, cm.f0, cm.D, 100.0, cm.units)
    a = init!(FrequencyResponseEngine, cm; dt = 0.02)
    b = init!(FrequencyResponseEngine, slow; dt = 0.02)
    inject!(a, TripGenerator(:G1)); inject!(b, TripGenerator(:G1))
    same = true
    for _ in 1:500
        sa = step!(a, 0.02); sb = step!(b, 0.02)
        same &= (sa.f == sb.f)                   # bit-identical, not merely close
    end
    @test same
    @test current_state(a).ΔPm == 0.0            # the governor never moved...
    @test current_state(a).f < 49.0              # ...but the frequency did
end

@testset "V4a: the aggregate view is EXACT where the tier's assumption holds" begin
    # The COI of the swing model obeys, exactly (the network terms cancel — the
    # branches are lossless):
    #     2·Σ_online H · dω_coi/dt = Σ_online Pm − Σ_online Dᵢ·ωᵢ
    # M1's aggregate obeys `2·H_sys·dΔω/dt = ΔP_dist − D_sys·Δω`. The two are the
    # SAME scalar ODE when (i) the tripped machine has D = 0, so the aggregate's
    # fixed D_sys equals Σ_online Dᵢ, and (ii) the survivors share D/H, so
    # Σ Dᵢωᵢ = D_sys·ω_coi even while they swing apart. Both hold here by
    # construction, so the two engines must agree for the WHOLE run — not just
    # early — and any error in the H or D mapping breaks it immediately: dropping
    # the weight on D here gives 4.0 instead of 15.5, so the aggregate would
    # settle at 40.0 Hz against the swing model's 47.42.
    net = ratio_ring()                            # D_G1 = 0; survivors D/H = 0.5
    ma  = machine_arrays(net)
    @test ma.D[1] == 0.0
    @test ma.D[2] / ma.H[2] ≈ ma.D[3] / ma.H[3] ≈ 0.5
    @test coi_model(net).D ≈ sum(ma.D) ≈ 15.5     # = Σ_online D, since D_G1 = 0

    r = lockstep_coi(net, :G1; nsteps = 3000)     # 60 s
    @test maximum(r.gap) < 1e-11                  # measured 7.1e-15 Hz

    # Not vacuous: the run is a real disturbance and the machines really do swing
    # against one another — the agreement is exactness, not stillness.
    @test r.f_sw[end] ≈ 50.0 * (1 + (sum(ma.Pm) - ma.Pm[1]) / sum(ma.D)) atol = 1e-3
    @test r.f_sw[end] < 47.5
    @test maximum(r.spread) > 1e-5                # measured 7.5e-5 pu ≈ 3.8 mHz
    # Inertia bookkeeping survives the event on both sides of the compile.
    @test system_inertia(r.sw) ≈ system_inertia(r.fr) ≈ sum(ma.H) - ma.H[1]
end

@testset "V4b: what the aggregate averages away, isolated and measured" begin
    # Same fixture, but the survivors' D/H ratios are no longer equal, so
    # condition (ii) above fails while (i) still holds. The two models therefore
    # start identical (same initial RoCoF) and settle identical (same ω_∞), and
    # the ONLY difference is the transient — which is exactly the inter-machine
    # swing content the aggregate model averages away. This is the number the
    # step-6 plan promised; V4c is where that promise does not hold.
    net = ratio_ring(; D3 = 2.0)                  # D/H = 0.5 vs 0.4
    ma  = machine_arrays(net)
    @test !isapprox(ma.D[2] / ma.H[2], ma.D[3] / ma.H[3])
    @test coi_model(net).D ≈ sum(ma.D) ≈ 13.0

    r = lockstep_coi(net, :G1; nsteps = 3000)     # 60 s
    peak, ipeak = findmax(r.gap)
    # Measured: 4.4325e-6 Hz at t = 0.26 s. Stable to 8 significant figures
    # from the solver's default tolerance down to reltol 1e-12 (see m2-context.md),
    # so it is the physics
    # and not integration error — which matters, because it sits BELOW the
    # solver's own default abstol and would otherwise be indistinguishable.
    @test peak ≈ 4.4325e-6 rtol = 5e-3
    @test 0.2 < r.t[ipeak] < 0.35
    # Both ends pinned: agree at the disturbance, agree at the new steady state.
    @test r.gap[2] < 1e-7                          # first post-trip sample
    @test r.gap[end] < 1e-8                        # 60 s, measured 1.2e-10

    # The "so what": the machines are 3.9 mHz apart from each other at the peak
    # of the swing, and only 4.4 µHz of that reaches the aggregate — a factor of
    # nearly 900 averaged away. Asserting the ratio is what makes this a
    # statement about the model rather than a small number with no scale.
    @test maximum(r.spread) * 50.0 / peak > 500
end

@testset "V4c: on the shipped ring the DAMPING gap dominates (the finding)" begin
    # The step-6 plan says the late divergence is "inter-machine swings the
    # aggregate averages away". On `three_machine_ring` that is not true, and the
    # test says so rather than quietly asserting a band that happens to pass.
    # M1's `D` is ONE system-wide constant that `aggregates` passes through
    # unchanged, so the aggregate keeps damping a machine that has tripped, while
    # the network model's damping leaves with it. The two therefore settle at
    # different frequencies, and that gap is ~200 000× the swing content V4b
    # isolated. Recorded as a finding in docs/plans/m2-context.md.
    net = three_machine_ring()
    ma  = machine_arrays(net)
    r = lockstep_coi(net, :G1; nsteps = 3000)     # 60 s

    # They DO track early: the initial RoCoF is analytically identical, because
    # `Σ P0 = 0` at construction makes `Σ Pm_online` equal M1's `ΔP_dist`, and
    # both models drop the tripped machine's inertia.
    @test r.gap[2] < 1e-4                          # first post-trip sample: 1.2e-5
    early = maximum(r.gap[r.t .<= 0.1])
    @test early < 5e-4                             # measured 3.0e-4 Hz at 0.1 s

    # And they DO diverge later — asserting only the tracking would pass
    # vacuously if `coi_model` ever returned something trivial. The ratio is the
    # honest statement of "track early, diverge later": ~2800× apart, measured.
    @test r.gap[end] > 0.8
    @test r.gap[end] / early > 1000

    # The divergence is a DERIVED number, not a band: Σ Pm_online over the
    # surviving damping, against the same numerator over the *whole* damping.
    ΣPm_online = sum(ma.Pm) - ma.Pm[1]             # = −Pm_G1, since Σ P0 = 0
    f_swing = 50.0 * (1 + ΣPm_online / (sum(ma.D) - ma.D[1]))   # 47.142857 Hz
    f_coi   = 50.0 * (1 + ΣPm_online / sum(ma.D))               # 48.0 Hz
    @test f_swing ≈ 47.142857 atol = 1e-5
    @test f_coi ≈ 48.0 atol = 1e-12
    @test r.gap[end] ≈ f_coi - f_swing atol = 1e-5   # residual 3.7e-6 is settling
    @test r.gap[end] < f_coi - f_swing               # ...and it approaches from below

    # The aggregate view has no line to trip at all: a `SystemModel` has no
    # branches, so `TripLine` is not merely inaccurate on it, it is unexpressible.
    # That is the honest boundary of the compiled view, and it is why step 5's
    # split-grid case has no cross-fidelity counterpart.
    @test_throws MethodError inject!(r.fr, TripLine(:B1, :B2))
end

@testset "V5: no n² structure anywhere the engine owns" begin
    # SPEC §4 forbids a dense admittance matrix. Under D3 the engine never
    # assembles *any* admittance matrix, so "assert it is not dense" is a
    # checkbox that cannot fail. The version with teeth is a count: coupling
    # lives on graph edges, so every array the engine owns must be linear in
    # (machines + branches), and a single dense Y-bus would break that by itself.
    #
    # Scope, stated: this covers the engine's own fields AND NetworkDynamics'
    # flat state/parameter arrays (which the engine shares, so their lengths are
    # upstream's storage, not ours). It does not reach inside the compiled
    # `Network` object. There, D3 holds by construction rather than by this test.
    #
    # `Base.summarysize` scaling was measured as an alternative and DROPPED: the
    # fixed per-machine overhead of the compiled network is ~2.4 kB, so a dense
    # n×n Float64 matrix does not overtake it until n ≈ 300. It would have passed
    # without discriminating, which is worse than an absent test.
    function big_ring(n)                 # even n, alternating ±P so Σ P0 = 0
        buses = [Bus(Symbol("B", i), 400.0) for i in 1:n]
        machines = [Machine(Symbol("G", i), Symbol("B", i), 200.0, 4.0, 2.0, 0.3,
                            1.05, isodd(i) ? 40.0 : -40.0) for i in 1:n]
        branches = [Branch(Symbol("L", i), Symbol("B", i), Symbol("B", mod1(i + 1, n)),
                           0.25, 500.0) for i in 1:n]
        return NetworkModel(100.0, 50.0, buses, branches, machines)
    end

    # Total elements across every container the engine holds. `incident` is a
    # vector of vectors, so its inner lengths are what count — that is where an
    # all-pairs structure would hide most naturally.
    #
    # `AbstractDict` is counted too, and that is not decoration: step 7 added a
    # bus-pair index, and a `Dict` is not an `AbstractArray`, so an array-only
    # sweep would have let an all-pairs *dictionary* be added later without
    # moving these counts or the slope beside them. Exactly the shape of this
    # file's own edge-order lesson — if no test would fail, write one.
    function array_elems(eng)
        tot = 0
        for f in fieldnames(SwingEngine)
            x = getfield(eng, f)
            if x isa AbstractDict
                tot += length(x)
                continue
            end
            x isa AbstractArray || continue
            @test !(x isa AbstractMatrix)          # nothing two-dimensional at all
            tot += eltype(x) <: AbstractArray ? sum(length, x) : length(x)
        end
        return tot
    end

    counts = Int[]
    for n in (4, 10, 40)
        net = big_ring(n)
        eng = init!(SwingEngine, net; dt = 0.02)
        nb, ne = length(net.buses), length(net.branches)
        @test length(eng.params) == 10nb + ne      # 10 per machine, 1 per branch
        @test length(eng.integrator.u) == 3nb      # (δ, ω, ΔPm) per machine
        @test sum(length, eng.incident) == 2ne     # each branch at exactly 2 buses
        @test length(eng.K_pidx) == ne
        @test length(eng.branch_of_buses) == ne     # one key per branch at EVERY n
        push!(counts, array_elems(eng))
    end
    # A tripwire, not a correctness claim: a legitimate new per-machine array
    # field changes these deliberately. The two assertions below are the claim.
    # Moved at M2 step 7, deliberately and by exactly the right amount: `δ_coi`
    # adds ONE element to the sample buffer regardless of n (17n+1 → 17n+2),
    # and counting the bus-pair index adds one key per branch, i.e. one per
    # machine on this ring (17n+2 → 18n+2). A per-machine mistake in the first
    # or an all-pairs structure in the second would have shifted the slope,
    # which the next assertion is what catches.
    #
    # Moved again at M3 step 1, by exactly 6n — and the whole point of the
    # tripwire is that the move has to be accounted for rather than re-pinned:
    # three new vertex parameters (`invR`, `headroom`, `Tg`) add 3n to the
    # shared parameter vector, and three new index vectors (`ΔPm_idx`,
    # `invR_pidx`, `hr_pidx`) add n each. 18n + 2 → 24n + 2. The recorder is
    # deliberately NOT in that list: `ΔPm` is read through `current_state`
    # rather than recorded as 1 channel per machine, which would have added
    # another n to the sample buffer and a per-machine trace nothing asked for.
    #
    # And again at M3 step 5, by exactly 4n, accounted for the same way: the
    # generation ramp's three vertex parameters (`rate`, `t_start`, `duration`)
    # add 3n, and ONE new index vector (`rate_pidx`) adds n. `t_start` and
    # `duration` deliberately get no index — they are written once at
    # construction and nothing may move them, so a handle to them would be a
    # handle to something with no writer. 24n + 2 → 28n + 2. `eng.ramps` is a
    # vector too, but it holds one entry per *armed* ramp and these rings arm
    # none, so it contributes zero here and cannot scale with n at all.
    @test counts == [114, 282, 1122]               # exactly 28n + 2

    # Linear, asserted as such: equal slope over both intervals. A dense n×n
    # anywhere would make the second slope 30× the first.
    @test (counts[2] - counts[1]) / (10 - 4) == (counts[3] - counts[2]) / (40 - 10)
    # The positive control, stated as a number: at n = 40 the engine's ENTIRE
    # array storage is 1122 elements, while one dense Y-bus alone would be 1600.
    # The margin has narrowed twice — 722 before the governor state, 962 before
    # the ramp — which is the honest reading: a linear model with a bigger
    # constant is still linear, and the slope assertion above is what actually
    # rules out the n² structure. It is also worth saying that this control
    # expires: at n = 40 the gap to 1600 is 478 elements, i.e. about twelve more
    # per-machine terms — six more parameters each carrying its own index vector
    # — would put the count past 40² while the model stayed perfectly linear. So
    # the slope is the claim and this line is a sanity check with a known shelf
    # life.
    @test counts[3] < 40^2
end
