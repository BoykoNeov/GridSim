# ─────────────────────────────────────────────────────────────────────────────
# M9 step 1 — line resistance in the detailed tier (m9-context.md D0, Hurdle 17)
#
# The edge current is (Vf − Vt)/(R + jX). Nothing here is a band fitted to a gap: the
# flat run is a residual, and the two dynamic checks are identities in the losses —
# each side of each one read from its own solution. The fixtures are the two grids
# the outage screen reports on (`scripts/outage_screen.jl`), both lossy, which the
# tier refused outright through M8.
#
# The gate that NOTHING LOSSLESS MOVED is not in this file: it is four captures at
# full precision (M5's criterion values, the 83-case AC digest, the M8 screen outputs,
# step 0's lossless dip table), compared byte for byte before and after
# (m9-tasks.md step 1). A test with a tolerance cannot state "bit-identical".
# ─────────────────────────────────────────────────────────────────────────────

const _OSR = OutageScreenScript
const _FBDF = OrdinaryDiffEq.FBDF

# The network's losses right now, read the only way that sees them: each branch at BOTH
# of its terminals, `branch_power(a, b) + branch_power(b, a)`.
_r_losses(eng) = sum(branch_power(eng, b.from, b.to) + branch_power(eng, b.to, b.from)
                     for b in eng.model.branches)

_r_fixtures() = [("$nm $ld", f(; loads = ld))
                 for (nm, f) in (("case9", _OSR.case9), ("mesh", _OSR.mesh))
                 for ld in (:constant_power, :default)]

@testset "M9 step 1 — line resistance in the detailed tier" begin

@testset "the fixtures are lossy, so every check below has R to read" begin
    for (name, net) in _r_fixtures()
        @test any(b -> b.R > 0, net.branches)
        @test sum(ac_powerflow(net).loss) > 1e-3        # pu: losses a check can see
    end
end

@testset "each end read at its own terminal: the two ends sum to the AC loss" begin
    # At the seed the tier's bus voltages ARE the AC solution's, so each branch's two
    # end powers must sum to the loss `ac_powerflow` computed from the same voltages —
    # with a separately written admittance (`_ac_branch_flows`). The sending end must
    # match `flow`; the receiving end is NOT the negated sending end.
    for (name, net) in _r_fixtures()
        sol = ac_powerflow(net)
        eng = init!(DetailedEngine, net; powerflow = sol)
        for (e, b) in pairs(net.branches)
            fwd, rev = branch_power(eng, b.from, b.to), branch_power(eng, b.to, b.from)
            @test fwd ≈ sol.flow[e] atol = 1e-12
            @test rev ≈ sol.flow_rev[e] atol = 1e-12
            @test fwd + rev ≈ sol.loss[e] atol = 1e-12
        end
        # …and the anti-vacuity half: on these fixtures the loss is not zero, so a
        # read-out that negated the sending end would fail the line above.
        @test maximum(sol.loss) > 1e-3
        # The vector form is model order, sending end, as before.
        @test branch_power(eng) ≈ sol.flow atol = 1e-12
    end
end

@testset "the seeded run is flat on a lossy grid, per state, at two tolerances" begin
    # Hurdle 17.2 — M6 step 4's oracle A carried to a lossy network. `init!` already
    # refuses a seed that is not a fixpoint of the DYNAMIC network's equations; this is
    # the run that follows, held to M6's 1e-10 per state.
    for (name, net) in _r_fixtures()
        sol = ac_powerflow(net)
        for (rtol, atol) in ((1e-3, 1e-6), (1e-8, 1e-11))
            eng = init!(DetailedEngine, net; powerflow = sol, reltol = rtol, abstol = atol)
            ser = solve!(eng, (0.0, 50.0); saveat = 0.05)
            worst, chan = _worst_drift(ser)
            @test worst < 1e-10
            worst < 1e-10 || @info "lossy seeded flat run drifted" name rtol worst chan
        end
    end
end

@testset "the tier's own steady state builds on a lossy grid, and is flat" begin
    # The fixpoint path (`powerflow = nothing`) solves the STATIC network, a second
    # compiled copy of the same edges; a resistance written into one network and not
    # the other is what this path exists to catch (the seeded path never solves the
    # static network until an event).
    #
    # THE MESH ONLY, measured rather than chosen. This path holds each machine's
    # internal voltage at `Machine.E′`, not at `V_set`, and case9's machines carry
    # E′ = 1.0: lossless case9 on constant-power loads is refused here already (B5 at
    # 0.893 pu, outside the band), and the lossy copy on default loads sags B9 to
    # 0.889 pu where the lossless one passes — a real voltage effect of the
    # resistance, on a path the screen does not use.
    for (name, net) in _r_fixtures()
        startswith(name, "mesh") || continue
        eng = init!(DetailedEngine, net)
        @test _r_losses(eng) > 1e-3
        ser = solve!(eng, (0.0, 20.0); saveat = 0.05)
        worst, chan = _worst_drift(ser)
        @test worst < 1e-10
    end
end

@testset "t⁺: the initial rate of fall accounts for the change in losses EXACTLY" begin
    # Hurdle 17.3. On constant-power loads, at the instant after a trip,
    #     Σ 2H·ω̇ = ΣPm_left − ΣPe_left(t⁺) = −(P_lost + L(t⁺) − L(t⁻)),
    # every term read from the network: ω̇ from the right-hand side at the
    # re-initialised state (`coi_rocof`), the losses from both ends of every branch.
    # The trip is at t0, so t⁻ is the seed itself and `P_lost` is the lost machine's
    # dispatched power exactly.
    nchecked, refused_at_trip = 0, Symbol[]
    for name in ("case9 constant_power", "mesh constant_power")
        net = Dict(_r_fixtures())[name]
        sol = ac_powerflow(net)
        ma = machine_arrays(net)
        for (k, m) in pairs(net.machines)
            eng = init!(DetailedEngine, net; powerflow = sol, reltol = 1e-8, abstol = 1e-10,
                        solver = _FBDF())
            P_lost = eng.params[eng.Pm_pidx[k]]
            L⁻ = _r_losses(eng)
            # ONLY the voltage band is a refusal here (D0 16.6). The first version of
            # this catch took any re-initialisation error, and so swallowed the dynamic
            # Kirchhoff check's own throw when `R` reached one network and not the other
            # (sabotage S4) — that went red only through the count below.
            refused = try
                inject!(eng, TripGenerator(m.id)); false
            catch err
                err isa ErrorException && occursin("re-initialisation", err.msg) &&
                    occursin("outside [0.9, 1.1]", err.msg) || rethrow()
                true
            end
            refused && (push!(refused_at_trip, Symbol(first(split(name)), "_", m.id)); continue)
            ΔL = _r_losses(eng) - L⁻
            H = sum(ma.H[j] for j in eachindex(net.machines) if j != k)
            imbalance = coi_rocof(eng) * 2H / net.f0
            @test imbalance ≈ -(P_lost + ΔL) rtol = 1e-8
            # Anti-vacuity: the losses term is what closes it — without it, the same
            # comparison fails by orders of magnitude more than the tolerance.
            @test abs(imbalance + P_lost) > 1e3 * 1e-8 * abs(imbalance)
            nchecked += 1
        end
    end
    @test nchecked == 4         # case9 G3, mesh G1–G3: exercised, not skipped
    @test refused_at_trip == [:case9_G1, :case9_G2]     # step 0's set, on the lossy grid
end

@testset "settled: the dynamic run and the AC screen differ by the losses, and only by them" begin
    # Hurdle 17.4, an identity rather than a band. With every governor uncapped on
    # constant-power loads, both sides balance the lost power against droop and
    # damping (Σw), and the only thing they hold differently is the voltage — the
    # tier holds field flux, the screen holds V_set — which moves the losses:
    #     Δω_dyn − Δω_AC = −(L_dyn − L_AC)/Σw,
    # each side's post-outage losses read from its own solution.
    # The only two such outages on the report grids: case9's G1 and G2 are refused at
    # the trip (D0 16.6), the mesh's G1 caps both governors and its G2 caps G3's 5 MW
    # of headroom.
    cases = (("case9 constant_power", :G3), ("mesh constant_power", :G3))
    for (name, id) in cases
        net = Dict(_r_fixtures())[name]
        sol = ac_powerflow(net)
        acg = ac_generator_outages(net)
        k = findfirst(m -> m.id === id, net.machines)
        @test acg.outcome[k] === :secure && !any(acg.capped[k])     # the precondition
        ma = machine_arrays(net)
        Σw = sum(ma.invR[j] + ma.D[j] for j in eachindex(net.machines) if j != k)
        eng = init!(DetailedEngine, net; powerflow = sol, reltol = 1e-10, abstol = 1e-12,
                    solver = _FBDF())
        # 400 s: what decides the residual is how settled the run is, not the solver
        # (measured on case9 G3: 5e-9 at 100 s, 4e-12 at 200 s, 4e-14 at 400 s,
        # against a gap of 3.0e-5).
        ser = solve!(eng, (0.0, 400.0); perturbations = [1.0 => TripGenerator(id)],
                     saveat = 0.5)
        Δω_dyn = ser.f_coi[end] / net.f0 - 1
        lhs = Δω_dyn - acg.Δω[k]
        rhs = -(_r_losses(eng) - sum(acg.solution[k].loss)) / Σw
        @test lhs ≈ rhs rtol = 1e-6
        # Anti-vacuity: the two sides really differ (this is not 0 ≈ 0), by more than
        # the identity's residual by orders of magnitude.
        @test abs(lhs) > 1e3 * abs(lhs - rhs)
    end
end

end

# ─────────────────────────────────────────────────────────────────────────────
# M9 step 2 — line resistance in the classical (swing) tier (Hurdle 17.6)
#
# The coupling gains its conductance, and the model's reference bus picks up the
# losses (the detailed tier's own rule — without it a lossy grid has no steady state
# at all, since the schedule sums to zero). As in step 1, the gate that NOTHING
# LOSSLESS MOVED is five full-precision captures compared byte for byte, not a test.
#
# Which check sees what (m9-context.md D6): the dispatch and the swing-against-DC
# identity read the losses through the engine's own edge code, so a wrong edge
# equation passes them. The independent end-power formula and the detailed tier at
# the frozen-flux degeneration are the two that see the equation itself.
# ─────────────────────────────────────────────────────────────────────────────

# A copy of `net` with every branch given `R = f·X`.
_r_with_R(net::NetworkModel, f::Real) = NetworkModel(net.S_base, net.f0, net.buses,
    [Branch(b.id, b.from, b.to, b.X, b.rating; R = f * b.X) for b in net.branches],
    net.machines, net.loads; slack = net.slack, inverters = net.inverters)

# A radial pair whose one branch is written AGAINST the graph's order (B2 → B1, where
# the graph holds 1 → 2), with unequal E′ — so a self term put on the wrong end moves
# a number. Machines rated away from S_base; X′d small enough to reduce.
_r_pair(; R = 0.04, slack = :B1) = NetworkModel(100.0, 50.0,
    [Bus(:B1, 230.0), Bus(:B2, 230.0)],
    [Branch(:L21, :B2, :B1, 0.25, 500.0; R)],
    [Machine(:G1, :B1, 200.0, 4.0, 2.0, 0.10, 1.05, 60.0),
     Machine(:G2, :B2, 100.0, 3.0, 1.5, 0.075, 0.98, -60.0)]; slack)

# Power INTO a branch at end `a`, written from the phasors and nothing else:
# `Re(Va · conj((Va − Vb)/(R + jX)))`. Shares no code with the engine.
_r_end(Ea, δa, Eb, δb, R, X) =
    (Va = Ea * cis(δa); Vb = Eb * cis(δb); real(Va * conj((Va - Vb) / complex(R, X))))

_r_swing_fixtures() = [("pair", _r_pair()), ("pair, B2 the reference", _r_pair(slack = :B2)),
                       ("ring", _r_with_R(ratio_ring(D1 = 1.0), 0.3)),
                       ("mesh", _r_with_R(_m8_genmesh(), 0.3)),
                       ("mesh with an inverter", _r_with_R(_m8_genmesh(gfm = true), 0.3))]

@testset "M9 step 2 — line resistance in the swing tier" begin

@testset "the reference bus picks up the losses; every other source holds its schedule" begin
    for (name, net) in _r_swing_fixtures()
        eng = SwingEngine(net; reltol = 1e-10, abstol = 1e-12)
        L = _r_losses(eng)
        @test L > 1e-4                                   # pu: losses a check can see
        sched = GridSim._swing_vertices(net).Pm
        Pm = eng.params[eng.Pm_pidx]
        vref = net.bus_index[net.slack]
        @test all(Pm[v] == sched[v] for v in eachindex(Pm) if v != vref)
        @test Pm[vref] - sched[vref] ≈ L atol = 1e-12
        @test sum(Pm) ≈ L atol = 1e-12
    end
end

@testset "each end at its own terminal, against a formula that shares no code" begin
    for (name, net) in _r_swing_fixtures()[1:3]        # machine-only: E is E′
        eng = SwingEngine(net; reltol = 1e-10, abstol = 1e-12)
        E, δ = machine_arrays(net).E, current_state(eng).δ
        for b in net.branches
            i, j = net.bus_index[b.from], net.bus_index[b.to]
            Pf, Pt = branch_power(eng, b.from, b.to), branch_power(eng, b.to, b.from)
            @test Pf ≈ _r_end(E[i], δ[i], E[j], δ[j], b.R, b.X) atol = 1e-13
            @test Pt ≈ _r_end(E[j], δ[j], E[i], δ[i], b.R, b.X) atol = 1e-13
            @test Pf + Pt > 1e-6                         # not antisymmetric any more
        end
    end
    # The fixtures can see an end swapped: a branch written against the graph's
    # order, between unequal voltages.
    pair = _r_pair()
    @test pair.bus_index[pair.branches[1].from] > pair.bus_index[pair.branches[1].to]
    @test machine_arrays(pair).E[1] != machine_arrays(pair).E[2]
end

@testset "flat on a lossy grid: an exact start, and drift that is the integrator's" begin
    # The start is checked as a RESIDUAL, at machine precision. The run's drift is not
    # gated at step 1's 1e-10: this tier integrates with an explicit Runge–Kutta, and
    # its lossless twin drifts just as much — measured (`probe_flat.jl`, 50 s): ring
    # 2.0e-6 lossless / 3.2e-7 lossy at reltol 1e-6, mesh 6.4e-7 / 6.6e-7, all in an
    # absolute angle; ~3e-10 for both at 1e-10. So what is asserted is what tells a
    # wrong start from solver noise: the drift falls with the tolerance.
    for (name, net) in _r_swing_fixtures()
        drift = map(((1e-6, 1e-9), (1e-10, 1e-12))) do (rt, at)
            eng = SwingEngine(net; reltol = rt, abstol = at)
            u = eng.integrator.u
            du = similar(u)
            eng.nw(du, u, eng.integrator.p, eng.integrator.t)
            @test maximum(abs, du) < 1e-13
            first(_worst_drift(solve!(eng, (0.0, 50.0); saveat = 0.5)))
        end
        @test drift[2] < 1e-8
        @test drift[2] <= drift[1] / 100        # (the pair is flat to the bit: 0 ≤ 0)
    end
end

@testset "the playback series reads the end it is asked for" begin
    # Found writing the lossy read: on a lossless model `branch_power_series` returned
    # the branch's own direction whatever order it was asked in (the gate capture
    # printed (:B2, :B1) equal to (:B1, :B2)). Every caller named the stored order, so
    # nothing moved; the sign now follows the caller, as `branch_power`'s does.
    eng = SwingEngine(two_machine_system(); reltol = 1e-9, abstol = 1e-12)
    eng.params[eng.Pm_pidx[1]] += 0.05
    solve!(eng, (0.0, 2.0); saveat = 0.1)
    a, b = branch_power_series(eng, :B1, :B2).P, branch_power_series(eng, :B2, :B1).P
    @test b == -a
    @test maximum(abs, a .- a[1]) > 1e-3                 # the flow really moved
    # Lossy: each end at its own terminal, sample by sample, and the last sample is
    # what `branch_power` reads at the same instant.
    lp = SwingEngine(_r_pair(); reltol = 1e-9, abstol = 1e-12)
    lp.params[lp.Pm_pidx[2]] += 0.05
    solve!(lp, (0.0, 2.0); saveat = 0.1)
    f, t = branch_power_series(lp, :B2, :B1).P, branch_power_series(lp, :B1, :B2).P
    @test all(f .+ t .> 1e-6)
    @test f[end] ≈ branch_power(lp, :B2, :B1) atol = 1e-14
    @test t[end] ≈ branch_power(lp, :B1, :B2) atol = 1e-14
end

@testset "a trip leaves nothing on a dead branch, at either end" begin
    net = _r_with_R(_m8_genmesh(), 0.3)
    eng = SwingEngine(net)
    inject!(eng, TripLine(:B, :C))
    @test branch_power(eng, :B, :C) == 0.0 && branch_power(eng, :C, :B) == 0.0
    inject!(eng, TripGenerator(:G2))                     # bus C: AC, CD (BC already out)
    for (a, b) in ((:A, :C), (:C, :D))
        @test branch_power(eng, a, b) == 0.0 && branch_power(eng, b, a) == 0.0
    end
    # …and the branches left in service still carry their losses.
    @test branch_power(eng, :A, :B) + branch_power(eng, :B, :A) > 1e-6
end

@testset "the cross-tier oracle: the detailed tier at the frozen-flux degeneration, lossy" begin
    for slack in (:B1, :B2)
        net = _r_pair(; slack)
        red = terminal_bus_reduced(net)
        @test red.branches[1].R == net.branches[1].R     # the reduction keeps R
        @test red.slack === net.slack
        # THE SAME DISPATCH FIRST (M5's rule): on a lossy grid both tiers' reference
        # machine absorbs the losses, and the two must agree on how much before any
        # trajectory is compared — or the comparison reads a dispatch gap as physics.
        let sw = init!(SwingEngine, net), de = init!(DetailedEngine, red)
            for k in 1:2
                @test de.params[de.Pm_pidx[k]] ≈ sw.params[sw.Pm_pidx[k]] atol = 1e-12
            end
            vref = net.bus_index[slack]
            @test sw.params[sw.Pm_pidx[vref]] - machine_arrays(net).Pm[vref] > 1e-4
        end
        for (rtol, atol) in ((1.0e-4, 1.0e-7), (1.0e-7, 1.0e-10))
            sw, de   = tier_pair(net, red; reltol = rtol,        abstol = atol)
            swf, def = tier_pair(net, red; reltol = rtol / 1000,  abstol = atol / 1000)
            @test sw.t == de.t
            for (name, ch) in TIER_CHANNELS
                band = convergence_band(sw, swf, de, def; channel = ch)
                @test band > 0
                d = divergence(sw, de; band = band, channel = ch)
                @test d.max < band
                @test isnan(d.t_depart)
            end
            @test maximum(abs, sw.f_coi .- sw.f_coi[1]) > 0.05
        end
    end
end

@testset "swing against DC on a lossy grid: the losses, and nothing else" begin
    # At R = 0 the swing tier is the DC screen's exact oracle (M8 step 4). With losses
    # it cannot be — the DC screen has none — and the gap is exact, every governor
    # uncapped: survivors balance `Σ Pm_surv − L_post = Σw·ω`, the pre-outage dispatch
    # balances `Σ Pm = L_pre`, so
    #     ω_swing − Δω_DC = (L_pre − L_post − [reference lost]·L_pre)/Σw,
    # the last term because a lost reference machine takes the losses it carried.
    cases = ((_r_with_R(_m8_genmesh(), 0.3), :G3), (_r_with_R(_m8_genmesh(), 0.3), :LB),
             (_r_with_R(_m8_genmesh(slack = :E), 0.3), :G3))
    for (net, lost) in cases
        dc = pickup_shares(net, lost)
        @test !any(dc.capped)                            # the precondition
        k = findfirst(m -> m.id === lost, net.machines)
        ma = machine_arrays(net)
        Σw = sum(ma.invR[j] + ma.D[j] for j in eachindex(net.machines) if j != k)
        eng = SwingEngine(net; reltol = 1e-10, abstol = 1e-12, dt = 0.05)
        L_pre = _r_losses(eng)
        while eng.integrator.t < 1.0 - 1e-9; step!(eng, 0.05); end
        inject!(eng, TripGenerator(lost))
        while eng.integrator.t < 200.0 - 1e-9; step!(eng, 0.05); end
        st = current_state(eng)
        # Every surviving GOVERNOR uncapped (a governor-free machine's headroom is 0 by
        # construction and its ΔPm stays 0, so it is not a cap).
        @test all(st.ΔPm[j] < ma.headroom[j] for j in eachindex(net.machines)
                  if j != k && ma.invR[j] > 0)
        ref_lost = ma.bus[k] == net.bus_index[net.slack]
        lhs = st.ω_coi - dc.Δω
        rhs = (L_pre - _r_losses(eng) - (ref_lost ? L_pre : 0.0)) / Σw
        @test lhs ≈ rhs rtol = 1e-6
        @test abs(lhs) > 1e3 * abs(lhs - rhs)
    end
end

@testset "the reach guard reads the conductance on a lossy grid" begin
    # E = 1 at both ends, X = 0.1, R = 0.05: |y| = 8.94, g = 4. The lossless bound
    # passes any |P| ≤ 10; the lossy one bounds an ABSORBER at 4 − 8.94 = −4.94 pu.
    two(R) = NetworkModel(100.0, 50.0, [Bus(:A, 230.0), Bus(:B, 230.0)],
                          [Branch(:AB, :A, :B, 0.1, 5000.0; R)],
                          [Machine(:G1, :A, 1000.0, 5.0, 1.0, 0.25, 1.0, 600.0),
                           Machine(:G2, :B, 1000.0, 5.0, 1.0, 0.25, 1.0, -600.0)])
    @test SwingEngine(two(0.0)) isa SwingEngine
    msg = argerr_msg(() -> SwingEngine(two(0.05)))
    @test occursin("G2", msg) && occursin("no steady state exists", msg)
    # The bound is necessary, not sufficient: two exporters inside their own bounds
    # (≤ 25.9 pu each) that the shared ring cannot carry at once. The static solve
    # finds no steady state, and the refusal says why in this tier's words rather
    # than the solver library's.
    ring = NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C)],
                        [Branch(:AB, :A, :B, 0.1, 9000.0; R = 0.05),
                         Branch(:BC, :B, :C, 0.1, 9000.0; R = 0.05),
                         Branch(:CA, :C, :A, 0.1, 9000.0; R = 0.05)],
                        [Machine(:GA, :A, 1000.0, 5.0, 1.0, 0.25, 1.0, -4000.0),
                         Machine(:GB, :B, 1000.0, 5.0, 1.0, 0.25, 1.0, 2000.0),
                         Machine(:GC, :C, 1000.0, 5.0, 1.0, 0.25, 1.0, 2000.0)])
    msg = argerr_msg(() -> SwingEngine(ring))
    @test occursin("no steady state", msg) && occursin("reference bus", msg)
end

@testset "a grid-forming inverter is not a lossy grid's reference" begin
    lossy = _r_with_R(_m8_genmesh(gfm = true, slack = :E), 0.3)
    msg = argerr_msg(() -> SwingEngine(lossy))
    @test occursin("grid-forming", msg) && occursin("reference", msg)
    @test SwingEngine(_m8_genmesh(gfm = true, slack = :E)) isa SwingEngine   # lossless: as before
end

end
