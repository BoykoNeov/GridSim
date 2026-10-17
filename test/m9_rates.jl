# ─────────────────────────────────────────────────────────────────────────────
# M9 step 6 — the rate of fall (m9-context.md D0 Hurdle 16.7, D10)
#
# Read from the dip step's own runs: no new integration. Every surviving machine's
# windowed rate is judged (the user's choice, D10), the centre-of-inertia rate reported
# beside it. The closed form at t⁺ is computed here from the RAW `Machine` fields —
# never through `machine_arrays`, so a misreading there cannot move both sides of the
# check (step 3's lesson; step 1's t⁺ test reads `machine_arrays` and so cannot see it).
# ─────────────────────────────────────────────────────────────────────────────

const _OSRt = OutageScreenScript

_rt_losses(eng) = sum(branch_power(eng, b.from, b.to) + branch_power(eng, b.to, b.from)
                      for b in eng.model.branches)
# The survivors' inertia on the system base, from the raw fields.
_rt_HS(net, j) = net.machines[j].H * net.machines[j].S_rated / net.S_base

# The lossy report grids, both load models, built once.
const _RT_RUNS = Dict{Tuple{Symbol,Symbol},Any}()
for (name, build) in ((:case9, _OSRt.case9), (:mesh, _OSRt.mesh)),
    loads in (:constant_power, :default)
    net = build(; loads)
    ac = ac_generator_outages(net)
    _RT_RUNS[(name, loads)] = (; net, ac, d = generator_dips(net, ac),
                               g = compare_generator_screens(net, dc_generator_outages(net), ac))
end

# The largest |windowed rate| over windows ending after the trip, computed HERE by
# index — `m` samples back on the uniform grid — so the library's half-sample lookup is
# checked against a read that cannot slip a sample.
function _rt_largest(t, f, w, t_trip)
    m = round(Int, w / 0.01)
    best, span = NaN, NaN
    for i in (m + 1):length(t)
        t[i] > t_trip || continue
        r = (f[i] - f[i - m]) / (t[i] - t[i - m])
        (isnan(best) || abs(r) > abs(best)) && (best = r; span = t[i] - t[i - m])
    end
    return best, span
end

@testset "M9 step 6 — the rate of fall" begin

@testset "the traces are the runs' own samples, on the output grid, never decimated" begin
    for ((name, loads), r) in _RT_RUNS, (k, id) in enumerate(r.d.machines)
        r.d.outcome[k] === :measured || (@test isempty(r.d.trace[k].t); continue)
        for (tr, x) in ((r.d.trace[k], r.d.Δf_machine[k]),
                        (r.d.trace_coarse[k], r.d.Δf_machine_coarse[k]))
            @test tr.t[1] == 0.0
            @test all(dt -> abs(dt - 0.01) < 1e-9, diff(tr.t))      # uniform, no repeats
            @test tr.t[end] ≈ r.d.t_stop[k] atol = 1e-9             # both cover the fine span
            @test size(tr.f) == (length(tr.t), length(r.d.machines))
            # Tied to the dip: each survivor's extreme is its trace's extreme.
            for j in eachindex(r.d.machines)
                j == k && continue
                lo, hi = extrema(view(tr.f, :, j)) .- r.net.f0
                @test GridSim._extreme(lo, hi) ≈ x[j] atol = 1e-12
            end
        end
    end
    # A decimated recorder is never differenced: every window would silently widen.
    m = _OSRt.mesh(; loads = :constant_power)
    e = init!(DetailedEngine, m; powerflow = ac_powerflow(m), capacity = 16)
    solve!(e, (0.0, 2.0); saveat = 0.01)
    err = try GridSim._frequency_trace(e); nothing catch x; x end
    @test err isa ErrorException && occursin("decimated", err.msg)
    # …and a horizon whose run could fill the recorder is refused before any run.
    err = try generator_dips(m, ac_powerflow(m); horizon = 1e5); nothing catch x; x end
    @test err isa ArgumentError && occursin("recorder", err.msg)
end

@testset "the windows: the library's read is the by-index read, bit for bit" begin
    # Every channel, every measured row, windows from one sample to one second: the
    # half-sample lookup finds exactly the sample one window back, and the span is the
    # window (D10 decision 3).
    for ((name, loads), r) in _RT_RUNS, w in (0.01, 0.02, 0.05, 0.25, 0.5, 1.0)
        rt = generator_rates(r.d; window = w)
        @test rt.window === w
        for (k, id) in enumerate(r.d.machines)
            r.d.outcome[k] === :measured || continue
            tr, tc = r.d.trace[k], r.d.trace_coarse[k]
            v, span = _rt_largest(tr.t, tr.f_coi, w, r.d.t_trip)
            @test rt.rate_coi[k] === v
            @test abs(span - w) < 1e-9
            @test rt.rate_coi_coarse[k] === _rt_largest(tc.t, tc.f_coi, w, r.d.t_trip)[1]
            for j in eachindex(r.d.machines)
                j == k && (@test isnan(rt.rate_machine[k][j]); continue)
                @test rt.rate_machine[k][j] === _rt_largest(tr.t, view(tr.f, :, j), w, r.d.t_trip)[1]
                @test rt.rate_machine_coarse[k][j] ===
                      _rt_largest(tc.t, view(tc.f, :, j), w, r.d.t_trip)[1]
            end
        end
    end
    # A window off the output grid is refused, by name — 5 ms would become 10 ms.
    d = _RT_RUNS[(:mesh, :constant_power)].d
    for bad in (0.005, 0.015, 0.0)
        @test_throws ArgumentError generator_rates(d; window = bad)
    end
    @test generator_rates(d; window = 0.03).window === 0.03
end

@testset "t⁺: the windowed COI rate approaches the closed form from below" begin
    # Constant-power loads only: on default loads load relief adds a term the formula
    # does not have (M7 D16). The closed form is step 1's identity,
    #     ḟ_coi(t⁺) = −(P_lost + ΔL)·f0 / (2ΣHS),
    # ΣHS the survivors' inertia from the RAW fields, ΔL the change in losses across
    # the trip read at both ends of every branch.
    nchecked = 0
    for name in (:case9, :mesh)
        r = _RT_RUNS[(name, :constant_power)]
        for (k, id) in enumerate(r.d.machines)
            r.d.outcome[k] === :measured || continue
            eng = init!(DetailedEngine, r.net; powerflow = r.ac.base, reltol = 1e-8,
                        abstol = 1e-10, solver = GridSim.OrdinaryDiffEq.FBDF())
            P_lost, L⁻ = eng.params[eng.Pm_pidx[k]], _rt_losses(eng)
            inject!(eng, TripGenerator(id))
            ΣHS = sum(_rt_HS(r.net, j) for j in eachindex(r.net.machines) if j != k)
            cf = -(P_lost + _rt_losses(eng) - L⁻) * r.net.f0 / (2ΣHS)
            # The engine's own instantaneous rate agrees with the raw-field formula — the
            # check an inertia misread in `machine_arrays` cannot pass.
            @test coi_rocof(eng) ≈ cf rtol = 1e-8
            gaps = Float64[]
            for w in (0.5, 0.2, 0.1, 0.04, 0.02, 0.01)
                g = generator_rates(r.d; window = w).rate_coi[k]
                @test sign(g) == sign(cf)
                push!(gaps, abs(cf) - abs(g))
            end
            @test all(>(0), gaps)                  # from below, at every window
            @test issorted(gaps; rev = true)       # closer as the window shrinks
            @test 1.7 <= gaps[5] / gaps[6] <= 2.3  # first order in the window
            @test gaps[6] < 5e-3 * abs(cf)         # within 0.5 % at one sample
            nchecked += 1
        end
    end
    @test nchecked == 4             # case9 G3, mesh G1–G3: exercised, not skipped
end

@testset "every machine judged: the COI rate is the machines' inertia-weighted mean" begin
    # In a window lying wholly after the trip the COI weights are fixed, so the COI rate
    # IS the weighted mean of the machines' rates — the identity that ties the two reads
    # together, and why |worst| can never be below |COI| there.
    for ((name, loads), r) in _RT_RUNS, (k, id) in enumerate(r.d.machines)
        r.d.outcome[k] === :measured || continue
        tr = r.d.trace[k]
        others = [j for j in eachindex(r.d.machines) if j != k]
        h = [_rt_HS(r.net, j) for j in others]
        rc = windowed_rocof(tr.t, tr.f_coi; window = 0.495)
        rm = [windowed_rocof(tr.t, tr.f[:, j]; window = 0.495) for j in others]
        post = findall(>(r.d.t_trip + 0.5 + 1e-9), tr.t)
        @test !isempty(post)
        @test maximum(abs(rc[i] - sum(h .* getindex.(rm, i)) / sum(h)) for i in post) < 1e-9
        rt = generator_rates(r.d; window = 0.5)
        @test abs(rt.rate_worst[k]) >= abs(rt.rate_coi[k]) - 1e-12
        @test rt.worst[k] === r.d.machines[others[argmax(abs.(rt.rate_machine[k][others]))]]
        @test rt.rate_worst[k] === rt.rate_machine[k][findfirst(==(rt.worst[k]), r.d.machines)]
    end
    # A limit between the worst machine and the average: the machines fail it, the
    # average alone would pass — so the verdict reads the machines.
    r = _RT_RUNS[(:mesh, :constant_power)]
    rt = generator_rates(r.d; window = 0.5)
    k = argmax([r.d.outcome[k] === :measured ? abs(rt.rate_worst[k]) / abs(rt.rate_coi[k]) : 0.0
                for k in eachindex(r.d.machines)])
    @test abs(rt.rate_worst[k]) > 1.02 * abs(rt.rate_coi[k])
    lim = (abs(rt.rate_worst[k]) + abs(rt.rate_coi[k])) / 2
    v = frequency_verdicts(r.net, r.g, FrequencyLimits(; rate = lim, rate_window = 0.5);
                           dips = r.d)
    @test v.rate[k] === :fail && v.rocof[k] === rt.rate_worst[k]
    @test v.rate_read === :worst_machine
end

@testset "the verdict: the limit's own window, both tolerances, never a pass from nothing" begin
    r = _RT_RUNS[(:mesh, :constant_power)]
    judge(lim, w) = frequency_verdicts(r.net, r.g, FrequencyLimits(; rate = lim,
                                       rate_window = w); dips = r.d)
    # The window is the limit's: a limit between the 1 s and 500 ms worst rates of one
    # outage passes over 1 s and fails over 500 ms.
    a, b = generator_rates(r.d; window = 1.0), generator_rates(r.d; window = 0.5)
    k = 2
    @test abs(a.rate_worst[k]) < abs(b.rate_worst[k])
    lim = (abs(a.rate_worst[k]) + abs(b.rate_worst[k])) / 2
    @test judge(lim, 1.0).rate[k] === :pass && judge(lim, 0.5).rate[k] === :fail
    # Reaching the limit passes (≤); between the two tolerances' values neither verdict
    # is reported.
    f, c = abs(b.rate_worst[k]), abs(b.rate_worst_coarse[k])
    @test f != c                                  # the premise of the pair below
    @test judge(max(f, c), 0.5).rate[k] === :pass
    @test judge(prevfloat(max(f, c)), 0.5).rate[k] === :tolerance_dependent
    @test judge(prevfloat(min(f, c)), 0.5).rate[k] === :fail
    # Without the runs the rate is `:not_run`; without a rate limit, `:no_limit`.
    @test frequency_verdicts(r.net, r.g, FrequencyLimits(; rate = 1.0, rate_window = 0.5)).rate ==
          fill(:not_run, 3)
    @test all(isnan, frequency_verdicts(r.net, r.g,
              FrequencyLimits(; rate = 1.0, rate_window = 0.5)).rocof)
    @test frequency_verdicts(r.net, r.g, continental_europe_limits(); dips = r.d).rate ==
          fill(:no_limit, 3)
    # A run that measured nothing carries its own outcome, never a pass.
    q = _RT_RUNS[(:case9, :constant_power)]
    v = frequency_verdicts(q.net, q.g, FrequencyLimits(; rate = 100.0, rate_window = 0.5);
                           dips = q.d)
    @test v.rate == [:refused_at_trip, :refused_at_trip, :pass]
    @test isnan(v.rocof[1]) && isfinite(v.rocof[3])
    # A window off the output grid is refused through the verdict too.
    @test_throws ArgumentError judge(1.0, 0.005)
end

@testset "the OutageScreen form: lone-source lines carry their machine's rate" begin
    net = _OSRt.case9(; loads = :default)
    s = outage_screen(net)
    d = generator_dips(net, s)
    v = frequency_verdicts(net, s, FrequencyLimits(; rate = 0.5, rate_window = 0.5); dips = d)
    nb = length(net.branches)
    for (row, via) in enumerate(s.via)
        row <= nb || break
        if via === :none
            @test v.rate[row] === :not_applicable && isnan(v.rocof[row])
        else
            kk = findfirst(==(via), d.machines)
            @test v.rate[row] === v.rate[nb + kk] && isequal(v.rocof[row], v.rocof[nb + kk])
        end
    end
    @test any(!=(:none), s.via[1:nb])
    @test any(isfinite, v.rocof[nb+1:end])
end

end
