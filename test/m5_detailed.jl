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
    @test length(eng.integrator.u) == 2 * nb + 5 * length(eng.ids)
    # THE `nb²` FORM OF THIS CHECK FAILED IN STEP 2, AND IT DESERVED TO. It read
    # `length(u) < nb^2 + 2nb`, which on this 3-bus fixture became `16 < 15` the
    # moment a machine carried five states instead of three. The state count was
    # never the quantity in question: it is `2·nb + 5·nm`, LINEAR in both, and
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
@testset "the tier's state and channels grew by exactly two per machine" begin
    eng = init!(DetailedEngine, load_bus_system())
    nb = length(eng.model.buses)
    nm = length(eng.ids)
    @test length(eng.integrator.u) == 2 * nb + 5 * nm
    ser = solve!(eng, (0.0, 1.0); saveat = 0.05)
    ks = keys(ser)
    for ch in (:E′q_G1, :E′q_G2, :E′d_G1, :E′d_G2)
        @test ch in ks
    end
    st = current_state(eng)
    @test length(st.E′q) == nm && length(st.E′d) == nm
    # `Efd` is a PARAMETER at this step — the regulator is plan step 5 — and it is
    # the machine's initial `E′q` exactly, because `Xd − X′d = 0` here.
    @test all(eng.params[eng.Efd_pidx[k]] ≈ st.E′q[k] for k in 1:nm)
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
    @test eng.params[eng.Efd_pidx[1]] ≈ st.E′q[1] + (ma.Xd[1] - ma.Xd′[1]) * Id atol = 1.0e-12
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
                 Tq0′ = 10.0 * m.Tq0′, Ra = m.Ra) for m in net.machines])
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
