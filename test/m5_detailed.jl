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

    # a ZIP share this step does not solve is refused rather than ignored
    zip_net = NetworkModel(100.0, 50.0, net.buses, net.branches, net.machines,
                           [Load(:L3, :B3, 110.0, 30.0, 0.5, 0.5, 0.0)])
    @test occursin("constant-impedance term only",
                   argerr_msg(() -> init!(DetailedEngine, zip_net)))
    @test occursin("step 6", argerr_msg(() -> init!(DetailedEngine, zip_net)))

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
    for (name, net) in (("two_machine", two_machine_system()),
                        ("three_ring",  three_machine_ring()),
                        ("load_bus",    load_bus_system()))
        for (rtol, atol) in ((1e-3, 1e-6), (1e-8, 1e-11))
            eng = init!(DetailedEngine, net; reltol = rtol, abstol = atol)
            ser = solve!(eng, (0.0, 10.0); saveat = 0.05)
            @test length(ser.t) > 100
            for ch in keys(ser)
                ch === :t && continue
                v = getproperty(ser, ch)
                drift = maximum(abs, v .- v[1])
                # 1e-10 is far below every measured value (worst seen: 1.6e-14)
                # and far above machine precision, so it is a real gate rather
                # than either a rubber stamp or a flake.
                @test drift < 1e-10
            end
        end
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
    @test length(eng.integrator.u) == 2 * nb + 3 * length(eng.ids)
    @test length(eng.integrator.u) < nb^2 + 2 * nb          # never a dense block
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
