# ─────────────────────────────────────────────────────────────────────────────
# M9 step 7 — the report (`scripts/outage_screen.jl` sections 4–5)
#
# The frequency verdict beside M8's screens, on the two lossy report grids and both load
# models. Asserted against the script's own row builder (`frequency_rows`), handed the
# dip step's runs (`_D_RUNS`, `m9_dips.jl`) so nothing is integrated twice — and once on
# its own default path, so the path the script takes is the one tested. Every claim was
# written AFTER the tables were read (`docs/evidence/gridsim-m9/step7/predictions.md`
# holds what was predicted first) and is asserted here at the precision it prints.
# ─────────────────────────────────────────────────────────────────────────────

const _OSR = OutageScreenScript

const _R_ROWS = Dict{Tuple{Symbol,Symbol},Any}()
for name in (:case9, :mesh), loads in (:constant_power, :default)
    run = _D_RUNS[(:lossy, name, loads)]
    s = outage_screen(run.net)
    _R_ROWS[(name, loads)] = (; run.net, s, d = run.d,
                              rows = _OSR.frequency_rows(run.net; s, dips = run.d))
end
_r_row(name, loads, id) = only(r for r in _R_ROWS[(name, loads)].rows if r.id === id)
_r_measured() = [(k, r) for (k, x) in _R_ROWS for r in x.rows if r.dyn === :measured]

@testset "M9 step 7 — the report: the frequency verdict beside the screens" begin

@testset "the script's default path is the one tested" begin
    # The cached runs are `generator_dips(net, ac_generator_outages(net))`; the script
    # calls `generator_dips(net, outage_screen(net))`. Same base, so the same rows.
    x = _R_ROWS[(:mesh, :constant_power)]
    @test isequal(_OSR.frequency_rows(x.net), x.rows)
end

@testset "each column reads what its header says" begin
    @test _OSR.RATE_WINDOWS == (0.5, 1.0)
    for ((name, loads), x) in _R_ROWS
        net, s, d = x.net, x.s, x.d
        nb = length(net.branches)
        v = frequency_verdicts(net, s, continental_europe_limits(); dips = d)
        # The preset judges no rate: the report prints it, the verdict has none.
        @test all(v.rate[nb+1:end] .=== :no_limit)
        r500, r1 = generator_rates(d; window = 0.5), generator_rates(d; window = 1.0)
        @test [r.id for r in x.rows] == [m.id for m in net.machines]
        for (k, r) in pairs(x.rows)
            i = nb + k
            @test (r.dc, r.ac) === (s.dc_outcome[i], s.ac_outcome[i])
            @test (r.settled_dc, r.settled_ac, r.settled) ===
                  (v.settled_dc[i], v.settled_ac[i], v.settled[i])
            @test isequal((r.Δf_dc, r.Δf_ac), (s.generators.Δω_dc[k] * net.f0,
                                               s.generators.Δω_ac[k] * net.f0))
            @test (r.dyn, r.reason, r.dip) === (d.outcome[k], d.reason[k], v.dip[i])
            @test isequal((r.Δf_dip, r.Δf_dip_coi, r.dip_worst),
                          (d.Δf_worst[k], d.Δf_coi[k], d.worst[k]))
            # Each window's own rates, the worst machine's and the COI's — never the
            # other window's.
            @test isequal(r.rate, [r500.rate_worst[k], r1.rate_worst[k]])
            @test isequal(r.rate_coi, [r500.rate_coi[k], r1.rate_coi[k]])
            @test r.rate_worst == [r500.worst[k], r1.worst[k]]
        end
    end
end

@testset "the printed table: a refusal is named, never a pass or a number" begin
    for ((name, loads), x) in _R_ROWS
        out = sprint(io -> _OSR.print_frequency_table(io, "t", x.rows))
        lines = split(out, '\n')
        for r in x.rows
            line = only(l for l in lines if startswith(l, rpad(String(r.id), 4) * " |"))
            if r.dyn === :measured
                @test occursin(_OSR._f(r.Δf_dip, "%.3f"), line)
                @test occursin(r.dip === :pass ? " pass" : " FAIL", split(line, '|')[4])
            else
                @test occursin("$(r.dyn) ($(r.reason))", line)
                @test !occursin("pass", split(line, '|')[4]) &&
                      !occursin("FAIL", split(line, '|')[4])
            end
        end
    end
end

# ── The claims (`scripts/outage_screen.jl` section 5), each as printed ─────────────

@testset "claim f: claim (d) revisited — secure, and failing every part judged" begin
    for (loads, ac, dip) in ((:constant_power, -11.22, -11.260), (:default, -11.06, -8.905))
        r = _r_row(:mesh, loads, :G1)
        @test (r.dc, r.ac) === (:secure, :secure)
        @test (r.settled_dc, r.settled_ac, r.dip) === (:fail, :fail, :fail)
        @test r.Δf_dc ≈ -10.94 atol = 5e-3
        @test r.Δf_ac ≈ ac atol = 5e-3
        @test r.Δf_dip ≈ dip atol = 5e-4
        # "at both solver tolerances": the coarse run fails the 0.8 Hz limit as well.
        k = findfirst(m -> m.id === :G1, _R_ROWS[(:mesh, loads)].net.machines)
        @test abs(_R_ROWS[(:mesh, loads)].d.Δf_worst_coarse[k]) > 0.8
    end
    # The second way: secure in both screens, refused by the dynamic run at the trip.
    r = _r_row(:case9, :constant_power, :G2)
    @test (r.dc, r.ac) === (:secure, :secure)
    @test (r.dyn, r.reason, r.dip) === (:refused_at_trip, :voltage, :refused_at_trip)
    @test isnan(r.Δf_dip)
end

@testset "claim g: under the preset the settled limit decides, the dip never" begin
    all_rows = [r for x in values(_R_ROWS) for r in x.rows]
    @test length(all_rows) == 12
    @test count(r -> r.settled === :both_fail, all_rows) == 9
    @test [r.id for r in all_rows if r.settled === :both_pass] == [:G3]
    @test _r_row(:mesh, :default, :G3).settled === :both_pass
    @test _r_row(:mesh, :constant_power, :G3).settled === :ac_only_fails
    @test _r_row(:case9, :default, :G1).settled === :dc_only_fails
    # The dip fails only on the mesh's G1, which the settled value fails at both.
    fails = [(k, r.id) for (k, r) in _r_measured() if r.dip === :fail]
    @test Set(fails) == Set([((:mesh, :constant_power), :G1), ((:mesh, :default), :G1)])
    @test all(_r_row(f..., :G1).settled === :both_fail for f in ((:mesh, :constant_power), (:mesh, :default)))
    # Largest dip-to-settled ratio 1.66, on case9's G3 (0.7515 against 0.4515 Hz). First
    # printed as 1.67 — DC's ratio (1.674), not the AC one the sentence names; this
    # assertion caught it. The dip sits on a rounding boundary (the table's %.3f prints
    # 0.752, and 0.752/0.4515 reads 1.67 again), so the claim prints it to four places.
    ratios = [(r.Δf_dip / r.Δf_ac, k, r.id) for (k, r) in _r_measured()]
    top = maximum(ratios)
    @test top[1] ≈ 1.66 atol = 5e-3
    @test top[2:3] == ((:case9, :constant_power), :G3)
    r = _r_row(:case9, :constant_power, :G3)
    @test r.Δf_dip ≈ -0.7515 atol = 5e-5
    @test r.Δf_ac ≈ -0.4515 atol = 5e-5
    lim = continental_europe_limits()
    @test lim.dip / lim.settled == 4.0
end

@testset "claim h: on default loads the dip can be shallower than AC's settled value" begin
    shallower = [r.id for (k, r) in _r_measured()
                 if k == (:mesh, :default) && abs(r.Δf_dip) < abs(r.Δf_ac)]
    @test shallower == [:G1, :G3]
    # …and only there: never on constant power, never on case9.
    @test all(abs(r.Δf_dip) >= abs(r.Δf_ac) for (k, r) in _r_measured() if k != (:mesh, :default))
    g1, g3 = _r_row(:mesh, :default, :G1), _r_row(:mesh, :default, :G3)
    @test g1.Δf_dip ≈ -8.905 atol = 5e-4
    @test g1.Δf_ac ≈ -11.059 atol = 5e-4
    @test g3.Δf_dip ≈ -0.151 atol = 5e-4
    @test g3.Δf_ac ≈ -0.153 atol = 5e-4
    # "Neither run is cut short": both stopped on their own settling, inside the horizon.
    for id in (:G1, :G3)
        x = _R_ROWS[(:mesh, :default)]
        k = findfirst(m -> m.id === id, x.net.machines)
        @test x.d.outcome[k] === :measured && isfinite(x.d.t_stop[k])
    end
end

@testset "claim i: the window matters more than whose frequency" begin
    m = _r_measured()
    # Worst machine against the COI: dip at most 8.1 % deeper (the mesh's G2, constant
    # power: G3 0.561 against 0.519 Hz); 500 ms rate at most 4.0 % faster.
    dipr = [(r.Δf_dip / r.Δf_dip_coi, k, r.id) for (k, r) in m]
    @test 100 * (maximum(dipr)[1] - 1) ≈ 8.1 atol = 0.05
    @test maximum(dipr)[2:3] == ((:mesh, :constant_power), :G2)
    r = _r_row(:mesh, :constant_power, :G2)
    @test r.dip_worst === :G3
    @test r.Δf_dip ≈ -0.561 atol = 5e-4
    @test r.Δf_dip_coi ≈ -0.519 atol = 5e-4
    @test 100 * (maximum(r.rate[1] / r.rate_coi[1] for (_, r) in m) - 1) ≈ 4.0 atol = 0.05
    # The 500 ms read is 1.18–1.54 times the 1 s read, on every measured row.
    w = [r.rate[1] / r.rate[2] for (_, r) in m]
    @test minimum(w) ≈ 1.18 atol = 5e-3
    @test maximum(w) ≈ 1.54 atol = 5e-3
    # The fastest: the mesh's G1 on constant power, 3.095 Hz/s over 500 ms.
    top = argmax(x -> abs(x[2].rate[1]), m)
    @test top[1] == (:mesh, :constant_power) && top[2].id === :G1
    @test top[2].rate[1] ≈ -3.095 atol = 5e-4
end

@testset "claim j: no verdict depends on the tolerance; three rows have no dip" begin
    all_rows = [(k, r) for (k, x) in _R_ROWS for r in x.rows]
    @test all(r.dip in (:pass, :fail) for (_, r) in all_rows if r.dyn === :measured)
    @test !any(r.dip === :tolerance_dependent for (_, r) in all_rows)
    @test Set((k, r.id) for (k, r) in all_rows if r.dyn !== :measured) ==
          Set([((:case9, :constant_power), :G1), ((:case9, :default), :G1),
               ((:case9, :constant_power), :G2)])
    @test all(r.dyn === :refused_at_trip for (_, r) in all_rows if r.dyn !== :measured)
end

end
