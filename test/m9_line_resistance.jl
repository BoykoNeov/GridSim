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
