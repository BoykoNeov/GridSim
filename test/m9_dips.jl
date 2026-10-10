# ─────────────────────────────────────────────────────────────────────────────
# M9 step 5 — the dip (m9-context.md D0 Hurdles 16.2–16.6, D9)
#
# One detailed-tier run per generator outage, at two frozen tolerances, the fine one
# deciding when to stop. The gate (nothing old moved) is the five captures compared
# byte for byte (m9-tasks.md step 5), not a test here.
#
# Every number pinned below rests on algebra or on an earlier run of a different code
# path (step 0's one-shot spike, `dips-HEAD.txt`), never on a fixture's verdict: the
# dynamics are invented (`outage_screen.jl` says so).
# ─────────────────────────────────────────────────────────────────────────────

const _OSD = OutageScreenScript

_d_lossless(n) = NetworkModel(n.S_base, n.f0, n.buses,
                              [Branch(b.id, b.from, b.to, b.X, b.rating) for b in n.branches],
                              n.machines, n.loads; slack = n.slack)
_d_scaleR(n, f) = NetworkModel(n.S_base, n.f0, n.buses,
                               [Branch(b.id, b.from, b.to, b.X, b.rating; R = f * b.R)
                                for b in n.branches], n.machines, n.loads; slack = n.slack)

# The runs every testset below reads, built once: the two report grids, both load models,
# lossy (the grids themselves) and lossless (step 0's copies).
const _D_RUNS = Dict{Tuple{Symbol,Symbol,Symbol},Any}()
for grid in (:lossy, :lossless), (name, build) in ((:case9, _OSD.case9), (:mesh, _OSD.mesh)),
    loads in (:constant_power, :default)
    n0 = build(; loads)
    net = grid === :lossless ? _d_lossless(n0) : n0
    ac = ac_generator_outages(net)
    _D_RUNS[(grid, name, loads)] = (; net, ac, d = generator_dips(net, ac))
end

@testset "M9 step 5 — the dip" begin

@testset "step 0's lossless table, reproduced from the new code" begin
    # Step 0's spike (`docs/evidence/gridsim-m9/step0_dips.jl`, captured at full precision
    # in `dips_snapshot.jl`): one-shot `solve!`, FBDF 1e-8, 150 s. Our runs are chunked
    # and stop on their own settling, so the band is the stopping rule's own promise —
    # `_DIP_SHORTFALL`, 1e-5 Hz — stated before the comparison (step5/predictions.md).
    # (coi dip, settled, worst machine and its value), step 0's `repr` values.
    ref = Dict(
        (:case9, :constant_power, :G3) => (-0.740886580950793, -0.4490022170796948, :G2, -0.7443507870549987),
        (:case9, :default, :G2) => (-0.6557459277036557, -0.3973781108512, :G1, -0.6575351129031581),
        (:case9, :default, :G3) => (-0.5810888636594882, -0.35219083203555357, :G2, -0.582645673651455),
        (:mesh, :constant_power, :G1) => (-10.93749987992598, -10.937499879101765, :G3, -10.937609724388404),
        (:mesh, :constant_power, :G2) => (-0.5102767840562308, -0.4243827149754438, :G3, -0.5498444130164337),
        (:mesh, :constant_power, :G3) => (-0.25451489305137187, -0.1932367145789584, :G2, -0.2631786790292879),
        (:mesh, :default, :G1) => (-8.668895957319286, -8.668895646266002, :G3, -8.669059307914308),
        (:mesh, :default, :G3) => (-0.16718267816735732, -0.12709096965416933, :G2, -0.17403070830641598))
    for ((name, loads, id), (coi, settled, wid, worst)) in ref
        r = _D_RUNS[(:lossless, name, loads)]
        k = findfirst(==(id), r.d.machines)
        @test r.d.outcome[k] === :measured
        @test r.d.Δf_coi[k] ≈ coi atol = 1e-5
        @test r.d.Δf_end[k] ≈ settled atol = 1e-5
        @test r.d.worst[k] === wid
        @test r.d.Δf_worst[k] ≈ worst atol = 1e-5
    end
    # Step 0 could not judge mesh-default G2 at 1e-8 (one-shot `Unstable` at 5.6 s); its
    # three other settings agreed on −0.391 Hz, and so do both of ours (D9 finding 1).
    r = _D_RUNS[(:lossless, :mesh, :default)]
    @test r.d.outcome[2] === :measured
    @test round(r.d.Δf_coi[2]; digits = 3) == -0.391 == round(r.d.Δf_coi_coarse[2]; digits = 3)
end

@testset "the stopping rule leaves at most its shortfall on the slowest case" begin
    # Lossless, constant power, losing the mesh's G1: both governors cap and the 105 MW
    # they cannot pick up is left to damping alone — the case where the dip is the
    # settled value and stopping early is a false pass. Lossless on constant power the
    # pickup is the lost power whatever the voltages (D0 17.4), so the DC screen's
    # settled value (exact, M8 step 4) is this run's settled value too.
    r = _D_RUNS[(:lossless, :mesh, :constant_power)]
    ma = machine_arrays(r.net)
    exact = dc_generator_outages(r.net).Δω[1] * 50.0
    @test exact ≈ -10.9375 rtol = 1e-12
    @test abs(r.d.Δf_end[1] - exact) <= GridSim._DIP_SHORTFALL
    @test r.d.Δf_coi[1] >= exact                    # short of it, never past it
    # It stopped on the rule, inside the horizon, after at least one τ = 4.25 s of quiet.
    τ = 2 * sum(ma.H[2:3]) / sum(ma.D[2:3])
    @test τ ≈ 4.25 rtol = 1e-14
    @test r.d.t_trip + τ < r.d.t_stop[1] < r.d.t_trip + GridSim._DIP_HORIZON * τ
    # Positive control for "not reached": a horizon too short to settle reports nothing,
    # never its last sample.
    d1 = generator_dips(r.net, r.ac; horizon = 1)
    @test d1.outcome[1] === :not_reached && d1.reason[1] === :horizon
    @test isnan(d1.Δf_coi[1]) && isnan(d1.Δf_worst[1]) && isnan(d1.Δf_end[1]) &&
          d1.worst[1] === :none && all(isnan, d1.Δf_machine[1])
end

@testset "every machine judged: the worst is not the average" begin
    # The mesh's G2 loss (constant power, lossy): the worst machine (G3) dips 8 % deeper
    # than the centre of inertia — the fixture Hurdle 16.3 names.
    r = _D_RUNS[(:lossy, :mesh, :constant_power)]
    @test r.d.worst[2] === :G3
    @test abs(r.d.Δf_worst[2]) > 1.07 * abs(r.d.Δf_coi[2])
    # A limit between the two: the machines fail it, the average alone would pass.
    lim = (abs(r.d.Δf_worst[2]) + abs(r.d.Δf_coi[2])) / 2
    v = frequency_verdicts(r.net, compare_generator_screens(r.net,
                           dc_generator_outages(r.net), r.ac),
                           FrequencyLimits(; dip = lim); dips = r.d)
    @test v.dip[2] === :fail && v.Δf_dip[2] === r.d.Δf_worst[2]
    # The machine lost carries no value; every survivor does.
    @test isnan(r.d.Δf_machine[2][2]) && all(isfinite, r.d.Δf_machine[2][[1, 3]])
    @test r.d.Δf_worst[2] == minimum(r.d.Δf_machine[2][[1, 3]])
end

@testset "refused at the trip: every outage run, and the mismatch with the AC screen" begin
    # Hurdle 16.6: the tier's re-initialisation judges voltage the instant after the
    # trip, the AC screen after settling. Reported, not asserted empty: the one outage
    # the tier refuses and the AC screen calls secure, on the lossy grids and their
    # lossless copies alike, is case9-constant-power G2 (step 0 predicted it).
    for grid in (:lossy, :lossless)
        mism = Tuple{Symbol,Symbol,Symbol}[]
        refused = Tuple{Symbol,Symbol,Symbol}[]
        for name in (:case9, :mesh), loads in (:constant_power, :default)
            r = _D_RUNS[(grid, name, loads)]
            for (k, id) in enumerate(r.d.machines)
                r.d.outcome[k] === :refused_at_trip || continue
                @test r.d.reason[k] === :voltage
                push!(refused, (name, loads, id))
                r.ac.outcome[k] === :secure && push!(mism, (name, loads, id))
            end
        end
        @test sort(refused) == [(:case9, :constant_power, :G1), (:case9, :constant_power, :G2),
                                (:case9, :default, :G1)]
        @test mism == [(:case9, :constant_power, :G2)]
    end
    # A refusal is never a value.
    r = _D_RUNS[(:lossy, :case9, :constant_power)]
    @test isnan(r.d.Δf_coi[2]) && r.d.worst[2] === :none
    v = frequency_verdicts(r.net, compare_generator_screens(r.net,
                           dc_generator_outages(r.net), r.ac),
                           continental_europe_limits(); dips = r.d)
    @test v.dip[1:2] == [:refused_at_trip, :refused_at_trip] && v.dip[3] === :pass
    @test isnan(v.Δf_dip[2]) && v.settled_ac[2] !== :no_value   # the AC screen did judge it
end

@testset "a solver failure is an outcome, never a verdict (Hurdle 16.5)" begin
    # (a) A STALLED re-initialisation, from model data (step 3's reproducer, D7 finding
    # 2): case9 constant power with every R ×1.1 — losing G1 stalls the static solve,
    # and it is told apart from the voltage refusal on the next row.
    net = _d_scaleR(_OSD.case9(; loads = :constant_power), 1.1)
    d = generator_dips(net, ac_generator_outages(net))
    @test d.outcome == [:solver_failure, :refused_at_trip, :measured]
    @test d.reason == [:stalled, :voltage, :none]
    @test isnan(d.Δf_coi[1])
    # The thrower beneath it still throws the library's error, unchanged, for every
    # other caller.
    eng = init!(DetailedEngine, net; powerflow = ac_powerflow(net), reltol = 1e-8,
                abstol = 1e-10, solver = GridSim.OrdinaryDiffEq.FBDF())
    @test_throws GridSim.NetworkDynamics.NetworkInitError inject!(eng, TripGenerator(:G1))
    # (b) A FAILED INTEGRATION, read off the integrator's own retcode: the run given
    # too few steps.
    m = _OSD.mesh(; loads = :constant_power)
    st, why, e, _ = GridSim._dip_run(m, ac_powerflow(m), :G1, 1.0, 4.25, 1e-8, 1e-10;
                                     maxiters = 100)
    @test st === :failed && why === :integration
    @test !GridSim.SciMLBase.successful_retcode(e.integrator.sol.retcode)
    # ...and an error raised while the retcode still reads success is the caller's
    # mistake, rethrown, never classified as a failure.
    e2 = init!(DetailedEngine, m; powerflow = ac_powerflow(m))
    @test_throws ArgumentError GridSim._dip_solve!(e2, 5.0, 6.0)
    # The dynamic-network Kirchhoff check stays a THROW through the classifying path
    # too (a one-sided parameter write is a bug, not an outcome).
    e3 = init!(DetailedEngine, m; powerflow = ac_powerflow(m))
    e3.params[e3.mstat_pidx[2]] = 0.0
    msg = try; GridSim._trip_generator!(e3, TripGenerator(:G1)); ""; catch err; err.msg; end
    @test occursin("DYNAMIC network's Kirchhoff rows", msg)
end

@testset "the verdict counts only where both tolerances agree" begin
    r = _D_RUNS[(:lossy, :mesh, :constant_power)]
    g = compare_generator_screens(r.net, dc_generator_outages(r.net), r.ac)
    # Positive control: G1's 11.26 Hz dip fails the sourced 0.8 Hz at both; G3's passes.
    v = frequency_verdicts(r.net, g, continental_europe_limits(); dips = r.d)
    @test v.dip == [:fail, :pass, :pass]
    @test v.Δf_dip == r.d.Δf_worst
    # A limit landing exactly on the fine run's |worst|: reaching it passes (≤), and the
    # coarse run is shallower, so both pass. One ulp below, the fine run fails and the
    # coarse one does not: neither verdict is reported.
    f, c = abs(r.d.Δf_worst[1]), abs(r.d.Δf_worst_coarse[1])
    @test c < f                                   # the premise of the pair below
    judge(lim) = frequency_verdicts(r.net, g, FrequencyLimits(; dip = lim); dips = r.d).dip[1]
    @test judge(f) === :pass
    @test judge(prevfloat(f)) === :tolerance_dependent
    @test judge(prevfloat(c)) === :fail
    # Without the runs the dip is `:not_run`, exactly as step 4 left it.
    @test frequency_verdicts(r.net, g, continental_europe_limits()).dip == fill(:not_run, 3)
    # Runs of another model are refused — case9 and the mesh share machine ids G1–G3.
    other = _D_RUNS[(:lossy, :case9, :constant_power)].d
    @test_throws ArgumentError frequency_verdicts(r.net, g, continental_europe_limits();
                                                  dips = other)
    # A lossless copy has the same ids and branches: told apart by nothing here, and
    # that is stated rather than hidden — the runs are tied to the model by id and f0.
    @test _D_RUNS[(:lossless, :mesh, :constant_power)].d.branches == r.d.branches
end

@testset "the OutageScreen form: the screen's own base, and lone-source lines" begin
    net = _OSD.case9(; loads = :default)
    s = outage_screen(net)
    d = generator_dips(net, s)
    r = _D_RUNS[(:lossy, :case9, :default)]
    @test d.outcome == r.d.outcome && isequal(d.Δf_worst, r.d.Δf_worst)  # same base, same runs
    v = frequency_verdicts(net, s, continental_europe_limits(); dips = d)
    for (row, via) in enumerate(s.via)
        row <= length(net.branches) || break
        if via === :none
            @test v.dip[row] === :not_applicable && isnan(v.Δf_dip[row])
        else
            k = findfirst(==(via), d.machines)
            @test v.dip[row] === v.dip[length(net.branches) + k]
        end
    end
    @test any(!=(:none), s.via[1:length(net.branches)])          # the bridge case is reached
end

@testset "the per-machine extremes: exact over the grid, never shallower than the recorder" begin
    m = _OSD.mesh(; loads = :constant_power)
    # Inside the recorder's capacity: bit for bit the recorded series' extremes.
    e = init!(DetailedEngine, m; powerflow = ac_powerflow(m))
    s = solve!(e, (0.0, 4.0); perturbations = [1.0 => TripGenerator(:G2)], saveat = 0.01)
    x = speed_extremes(e)
    for (k, id) in enumerate(x.ids)
        ω = getproperty(s, Symbol(:ω_, id))
        if id === :G2
            # The machine lost: only its samples up to the trip count. (Its rotor does
            # not move afterwards at this tier — torque and current are both zeroed, so
            # it sits at its trip-instant speed, ~1e-17 — which leaves the online guard
            # in `_record_at!` with nothing to catch here; D9 records it.)
            i = findlast(<=(1.0), s.t)
            @test x.Δf_min[k] == minimum(ω[1:i]) * 50.0 && x.Δf_max[k] == maximum(ω[1:i]) * 50.0
        else
            @test x.Δf_min[k] == minimum(ω) * 50.0 && x.Δf_max[k] == maximum(ω) * 50.0
        end
    end
    # A recorder that decimates: the engine's extremes are never shallower, and on this
    # run strictly deeper on at least one machine (so the check is not vacuous).
    e = init!(DetailedEngine, m; powerflow = ac_powerflow(m), capacity = 16)
    s = solve!(e, (0.0, 4.0); perturbations = [1.0 => TripGenerator(:G2)], saveat = 0.01)
    x = speed_extremes(e)
    deeper = false
    for (k, id) in enumerate(x.ids)
        id === :G2 && continue
        ω = getproperty(s, Symbol(:ω_, id)) .* 50.0
        @test x.Δf_min[k] <= minimum(ω)
        deeper |= x.Δf_min[k] < minimum(ω)
    end
    @test deeper
end

@testset "refused by name" begin
    m = _OSD.mesh()
    @test_throws ArgumentError generator_dips(m, ac_powerflow(m); t_trip = 0.0)
    @test_throws ArgumentError generator_dips(m, ac_powerflow(m); horizon = 0)
    # No damping left after a loss: the stopping rule has no time constant.
    ms = [GridSim._machine_with(x; D = 0.0) for x in m.machines]
    nd = NetworkModel(m.S_base, m.f0, m.buses, m.branches, ms, m.loads; slack = m.slack)
    e = try generator_dips(nd, ac_powerflow(nd)) catch err; err end
    @test e isa ArgumentError && occursin("no damping", e.msg)
end

end
