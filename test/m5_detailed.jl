# M5 step 1 — the algebraic network, the power flow, and the flat run.
#
# The three land together because none of them is testable without the others:
# the flat run is the check on the initialisation, the initialisation needs the
# power flow, and the power flow needs a network whose bus voltages are unknowns.
#
# EVERY NUMBER BELOW WAS MEASURED BEFORE IT WAS ASSERTED. Where a check has a
# positive control it is the *real* bug rather than a stand-in, and where a
# quantity is expected to differ the test asserts its SIZE, not merely that it
# differs (M2's standing lesson — a loosened tolerance is not a finding).

@testset "M5 step 1 — the detailed (DAE) tier" begin

# --- the Load type ----------------------------------------------------------
@testset "Load: what the canonical model will and will not accept" begin
    @test Load(:L, :B, 100.0, 25.0) isa Load
    # the default IS constant impedance — the case with a closed form
    @test Load(:L, :B, 100.0, 25.0).a_z == 1.0
    @test Load(:L, :B, 100.0, 25.0).a_i == 0.0
    @test Load(:L, :B, 100.0, 25.0).a_p == 0.0
    # zero P is legal (a purely reactive shunt is a real device); negative is not
    @test Load(:L, :B, 0.0, 25.0) isa Load
    @test occursin("must be ≥ 0 MW", argerr_msg(() -> Load(:L, :B, -1.0, 0.0)))
    @test occursin("Machine", argerr_msg(() -> Load(:L, :B, -1.0, 0.0)))
    # Q may be negative — a capacitive bus
    @test Load(:L, :B, 100.0, -25.0) isa Load
    # the shares must sum to one, or `P0` silently stops meaning "drawn at V = 1"
    @test occursin("sum to 1", argerr_msg(() -> Load(:L, :B, 100.0, 0.0, 0.5, 0.2, 0.0)))
    @test occursin("must be ≥ 0", argerr_msg(() -> Load(:L, :B, 100.0, 0.0, 1.5, -0.5, 0.0)))
    @test Load(:L, :B, 100.0, 0.0, 0.4, 0.35, 0.25) isa Load     # a valid ZIP split
end

@testset "load_bus_system: the fixture the flat run needs to have content" begin
    net = load_bus_system()
    @test net isa NetworkModel
    @test length(net.machines) == 2
    @test length(net.loads) == 1
    # B3 is the thing the classical tier cannot represent at all
    v3 = net.bus_index[:B3]
    @test isempty(net.machines_at_bus[v3])
    @test net.load_at_bus[v3] == 1
    @test load_at(net, :B3).id === :L3
    @test load_at(net, :B1) === nothing
    @test machines_at(net, :B3) == Machine[]
    @test length(machines_at(net, :B1)) == 1
    # the balance guard sees a load's P0 as a DRAW, opposite in sign to a machine's
    @test sum(m.P0 for m in net.machines) ≈ sum(l.P0 for l in net.loads)
    # and the classical tier refuses it, by name, from all three entry points
    @test occursin("carries no machine", argerr_msg(() -> init!(SwingEngine, net)))
    @test occursin("carries no machine", argerr_msg(() -> coi_model(net)))
    @test occursin("branch_arrays", argerr_msg(() -> branch_arrays(net)))
    # `coi_model` names the LOAD too, not just the empty bus — the two refusals are
    # distinct and a model could hit either first
    let with_load = NetworkModel(100.0, 50.0, [Bus(:B1, 400.0), Bus(:B2, 400.0)],
                                 [Branch(:L12, :B1, :B2, 0.25, 500.0)],
                                 [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 60.0),
                                  Machine(:G2, :B2, 400.0, 5.0, 2.0, 0.30, 1.02, -50.0)],
                                 [Load(:L2, :B2, 10.0, 2.0)])
        @test occursin("unvalidated modelling claim", argerr_msg(() -> coi_model(with_load)))
        @test occursin("constant-magnitude E", argerr_msg(() -> init!(SwingEngine, with_load)))
    end
end

# --- topology views ---------------------------------------------------------
@testset "branch_topology: the machine-free view of the branches" begin
    net = load_bus_system()
    bt = branch_topology(net)
    @test length(bt.src) == 3
    # it agrees with `branch_arrays` wherever `branch_arrays` is legal at all
    let ring = three_machine_ring()
        ba, bt2 = branch_arrays(ring), branch_topology(ring)
        @test bt2.src == ba.src && bt2.dst == ba.dst && bt2.X == ba.X
    end
end

# --- the engine's own preconditions ----------------------------------------
@testset "DetailedEngine preconditions: refused by name, with the step named" begin
    net = load_bus_system()
    # a bus with two machines: the canonical model expresses it, this engine does not
    two_up = NetworkModel(100.0, 50.0, net.buses, net.branches,
                          [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 70.0),
                           Machine(:G2, :B1, 400.0, 5.0, 2.0, 0.30, 1.04, 40.0)],
                          net.loads)
    @test two_up isa NetworkModel                        # the model is fine…
    @test occursin("carries 2 machines", argerr_msg(() -> init!(DetailedEngine, two_up)))
    # …and the message says UNBUILT WORK, not a tier boundary — the distinction is
    # the whole reason this repo names its refusals
    @test occursin("unbuilt work", argerr_msg(() -> init!(DetailedEngine, two_up)))

    # A ZIP share was refused here through step 5 and is SOLVED as of step 6, so
    # the rejection is gone and the check that it is gone lives here — a lifted
    # precondition that nothing asserts is one that can come back by accident.
    zip_net = NetworkModel(100.0, 50.0, net.buses, net.branches, net.machines,
                           [Load(:L3, :B3, 110.0, 30.0, 0.5, 0.5, 0.0)])
    @test init!(DetailedEngine, zip_net) isa DetailedEngine

    # the slack must be a machine: a passive bus has no rotor angle to pin
    @test occursin("not a machine",
                   argerr_msg(() -> init!(DetailedEngine, net; slack = :B3)))
    @test occursin("not a machine",
                   argerr_msg(() -> init!(DetailedEngine, net; slack = :nope)))
end

# --- the power flow ---------------------------------------------------------
@testset "the power flow is CHECKED, not trusted" begin
    net = load_bus_system()
    eng = init!(DetailedEngine, net)
    st = current_state(eng)
    @test all(v -> 0.9 <= v <= 1.1, st.V)
    # the slack's rotor angle IS the reference — to the residual the solve drives
    # the pinned equation down to, which is 2.8e-24 here and not literally zero
    @test abs(st.δ[1]) < 1e-15

    # THE BAND IS THE DISCRIMINATOR, AND THIS IS WHY IT EXISTS. The collapsed
    # spurious solution is self-consistent and converges to a residual 400x
    # TIGHTER than the true one (measured: 5.0e-16 against 1.8e-13), so no
    # residual test separates them. Fed a collapsed voltage with a perfect
    # residual, the check must still refuse it.
    collapsed = ComplexF64[0.389 + 0im, 0.203 + 0im, 0.131 + 0im]
    msg = try
        GridSim._check_power_flow(net, collapsed, zeros(3), 0.0, "unit check")
        "NO ERROR THROWN"
    catch e
        e.msg
    end
    @test occursin("outside", msg)
    @test occursin("TIGHTER residual", msg)          # the reason, not just the rule
    # …and it passes the same solution at a healthy voltage, so the guard is not
    # simply always-on
    healthy = ComplexF64[1.0 + 0im, 1.0 + 0im, 1.0 + 0im]
    @test GridSim._check_power_flow(net, healthy, zeros(3), 0.0, "unit check") === nothing
    # an over-rating flow is refused even though the voltages are fine
    over = try
        GridSim._check_power_flow(net, healthy, fill(100.0, 3), 0.0, "unit check")
        "NO ERROR THROWN"
    catch e
        e.msg
    end
    @test occursin("against a rating", over)
end

@testset "Pm comes from the POWER FLOW, not from Machine.P0" begin
    # This is the check that is VACUOUS on every fixture the repo shipped before
    # M5, and the reason `load_bus_system` exists. With no load and no stator
    # resistance the air-gap power equals P0 exactly, so the back-substitution
    # could be wrong and nothing would show.
    for net in (two_machine_system(), three_machine_ring())
        eng = init!(DetailedEngine, net)
        ma = machine_arrays(net)
        @test [eng.params[i] for i in eng.Pm_pidx] ≈ ma.Pm atol = 1e-12
    end
    # …and here it is not vacuous.
    net = load_bus_system()
    eng = init!(DetailedEngine, net)
    ma = machine_arrays(net)
    Pm = [eng.params[i] for i in eng.Pm_pidx]
    @test Pm[2] ≈ ma.Pm[2] atol = 1e-12          # a non-slack machine holds its schedule
    @test !isapprox(Pm[1], ma.Pm[1]; atol = 1e-4)  # the slack does not
    # the SIZE of the gap, not merely that there is one: the load draws P0·|V|²,
    # so the slack absorbs exactly the shortfall
    la = load_arrays(net)
    V_load = current_state(eng).V[la.bus[1]]
    @test sum(Pm) ≈ la.P[1] * V_load^2 atol = 1e-10
    @test Pm[1] ≈ 0.65427 atol = 1e-4            # measured
end

# --- THE FLAT RUN -----------------------------------------------------------
@testset "the flat run: per state, at two tolerances" begin
    # No disturbance, full horizon, every state constant to solver tolerance.
    # ASSERTED PER STATE and never on `f_coi` alone — a wrong internal state can
    # leave frequency flat while a voltage rings, which is the whole reason this
    # check is written channel by channel.
    #
    # THE THIRD PASS IS NOT A THIRD TOLERANCE, AND WITHOUT IT THIS CHECK CLAIMS
    # MORE THAN IT EARNS. Left to choose its own steps, `Rodas5P` crosses a 20 s
    # flat horizon in **four accepted steps** — so 200 samples at `saveat = 0.05`
    # are almost all interpolations inside a handful of enormous ones, and what is
    # really being asserted is that an implicit solver parks on an equilibrium,
    # which it will do even for equations that are wrong in ways that cancel at
    # the fixpoint. `dtmax = 0.05` forces 201 real steps. Measured: still flat, to
    # 4.4e-14 — the same order as the unforced run, which is what makes the
    # unforced result meaningful rather than merely quiet.
    for (name, net) in (("two_machine", two_machine_system()),
                        ("three_ring",  three_machine_ring()),
                        ("load_bus",    load_bus_system()))
        for (rtol, atol, dtmax, min_steps) in ((1e-3, 1e-6, Inf,  0),
                                               (1e-8, 1e-11, Inf, 0),
                                               (1e-3, 1e-6, 0.05, 150))
            eng = init!(DetailedEngine, net; reltol = rtol, abstol = atol,
                        dtmax = dtmax)
            ser = solve!(eng, (0.0, 10.0); saveat = 0.05)
            @test length(ser.t) > 100
            # the forced pass must actually have stepped, or it silently becomes
            # a fourth copy of the lazy one
            @test eng.integrator.stats.naccept >= min_steps
            for ch in keys(ser)
                ch === :t && continue
                v = getproperty(ser, ch)
                drift = maximum(abs, v .- v[1])
                # 1e-10 is far below every measured value (worst seen: 4.4e-14)
                # and far above machine precision, so it is a real gate rather
                # than either a rubber stamp or a flake.
                @test drift < 1e-10
            end
        end
    end
    # …and the lazy pass really is lazy, which is the fact the comment above rests
    # on. Pinned so that a future change making the solver step more would not
    # quietly turn the third pass into a duplicate of the first.
    let eng = init!(DetailedEngine, three_machine_ring())
        solve!(eng, (0.0, 10.0); saveat = 0.05)
        @test eng.integrator.stats.naccept < 20
    end
end

@testset "the flat run's positive control IS the real bug" begin
    # The plan's control ("perturb one E′q by 1 %") names a state that does not
    # exist until step 2. The control used instead is the actual failure the
    # back-substitution exists to prevent: take `Pm` from the schedule rather
    # than from the power flow, which is what a careless implementation does.
    net = load_bus_system()
    eng = init!(DetailedEngine, net)
    ma = machine_arrays(net)
    for k in eachindex(eng.Pm_pidx)
        eng.params[eng.Pm_pidx[k]] = ma.Pm[k]
    end
    ser = solve!(eng, (0.0, 10.0); saveat = 0.05)
    worst = 0.0
    for ch in keys(ser)
        ch === :t && continue
        v = getproperty(ser, ch)
        worst = max(worst, maximum(abs, v .- v[1]))
    end
    # measured: the rotor angles run away by ~6.6 rad and f_coi moves 0.157 Hz
    @test worst > 1.0
    @test maximum(abs, ser.f_coi .- ser.f_coi[1]) > 0.1
    # AND THE HONEST PART: at THIS step the aggregate frequency channel would also
    # have caught it. The per-state form is not yet proven necessary here — it is
    # required for step 2's flux states, where a wrong E′d moves a voltage and
    # leaves frequency flat. Asserted so that the claim is dated rather than
    # assumed to have always held.
    @test maximum(abs, ser.f_coi .- ser.f_coi[1]) > 1e-3
end

@testset "a state written into the integrator is DISCARDED unless it is told" begin
    # The M3 finding, pinned here because `_reinitialise_algebraic!` writes bus
    # voltages straight into `integrator.u` and its correctness depends on this.
    # Measured: a bare write leaves the run flat (3.9e-15); the same write with
    # `u_modified!` + `auto_dt_reset!` produces the seeded 0.05 offset.
    net = load_bus_system()
    drifts = Float64[]
    for tell in (false, true)
        eng = init!(DetailedEngine, net)
        eng.integrator.u[eng.δ_idx[2]] += 0.05
        if tell
            SciMLBase.u_modified!(eng.integrator, true)
            SciMLBase.auto_dt_reset!(eng.integrator)
        end
        ser = solve!(eng, (0.0, 5.0); saveat = 0.05)
        push!(drifts, maximum(abs, ser.δ_G2 .- ser.δ_G2[1]))
    end
    @test drifts[1] < 1e-12          # silently discarded
    @test drifts[2] > 1e-2           # and it takes once the integrator is told
end

# --- the slack ---------------------------------------------------------------
@testset "the slack: a gauge choice only where nothing depends on voltage" begin
    # The obvious claim is that the slack is pure gauge and every observable is
    # invariant. HALF of that is true, and the boundary is measured rather than
    # assumed — an invariance test written without it would have failed the first
    # time anyone put a load in a model.
    for net in (two_machine_system(), three_machine_ring())
        ids = [m.id for m in net.machines]
        a = init!(DetailedEngine, net; slack = ids[1])
        b = init!(DetailedEngine, net; slack = ids[2])
        sa, sb = current_state(a), current_state(b)
        @test maximum(abs, sa.V .- sb.V) < 1e-12
        # angles only mean anything as differences, so the gauge is removed first
        @test maximum(abs, (sa.δ .- sa.δ[1]) .- (sb.δ .- sb.δ[1])) < 1e-12
        @test maximum(abs, [a.params[i] for i in a.Pm_pidx] .-
                           [b.params[i] for i in b.Pm_pidx]) < 1e-12
    end

    # With a voltage-dependent load it is a DISPATCH choice and it survives. The
    # size is asserted, not just the fact — and each answer is checked to be a
    # correct operating point in its own right.
    net = load_bus_system()
    la = load_arrays(net)
    a = init!(DetailedEngine, net; slack = :G1)
    b = init!(DetailedEngine, net; slack = :G2)
    sa, sb = current_state(a), current_state(b)
    @test maximum(abs, sa.V .- sb.V) > 1e-5                       # measured 3.6e-4
    @test maximum(abs, (sa.δ .- sa.δ[1]) .- (sb.δ .- sb.δ[1])) > 1e-3   # measured 1.5e-2
    for (eng, st) in ((a, sa), (b, sb))
        Pm = [eng.params[i] for i in eng.Pm_pidx]
        @test sum(Pm) ≈ la.P[1] * st.V[la.bus[1]]^2 atol = 1e-10   # self-consistent
    end
    # both are flat runs, which is the point: neither is the wrong answer
    for eng in (a, b)
        ser = solve!(eng, (0.0, 5.0); saveat = 0.05)
        @test maximum(abs, ser.V_B3 .- ser.V_B3[1]) < 1e-10
    end
end

# --- structure and read-out --------------------------------------------------
@testset "no admittance matrix is formed anywhere (SPEC §6)" begin
    # Structural, as M2's was: the coupling is assembled edge by edge inside
    # NetworkDynamics, so nothing in this engine may allocate an nb x nb array.
    src = read(joinpath(@__DIR__, "..", "src", "engines", "detailed.jl"), String)
    @test !occursin("Ybus", src)
    @test !occursin("admittance matrix", replace(src, "no admittance matrix" => ""))
    # the positive half: the engine's own dimension is states, not buses squared
    eng = init!(DetailedEngine, load_bus_system())
    nb = length(eng.model.buses)
    @test length(eng.integrator.u) == 2 * nb + 6 * length(eng.ids)
    # THE `nb²` FORM OF THIS CHECK FAILED IN STEP 2, AND IT DESERVED TO. It read
    # `length(u) < nb^2 + 2nb`, which on this 3-bus fixture became `16 < 15` the
    # moment a machine carried five states instead of three. The state count was
    # never the quantity in question: it is `2·nb + 6·nm` (step 5's exciter made it
    # six), LINEAR in both, and
    # bounding a linear count by a quadratic one only holds while the linear
    # constant is small — on a small system it says nothing, and on a large one it
    # would pass against a genuinely dense engine.
    #
    # What SPEC §6 forbids is a dense `nb × nb` object, so what is asserted is the
    # GROWTH: `load_bus_system()` is `two_machine_system()` with one extra
    # (machine-free) bus, and it costs exactly two more states. A formulation that
    # built an admittance block would cost O(nb) more.
    @test length(eng.integrator.u) -
          length(init!(DetailedEngine, two_machine_system()).integrator.u) == 2
    @test length(two_machine_system().buses) + 1 == nb      # …one extra bus, and only one
end

@testset "state_series carries one voltage channel per BUS" begin
    eng = init!(DetailedEngine, load_bus_system())
    ser = solve!(eng, (0.0, 1.0); saveat = 0.05)
    ks = keys(ser)
    @test :V_B1 in ks && :V_B2 in ks && :V_B3 in ks     # including the machine-free one
    @test :δ_G1 in ks && :ω_G2 in ks
    @test :δ_coi in ks && :f_coi in ks
    @test machine_ids(eng) == [:G1, :G2]
    @test timestep(eng) == 0.02
    # the aggregate weight is the MACHINE inertia sum: algebraic states are outside
    # it, so a voltage moving must not read as a change in who is online
    @test GridSim._aggregate_weight(eng) ≈ sum(machine_arrays(load_bus_system()).H)
    @test system_inertia(eng) == GridSim._aggregate_weight(eng)
end

@testset "inject!: a line trip re-solves the algebraic states" begin
    net = load_bus_system()
    eng = init!(DetailedEngine, net)
    @test is_online(eng, :B2, :B3)
    @test is_online(eng, :B3, :B2)              # either order, as TripLine promises
    solve!(eng, (0.0, 1.0); saveat = 0.05)
    inject!(eng, TripLine(:B2, :B3))
    @test !is_online(eng, :B2, :B3)
    @test n_events(eng) == 1
    @test event_log(eng)[1].kind === :trip_line
    # the post-event point satisfies the DYNAMIC network's own residual, which is
    # the whole content of a consistent re-initialisation
    du = similar(eng.integrator.u)
    eng.nw(du, eng.integrator.u, eng.params, eng.integrator.t)
    # the algebraic rows must be at machine precision; the differential ones are
    # free to be non-zero, because the system is genuinely swinging now
    for v in 1:length(net.buses)
        @test abs(du[eng.Vre_idx[v]]) < 1e-9
        @test abs(du[eng.Vim_idx[v]]) < 1e-9
    end
    # ANTI-VACUITY: the differential rows must NOT be zero. Without this, a
    # re-initialisation that quietly zeroed the whole state vector would satisfy
    # every assertion above — the residual would be perfect because nothing is
    # happening. After losing a line the machines are genuinely accelerating.
    @test any(abs(du[eng.ω_idx[k]]) > 1e-6 for k in eachindex(eng.ω_idx))
    @test all(isfinite, eng.integrator.u)
    @test all(v -> 0.5 < v < 1.5, current_state(eng).V)   # not a collapsed re-solve
    # …and it keeps stepping afterwards rather than aborting on an inconsistent point
    ser = solve!(eng, (eng.integrator.t, eng.integrator.t + 2.0); saveat = 0.05)
    @test length(ser.t) > 20
    @test all(isfinite, ser.V_B3)
    # tripping it twice is a no-op, not a second re-solve
    inject!(eng, TripLine(:B3, :B2))
    @test n_events(eng) == 1
end

@testset "inject!(::TripGenerator) is refused by name, not approximated" begin
    eng = init!(DetailedEngine, load_bus_system())
    msg = argerr_msg(() -> inject!(eng, TripGenerator(:G1)))
    @test occursin("not built at this tier yet", msg)
    # the message must say WHY the obvious shortcut is wrong, because that is the
    # thing a later reader would otherwise reinvent
    @test occursin("shunt to ground", msg)
end

end

# =============================================================================
# M5 step 2 — the two-axis machine, and the frozen-flux degeneration
#
# The machine of `docs/plans/m5-prestudy.md` §2 in the POWER form (D6), with the
# flux equations present and the DEFAULT parameters degenerating them away (D4).
#
# WHAT THIS STEP'S ORACLE VALIDATES, AND WHAT IT PROVABLY CANNOT. At `X′d = X′q`,
# `T′do = T′qo = ∞`, `Ra = 0` the tier must reproduce `SwingEngine` exactly. That
# checks the swing equation, the stator algebra, the rotor-frame rotation, the
# network and the initialisation. It checks the flux equations NOT AT ALL, because
# they are switched off — and the plan's proposed mutation for it ("perturb one
# flux coefficient") is *invisible* here. That invisibility is not asserted by
# assumption below; it is MEASURED, by running with the flux coefficients changed
# and showing the trajectory does not move. Plan step 4 owns the flux equations.
# =============================================================================

@testset "M5 step 2 — the two-axis machine and the frozen-flux degeneration" begin

# --- the canonical model ----------------------------------------------------
@testset "Machine: the detailed data is keyword-only, and its defaults ARE the degeneration" begin
    m = Machine(:G, :B, 250.0, 4.0, 2.0, 0.25, 1.05, 60.0)
    # D4: a machine built the M2/M3 way is exactly the frozen-flux machine of
    # m5-prestudy.md §3 — which is what makes the degeneration oracle below run on
    # the scenarios that already exist rather than on a parallel set of fixtures.
    @test m.Xd == 0.25 && m.Xq == 0.25 && m.Xq′ == 0.25
    @test m.Td0′ == Inf && m.Tq0′ == Inf
    @test m.Ra == 0.0

    # KEYWORD-ONLY, and that is D4 with one change (see the constructor's comment):
    # an outer keyword constructor cannot exist beside the inner one, because
    # keywords do not dispatch and the eight-positional forms would collide. The
    # practical consequence is the one that matters — no M2/M3 call site can land
    # data in these six by adding a positional argument.
    @test_throws MethodError Machine(:G, :B, 250.0, 4.0, 2.0, 0.25, 1.05, 60.0,
                                     Inf, 60.0, 1.0, 1.8)
    d = Machine(:G, :B, 250.0, 4.0, 2.0, 0.25, 1.05, 60.0;
                Xd = 1.8, Xq = 1.7, Xq′ = 0.55, Td0′ = 6.0, Tq0′ = 0.5, Ra = 0.003)
    @test (d.Xd, d.Xq, d.Xq′, d.Td0′, d.Tq0′, d.Ra) == (1.8, 1.7, 0.55, 6.0, 0.5, 0.003)
    # the M3 governor triple still arrives positionally, untouched
    @test Machine(:G, :B, 250.0, 4.0, 2.0, 0.25, 1.05, 60.0, 0.05, 80.0, 5.0).R == 0.05

    # every one of the six is validated, by name
    mk(; kw...) = Machine(:G, :B, 250.0, 4.0, 2.0, 0.25, 1.05, 60.0; kw...)
    @test occursin("must be ≥ Xd′", argerr_msg(() -> mk(Xd = 0.2)))
    @test occursin("must be ≥ Xq′", argerr_msg(() -> mk(Xq = 0.5, Xq′ = 0.6)))
    @test occursin("determinant", argerr_msg(() -> mk(Xq′ = 0.0)))
    @test occursin("Use Td0′ = Inf", argerr_msg(() -> mk(Td0′ = 0.0)))
    @test occursin("Tq0′", argerr_msg(() -> mk(Tq0′ = -1.0)))
    @test occursin("negative stator resistance", argerr_msg(() -> mk(Ra = -0.1)))
    # equality is legal in both orderings — equality IS the degeneration
    @test mk(Xd = 0.25, Xq = 0.25, Xq′ = 0.25) isa Machine
end

@testset "machine_arrays: the new columns, with the WRONG conversions asserted by name" begin
    net = NetworkModel(100.0, 50.0, [Bus(:B1, 400.0), Bus(:B2, 400.0)],
                       [Branch(:L12, :B1, :B2, 0.25, 500.0)],
                       [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 60.0;
                                Xd = 1.8, Xq = 1.7, Xq′ = 0.55,
                                Td0′ = 6.0, Tq0′ = 0.5, Ra = 0.003),
                        Machine(:G2, :B2, 400.0, 5.0, 2.0, 0.30, 1.02, -60.0)])
    ma = machine_arrays(net)
    w = 250.0 / 100.0                      # machine base -> system base, for POWERS
    # Reactances take the INVERSE weight, exactly as `Xd′` has since M2.
    @test ma.Xd[1]  ≈ 1.8   / w
    @test ma.Xq[1]  ≈ 1.7   / w
    @test ma.Xq′[1] ≈ 0.55  / w
    @test ma.Ra[1]  ≈ 0.003 / w
    # THE WRONG CONVERSIONS, BY NAME (the discipline M2 established for `Xd′` and
    # `R`): `X · w` is the mirror image and is wrong by `w²` = 6.25 here, which is
    # exactly the kind of error that looks like a plausible reactance.
    @test ma.Xd[1]  ≉ 1.8   * w
    @test ma.Xq[1]  ≉ 1.7   * w
    @test ma.Xq′[1] ≉ 0.55  * w
    @test ma.Ra[1]  ≉ 0.003 * w
    # …and "no conversion at all" is a third wrong answer, which a machine rated at
    # the system base would hide. This fixture is rated away from it for that reason.
    @test ma.Xd[1] ≉ 1.8
    # Time constants are SECONDS: base-free, so NEITHER weight is applied. Passed
    # through to the bit, not merely to a tolerance.
    @test ma.Td0′[1] === 6.0
    @test ma.Tq0′[1] === 0.5
    @test ma.Td0′[1] ≉ 6.0 / w && ma.Td0′[1] ≉ 6.0 * w
    # `Inf` survives the conversion as `Inf` — the frozen-flux limit the defaults
    # sit at, and the value a `/w` or `*w` would also survive, which is why the
    # configured machine above carries the finite ones.
    @test ma.Td0′[2] === Inf && ma.Tq0′[2] === Inf
    @test ma.Ra[2] === 0.0
    @test ma.Xd[2] == ma.Xq[2] == ma.Xq′[2] == ma.Xd′[2]
    @test all(a -> a isa Vector{Float64},
              (ma.Xd, ma.Xq, ma.Xq′, ma.Td0′, ma.Tq0′, ma.Ra))
end

@testset "the classical tier refuses detailed data rather than dropping it" begin
    net = two_machine_system()
    detailed = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
                            [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 60.0;
                                     Xd = 1.8, Td0′ = 6.0),
                             net.machines[2]])
    @test detailed isa NetworkModel                    # the canonical model holds it…
    for f in (() -> init!(SwingEngine, detailed), () -> coi_model(detailed))
        msg = argerr_msg(f)
        @test occursin("FROZEN-FLUX limit", msg)
        @test occursin("DetailedEngine", msg)          # …and it names the way out
    end
    # `Ra` alone is refused too, and the guard's docstring says why: it changes the
    # INITIALISATION (air-gap power exceeds terminal power by Ra·|I|²), so a model
    # carrying it is dispatched differently at the two tiers.
    ra_only = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
                           [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 60.0; Ra = 0.01),
                            net.machines[2]])
    @test occursin("FROZEN-FLUX limit", argerr_msg(() -> init!(SwingEngine, ra_only)))
    # ANTI-VACUITY: every fixture the repo ships is at the defaults, so the guard
    # must let all of them through. A guard that refused everything would pass the
    # three assertions above.
    for f in (two_machine_system, three_machine_ring)
        @test init!(SwingEngine, f()) isa SwingEngine
        @test coi_model(f()) isa SystemModel
    end
end

# --- the degeneration, in the STATE ------------------------------------------
@testset "the degeneration is exact in the STATE, which is what pins the rotor frame" begin
    # E′ lies entirely on the q-axis: at `Xq = X′d` and `Ra = 0` the phasor
    # `Ẽ = V + (Ra + jXq)·I` IS the classical internal voltage, so the d-component
    # is zero and the q-component is the datum `Machine.E′`.
    #
    # THIS IS THE CHECK THAT PINS THE ROTOR-FRAME CONVENTION, and it is the only
    # one here that does. MEASURED, by running both mutations against the source:
    #
    #   REFLECTED frame (`Vd = Vre·sin δ + Vim·cos δ`): caught at BUILD time, by the
    #   back-substituted-fixpoint check, with |residual| = 5.03 against a 1e-10
    #   gate. A reflection is not a rotation and does not preserve the inner
    #   product, so the two expressions stop agreeing.
    #
    #   CONSISTENTLY TURNED frame (δ → δ + π/2 at BOTH rotation sites): `init!`
    #   SUCCEEDS. The residual check passes, the air-gap-power identity passes, and
    #   the flat run is flat — because both expressions turn together and the
    #   difference cancels. What comes out is `E′d = [1.05, 1.02]`, `E′q ≈ 0`: the
    #   magnitude in the wrong state. Only the two assertions below see it.
    for net in (two_machine_system(), three_machine_ring(), load_bus_system())
        eng = init!(DetailedEngine, net)
        st = current_state(eng)
        for (k, m) in pairs(net.machines)
            @test abs(st.E′d[k]) < 1.0e-13
            @test st.E′q[k] ≈ m.E′ atol = 1.0e-12
        end
    end
end

@testset "the flat run now covers the flux states — and that coverage is VACUOUS here" begin
    # The flux channels are flat, and they are flat BY CONSTRUCTION: at `T′ = Inf`
    # the derivative is `finite/Inf`, which is `0.0` exactly. So this is not
    # evidence that the flux equations are right — it is evidence that they are
    # switched off, which is a different statement and the one plan step 4 exists
    # to replace. Said here rather than left for a later reader to infer from a
    # green test.
    eng = init!(DetailedEngine, load_bus_system(); dtmax = 0.05)
    ser = solve!(eng, (0.0, 10.0); saveat = 0.05)
    for ch in (:E′q_G1, :E′q_G2, :E′d_G1, :E′d_G2)
        v = getproperty(ser, ch)
        @test maximum(abs, v .- v[1]) < 1.0e-12
    end
    @test eng.integrator.stats.naccept >= 150          # the run really did step
end

# --- THE INTERNAL ORACLE -----------------------------------------------------
@testset "the internal oracle: the detailed tier reproduces SwingEngine at the degeneration" begin
    net = two_machine_system()
    ma = machine_arrays(net)
    # The helper indexes through `ma.bus`; on this fixture that is the identity, and
    # it is asserted rather than assumed because `reduced_line_reactance` in
    # `reference/` makes exactly the assumption and is correct only while it holds.
    @test ma.bus == [1, 2]
    red = terminal_bus_reduced(net)
    @test red.branches[1].X ≈ 0.25 - 0.10 - 0.075      # = 0.075, and positive
    @test red.branches[1].X > 0
    # RADIAL ONLY. Both machines have branch degree 1 here. On `three_machine_ring()`
    # every machine has degree 2 and the reduction would subtract one internal
    # reactance from two lines — so the ring is NOT a case for THIS comparison. It
    # IS a valid case for the external oracle of plan step 3, where both sides sit
    # on terminal buses and nothing is reduced. The two comparisons have opposite
    # topology restrictions, and neither is a general statement about the ring.
    # …and the helper REFUSES it rather than documenting it. The arithmetic would
    # have worked: every X′d on the ring converts to 0.10, so it returns
    # X = 0.05 > 0 — a positive reactance and a model that builds, on a reduction
    # that does not exist for it. `oracle.jl` states the rule this follows: a
    # comment saying the ring is not a valid case is what gets stepped over later.
    @test occursin("branch degree 2", argerr_msg(() -> terminal_bus_reduced(three_machine_ring())))
    @test occursin("would still be a positive reactance",
                   argerr_msg(() -> terminal_bus_reduced(three_machine_ring())))
    # the other half of the refusal: a tie the internal reactances swallow entirely
    let tight = NetworkModel(100.0, 50.0, net.buses,
                             [Branch(:L12, :B1, :B2, 0.05, 500.0)], net.machines)
        @test occursin("no line left", argerr_msg(() -> terminal_bus_reduced(tight)))
    end

    # THE SAME DISPATCH ON BOTH SIDES, asserted before anything is compared. The
    # detailed tier takes `Pm` from its power flow and the classical tier from
    # `Machine.P0`; on a lossless model with no load these are the same number, and
    # a comparison that did not check it could be reading a slack absorption as a
    # physics difference.
    let sw = init!(SwingEngine, net), de = init!(DetailedEngine, red)
        for k in 1:2
            @test de.params[de.Pm_pidx[k]] ≈ sw.params[sw.Pm_pidx[k]] atol = 1.0e-12
            @test de.params[de.Pm_pidx[k]] ≈ ma.Pm[k] atol = 1.0e-12
        end
    end

    # TWO TOLERANCES, and the band at each is derived from each side's OWN
    # convergence — never from the gap it is about to judge (`convergence_band`).
    # `tolerance_band` is the wrong derivation here for the reason M4 step 4
    # measured: an explicit Runge–Kutta against a stiff Rosenbrock is two different
    # global-error accumulations, and their ratio does not settle.
    for (rtol, atol) in ((1.0e-4, 1.0e-7), (1.0e-7, 1.0e-10))
        sw, de   = tier_pair(net, red; reltol = rtol,        abstol = atol)
        swf, def = tier_pair(net, red; reltol = rtol / 1000,  abstol = atol / 1000)
        # ONE GRID, never resampled: both sides are handed the same `saveat` and the
        # comparison refuses two grids rather than straight-lining between samples
        # (M4 step 2 — there is no interpolant left after a solve to resample with).
        @test sw.t == de.t
        for (name, ch) in TIER_CHANNELS
            band = convergence_band(sw, swf, de, def; channel = ch)
            @test band > 0                     # a zero band would pass vacuously
            d = divergence(sw, de; band = band, channel = ch)
            @test d.max < band
            @test isnan(d.t_depart)             # never leaves the band at all
        end
        # The disturbance is real: a check that agreed because nothing happened
        # would pass every assertion above.
        @test maximum(abs, sw.f_coi .- sw.f_coi[1]) > 0.05
        @test maximum(abs, de.δ_G2 .- de.δ_G1 .- (de.δ_G2[1] - de.δ_G1[1])) > 0.01
    end
end

# --- anti-vacuity, and the list of what is provably invisible ----------------
@testset "anti-vacuity: what a stator mutation does, and what a flux mutation does not" begin
    net = two_machine_system()
    red = terminal_bus_reduced(net)
    sw, de = tier_pair(net, red)
    base = convergence_band(sw, sw, de, de)          # zero by construction

    # (a) THE VISIBLE ONE. `X′q` sits inside the stator inversion's determinant and
    # in the current it produces. Perturbing it by 1 % must take the comparison red.
    # A PARAMETER mutation rather than a source edit, so it runs in the suite every
    # time — the standing rule is that the mutation is EXECUTED, not described.
    let de2 = init!(DetailedEngine, red)
        SII = NetworkDynamics.SII
        for k in 1:2
            i = SII.parameter_index(de2.nw,
                    NetworkDynamics.VPIndex(de2.machine_bus[k], :Xq′))
            de2.params[i] *= 1.01
        end
        de2.params[de2.Pm_pidx[1]] += 0.05
        SciMLBase.auto_dt_reset!(de2.integrator)
        bad = solve!(de2, (0.0, 10.0); saveat = 0.02)
        swf, def = tier_pair(net, red; reltol = 1.0e-9, abstol = 1.0e-12)
        # Measured: 64× the band on `f_coi`, 77× and 76× on the two speeds, 173× on
        # the relative angle. Red by two orders, not marginally.
        for (name, ch) in TIER_CHANNELS
            band = convergence_band(sw, swf, de, def; channel = ch)
            @test divergence(sw, bad; band = band, channel = ch).max > 10 * band
        end
    end

    # (b) THE INVISIBLE ONES, MEASURED RATHER THAN ASSUMED. At this degeneration
    # `Xd − X′d = 0` and `Xq − X′q = 0`, so the flux right-hand sides are
    # identically zero whatever the time constants are — and `Efd` was initialised
    # to `E′q`, so the field equation's own restoring term cancels too. Changing
    # `T′do`/`T′qo` from `Inf` to 5 s therefore changes NOTHING, and that is the
    # honest statement of what this oracle cannot see.
    #
    # EXACTNESS IS NOT AVAILABLE HERE, unlike M4 step 3's `===` comparison. `0/Inf`
    # and `0/5.0` are both exactly `0.0`, but the implicit solver's Newton step does
    # not reproduce the zero increment bit for bit once the Jacobian differs, so the
    # claim is "below every band in this file by orders of magnitude" rather than
    # "identical". MEASURED worst deviation across the four channels: 2.3e-14 on the
    # relative angle, 1.4e-14 on `f_coi`, 4.5e-16 on the speeds — against a band of
    # 4.8e-4 at the loosest tolerance this file uses. Four orders of margin, wholly
    # invisible.
    let flux_net = NetworkModel(red.S_base, red.f0, red.buses, red.branches,
            [Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, m.P0,
                     m.R, m.Pmax, m.Tg; Td0′ = 5.0, Tq0′ = 0.5) for m in red.machines])
        _, thawed = tier_pair(net, flux_net)
        for (name, ch) in TIER_CHANNELS
            @test maximum(abs, ch(de) .- ch(thawed)) < 1.0e-10
        end
    end

    # (c) THE REST OF THE INVISIBLE LIST, so nobody later reads this testset as
    # covering more than it does. Each of these is zero or absent at the
    # degeneration, so no mutation of it can move a number here:
    #   - `Ra` — it is 0.0, so any factor on it is 0.0;
    #   - the saliency term `(X′q − X′d)·Id·Iq` in the air-gap power — the bracket
    #     is exactly 0.0;
    #   - the flux coefficients `(Xd − X′d)` and `(Xq − X′q)` — both exactly 0.0;
    #   - `Td0′`/`Tq0′` themselves — measured in (b) above.
    # The mutations that ARE visible: a sign in the rotor-frame rotation, `X′d` or
    # `X′q` inside the inversion, the determinant, and the `E′d·Id + E′q·Iq` terms.
    let ma_red = machine_arrays(red)
        @test all(ma_red.Ra .== 0.0)
        @test all(ma_red.Xq′ .- ma_red.Xd′ .== 0.0)
        @test all(ma_red.Xd .- ma_red.Xd′ .== 0.0)
        @test all(ma_red.Xq .- ma_red.Xq′ .== 0.0)
    end
    @test base == 0.0
end

# --- read-out and structure --------------------------------------------------
@testset "the tier's state and channels grew by exactly three per machine" begin
    # Two in step 2 (the flux pair) and one more in step 5 (the exciter), so the
    # count is `2·nb + 6·nm`. The testset title carries the running total rather
    # than the increment of whichever step last touched it.
    eng = init!(DetailedEngine, load_bus_system())
    nb = length(eng.model.buses)
    nm = length(eng.ids)
    @test length(eng.integrator.u) == 2 * nb + 6 * nm
    ser = solve!(eng, (0.0, 1.0); saveat = 0.05)
    ks = keys(ser)
    for ch in (:E′q_G1, :E′q_G2, :E′d_G1, :E′d_G2, :Efd_G1, :Efd_G2)
        @test ch in ks
    end
    st = current_state(eng)
    @test length(st.E′q) == nm && length(st.E′d) == nm
    # `Efd` is the machine's initial `E′q` exactly, because `Xd − X′d = 0` here. It
    # became a STATE in step 5 (the regulator) and is read as one; with `T_E = Inf`
    # — the default this fixture sits at — it is still a constant.
    @test all(st.Efd[k] ≈ st.E′q[k] for k in 1:nm)
end

@testset "the re-initialisation holds the FLUX too, in a third static mode" begin
    # Step 1 re-solved the algebraic states with the machine's STEADY-STATE source
    # (`Ẽ` on the q-axis, magnitude `Machine.E′`). That is a statement about a
    # machine at rest and stops being true the moment the flux moves, so step 2
    # added `_PF_HOLD`: the machine's actual stator algebra at the held
    # `(δ, E′q, E′d)`. At this degeneration the two modes agree exactly, which is
    # why step 1's version was not wrong — only narrower than it looked.
    net = load_bus_system()
    eng = init!(DetailedEngine, net)
    solve!(eng, (0.0, 1.0); saveat = 0.05)
    before = copy(current_state(eng).E′q)
    inject!(eng, TripLine(:B2, :B3))
    after = current_state(eng)
    # the flux is a DIFFERENTIAL state and must survive the discontinuity untouched
    @test after.E′q ≈ before atol = 1.0e-14
    # and the re-solved point satisfies the dynamic network's algebraic rows
    du = similar(eng.integrator.u)
    eng.nw(du, eng.integrator.u, eng.params, eng.integrator.t)
    for v in 1:length(net.buses)
        @test abs(du[eng.Vre_idx[v]]) < 1.0e-9
        @test abs(du[eng.Vim_idx[v]]) < 1.0e-9
    end
    @test GridSim._PF_HOLD == 2.0
    @test all(eng.p_static[i] == GridSim._PF_HOLD for i in eng.smode_pidx)
end

end

# ═══════════════════════════════════════════════════════════════════════════
# M5 step 4 — the flux equations switched on.
#
# Step 2 validated the tier at `T′ = Inf`, and said out loud that the limit
# validates the flux equations NOT AT ALL: at `X = X′` with a zero derivative,
# `(Xd − X′d)`, `(Xq − X′q)`, `T′do` and `T′qo` are all multiplied by zero and no
# mutation of them can move a number. Step 3 asserted that blindness rather than
# caveating it — a ×4 `Xd` left every channel bit-identical. This step is what
# that left to earn, and it earns it three ways: the OTHER limit (`T′ → 0`), a
# CLOSED FORM for the decay itself, and — in `reference/` — the external oracle
# with the mechanism switched on.
# ═══════════════════════════════════════════════════════════════════════════

@testset "M5 step 4 — the flux equations, switched on" begin

# ---------------------------------------------------------------------------
@testset "the flux fixpoint is a real condition here, and the flat run covers it" begin
    # Step 1 recorded a vacuity: `Pm := Pe` versus `Pm := P0` is unobservable on a
    # model with no load. THIS IS A DIFFERENT ONE and the two must not be merged.
    # On every frozen-flux fixture the flux part of the fixpoint reads `0 = 0`:
    # `Xd − X′d` and `Xq − X′q` are both zero, so `E′d = (Xq − X′q)·Iq` holds
    # whatever the initialisation writes. `detailed_pair()` is the first fixture in
    # the repo where it does not.
    net = detailed_pair()
    eng = init!(DetailedEngine, net)
    st  = current_state(eng)
    ma  = machine_arrays(net)
    u   = eng.integrator.u

    # The q-axis condition, checked against the machine's OWN stator rather than
    # against a remembered number: `E′d` must equal `(Xq − X′q)·Iq` at the solved
    # point. It follows from the power flow's q-axis property (`Ẽd = 0`) and from
    # nothing the back-substitution asserts directly, which is what makes it a
    # check rather than a restatement.
    v = eng.machine_bus[1]
    Id, Iq, _, _, _ = GridSim._stator(u[eng.Vre_idx[v]], u[eng.Vim_idx[v]], st.δ[1],
                                      st.E′q[1], st.E′d[1], ma.Ra[1], ma.Xd′[1],
                                      ma.Xq′[1], 1.0)
    @test st.E′d[1] ≈ (ma.Xq[1] - ma.Xq′[1]) * Iq atol = 1.0e-12
    # …and the d-axis one, which holds BY CONSTRUCTION (`Efd` is defined from it)
    # and is asserted anyway, because a definition living in one place is exactly
    # what makes a later second definition invisible.
    @test st.Efd[1] ≈ st.E′q[1] + (ma.Xd[1] - ma.Xd′[1]) * Id atol = 1.0e-12
    # The fixture is not vacuous: the saliency and the q-axis flux are live in it.
    @test abs(st.E′d[1]) > 0.15                      # measured 0.184
    @test !isapprox(st.E′q[1], net.machines[1].E′; atol = 1.0e-3)   # 0.9639 vs 1.00
    @test isfinite(ma.Td0′[1]) && isfinite(ma.Tq0′[1])
    # …and `Machine.E′` really has stopped being the terminal voltage at this tier
    # (D4's silent reinterpretation), which is why this fixture's numbers were
    # scanned rather than chosen: `|V|` lands inside the power flow's own band and
    # `E′` does not predict it.
    @test 0.9 < hypot(u[eng.Vre_idx[v]], u[eng.Vim_idx[v]]) < 1.1

    # THE FLAT RUN, per state, at two tolerances and then forced to step. The same
    # three-pass shape step 1 established and for the same reason: left to itself
    # `Rodas5P` crosses the horizon in a handful of enormous steps, and a run that
    # takes four steps is only establishing that an implicit method parks on an
    # equilibrium.
    for (rt, at) in ((1.0e-3, 1.0e-6), (1.0e-8, 1.0e-11))
        e = init!(DetailedEngine, detailed_pair(); reltol = rt, abstol = at)
        sr = solve!(e, (0.0, 10.0); saveat = 0.05)
        for k in keys(sr)
            k === :t && continue
            @test maximum(abs, getproperty(sr, k) .- getproperty(sr, k)[1]) < 1.0e-11
        end
        @test e.integrator.stats.naccept < 20        # measured 4 and 6
    end
    ef = init!(DetailedEngine, detailed_pair(); reltol = 1.0e-8, abstol = 1.0e-11,
               dtmax = 0.05)
    sf = solve!(ef, (0.0, 10.0); saveat = 0.05)
    @test ef.integrator.stats.naccept >= 150         # measured 201
    for k in keys(sf)
        k === :t && continue
        @test maximum(abs, getproperty(sf, k) .- getproperty(sf, k)[1]) < 1.0e-11
    end
end

# ---------------------------------------------------------------------------
@testset "the closed form: the field flux decays with T′do·(X′d+Xe)/(Xd+Xe)" begin
    # THE HEFFRON-PHILLIPS `K₃T′do` CONSTANT — the only check in this milestone
    # that pins `(Xd − X′d)` and `T′do` INSIDE the equation with an interpretable
    # number. Both of the other oracles report a diffuse disagreement instead.
    #
    # The prediction is written before anything is solved, and it comes from
    # `machine_arrays` — the SYSTEM base — because `G1` is rated 250 MVA against a
    # 100 MVA system while the `Machine` fields are on the machine base.
    net = infinite_bus_system()
    τp  = flux_tau_pred(net)
    @test 2.8 < τp < 3.0                             # 8·(0.1+0.25)/(0.72+0.25)

    # The rotor here is not merely heavy, it is IMMOBILE, and that is the fixture's
    # design rather than a tolerance: at zero loading the whole solution sits on
    # the real axis, so `Iq ≡ 0`, `E′d ≡ 0`, `Pe ≡ 0`, and the swing equation has
    # nothing to integrate. That is what makes the closed form exact instead of
    # approximate — the next testset is what happens when it is not.
    for (rt, at) in ((1.0e-6, 1.0e-9), (1.0e-9, 1.0e-12))
        s  = efd_step_run(net; ΔEfd = 0.05, reltol = rt, abstol = at)
        i1 = findlast(t -> t <= 3τp, s.t) - 20
        τm, n = flux_tau_fit(s.t, s.E′q_G1; h = 20, i1 = i1)
        @test n > 100
        @test τm ≈ τp rtol = 1.0e-4                  # measured 3e-6 and 3e-9
        # The rotor stayed put — asserted, not assumed.
        @test maximum(abs, s.δ_G1 .- s.δ_G1[1]) < 1.0e-9
        @test maximum(abs, s.ω_G1) < 1.0e-11
        @test maximum(abs, s.E′d_G1) < 1.0e-12       # the q axis is inert at δ = 0
        # …and the GAIN is the same two constants read a second, independent way:
        # `ΔE′q(t) = K₃·ΔEfd·(1 − e^{−t/τ})` with `K₃ = τ/T′do`. A time constant
        # fitted from the shape and a gain read off the endpoint are different
        # functions of the same two reactances.
        #
        # THE FINITE HORIZON IS IN THE PREDICTION RATHER THAN IN THE TOLERANCE, and
        # that was a failure before it was a comment: comparing the endpoint against
        # the `t = ∞` asymptote is off by `e^{−25/τ} = 1.73e-4`, which is exactly
        # what the run came up short by. Loosening `rtol` past it would have hidden
        # the one place the exponential's SHAPE reaches the endpoint check; carrying
        # the factor instead tightens the agreement to 3e-7.
        @test s.E′q_G1[end] - s.E′q_G1[1] ≈
              0.05 * (τp / machine_arrays(net).Td0′[1]) *
              (1 - exp(-s.t[end] / τp)) rtol = 1.0e-5
    end
    # Linear in the step size: doubling `ΔEfd` doubles the asymptote and leaves the
    # time constant alone. A nonlinearity here would mean the fit is reading the
    # operating point rather than the equation.
    s1 = efd_step_run(net; ΔEfd = 0.05)
    s2 = efd_step_run(net; ΔEfd = 0.10)
    @test (s2.E′q_G1[end] - s2.E′q_G1[1]) /
          (s1.E′q_G1[end] - s1.E′q_G1[1]) ≈ 2.0 rtol = 1.0e-4
    i2 = findlast(t -> t <= 3τp, s2.t) - 20
    @test flux_tau_fit(s2.t, s2.E′q_G1; h = 20, i1 = i2)[1] ≈ τp rtol = 1.0e-4

    # ── THE ANTI-VACUITY MUTATION, and it is a PREDICTED move rather than merely a
    # move. `Xd` on the machine under test drops from 1.8 to 1.0 pu (machine base)
    # and the constant must land on the NEW prediction, which is a different number
    # and not a rescaling of the old one. Predicted first: 4.3077 s against
    # 2.8866 s, a ratio of 1.4923.
    slow = infinite_bus_system(; Xd = 1.0)
    τp2  = flux_tau_pred(slow)
    @test τp2 / τp ≈ 1.4923 rtol = 1.0e-3
    s2m  = efd_step_run(slow)
    i2m  = findlast(t -> t <= 3τp2, s2m.t) - 20
    τm2, _ = flux_tau_fit(s2m.t, s2m.E′q_G1; h = 20, i1 = i2m)
    @test τm2 ≈ τp2 rtol = 1.0e-4
    # …and stated as the RATIO the plan asked for, which cancels anything common to
    # the two runs.
    τm1, _ = flux_tau_fit(s1.t, s1.E′q_G1; h = 20,
                          i1 = findlast(t -> t <= 3τp, s1.t) - 20)
    @test τm2 / τm1 ≈ τp2 / τp rtol = 1.0e-3
    # The mutation is not a null one: 49 % is four orders above the fit's own error.
    @test τm2 / τm1 > 1.4

    # WHAT THIS CHECK DOES NOT REACH, asserted rather than left to be assumed. At
    # `δ ≡ 0` the q axis carries no current at all, so `Tq0′` and `(Xq − X′q)` are
    # multiplied by zero here exactly as `(Xd − X′d)` was in step 2's limit. Ten
    # times `Tq0′` moves nothing. The q-axis flux gets its check from the `T′ → 0`
    # limit below and from the external oracle, and from nothing in this testset.
    qmut = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
        [Machine(m.id, m.bus, m.S_rated, m.H, m.D, m.Xd′, m.E′, m.P0, m.R, m.Pmax,
                 m.Tg; Xd = m.Xd, Xq = m.Xq, Xq′ = m.Xq′, Td0′ = m.Td0′,
                 Tq0′ = 10.0 * m.Tq0′, Ra = m.Ra, K_A = m.K_A, T_E = m.T_E,
                 Efd_min = m.Efd_min, Efd_max = m.Efd_max) for m in net.machines])
    sq = efd_step_run(qmut)
    @test maximum(abs, sq.E′q_G1 .- s1.E′q_G1) < 1.0e-12
end

# ---------------------------------------------------------------------------
@testset "why that closed form is exact only at zero loading — inertia does not help" begin
    # THE MEASUREMENT THAT DECIDED THE FIXTURE'S DEFAULT. The obvious way to hold
    # the rotor still is a very large `H`, and IT DOES NOT WORK: the rotor's new
    # equilibrium angle after a field step is `ΔP/K_syn`, which does not contain
    # `H` at all. A heavier rotor only takes longer to get there, and over a fit
    # window of a few `τ` the contamination does not shrink. Measured across a 64×
    # range of inertia — with the RELATIVE angle read, because the first pass read
    # only `δ_G1` and missed that the infinite-bus machine's own rotor was the one
    # moving.
    τp = flux_tau_pred(infinite_bus_system())
    errs = Float64[]
    for (H, H_inf) in ((200.0, 100.0), (12800.0, 6400.0))
        net = infinite_bus_system(; P0 = 40.0, H = H, H_inf = H_inf)
        s   = efd_step_run(net)
        i1  = findlast(t -> t <= 3τp, s.t) - 20
        τm, _ = flux_tau_fit(s.t, s.E′q_G1; h = 20, i1 = i1)
        rel = s.δ_G1 .- s.δ_G_inf
        # The precondition is visibly violated: the machine turns against the bus.
        @test maximum(abs, rel .- rel[1]) > 1.0e-2
        push!(errs, τm / τp - 1)
    end
    @test all(e -> e > 0.15, errs)                   # measured +21.8 % and +25.8 %
    # 64× the inertia does not reduce it, which is the finding. (It does not
    # increase it much either; what is asserted is that the error SURVIVES, where a
    # `1/H` contamination would have fallen by 64×.)
    @test errs[2] > 0.5 * errs[1]
end

# ---------------------------------------------------------------------------
@testset "the other limit: T′ → 0 reproduces the steady-state (Xd, Xq) machine" begin
    # WITH STEP 2 THIS BRACKETS THE FLUX EQUATION FROM BOTH SIDES. Step 2 froze the
    # flux and reproduced `SwingEngine`; here the flux is made arbitrarily FAST and
    # must reproduce a constant-`Efd` machine behind `(Ra + jXq)` — which is
    # `flux_limit_model`: a model rather than a limit, sharing this one's power flow
    # to the bit.
    #
    # A FLAT RUN WOULD BE VACUOUS, because both models sit at the same fixpoint. So
    # the comparison runs across a mechanical-power step.
    base = detailed_pair()
    lim  = pm_step_run(flux_limit_model(base))
    # The two are genuinely different machines — the limit's `E′q` carries the whole
    # `(Xd − X′d)·Id` drop, which is why the flux channels are NOT compared (see
    # `flux_limit_model`).
    @test abs(lim.E′q_G1[1] - pm_step_run(base).E′q_G1[1]) > 0.03

    gaps = Dict{Float64,Dict{Symbol,Float64}}()
    for λ in (0.001, 0.0003, 0.0001)
        s = pm_step_run(scale_flux_time(base, λ))
        gaps[λ] = Dict(k => maximum(abs, getproperty(s, k) .- getproperty(lim, k))
                       for k in FLUX_LIMIT_CHANNELS)
    end
    # It converges, and it converges LINEARLY in `T′` — the statement that this is
    # the singular-perturbation limit and not two models that merely happen to be
    # close. Predicted before it was measured: the quasi-steady flux error is first
    # order in the time constant.
    for k in FLUX_LIMIT_CHANNELS
        @test gaps[0.001][k] > gaps[0.0003][k] > gaps[0.0001][k]
    end
    # The RATE is asserted on the two channels it was measured on, rather than on
    # every channel by analogy — an aggregate can be linear for reasons of its own.
    for k in (:V_B1, :δ_G1)
        @test gaps[0.001][k] / gaps[0.0003][k] ≈ 10/3 rtol = 0.15
        @test gaps[0.0003][k] / gaps[0.0001][k] ≈ 3.0 rtol = 0.15
    end
    # …and the smallest gap is still a MODEL residual rather than solver noise: the
    # reference side's own convergence spread is orders below it.
    slow = pm_step_run(flux_limit_model(base); reltol = 1.0e-5, abstol = 1.0e-8)
    for k in (:V_B1, :δ_G1)
        band = maximum(abs, getproperty(slow, k) .- getproperty(lim, k))
        @test gaps[0.0001][k] > 20 * band
    end
    # Tolerance-independent, which says the same thing a second way.
    s6 = pm_step_run(scale_flux_time(base, 0.001); reltol = 1.0e-6, abstol = 1.0e-9)
    l6 = pm_step_run(flux_limit_model(base); reltol = 1.0e-6, abstol = 1.0e-9)
    @test maximum(abs, s6.V_B1 .- l6.V_B1) ≈ gaps[0.001][:V_B1] rtol = 1.0e-3

    # ── ANTI-VACUITY, and it is a mutation the LIMIT SIDE CANNOT SEE. `Xd` enters
    # the fast model only through the flux numerator `(Xd − X′d)·Id`, and the limit
    # model's `T′ = Inf` divides that numerator away entirely — so mutating `Xd` on
    # the FAST side alone is an error the reference is structurally immune to. Its
    # signature is the right one: the ladder stops converging, because the fast
    # model is now approaching a DIFFERENT machine.
    mut = scale_Xd(base, :G1, 0.99)
    m3 = pm_step_run(scale_flux_time(mut, 0.0003))
    m4 = pm_step_run(scale_flux_time(mut, 0.0001))
    g3 = maximum(abs, m3.V_B1 .- lim.V_B1)
    g4 = maximum(abs, m4.V_B1 .- lim.V_B1)
    @test g4 > 4 * gaps[0.0001][:V_B1]               # measured 5.7×
    @test g4 / g3 > 0.5                              # measured 0.84 — it has PLATEAUED
    @test gaps[0.0001][:V_B1] / gaps[0.0003][:V_B1] < 0.4   # …the true one has not

    # ── AND WHAT THE SAME CHECK IS BLIND TO, measured rather than caveated. `X′d`
    # does not survive the limit either: as `T′ → 0` it cancels out of the terminal
    # relations entirely and only sets the RATE of approach. So a 10 % `X′d` error —
    # ten times the size of the `Xd` mutation above — moves this comparison by under
    # 2 %, where the `Xd` one moves it by a third. `X′d` is pinned by step 2's
    # frozen limit and by the flat run, not here.
    xd′_bad = NetworkModel(base.S_base, base.f0, base.buses, base.branches,
        [Machine(m.id, m.bus, m.S_rated, m.H, m.D,
                 m.id === :G1 ? 0.9 * m.Xd′ : m.Xd′, m.E′, m.P0, m.R, m.Pmax, m.Tg;
                 Xd = m.Xd, Xq = m.Xq, Xq′ = m.Xq′, Td0′ = m.Td0′, Tq0′ = m.Tq0′,
                 Ra = m.Ra) for m in base.machines])
    gx = maximum(abs, pm_step_run(scale_flux_time(xd′_bad, 0.001)).V_B1 .- lim.V_B1)
    @test abs(gx / gaps[0.001][:V_B1] - 1) < 0.02
    gm = maximum(abs, pm_step_run(scale_flux_time(mut, 0.001)).V_B1 .- lim.V_B1)
    @test gm / gaps[0.001][:V_B1] > 1.25
end

end # M5 step 4

# ═══════════════════════════════════════════════════════════════════════════
# M5 step 5 — the voltage regulator.
#
# Steps 1-4 ran with the field voltage HELD: `Efd` was whatever the power flow
# dispatched, constant for the whole horizon. That is the case every closed form
# in step 4 is written for, and it is still what the defaults are. This step gives
# the field voltage an exciter that moves it, and hard limits that stop it.
#
# THE ONE RULE THIS STEP EXISTS TO GET RIGHT is M1's, carried forward twice now:
# a limit is a saturation in the DERIVATIVE, never a clamp on the state. The
# checks below are arranged around what can and cannot see the difference, because
# most of them cannot — see the anti-vacuity testset at the end, which reproduces
# the clamp deliberately and finds that three of the four claims stay green under
# it, one of them MORE green than the correct run. Only the closed form is
# load-bearing.
# ═══════════════════════════════════════════════════════════════════════════

@testset "M5 step 5 — the voltage regulator" begin

@testset "the setpoint is DERIVED, so a regulated machine still starts at rest" begin
    # The exciter's own equation has one unknown left once the power flow has run:
    # at a steady state `0 = −Efd + K_A(Vref − |V|)`, so `Vref = |V| + Efd/K_A`.
    # Nothing else can be chosen — a setpoint taken as model data would put the
    # machine off its own equilibrium at t = 0, and every check downstream would be
    # reading a startup transient.
    net = regulator_bus_system()
    eng = init!(DetailedEngine, net; slack = :G_inf)
    st  = current_state(eng)
    K_A = machine_arrays(net).K_A[1]
    @test K_A == 200.0                                    # base-free, not converted
    @test eng.params[eng.Vref_pidx[1]] ≈ st.V[1] + st.Efd[1] / K_A atol = 1.0e-14
    # G_inf carries no regulator, so its setpoint is the fallback |V| and is inert.
    @test eng.params[eng.Vref_pidx[2]] == st.V[2]

    # THE EQUILIBRIUM IS THE CLOSED FORM'S, which is what makes `reg_V` an oracle
    # for the run rather than a restatement of it: the power flow solved a
    # five-branch network from a flat start and landed on the two-reactance
    # expression to 13 digits.
    Xe = reg_Xe(net)
    @test Xe ≈ 0.0383486 rtol = 1.0e-5                     # 0.02 ∥ 0.40 ∥ 0.50, + 0.02
    @test st.V[1] ≈ reg_V(net, Xe, st.E′q[1]) atol = 1.0e-13

    # THE FLAT RUN, per state and at two tolerances — step 1's discipline, extended
    # to the one state step 5 added.
    for (rt, at) in ((1.0e-6, 1.0e-9), (1.0e-9, 1.0e-12))
        e2 = init!(DetailedEngine, net; slack = :G_inf, reltol = rt, abstol = at)
        u0 = copy(e2.integrator.u)
        s  = solve!(e2, (0.0, 10.0); saveat = 0.5)
        @test maximum(abs, s.Efd_G1 .- s.Efd_G1[1]) < 1.0e-9
        @test maximum(abs, s.E′q_G1 .- s.E′q_G1[1]) < 1.0e-9
        @test maximum(abs, s.V_B1 .- s.V_B1[1]) < 1.0e-9
        @test maximum(abs, e2.integrator.u .- u0) < 1.0e-8
    end

    # ── THE POSITIVE CONTROL, AND THE PREDICTION IT CORRECTED. A `Vref` off by
    # 0.01 pu is the bug this derivation exists to prevent, and the obvious guess
    # at its size — `K_A·ΔVref = 2 pu` of extra field voltage — is WRONG BY 11x,
    # because the loop closes through the network: more field raises the terminal
    # voltage, which cancels most of the error that produced it. The DC loop gain
    # is `G = K_A·dV/dEfd`, and `dV/dEfd = Xe/(Xe + Xd)` falls out of the two
    # closed forms already here (`reg_Eq_inf` composed with `reg_V`), so
    #
    #     ΔEfd = K_A·ΔVref / (1 + G)
    #
    # This is the only check in the milestone that reads `K_A` INSIDE an equation
    # rather than as a label, and it lands to nine digits: 0.9660369472 predicted
    # against 0.9660369472 measured, where the open-loop guess would have said
    # 2.786.
    e3 = init!(DetailedEngine, net; slack = :G_inf)
    Efd0 = current_state(e3).Efd[1]
    G = reg_loop_gain(net, Xe)
    @test G ≈ 10.1138 rtol = 1.0e-4
    e3.params[e3.Vref_pidx[1]] += 0.01
    s3 = solve!(e3, (0.0, 30.0); saveat = 0.1)
    @test s3.Efd_G1[end] ≈ Efd0 + K_A * 0.01 / (1 + G) rtol = 1.0e-8
    @test !isapprox(s3.Efd_G1[end], Efd0 + K_A * 0.01; rtol = 0.5)   # …and NOT the open-loop guess
    @test s3.Efd_G1[end] - Efd0 > 0.1                                # not a null control
end

# ---------------------------------------------------------------------------
@testset "the ceiling HOLDS under sustained demand, and the flux decays under it" begin
    # THE SHARPEST CHECK IN THIS STEP, and it is step 4's closed form with one
    # constant changed. While the exciter sits on its ceiling `Efd` is a CONSTANT,
    # so the machine is exactly the constant-field machine already validated to
    # 3e-9 — same `T′d = T′do·(X′d + Xe)/(Xd + Xe)`, new asymptote.
    #
    # `Efd_max = 0.95` is below the post-trip UNLIMITED equilibrium field voltage
    # (0.99288 pu, measured), which is the criterion for the demand never falling
    # back: the terminal voltage a 0.95 pu field can produce is short of the one
    # that would relieve the regulator, so the limit binds for the whole horizon.
    net = regulator_bus_system(; Efd_max = 0.95)
    Xe1 = reg_Xe(net; out = (:L12,))
    τ1  = reg_tau(net, Xe1)
    Eq∞ = reg_Eq_inf(net, Xe1, 0.95)
    @test Xe1 ≈ 0.2422222 rtol = 1.0e-6                    # 0.40 ∥ 0.50, + 0.02
    @test τ1 ≈ 2.845266 rtol = 1.0e-5
    @test Eq∞ ≈ 1.014431 rtol = 1.0e-5

    overs = Float64[]
    for (rt, at, obound, ebound) in ((1.0e-6, 1.0e-9, 1.0e-4, 1.0e-4),
                                     (1.0e-9, 1.0e-12, 1.0e-6, 1.0e-6))
        eng, s = reg_run(net; reltol = rt, abstol = at, T = 25.0, saveat = 0.01)
        # THE SAMPLE AT THE EVENT INSTANT IS THE PRE-EVENT ONE, on this engine as on
        # every other in the repo (the playback driver records a step's samples
        # before applying the event that ends it). So `ipre` carries the flux the
        # decay starts from — which is the same number either side of the trip,
        # because the flux is a differential state — and `ipost` is the first sample
        # of the new network.
        ipre  = findlast(≤(1.0), s.t)
        ipost = findfirst(>(1.0), s.t)
        Eq0 = s.E′q_G1[ipre]

        # THE ALGEBRAIC RELATION, CHECKED AT EVERY POST-TRIP SAMPLE rather than at
        # the jump alone. `reg_V` is not a statement about one instant: with the
        # rotor pinned, the terminal voltage is that function of the flux and the
        # network reactance for the whole run, so asserting it 2,400 times is
        # strictly more than asserting the jump.
        @test all(abs(s.V_B1[i] - reg_V(net, Xe1, s.E′q_G1[i])) < 1.0e-9
                  for i in ipost:length(s.t))
        @test s.V_B1[ipost] < s.V_B1[ipre] - 0.01        # the trip really lowered it

        # THE LIMIT BINDS. It binds at `Efd_max + ε`, not at `Efd_max` — and that
        # `ε` is the whole of what bounds this state, so it is asserted as a number
        # rather than hidden inside a tolerance. Above the ceiling the saturated
        # derivative is zero, so the only excursion possible is the overshoot of the
        # single step that crosses; measured at 5.0e-8 pu, and it does not grow over
        # 24 s of sitting there. This is what replaces the `isoutofdomain` guard
        # that was written first and measured to make the ceiling unreachable
        # (`src/engines/detailed.jl`, above `_check_power_flow`).
        j0 = findfirst(t -> t ≥ 1.5, s.t)                  # past the exciter's own lag
        @test all(x -> x > 0.95 - 1.0e-9, @view s.Efd_G1[j0:end])
        over = maximum(s.Efd_G1) - 0.95
        @test 0 < over < obound
        push!(overs, over)

        # THE DECAY, fitted the way step 4 fits it: differenced against itself, so
        # the asymptote is never estimated and cannot absorb the error.
        i1 = findlast(t -> t ≤ 1.0 + 3τ1, s.t) - 20
        τm, n = flux_tau_fit(s.t[ipost:end], s.E′q_G1[ipost:end]; h = 20, i1 = i1 - ipost)
        @test n > 100
        @test τm ≈ τ1 rtol = 2.0e-3

        # …and the ASYMPTOTE, read a second and independent way off the endpoint,
        # with the finite horizon carried in the PREDICTION rather than in the
        # tolerance (step 4's lesson, and it was a failure there before it was a
        # comment). 24 s is 8.4 time constants.
        pred = Eq∞ + (Eq0 - Eq∞) * exp(-(s.t[end] - s.t[ipre]) / τ1)
        @test s.E′q_G1[end] ≈ pred rtol = ebound

        # The rotor never moved, so none of the above is an approximation.
        @test maximum(abs, s.δ_G1 .- s.δ_G1[1]) < 1.0e-12
        @test maximum(abs, s.E′d_G1) < 1.0e-12
    end
    # THE OVERSHOOT IS A LOCAL-ERROR EFFECT, WHICH IS WHY ITS BOUND IS NOT ONE
    # NUMBER. It is the excursion of the single step that lands on the ceiling, so
    # it shrinks with the solver's own tolerance: 5.3e-5 at reltol 1e-6 and 5.0e-8
    # at 1e-9. That ordering is the claim — a bound that held at both tolerances
    # without moving would mean the number is something other than local error.
    @test overs[2] < overs[1] / 100

    # ANTI-VACUITY on the prediction itself: `Xd` is what distinguishes `τ` from
    # `T′do`, and moving it must put the measured constant on the NEW prediction
    # rather than merely somewhere else. 1.8 → 1.0 pu (machine base).
    slow = regulator_bus_system(; Efd_max = 0.95, Xd = 1.0)
    τ2 = reg_tau(slow, reg_Xe(slow; out = (:L12,)))
    @test τ2 / τ1 > 1.4                                    # 4.31 s against 2.85 s
    _, s2 = reg_run(slow; T = 25.0, saveat = 0.01)
    i0 = findfirst(>(1.0), s2.t)
    i1 = findlast(t -> t ≤ 1.0 + 3τ2, s2.t) - 20
    τm2, _ = flux_tau_fit(s2.t[i0:end], s2.E′q_G1[i0:end]; h = 20, i1 = i1 - i0)
    @test τm2 ≈ τ2 rtol = 2.0e-3
end

# ---------------------------------------------------------------------------
@testset "…and it comes off the ceiling UNAIDED, when the same closed form says" begin
    # No event, no state surgery: the terminal voltage recovers under the ceiling
    # field until the regulator's own demand `K_A(Vref − |V|)` falls back through
    # `Efd_max`, and the saturation branch stops firing. A ceiling above the
    # post-trip unlimited equilibrium (0.99288) is what makes the recovery reach
    # the release point at all — and the three below bracket it, so the release
    # time is a FUNCTION of the ceiling rather than one number that happened to
    # come out right.
    #
    #   Efd_max   predicted   measured
    #     1.00      7.0106 s    7.010 s
    #     1.02      3.8056 s    3.805 s
    #     1.05      2.3982 s    2.398 s
    #
    # The prediction is the interval from the sample where the limit STARTS binding,
    # not from the trip: the exciter needs a few ms of its own lag to climb from the
    # dispatch to the ceiling, and putting that in the tolerance instead of taking
    # it out of the prediction is what step 4's endpoint check got wrong first.
    for (cap, tpred) in ((1.00, 7.0106), (1.02, 3.8056), (1.05, 2.3982))
        net = regulator_bus_system(; Efd_max = cap)
        Xe1 = reg_Xe(net; out = (:L12,))
        τ1  = reg_tau(net, Xe1)
        eng, s = reg_run(net; T = 25.0, saveat = 0.001)
        K_A = machine_arrays(net).K_A[1]
        Vref = eng.params[eng.Vref_pidx[1]]

        sat = findall(i -> s.Efd_G1[i] > cap - 1.0e-9, eachindex(s.t))
        @test s.t[findfirst(>(1.0), s.t)] > 1.0            # the post-event grid exists
        @test !isempty(sat)
        j0, j1 = first(sat), last(sat)
        # ONE binding window, entered once and left once — not chatter around the
        # limit, which is what a badly conditioned saturation would look like.
        @test j1 - j0 + 1 == length(sat)
        @test s.Efd_G1[end] < cap - 1.0e-3                 # it came off, and stayed off
        @test 0 < maximum(s.Efd_G1) - cap < 1.0e-6

        V∞   = reg_V(net, Xe1, reg_Eq_inf(net, Xe1, cap))
        Vrel = Vref - cap / K_A
        @test s.V_B1[j0] < Vrel < V∞                       # the release is reachable at all
        t_pred = -τ1 * log((Vrel - V∞) / (s.V_B1[j0] - V∞))
        @test t_pred ≈ tpred rtol = 1.0e-3                 # the prediction, before the run
        @test s.t[j1] - s.t[j0] ≈ t_pred atol = 2.0e-3     # …and the run, to the sample grid

        # THE RELEASE CONDITION ITSELF, asserted and labelled as the near-tautology
        # it is: at the release sample the demand equals the ceiling, because that
        # IS the branch condition. It is here because it pins `Vref`, `K_A` and the
        # terminal voltage into one identity, not because it is independent
        # evidence.
        @test s.V_B1[j1] ≈ Vrel atol = 1.0e-5

        # And afterwards the loop settles exactly where the UNLIMITED exciter
        # would: the limit left no trace once it stopped binding. All three caps
        # land on the same number, which is what "no trace" means.
        @test s.Efd_G1[end] ≈ 0.9928754 rtol = 1.0e-5
    end
    _, sf = reg_run(regulator_bus_system(); T = 25.0, saveat = 0.01)
    @test sf.Efd_G1[end] ≈ 0.9928754 rtol = 1.0e-5
end

# ---------------------------------------------------------------------------
@testset "a second disturbance while saturated does not freeze the integrator" begin
    # M1's test at this tier. There the bug was a ceiling that MOVED under a pinned
    # state; here the limits are constant model data and cannot move, so what is
    # checked is the weaker and still worth-checking claim: an engine sitting on a
    # saturated derivative keeps integrating across a further discontinuity.
    #
    # It is checked with a PREDICTION and not only with a retcode, because "still
    # running" is compatible with running wrong. The second trip changes the
    # network reactance, so the flux's time constant changes from 2.845 s to
    # exactly 4.0 s and its target REVERSES: `E′q` was climbing towards 1.01443 and
    # now falls towards 1.00000.
    net = regulator_bus_system(; Efd_max = 0.95)
    Xe2 = reg_Xe(net; out = (:L12, :L13))
    τ2  = reg_tau(net, Xe2)
    @test Xe2 ≈ 0.52 atol = 1.0e-12                        # only the 0.25+0.25 path, + 0.02
    @test τ2 ≈ 4.0 atol = 1.0e-12
    @test reg_Eq_inf(net, Xe2, 0.95) ≈ 1.0 atol = 1.0e-12

    eng, s = reg_run(net; trips = (1.0 => TripLine(:B1, :B2),
                                   6.0 => TripLine(:B1, :B3)),
                     T = 40.0, saveat = 0.01)
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    @test eng.integrator.t ≈ 40.0
    @test s.t[end] ≈ 40.0                                  # real progress, not a flatline
    @test n_events(eng) == 2

    i0 = findfirst(>(1.0), s.t)
    i1 = findfirst(>(6.0), s.t)
    @test s.E′q_G1[i1] > s.E′q_G1[i0]                      # it was climbing…
    @test s.E′q_G1[end] < s.E′q_G1[i1]                     # …and now falls
    @test 0 < maximum(s.Efd_G1) - 0.95 < 1.0e-6            # the ceiling held throughout
    @test all(x -> x > 0.95 - 1.0e-9, @view s.Efd_G1[i1:end])

    # The new time constant, fitted over the second window only.
    τm, n = flux_tau_fit(s.t[i1:end], s.E′q_G1[i1:end]; h = 20,
                         i1 = findlast(t -> t ≤ 6.0 + 3τ2, s.t) - i1 - 20)
    @test s.t[i1] > 6.0                                    # the post-event grid, again
    @test n > 100
    @test τm ≈ τ2 rtol = 3.0e-3
    @test s.E′q_G1[end] ≈ 1.0 + (s.E′q_G1[i1] - 1.0) * exp(-(40.0 - 6.0) / τ2) rtol = 1.0e-3
end

# ---------------------------------------------------------------------------
@testset "the regulator's four parameters do not convert with the machine base" begin
    # `Efd` is a VOLTAGE, built as `E′q + (Xd − X′d)·Id`, and a reactance times a
    # current is invariant under a change of power base. So `K_A`, `T_E` and the two
    # limits are base-free — and a row in `machine_arrays` dividing `K_A` by the
    # rating ratio, symmetric with the `Xd` rows above it, would look entirely
    # plausible and be wrong by 2.5x on this fixture.
    #
    # The control is the same PHYSICAL machine on a doubled rating: `S_rated`, every
    # machine-base reactance and the inverse of every machine-base power quantity
    # move together, so the system-base numbers are identical and the trajectory may
    # not move. It runs through the CEILING case, because a flat run would agree
    # whether or not the gain converted.
    net = regulator_bus_system(; Efd_max = 0.95)
    big = rescale_machine(net, :G1, 2.0)
    ma, mb = machine_arrays(net), machine_arrays(big)
    @test big.machines[1].S_rated == 500.0
    @test mb.Xd[1] ≈ ma.Xd[1] atol = 1.0e-14               # the conversions cancel…
    @test mb.H[1] ≈ ma.H[1] atol = 1.0e-14
    @test mb.K_A[1] == ma.K_A[1] == 200.0                  # …and this one is not a conversion
    @test mb.Efd_max[1] == ma.Efd_max[1] == 0.95

    _, sa = reg_run(net; T = 20.0, saveat = 0.05)
    _, sb = reg_run(big; T = 20.0, saveat = 0.05)
    @test maximum(abs, sb.Efd_G1 .- sa.Efd_G1) < 1.0e-9
    @test maximum(abs, sb.E′q_G1 .- sa.E′q_G1) < 1.0e-9
    @test maximum(abs, sb.V_B1 .- sa.V_B1) < 1.0e-9
    # Not a vacuous comparison: the run has real motion in it.
    @test maximum(sa.Efd_G1) - minimum(sa.Efd_G1) > 0.1
end

# ---------------------------------------------------------------------------
@testset "Machine and DetailedEngine refuse regulator data they cannot honour" begin
    base = (:G, :B1, 100.0, 4.0, 1.0, 0.2, 1.05, 50.0)
    @test_throws ArgumentError Machine(base...; K_A = -1.0)
    @test_throws ArgumentError Machine(base...; K_A = 10.0, T_E = 0.0)
    @test_throws ArgumentError Machine(base...; K_A = 10.0, T_E = -0.1)
    @test_throws ArgumentError Machine(base...; K_A = 1.0, Efd_min = 2.0, Efd_max = 1.0)
    # The ill-posed combination: zero gain with a live exciter has its only
    # equilibrium at Efd = 0, i.e. no field at all.
    @test_throws ArgumentError Machine(base...; K_A = 0.0, T_E = 0.5)
    @test Machine(base...; K_A = 0.0, T_E = Inf) isa Machine   # the default, spelled out

    # A tier that HOLDS the excitation reads none of the four numbers, so a machine
    # carrying them is refused there by name rather than run as a different machine.
    reg = regulator_bus_system()
    @test_throws ArgumentError GridSim._assert_no_regulator(reg, "who")
    @test_throws ArgumentError GridSim._assert_frozen_flux(reg, "who")
    plain = NetworkModel(100.0, 50.0, [Bus(:B1, 400.0), Bus(:B2, 400.0)],
        [Branch(:L12, :B1, :B2, 0.25, 500.0)],
        [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, 50.0; K_A = 50.0, T_E = 0.05),
         Machine(:G2, :B2, 250.0, 4.0, 2.0, 0.25, 1.05, -50.0)])
    @test_throws ArgumentError SwingEngine(plain)

    # And a dispatch outside the machine's own ceiling is refused at build time,
    # with the number, rather than left to become a run that cannot move.
    tight = regulator_bus_system(; Efd_max = 0.5)              # the dispatch is 0.786
    @test_throws ArgumentError init!(DetailedEngine, tight; slack = :G_inf)
end

# ---------------------------------------------------------------------------
@testset "ANTI-VACUITY: clamping the state instead of saturating the derivative" begin
    # M1'S BUG, REPRODUCED DELIBERATELY AND RUN. The engine is built with no limit
    # at all and the field voltage is clamped from outside every `h` seconds — a
    # post-hoc clamp on the state, which is exactly what the carried-forward rule
    # forbids.
    #
    # THE FINDING IS NOT THE ONE THIS TESTSET WAS WRITTEN TO MAKE. The prediction
    # was "three of the four claims stay green and one goes red", with the
    # inversion that a clamped state never exceeds its ceiling where the correct
    # one overshoots by 5e-8. Run, it turned out sharper than that: THE HEADLINE
    # CHECK READS RED OR GREEN DEPENDING ON WHERE IT LOOKS. Sampled at the clamp
    # instants the state is exactly at its cap and never above it — 0.0 excess, at
    # every step size tried. Sampled anywhere else it is 0.378 pu above the cap at
    # h = 0.005, seven million times the correct engine's 5e-8.
    #
    # That is the property a post-hoc clamp has and a saturation in the derivative
    # does not: the answer depends on the observation cadence. "The field voltage
    # never goes above its limit" is not a false statement about the clamped run
    # and not a true one — it is a statement about the recorder.
    net = regulator_bus_system(; Efd_max = 0.95)
    Xe1 = reg_Xe(net; out = (:L12,))
    τ1  = reg_tau(net, Xe1)
    _, good = reg_run(net; T = 25.0, saveat = 0.01)
    free = regulator_bus_system()                             # no limits: the clamp is all there is
    _, bad, post = clamped_run(free, 0.95; h = 0.005, T = 25.0)

    # ── THE SPLIT: one run, one state variable, two maxima that disagree by 0.378.
    #    `post` is the field voltage sampled just AFTER each clamp; `bad.Efd_G1` is
    #    the recorded trajectory, whose samples land just BEFORE the next one.
    @test post ≤ 0.95 + 1.0e-14                                # obedient, if you look here
    @test maximum(bad.Efd_G1) - 0.95 > 0.3                     # and 0.378 over, if you look here
    @test maximum(bad.Efd_G1) - 0.95 ≈ 0.3777 rtol = 0.05
    # …against which the correct engine's own excursion is a rounding error: it does
    # exceed the ceiling, by the local error of the one step that lands on it.
    @test maximum(good.Efd_G1) > 0.95
    @test maximum(good.Efd_G1) - 0.95 < 1.0e-6
    @test (maximum(bad.Efd_G1) - 0.95) > 1.0e6 * (maximum(good.Efd_G1) - 0.95)
    # ── STAYS GREEN 2: "it sits on the ceiling while the demand binds."
    j0 = findfirst(t -> t ≥ 1.5, bad.t)
    @test all(x -> x > 0.95 - 1.0e-9, @view bad.Efd_G1[j0:end])
    # ── STAYS GREEN 3: "a further disturbance does not freeze the integrator" —
    #    nothing about a clamp stops the solver advancing.
    @test bad.t[end] ≈ 25.0

    # ── GOES RED: the closed form. Between clamps the flux integrates against a
    #    field voltage that has run away above the ceiling, so `E′q` climbs past
    #    where a 0.95 pu field could take it. The correct run lands on the predicted
    #    asymptote; the clamped one overshoots it.
    i0 = findlast(≤(1.0), good.t)
    Eq∞ = reg_Eq_inf(net, Xe1, 0.95)
    pred = Eq∞ + (good.E′q_G1[i0] - Eq∞) * exp(-(good.t[end] - good.t[i0]) / τ1)
    @test good.E′q_G1[end] ≈ pred rtol = 1.0e-6
    err_good = abs(good.E′q_G1[end] - pred)
    err_bad  = abs(bad.E′q_G1[end] - pred)
    @test err_bad > 100 * err_good
    @test bad.E′q_G1[end] > good.E′q_G1[end]                  # it overshoots, not undershoots

    # ── AND THE SIGNATURE, which is what makes this a bug rather than a different
    #    model: the answer depends on how often the clamp is applied, and a correct
    #    method's answer does not move at all. IT IS READ ON THE EXCESS FIELD, NOT
    #    ON THE ENDPOINT FLUX, and which of the two carries the rate was measured
    #    rather than assumed. Over h = 0.02, 0.01, 0.005, 0.0025, 0.001, 0.0005:
    #
    #      excess field   1.2128  0.7089  0.3777  0.1942  0.0789  0.0396  → linear in h
    #      endpoint flux  0.0140  0.0128  0.0110  0.0086  0.0052  0.0031  → only monotone
    #
    #    The flux endpoint decays by a factor 0.78 per halving, not 0.5, because by
    #    24 s the voltage loop has closed around the clamped run and it has settled
    #    on an equilibrium of its own. A SETTLED OBSERVABLE CANNOT CARRY A RATE —
    #    the first version of this check asked the endpoint to halve, and it was the
    #    check that was wrong, not the engine.
    _, bad2, post2 = clamped_run(free, 0.95; h = 0.0025, T = 25.0)
    @test post2 ≤ 0.95 + 1.0e-14                               # the split is not an artefact of h
    exc1, exc2 = maximum(bad.Efd_G1) - 0.95, maximum(bad2.Efd_G1) - 0.95
    @test exc2 / exc1 ≈ 0.5 rtol = 0.1
    err2 = abs(bad2.E′q_G1[end] - pred)
    @test err2 < err_bad                                       # monotone, and only monotone
    @test err2 > 10 * err_good
end

# ---------------------------------------------------------------------------
@testset "the guard that was removed, and the one that stays — both measured" begin
    # M5 STEP 5'S SHARPEST FINDING, AND IT IS ABOUT CODE THAT SHIPPED THREE
    # MILESTONES AGO. `engines/swing.jl` says of its `ΔPm` domain guard: "During
    # continuous integration it cannot stall, because the derivative is already zero
    # at the ceiling, which puts the solution *at* headroom, not above it." The
    # derivative IS zero at the ceiling. What does not follow is that the solution
    # gets there: the guard accepts a step only if it lands at or below
    # `limit + 1e-10`, and a state approaching from below with a finite derivative
    # needs an ever-smaller step to land inside that window.
    #
    # Written first for this tier, it killed the run — the measurement is in
    # `src/engines/detailed.jl` above `_check_power_flow`. What THIS testset is for
    # is the other half: whether the engines that still carry the guard are stalling
    # too. They are not, and the reason is a single number nobody chose.
    gov = NetworkModel(100.0, 50.0,
        [Bus(:B1, 400.0), Bus(:B2, 400.0)],
        [Branch(:L12, :B1, :B2, 0.25, 500.0)],
        [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05,  60.0, 0.05, 65.0, 1.0),
         Machine(:G2, :B2, 400.0, 5.0, 2.0, 0.30, 1.02, -60.0)])
    eng = SwingEngine(gov; reltol = 1.0e-9, abstol = 1.0e-12)
    hr  = machine_arrays(gov).headroom[1]
    @test hr == 0.05
    eng.params[eng.Pm_pidx[2]] -= 0.30            # a deficit far beyond G1's reserve
    SciMLBase.auto_dt_reset!(eng.integrator)
    solve!(eng, (0.0, 2000.0); saveat = 1.0)
    over = current_state(eng).ΔPm[1] - hr
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    @test eng.integrator.t ≈ 2000.0
    @test eng.integrator.dt > 1.0e-3              # no step-size collapse: measured ~0.09 s

    # THE GOVERNOR LANDS *ABOVE* ITS CEILING, by 3.1e-11 — which is inside the
    # guard's 1e-10 window, and that is the entire reason it does not stall. The
    # sign matters: a state that stopped strictly below the limit would be the
    # stalling case.
    @test over > 0
    @test over < 1.0e-10                          # the window — measured 3.1e-11, 3x inside it
    @test over > 1.0e-13                          # …and a real excursion, not a zero
    # The exact 3.1e-11 is NOT asserted: it depends on the solver's step-size
    # history, and a number that a `Pkg` re-resolve can move is a number a test
    # should not pin. The claim is the sign, the order and the margin.

    # AND THE MARGIN IS A PROPERTY OF THE STATE'S SPEED, not of the guard. The
    # overshoot on the step that lands scales with how fast the state moves: this
    # governor's lag is 1 s and it overshoots by 3e-11; the exciter's is 0.05 s and
    # it needs 5e-8, which is 500x the window. Same construction, opposite outcome,
    # decided by a constant written for round-off.
    _, s = reg_run(regulator_bus_system(; Efd_max = 0.95); T = 25.0, saveat = 0.05)
    exciter_over = maximum(s.Efd_G1) - 0.95
    @test exciter_over > 100 * over
    @test exciter_over > 1.0e-9                   # …and larger than the window it would face

    # The other half of the sweep, kept because it is the reason `init!` takes a
    # `solver`: a hard saturation is a DISCONTINUOUS right-hand side, and Rodas5P
    # fails on this fixture at one isolated ceiling (1.2) and one isolated tolerance
    # (1e-9) while completing 1.15, 1.3 and the same 1.2 at 1e-6 and 1e-11. FBDF
    # completes it. Only the positive half is asserted — which solver version fails
    # where is not something a test should pin.
    net = regulator_bus_system(; Efd_max = 1.2)
    e2  = init!(DetailedEngine, net; slack = :G_inf, solver = OrdinaryDiffEq.FBDF(),
                reltol = 1.0e-9, abstol = 1.0e-12)
    s2  = solve!(e2, (0.0, 12.0); saveat = 0.005,
                 perturbations = (1.0 => TripLine(:B1, :B2),))
    @test SciMLBase.successful_retcode(e2.integrator.sol.retcode)
    @test 0 < maximum(s2.Efd_G1) - 1.2 < 1.0e-6
end

end # M5 step 5


# =============================================================================
# M5 STEP 6 — VOLTAGE-DEPENDENT LOAD
# =============================================================================
#
# The step that lets voltage actually FALL. Through step 5 a load drew `P₀·|V|²`
# and nothing else; the constant-current and constant-power terms were validated
# by `Load` and refused by the engine with this step named. They are solved now,
# on both the dynamic path and the power-flow path, and the checks below are
# ordered by what they can catch:
#
#   1. arithmetic — `_load_current` alone, with `===` rather than `≈`, because the
#      two exactness claims in its docstring are exact or they are nothing;
#   2. the fixpoint — the three pure ZIP cases on one fixture, whose drawn powers
#      are STRICTLY ORDERED by algebra with no tolerance to choose;
#   3. the flat run — the only check that can see the two paths disagreeing, since
#      it is the one that runs the dynamic equations from the power flow's answer;
#   4. a closed form with TWO roots — the P-V nose, which gives this step a derived
#      limit rather than a chosen one, and an assertion about WHICH solution the
#      solve landed on;
#   5. the mutations, run rather than predicted — and one of them turned out to be
#      indistinguishable from a control that was already in this file.

@testset "M5 step 6 — voltage-dependent load" begin

# --- 1. the arithmetic, exactly ---------------------------------------------
@testset "_load_current: the two exactnesses are exact, not approximate" begin
    G, B = 0.7, -0.3
    # THE DEFAULT PATH IS BITWISE WHAT IT WAS. Every M5 number measured before this
    # step was measured on `I = (G + jB)·V`, and `===` is the only comparison that
    # can say so — `≈` would pass a `k` that is `1 + 2eps` (M4 step 3's lesson: the
    # off-by-one was caught by `===` and by nothing weaker).
    for (Vre, Vim) in ((0.93, -0.11), (1.0, 0.0), (-0.4, 0.88), (0.0, 0.5))
        @test GridSim._load_current(Vre, Vim, G, B, 0.0, 0.0) ===
              (G * Vre - B * Vim, G * Vim + B * Vre)
    end
    # `k = 1` AT |V| = 1 FOR EVERY SPLIT. This is what makes `P₀` mean "drawn at
    # nominal voltage" regardless of the share split — the property `Load`'s
    # sum-to-one guard exists to buy, asserted here where it is actually used.
    for (a_i, a_p) in ((0.4, 0.35), (1.0, 0.0), (0.0, 1.0), (0.5, 0.5))
        @test GridSim._load_current(1.0, 0.0, G, B, a_i, a_p) ===
              GridSim._load_current(1.0, 0.0, G, B, 0.0, 0.0)
        @test GridSim._load_current(0.0, -1.0, G, B, a_i, a_p) ===
              GridSim._load_current(0.0, -1.0, G, B, 0.0, 0.0)
    end
    # …and away from |V| = 1 it is NOT the same current, or the two blocks above
    # would both pass against a `k` hard-wired to one.
    @test GridSim._load_current(0.8, 0.0, G, B, 0.0, 1.0)[1] >
          GridSim._load_current(0.8, 0.0, G, B, 0.0, 0.0)[1]
    # the scalar itself: at |V| = 0.5 a constant-power load draws four times the
    # current the same nominal admittance would
    let (Ire, _) = GridSim._load_current(0.5, 0.0, G, B, 0.0, 1.0)
        @test Ire ≈ (G * 0.5) * 4 atol = 1e-14
    end
    # A BUS WITH NO LOAD IS ARITHMETICALLY NO LOAD, including at a voltage where a
    # `1/|V|²` would be enormous — nothing here divides by a zero it did not have.
    @test GridSim._load_current(1e-8, 0.0, 0.0, 0.0, 0.0, 0.0) === (0.0, 0.0)
end

# --- 2. the fixpoint: three cases, strictly ordered --------------------------
@testset "the ZIP terms are SOLVED, and their drawn powers are ordered" begin
    # THE ORDERING IS THE DISCRIMINATOR AND IT NEEDS NO TOLERANCE. The network is
    # lossless, so `Σ Pm` at the solved point IS the power the load draws — read
    # from the engine's own parameters, not recomputed from the formula under
    # test. `load_bus_system` solves at |V| < 1, which is exactly where the three
    # ZIP terms stop agreeing: `P₀|V|² < P₀|V| < P₀`. A build that ignored `a_i`
    # and `a_p` would make all three identical.
    draw = Dict{Symbol,Float64}()
    volt = Dict{Symbol,Float64}()
    for (nm, sh) in ((:Z, (a_z = 1.0, a_i = 0.0, a_p = 0.0)),
                     (:I, (a_z = 0.0, a_i = 1.0, a_p = 0.0)),
                     (:P, (a_z = 0.0, a_i = 0.0, a_p = 1.0)))
        eng = init!(DetailedEngine, load_bus_system(; sh...))
        draw[nm] = sum(eng.params[i] for i in eng.Pm_pidx)
        volt[nm] = current_state(eng).V[3]
    end
    @test draw[:Z] < draw[:I] < draw[:P]
    # …and the voltage falls the other way, because more draw is more drop
    @test volt[:Z] > volt[:I] > volt[:P]
    # the measured values, so a change that preserves the ordering but moves the
    # numbers is still visible
    @test draw[:Z] ≈ 1.054270011424 atol = 1e-10      # P₀|V|², the step-1 number
    @test draw[:I] ≈ 1.074904942688 atol = 1e-10
    @test volt[:Z] ≈ 0.978992994415 atol = 1e-10
    @test volt[:P] ≈ 0.974951270571 atol = 1e-10

    # THE CONSTANT-POWER CASE HAS A CLOSED FORM WITH NO VOLTAGE IN IT AT ALL, and
    # it is the sharpest single number this step produces: a constant-power load
    # draws `P₀` whatever the network does, so `Σ Pm` must equal the schedule
    # EXACTLY, not to a power-flow tolerance. Measured: 8.9e-16, i.e. round-off.
    let net = load_bus_system(; a_z = 0.0, a_i = 0.0, a_p = 1.0)
        eng = init!(DetailedEngine, net)
        @test sum(eng.params[i] for i in eng.Pm_pidx) ≈ load_arrays(net).P[1] atol = 1e-14
    end
    # the constant-impedance closed form step 1 already had, restated at the share
    # that now has to be READ rather than assumed
    let net = load_bus_system(; a_z = 1.0)
        eng = init!(DetailedEngine, net)
        la = load_arrays(net)
        @test sum(eng.params[i] for i in eng.Pm_pidx) ≈
              la.P[1] * current_state(eng).V[la.bus[1]]^2 atol = 1e-10
    end
    # …and the constant-CURRENT one, which is neither of the two above
    let net = load_bus_system(; a_z = 0.0, a_i = 1.0, a_p = 0.0)
        eng = init!(DetailedEngine, net)
        la = load_arrays(net)
        @test sum(eng.params[i] for i in eng.Pm_pidx) ≈
              la.P[1] * current_state(eng).V[la.bus[1]] atol = 1e-10
    end
end

# --- 3. the flat run, which is the check that the two paths agree ------------
@testset "the flat run with a ZIP load, at two tolerances" begin
    # THIS IS THE CHECK THAT DISCRIMINATES THE WIRING. The dynamic RHS and the
    # power-flow RHS are two different vertex models that both call
    # `_load_current`; if only one of them were handed the shares, the fixpoint
    # would not be an equilibrium of the equations that are integrated, and the
    # run would not be flat. Nothing else in this file can see that.
    for (a_z, a_i, a_p) in ((0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (0.2, 0.3, 0.5))
        net = load_bus_system(; a_z = a_z, a_i = a_i, a_p = a_p)
        for (rtol, atol) in ((1e-3, 1e-6), (1e-8, 1e-11))
            eng = init!(DetailedEngine, net; reltol = rtol, abstol = atol)
            ser = solve!(eng, (0.0, 10.0); saveat = 0.05)
            @test length(ser.t) > 100
            for ch in keys(ser)
                ch === :t && continue
                v = getproperty(ser, ch)
                # worst measured across all six runs: 1.2e-13
                @test maximum(abs, v .- v[1]) < 1e-10
            end
        end
    end
end

# --- 4. the closed form with two roots, and which one we are on --------------
#
# A machine-free load bus fed from ONE machine through a reactance is the textbook
# P-V nose, and it is the closed form this step is worth having. With the source
# `E∠0` behind `jX` (`X = Xq + X_line`, `Ra = 0`) and `S = P + jQ` drawn at the far
# bus, `S = j(EV − |V|²)/X` gives, with `u = |V|²`,
#
#     u² + u(2QX − E²) + (PX)² + (QX)² = 0
#
# — a QUADRATIC, so there are two voltages at which the same constant-power load is
# served, and both are honest roots of the residual the solver drives to zero. The
# discriminant vanishing is the nose:
#
#     P_max = E·sqrt(E² − 4QX) / (2X)
#
# and that limit is DERIVED, not chosen — which is the whole reason this fixture
# exists rather than another band on `load_bus_system`.
_zip_radial(P0, Q0; a_z = 0.0, a_i = 0.0, a_p = 1.0, X = 0.20) =
    NetworkModel(100.0, 50.0,
        [Bus(:B1, 400.0), Bus(:B2, 400.0)],
        [Branch(:L12, :B1, :B2, X, 500.0)],
        [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05, P0)],
        [Load(:L2, :B2, P0, Q0, a_z, a_i, a_p)])

# the two roots, high branch first; `NaN`s past the nose
function _pv_roots(E, X, P, Q)
    b = 2Q * X - E^2
    d = b^2 - 4 * ((P * X)^2 + (Q * X)^2)
    d < 0 && return (NaN, NaN)
    return (sqrt((-b + sqrt(d)) / 2), sqrt((-b - sqrt(d)) / 2))
end
_pv_max(E, X, Q) = E * sqrt(E^2 - 4Q * X) / (2X)

@testset "the P-V nose: two roots, the branch we land on, and a derived limit" begin
    net = _zip_radial(60.0, 20.0)
    ma, bt, la = machine_arrays(net), branch_topology(net), load_arrays(net)
    E, X = ma.E[1], ma.Xq[1] + bt.X[1]
    hi, lo = _pv_roots(E, X, la.P[1], la.Q[1])

    # THE TWO ROOTS ARE FAR APART, so "which one" is a real question rather than a
    # rounding one: 0.972 pu and 0.195 pu, both exact solutions of the same
    # equations, and the residual cannot tell them apart (the header above
    # `_check_power_flow` measured the collapsed one converging 400x TIGHTER).
    @test hi ≈ 0.971792026 atol = 1e-8
    @test lo ≈ 0.195244100 atol = 1e-8
    @test hi - lo > 0.7

    # AND WE ARE ON THE HIGH ONE. The closed form is exact — nothing here is
    # linearised — so this is a 1e-9 claim rather than a band.
    eng = init!(DetailedEngine, net)
    @test current_state(eng).V[2] ≈ hi atol = 1e-9
    @test !isapprox(current_state(eng).V[2], lo; atol = 1e-2)

    # THE DERIVED LIMIT, AND THE SOLVER'S OWN FAILURE BRACKETING IT. `P_max` is
    # 1.62524 pu at this `Q`. Scanned: at 1.62 pu the roots are still distinct
    # (0.7283 / 0.6724) and the solve returns an answer; at 1.63 pu the
    # discriminant is negative, there is no solution to find, and the fixpoint
    # solver reports exactly that. So a limit derived on paper predicts, to better
    # than half a percent, where somebody else's Newton stops converging.
    @test _pv_max(E, X, la.Q[1]) ≈ 1.625240 atol = 1e-5
    @test all(!isnan, _pv_roots(E, X, 1.62, la.Q[1]))
    @test all(isnan,  _pv_roots(E, X, 1.63, la.Q[1]))
    # …and the roots coalesce as the nose is approached, which is what makes the
    # limit a nose rather than an arbitrary cut-off
    let r1 = _pv_roots(E, X, 1.50, la.Q[1]), r2 = _pv_roots(E, X, 1.62, la.Q[1])
        @test (r1[1] - r1[2]) > (r2[1] - r2[2]) > 0
        @test (r2[1] - r2[2]) < 0.06
    end
    # the engine past the nose: it does not return a wrong answer, it fails
    @test_throws Exception init!(DetailedEngine, _zip_radial(170.0, 20.0))
    # BELOW the nose but below the voltage band it also refuses — and the two
    # refusals are DIFFERENT THINGS, which is why both are named here. At 130 MW
    # the high root still exists and is what the solve finds (0.885364 pu, and the
    # closed form agrees to six digits); it is the |V| ∈ [0.9, 1.1] band, not the
    # nose, that rejects the case. Mistaking one refusal for the other would read
    # "infeasible" off a case that is merely poorly served.
    let (h130, l130) = _pv_roots(E, X, 1.30, la.Q[1])
        @test !isnan(h130) && !isnan(l130)
        @test h130 ≈ 0.885364426 atol = 1e-8          # the value the solve returns
    end
    @test occursin("outside", (try; init!(DetailedEngine, _zip_radial(130.0, 20.0)); ""
                               catch e; sprint(showerror, e) end))
    # …and at 120 MW, between the two, the engine simply builds — so neither
    # refusal is always-on.
    @test init!(DetailedEngine, _zip_radial(120.0, 20.0)) isa DetailedEngine
end

# --- 5. the mutations, RUN --------------------------------------------------
@testset "the ZIP wiring's anti-vacuity controls, and what running them found" begin
    la_bus = load_arrays(load_bus_system()).bus[1]
    a_p_pidx(eng, v) = NetworkDynamics.SII.parameter_index(
        eng.nw, NetworkDynamics.VPIndex(v, :a_p))

    # MUTATION A — the dynamic path drops the shares the power flow honoured. The
    # fixpoint is solved for a constant-POWER load (drawing 1.100 pu) and the
    # integrated equations are then made constant-impedance (drawing 1.054 pu), so
    # generation exceeds load by 0.046 pu and frequency RISES.
    let net = load_bus_system(; a_z = 0.0, a_i = 0.0, a_p = 1.0)
        eng = init!(DetailedEngine, net)
        eng.params[a_p_pidx(eng, la_bus)] = 0.0
        ser = solve!(eng, (0.0, 10.0); saveat = 0.05)
        Δf = ser.f_coi[end] - ser.f_coi[1]
        @test Δf > 0.1
        @test Δf ≈ 0.1570 atol = 1e-3
    end

    # …AND RUNNING IT IS WHAT FOUND THIS: mutation A is NUMERICALLY THE SAME RUN as
    # the `Pm`-from-the-schedule control already in this file (+0.157 Hz, ~6.6 rad),
    # and not by coincidence. Both are the same 0.046 pu imbalance between what the
    # machines inject and what the load draws; the two bugs differ in which side of
    # that equality is wrong, and the trajectory cannot see which. A mutation's
    # MAGNITUDE is not its identity. So the control that actually discriminates the
    # ZIP wiring is the one below, whose sign is the other way.

    # MUTATION C — the power flow solved a constant-IMPEDANCE load and the dynamic
    # path draws constant POWER. Same 0.046 pu, opposite direction: the load now
    # draws MORE than the machines were told to make, and frequency FALLS.
    let net = load_bus_system()                       # a_z = 1
        eng = init!(DetailedEngine, net)
        eng.params[a_p_pidx(eng, la_bus)] = 1.0
        ser = solve!(eng, (0.0, 10.0); saveat = 0.05)
        Δf = ser.f_coi[end] - ser.f_coi[1]
        @test Δf < -0.1                                # the SIGN is the finding
        @test Δf ≈ -0.15616 atol = 1e-3
    end

    # THE POSITIVE CONTROL FOR THE CONTROLS: the unmutated run of the same fixture
    # is flat, so the two numbers above are the mutation and not the fixture.
    let eng = init!(DetailedEngine, load_bus_system(; a_z = 0.0, a_i = 0.0, a_p = 1.0))
        ser = solve!(eng, (0.0, 10.0); saveat = 0.05)
        @test maximum(abs, ser.f_coi .- ser.f_coi[1]) < 1e-10
    end
end

end # M5 step 6

# =========== M5 step 7 — the criterion, and M3's protection at this tier ==========
#
# The milestone's purpose (m5-plan.md §Goal). Everything before this step exists to
# make ONE measurement attributable: at the tie strength where the classical tier
# loses synchronism at the report's cascade, the detailed tier must both lose
# synchronism AND carry a peak export above that tier's `P_max`.
#
# The anti-vacuity control is named in the plan and is the sharpest thing here: with
# the flux frozen, the same engine on the same topology has a DERIVED transfer
# ceiling, and the criterion must fail against it.
@testset "M5 step 7 — the criterion, and M3's protection at this tier" begin

@testset "the ramp at this tier: zero rate is the un-ramped machine, to the bit" begin
    # M3 step 5's first test, re-run one tier up. `Pm_eff = Pm + rate·clamp(…)` with
    # `rate = 0` is `Pm + 0.0`, so this is an EQUALITY and not a tolerance — which is
    # what makes it able to catch an armed ramp that changes the run when it should
    # not, at any size.
    net = governed_ring()
    a = solve!(init!(DetailedEngine, net; dt = 0.05), (0.0, 10.0))
    b = solve!(init!(DetailedEngine, net; dt = 0.05,
                     ramp = [:G1 => GenerationRamp(0.0, 1.0, 5.0)]), (0.0, 10.0))
    @test keys(a) == keys(b)
    for k in keys(a)
        @test a[k] == b[k]                      # `==`, not `≈`
    end
    # …and the ramp really was armed, so the equality above is about `rate = 0` and
    # not about an argument that was silently dropped on the way in.
    armed = init!(DetailedEngine, net; dt = 0.05,
                  ramp = [:G1 => GenerationRamp(0.0, 1.0, 5.0)])
    @test generation_ramp(armed, :G1).duration == 5.0
end

@testset "the ramp at this tier: read back, guarded, and inert at the fixpoint" begin
    net = governed_ring()
    r = GenerationRamp(-0.06, 1.0, 5.0)
    eng = init!(DetailedEngine, net; dt = 0.05, ramp = [:G1 => r])
    @test generation_ramp(eng, :G1) === r
    @test_throws KeyError generation_ramp(eng, :G2)

    # THE GUARDS ARE `SwingEngine`'s OWN (`_bind_ramps`), reached from this tier —
    # not a copy. One message each, the M2/M3 discipline.
    @test occursin("no machine named", argerr_msg(() ->
        init!(DetailedEngine, net; ramp = [:NOPE => r])))
    @test occursin("two ramps on machine", argerr_msg(() ->
        init!(DetailedEngine, net; ramp = [:G1 => r, :G1 => r])))
    @test occursin("before the run's own t0", argerr_msg(() ->
        init!(DetailedEngine, net; t0 = 2.0, ramp = [:G1 => GenerationRamp(-0.06, 1.0, 5.0)])))

    # INERT AT THE STEADY-STATE SOLVE. `t_start ≥ t0` makes the ramp term exactly
    # zero at `t0`, so the engine is placed on the equilibrium of the UN-ramped
    # system and starts flat. A mis-signed `t_start` would fold the ramp into the
    # initial condition and the run would ring from its first step with pure
    # artefact. Asserted on the state, not on the parameter.
    s = current_state(eng)
    @test all(iszero, s.ω) && all(iszero, s.ΔPm)
    @test s.f_coi ≈ net.f0 atol = 1e-12
end

@testset "the ramp's closed form holds at the detailed tier" begin
    # THE M3 CLOSED FORM THAT STILL APPLIES (D8). Summing the swing equations over a
    # lossless network kills `ΣPe`, so at rest
    #     ω_ss = ΔP / (Σ 1/R + Σ D)
    # — a statement about a POWER BALANCE and about nothing the tier changed. It is
    # therefore the right thing to re-check here: if it failed, the new tier's
    # governor, its per-unit conversion or its ramp would be wrong, and the number
    # says which because it is exact.
    net = governed_ring()                        # 50 pu of reserve: nothing saturates
    ma = machine_arrays(net)
    ΔP = -0.30
    r = GenerationRamp(ΔP / 5.0, 1.0, 5.0)
    ω_ss = ΔP / (sum(ma.invR) + sum(ma.D))
    eng = init!(DetailedEngine, net; dt = 0.05, ramp = [:G1 => r],
                reltol = 1e-8, abstol = 1e-10, maxiters = 10_000_000)
    solve!(eng, (0.0, 300.0))
    s = current_state(eng)
    @test s.ω[2] ≈ ω_ss rtol = 1e-8              # measured 9.5e-11
    @test s.ω[1] ≈ ω_ss rtol = 1e-8              # every machine at the SAME speed
    @test s.ω[3] ≈ ω_ss rtol = 1e-8
    # The half that pins the GAIN conversion all the way to a trajectory.
    @test s.ΔPm[2] ≈ -ω_ss * ma.invR[2] atol = 1e-9
    @test s.ΔPm[3] ≈ -ω_ss * ma.invR[3] atol = 1e-9
    # THE PRECONDITION, ASSERTED: no machine touched its ceiling, or the closed form
    # would have been asserted straight through a saturated transient.
    @test s.ΔPm[2] < 0.5 * ma.headroom[2]
    @test s.ΔPm[3] < 0.5 * ma.headroom[3]

    # POSITIVE CONTROL: with no ramp the same run settles at ω = 0 exactly, so the
    # number above is the ramp and not the fixture.
    bare = init!(DetailedEngine, net; dt = 0.05, reltol = 1e-8, abstol = 1e-10)
    solve!(bare, (0.0, 300.0))
    @test maximum(abs, current_state(bare).ω) < 1e-12

    # ANTI-VACUITY, RUN: scale the ramp by 1.5 and the settled speed must scale by
    # 1.5. A closed form asserted at one magnitude can be satisfied by a formula
    # that is wrong by a constant factor; this is what rules that out.
    eng15 = init!(DetailedEngine, net; dt = 0.05,
                  ramp = [:G1 => GenerationRamp(1.5 * ΔP / 5.0, 1.0, 5.0)],
                  reltol = 1e-8, abstol = 1e-10, maxiters = 10_000_000)
    solve!(eng15, (0.0, 300.0))
    @test current_state(eng15).ω[2] ≈ 1.5 * ω_ss rtol = 1e-8
end

@testset "the shed ladder at the detailed tier: instant, block, and settled speed" begin
    net = governed_ring()
    ma = machine_arrays(net)
    ΔP, thr, blk = -0.60, 49.7, 0.20
    r = GenerationRamp(ΔP / 4.0, 1.0, 4.0)
    de(; kw...) = init!(DetailedEngine, net; dt = 0.01, ramp = [:G1 => r],
                        reltol = 1e-8, abstol = 1e-10, maxiters = 10_000_000, kw...)

    # The bare run brackets G2's own crossing of the threshold to one `dt`.
    sb = solve!(de(), (0.0, 60.0))
    fG2 = net.f0 .* (1 .+ sb.ω_G2)
    k = findfirst(i -> fG2[i-1] >= thr > fG2[i], 2:length(fG2)) + 1
    tcross = sb.t[k]
    @test minimum(fG2) < thr - 0.05              # it really goes through, with margin

    eng = de(; shed = [:G2 => [LoadShedStage(thr, blk; label = :s1)]])
    Pm0 = eng.params[eng.Pm_pidx[2]]
    solve!(eng, (0.0, 300.0))
    lg = shed_log(shed_ladder(eng, :G2))
    @test length(lg.t) == 1 && lg.label == [:s1]
    @test shed_ladder(eng, :G2).armed == [false]        # latched
    # ROOT-FOUND, not stepped onto: inside the bare run's one-`dt` bracket, and off
    # the `dt` grid.
    @test tcross - 0.01 < lg.t[1] <= tcross
    @test !isapprox(lg.t[1] / 0.01, round(lg.t[1] / 0.01); atol = 1e-6)
    # …and it stepped THAT machine's power by exactly the block.
    @test eng.params[eng.Pm_pidx[2]] - Pm0 ≈ blk atol = 1e-14
    @test eng.params[eng.Pm_pidx[1]] == eng.params[eng.Pm_pidx[1]]   # untouched (NaN-free)

    # THE CLOSED FORM AGAIN, WITH THE BLOCK IN IT. This is the check that the shed
    # reaches the physics rather than only the log: the settled speed must be the
    # one the balance gives for `ΔP + blk`, and it is a different number from the
    # un-shed one by a factor of three.
    ω_shed = (ΔP + blk) / (sum(ma.invR) + sum(ma.D))
    ω_bare = ΔP / (sum(ma.invR) + sum(ma.D))
    @test current_state(eng).ω[2] ≈ ω_shed rtol = 1e-7
    @test !isapprox(ω_shed, ω_bare; rtol = 0.1)         # the two are far apart
end

@testset "the out-of-step relay at the detailed tier: root, trip, re-initialisation" begin
    net = governed_ring()
    r = GenerationRamp(-2.0 / 3.0, 1.0, 3.0)
    thr = 0.20
    de(; kw...) = init!(DetailedEngine, net; dt = 0.01, ramp = [:G1 => r],
                        reltol = 1e-8, abstol = 1e-10, maxiters = 10_000_000, kw...)

    sb = solve!(de(), (0.0, 30.0))
    db = abs.(sb.δ_G1 .- sb.δ_G2)
    @test db[1] < thr                                    # armed on a healthy tie
    @test maximum(db) > thr                              # …that the swing carries out
    k = findfirst(i -> db[i] >= thr > db[i-1], 2:length(db)) + 1
    tcross = sb.t[k]

    eng = de(; out_of_step = [(:B1, :B2) => OutOfStepTrip(thr; label = :oos)])
    solve!(eng, (0.0, 30.0))
    lg = out_of_step_log(out_of_step_relay(eng, :B1, :B2))
    @test lg.tripped
    @test tcross - 0.01 < lg.t <= tcross
    @test !isapprox(lg.t / 0.01, round(lg.t / 0.01); atol = 1e-6)
    # THE ROOT WAS FOUND ON THE INTENDED QUANTITY, and this is the direct check:
    # `|δ|` at the reported instant equals the threshold, not merely near it.
    @test abs(lg.δ) ≈ thr atol = 1e-9
    # It fired through the engine's OWN `inject!(::TripLine)` — the branch is out,
    # the event is logged once, and `_reinitialise_algebraic!` accepted the
    # post-trip algebraic solve (it throws with a number if it does not).
    @test !is_online(eng, :B1, :B2)
    @test n_events(eng) == 1
    @test event_log(eng)[1].kind === :trip_line

    # THE START GUARD IS REACHED FROM THIS TIER TOO, and it is `SwingEngine`'s own
    # (`_guard_out_of_step_start`), not a copy.
    @test occursin("protects nothing", argerr_msg(() ->
        de(; out_of_step = [(:B1, :B2) => OutOfStepTrip(0.01)])))
    @test occursin("no branch joins", argerr_msg(() ->
        de(; out_of_step = [(:B1, :NOPE) => OutOfStepTrip(thr)])))
end

@testset "a shed ladder is REFUSED on a model carrying a Load" begin
    # The one place M3's protection does NOT carry unchanged, refused by name rather
    # than documented. A ladder steps its machine's `Pm`, which at the classical
    # tier is a NET injection (so shedding load raises it by the block) and at this
    # tier is MECHANICAL power — so on a model with a real `Load` it would add
    # generation instead of disconnecting load, and the two differ by exactly the
    # voltage-dependence step 6 built.
    msg = argerr_msg(() -> init!(DetailedEngine, load_bus_system();
                                 shed = [:G1 => [LoadShedStage(49.5, 0.1)]]))
    @test occursin("refused on a model carrying a Load", msg)
    @test occursin("MECHANICAL power", msg)
    # …and it is the LOAD that is refused, not the ladder: the same ladder on a
    # load-free model builds.
    @test init!(DetailedEngine, governed_ring();
                shed = [:G1 => [LoadShedStage(49.5, 0.1)]]) isa DetailedEngine
end

@testset "the flat run ACROSS an event (D8's check, and nothing else does it)" begin
    # `inject!` ends in a consistent re-initialisation, and step 1's flat run cannot
    # see it: that run has no event in it. This one does.
    #
    # THE FIXTURE IS THE POINT. Every machine at zero injection with the SAME
    # internal voltage puts every bus at the same complex voltage, so every branch
    # carries EXACTLY zero current and removing one changes nothing at all. The
    # post-trip equilibrium is therefore known in closed form — it is the pre-trip
    # one — and any departure is re-initialisation artefact and nothing else.
    net = quiet_ring()
    eng = init!(DetailedEngine, net; dt = 0.05, reltol = 1e-8, abstol = 1e-10)
    @test maximum(abs, branch_power(eng)) < 1e-14         # the precondition, asserted
    ser = solve!(eng, (0.0, 10.0); perturbations = [3.0 => TripLine(:B2, :B3)])
    @test n_events(eng) == 1
    for ch in keys(ser)
        ch === :t && continue
        v = ser[ch]
        @test all(x -> x == v[1], v)                      # `==`, across the event
    end

    # THE FIXTURE CANNOT DISCRIMINATE ON ITS OWN, and saying so is the point: a
    # re-initialisation that did nothing at all would also come out flat here. What
    # it proves is that no artefact is INJECTED. The positive control below is the
    # other half — the same trip on a ring that is actually carrying power moves the
    # states by 0.29 rad, so the event is reaching the system.
    eng2 = init!(DetailedEngine, governed_ring(); dt = 0.05,
                 reltol = 1e-8, abstol = 1e-10, maxiters = 10_000_000)
    @test maximum(abs, branch_power(eng2)) > 0.1
    s2 = solve!(eng2, (0.0, 10.0); perturbations = [3.0 => TripLine(:B2, :B3)])
    @test maximum(abs, s2.δ_G2 .- s2.δ_G2[1]) > 0.1
end

@testset "branch_power reads one quantity on both tiers" begin
    # `K·sin(δ_from − δ_to)` and `Re(V·conj(I))` are the same physical quantity, and
    # the criterion below compares them across the two tiers — so they must be one
    # function and not two call sites.
    net = three_machine_ring()
    sw = SwingEngine(net)
    @test branch_power(sw, :B1, :B2) ≈ -branch_power(sw, :B2, :B1) atol = 1e-15
    ba = branch_arrays(net)
    s = current_state(sw)
    @test branch_power(sw, :B1, :B2) ≈
          ba.K[1] * sin(s.δ[ba.src[1]] - s.δ[ba.dst[1]]) atol = 1e-12
    # Kirchhoff at a bus with one machine and no load: everything the machine
    # injects leaves on the incident branches.
    @test branch_power(sw, :B1, :B2) + branch_power(sw, :B1, :B3) ≈
          machine_arrays(net).Pm[1] atol = 1e-9

    de = init!(DetailedEngine, net)
    @test branch_power(de, :B1, :B2) ≈ -branch_power(de, :B2, :B1) atol = 1e-15
    @test branch_power(de, :B1, :B2) + branch_power(de, :B1, :B3) ≈
          machine_arrays(net).Pm[1] atol = 1e-9
    # The two tiers agree on this quantity where they agree at all — the detailed
    # tier at the frozen-flux degeneration is the classical machine behind X′d, so
    # the flows differ by the reactance the classical tier folds away, not by a
    # convention.
    @test sign(branch_power(de, :B1, :B2)) == sign(branch_power(sw, :B1, :B2))

    # THE SERIES, and its refusal. Reading it needs the bus voltage ANGLES, which
    # `state_series` does not carry — that is why it exists at all.
    solve!(de, (0.0, 1.0); saveat = 0.1)
    ps = branch_power_series(de, :B1, :B2)
    @test length(ps.t) == length(ps.P) >= 11
    @test ps.P[end] ≈ branch_power(de, :B1, :B2) rtol = 1e-6
    de2 = init!(DetailedEngine, net)
    inject!(de2, TripLine(:B2, :B3))
    @test occursin("was affected by a trip_line", argerr_msg(() ->
        branch_power_series(de2, :B2, :B3)))
end

@testset "TWO MODELS, and the difference is exactly the tier boundary" begin
    # The plan asked for one model handed to both engines. It is NOT available, and
    # the reason is a guard M5 added on purpose: `SwingEngine` refuses detailed
    # machine data (`_assert_frozen_flux`) and a regulator (`_assert_no_regulator`),
    # because a classical engine handed a real `Xd` would silently run a machine its
    # own data does not describe.
    #
    # What holds instead is stronger, and it is what makes the criterion a
    # comparison of TIERS: the two models agree bit for bit in every quantity the
    # classical tier reads, and differ in exactly the set it refuses.
    IB = IberiaTwoArea
    plain = IB.two_area_model()
    det   = IB.two_area_model(; detailed = IB.DETAILED_FULL)
    mp, md = machine_arrays(plain), machine_arrays(det)
    for f in (:bus, :H, :D, :Xd′, :E, :Pm, :invR, :headroom, :Tg)
        @test getfield(mp, f) == getfield(md, f)          # `==`, not `≈`
    end
    @test branch_arrays(plain).X == branch_arrays(det).X
    @test branch_arrays(plain).K == branch_arrays(det).K
    # …and the fields that differ are the refused ones, all of them.
    for f in (:Xd, :Xq, :Xq′, :Td0′, :Tq0′, :K_A, :T_E, :Efd_max)
        @test getfield(mp, f) != getfield(md, f)
    end
    @test occursin("voltage regulator", argerr_msg(() -> init!(SwingEngine, det)))
    # The machine half is refused on its own too, with the regulator left off — so
    # the refusal is not only about `K_A`.
    mach_only = IB.two_area_model(; detailed = IB.MACH_DETAILED)
    @test occursin("Xd", argerr_msg(() -> init!(SwingEngine, mach_only)))

    # And the empty NamedTuple really is the classical machine: the DEFAULT model is
    # what it always was, so section 4's published numbers are untouched.
    @test IB.two_area_model(; detailed = NamedTuple()).machines ==
          IB.two_area_model().machines
end

@testset "THE CRITERION: the detailed tier passes it and the frozen-flux control fails" begin
    # The measurement M5 exists for (m5-plan.md §Goal). Coarse scan for the
    # boundary, as V7e uses: this is a claim about an ordering of tiers, and
    # resolving the boundary five times finer costs suite time and buys nothing.
    IB = IberiaTwoArea
    scan = 2_500.0:500.0:9_000.0
    b = IB.slip_boundary(; scan = scan)
    @test b.monotone && !b.saturated
    P = b.boundary

    # --- the classical tier at its own boundary: it slips, and its export is
    #     bounded by P_max because E′ is a constant of the model at both ends.
    cl = IB.classical_cell(; P_max_mw = P)
    @test cl.slipped
    @test cl.over <= 1.0 + 1e-9
    @test cl.over > 0.99                       # …and the bound is ATTAINED, not slack

    # --- the anti-vacuity control, and it is the sharp one. Freeze the flux and the
    #     same engine on the same topology has a DERIVED ceiling,
    #     |E′₁||E′₂| / (X_tie + X′d₁ + X′d₂), because each machine is again a
    #     constant source behind one reactance. The criterion must FAIL.
    fr = IB.detailed_cell(; P_max_mw = P, detailed = NamedTuple())
    @test fr.slipped                            # the first half still holds…
    @test !fr.exceeds                           # …and the second one does not
    @test fr.over < 0.98                        # measured 0.961
    # The ceiling is a PREDICTION, met to a part in a million at this tolerance —
    # not a tolerance fitted after the fact.
    @test fr.peak_export ≈ fr.ceiling_mw rtol = 1e-5
    @test fr.ceiling_mw < P                     # strictly tighter than P_max itself

    # --- the flux alone moves the answer the WRONG way, which nothing predicted.
    fl = IB.detailed_cell(; P_max_mw = P, detailed = IB.MACH_DETAILED)
    @test fl.slipped && !fl.exceeds
    @test fl.over < fr.over                     # worse than frozen, not better
    @test fl.V_min < 0.9                        # because the voltage actually falls

    # --- and the criterion itself.
    av = IB.detailed_cell(; P_max_mw = P, detailed = IB.DETAILED_FULL)
    @test av.slipped                            # half one, checked separately…
    @test av.exceeds                            # …and half two
    @test av.over > 1.02
    @test av.peak_export > av.ceiling_mw        # it passes the frozen bound too
    @test av.V_max > 1.0                        # the mechanism: the voltage RISES
    @test av.E′q_peak > av.E′q_0 * 1.03         # …because the field flux is driven up

    # THE TWO HALVES ARE CHECKED SEPARATELY, so "slips but does not swing" and
    # "swings but does not slip" are distinguishable from a pass. The frozen control
    # above is exactly the first of those, which is why it is not merely a failure.
    @test fr.slipped && !fr.exceeds
    @test av.slipped && av.exceeds

    # AT A TIGHTER TOLERANCE, because a margin of 3 % quoted at reltol 1e-3 is not a
    # result until the tolerance moves. `reltol = 1e-7` is NOT used and the reason
    # is measured, not omitted: the regulated cells do not complete there, because a
    # hard field ceiling is a discontinuous right-hand side (M5 step 5's finding).
    av5 = IB.detailed_cell(; P_max_mw = P, detailed = IB.DETAILED_FULL,
                            reltol = 1e-3, abstol = 1e-6)
    @test av5.exceeds && av5.slipped
    @test abs(av5.over - av.over) < 0.01
end

end # M5 step 7
