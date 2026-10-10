# ─────────────────────────────────────────────────────────────────────────────
# M9 step 4 — the frequency verdict and its limits, on the settled value
# (m9-context.md D0 Hurdle 16.1, D2, D3)
#
# The verdict is read FROM a finished screen and never written into it, so the gate
# that M8 did not move is a capture compared byte for byte (`screen_snapshot.jl`,
# m9-tasks.md step 4), not a test here.
#
# Every fixture the repo reports on runs at 50 Hz, so a dropped or hard-coded `f0`
# would be invisible on all of them: the 60 Hz copy below is the only check that sees
# it. Likewise a NaN judged by `abs(Δf) <= lim` comes out a silent `:fail` (and by `>` a
# silent pass), so every "no value" path is pinned on a real refusal.
# ─────────────────────────────────────────────────────────────────────────────

const _OSV = OutageScreenScript

_v_gens(net) = compare_generator_screens(net, dc_generator_outages(net),
                                         ac_generator_outages(net))
# `net` with its nominal frequency changed and nothing else.
_v_at(net, f0) = NetworkModel(net.S_base, f0, net.buses, net.branches, net.machines,
                              net.loads; slack = net.slack)

@testset "M9 step 4 — the frequency verdict and its limits" begin

@testset "FrequencyLimits refuses what is not a limit, by name" begin
    @test_throws ArgumentError FrequencyLimits()
    for bad in (0.0, -0.2, Inf, NaN)
        @test_throws ArgumentError FrequencyLimits(; settled = bad)
        @test_throws ArgumentError FrequencyLimits(; dip = bad)
        @test_throws ArgumentError FrequencyLimits(; rate = 1.0, rate_window = bad)
    end
    # A rate without its window, and a window with no rate: each refused, by name.
    e = try FrequencyLimits(; rate = 2.0) catch err; err end
    @test e isa ArgumentError && occursin("rate_window", e.msg) && occursin("500 ms", e.msg)
    e = try FrequencyLimits(; settled = 0.2, rate_window = 0.5) catch err; err end
    @test e isa ArgumentError && occursin("no `rate`", e.msg)
    l = FrequencyLimits(; settled = 1, rate = 2, rate_window = 0.5)
    @test l.settled === 1.0 && l.rate === 2.0 && l.rate_window === 0.5 && l.dip === nothing
end

@testset "the Continental Europe preset: SO GL Annex III's two values, no rate" begin
    ce = continental_europe_limits()
    @test ce.settled === 0.2 && ce.dip === 0.8
    @test ce.rate === nothing && ce.rate_window === nothing
    doc = string(@doc continental_europe_limits)
    @test occursin("2017/1485", doc) && occursin("Annex III", doc)
    @test occursin("design values, not a pass/fail rule", doc)
end

@testset "positive control: the mesh's G1 (10.94 Hz) fails the sourced limit at both fidelities" begin
    for loads in (:constant_power, :default)
        net = _OSV.mesh(; loads)
        g = _v_gens(net)
        v = frequency_verdicts(net, g, continental_europe_limits())
        # The screens' own numbers, converted with the model's f0 and nothing else.
        @test v.Δf_dc == g.Δω_dc .* 50.0 && v.Δf_ac == g.Δω_ac .* 50.0
        @test v.Δf_dc[1] ≈ -10.9375 rtol = 1e-12
        @test g.dc_outcome[1] === :secure && g.ac_outcome[1] === :secure
        @test v.settled_dc[1] === :fail && v.settled_ac[1] === :fail
        @test v.settled[1] === :both_fail
        # The dip has a limit and no run yet: never `:pass`, never the settled value.
        @test all(==(:not_run), v.dip) && all(==(:no_limit), v.rate)
        @test v.kind == fill(:machine, 3) && v.id == [:G1, :G2, :G3] && v.f0 === 50.0
    end
end

@testset "near the limit: the closed form, and a limit landing exactly on the value" begin
    net = _OSV.mesh()
    g = _v_gens(net)
    # Losing G3 leaves G1 and G2 uncapped, so DC's settled value is the closed form
    # −P₃ / Σ(1/R + D) over the survivors.
    ma = machine_arrays(net)
    @test g.Δω_dc[3] ≈ -ma.Pm[3] / sum(ma.invR[1:2] .+ ma.D[1:2]) rtol = 1e-14
    Δf = g.Δω_dc[3] * 50.0                        # −0.19324 Hz
    judge(lim) = frequency_verdicts(net, g, FrequencyLimits(; settled = lim)).settled_dc[3]
    @test judge(abs(Δf) + 0.002) === :pass
    @test judge(abs(Δf) - 0.002) === :fail
    # Reaching the limit exactly passes (a MAXIMUM deviation); one ulp under it fails.
    @test judge(abs(Δf)) === :pass
    @test judge(prevfloat(abs(Δf))) === :fail
end

@testset "the limit is in Hz: the same per-unit deviation at 60 Hz crosses it" begin
    a, b = _OSV.mesh(), _v_at(_OSV.mesh(), 60.0)
    ga, gb = _v_gens(a), _v_gens(b)
    @test ga.Δω_dc == gb.Δω_dc                    # f0 enters nowhere but the verdict
    lim = FrequencyLimits(; settled = 0.21)
    va, vb = frequency_verdicts(a, ga, lim), frequency_verdicts(b, gb, lim)
    @test vb.f0 === 60.0 && vb.Δf_dc == gb.Δω_dc .* 60.0
    @test va.settled_dc[3] === :pass              # 0.193 Hz
    @test vb.settled_dc[3] === :fail              # 0.232 Hz
end

@testset "frequency can rise: losing a load-as-machine is judged by its size" begin
    n = _OSV.mesh()
    net = NetworkModel(100.0, 50.0, n.buses, n.branches,
                       vcat(n.machines, [Machine(:LM, :B, 100.0, 1.0, 2.0, 0.25, 1.0, -30.0)]),
                       [Load(:LB, :B, 100.0, 30.0, 0, 0, 1), n.loads[2]]; slack = :A)
    g = _v_gens(net)
    k = findfirst(==(:LM), g.machines)
    v = frequency_verdicts(net, g, FrequencyLimits(; settled = 0.1))
    @test v.Δf_dc[k] > 0.1 && v.Δf_ac[k] > 0.1    # +0.120 / +0.122 Hz
    @test v.settled_dc[k] === :fail && v.settled_ac[k] === :fail
    @test frequency_verdicts(net, g, FrequencyLimits(; settled = 0.13)).settled[k] === :both_pass
end

@testset "each screen is judged on its OWN value, and the preset alone splits them both ways" begin
    ce = continental_europe_limits()
    # Constant power: AC's losses deepen the mesh's G3 just past 200 mHz.
    net = _OSV.mesh()
    v = frequency_verdicts(net, _v_gens(net), ce)
    @test abs(v.Δf_dc[3]) < 0.2 < abs(v.Δf_ac[3])     # 0.19324 / 0.20022 Hz
    @test v.settled_dc[3] === :pass && v.settled_ac[3] === :fail
    @test v.settled[3] === :ac_only_fails
    # Default loads: the sagging voltage sheds load, and case9's G1 halves in AC.
    net = _OSV.case9(; loads = :default)
    v = frequency_verdicts(net, _v_gens(net), ce)
    @test abs(v.Δf_ac[1]) < 0.2 < abs(v.Δf_dc[1])     # 0.195 / 0.401 Hz
    @test v.settled_dc[1] === :fail && v.settled_ac[1] === :pass
    @test v.settled[1] === :dc_only_fails
    # AC's `:voltage` is a solved operating point, so its frequency is judged.
    @test _v_gens(net).ac_outcome[1] === :voltage
end

@testset "no value is never a verdict: refusals, and AC's :no_solution" begin
    ce = continental_europe_limits()
    # Nothing responds to frequency: both screens refuse, Δω is NaN at both.
    n = _OSV.mesh()
    ms = [Machine(m.id, m.bus, m.S_rated, m.H, 0.0, m.Xd′, m.E′, m.P0; V_set = m.V_set)
          for m in n.machines]
    net = NetworkModel(100.0, 50.0, n.buses, n.branches, ms, n.loads; slack = :A)
    g = _v_gens(net)
    @test all(==(:no_response), g.dc_outcome) && all(==(:no_response), g.ac_outcome)
    v = frequency_verdicts(net, g, ce)
    @test all(==(:no_value), v.settled_dc) && all(==(:no_value), v.settled_ac)
    @test all(==(:unjudged), v.settled) && all(isnan, v.Δf_dc) && all(isnan, v.Δf_ac)
    # Only AC refuses: G1's headroom covers G2's loss in DC but not AC's added losses.
    net = _m8_tight()
    g = _v_gens(net)
    @test g.dc_outcome[2] === :secure && g.ac_outcome[2] === :reserve_exhausted
    v = frequency_verdicts(net, g, ce)
    @test v.settled_dc[2] === :fail && v.settled_ac[2] === :no_value
    @test v.settled[2] === :one_unjudged
    # AC's :no_solution can carry a Δω (a switching backoff gets that far); it is not a
    # solve the screen stands behind, so it is not judged, and its number not reported.
    syn = GeneratorScreenComparison([:G1, :G2, :G3], [:secure, :secure, :secure],
                                    [:no_solution, :secure, :secure], [Symbol[] for _ in 1:3],
                                    [Symbol[] for _ in 1:3], [:dc_blind, :agree, :agree],
                                    [-0.001, -0.001, -0.001], [-0.001, -0.001, -0.001],
                                    [Float64[] for _ in 1:3], [Float64[] for _ in 1:3])
    v = frequency_verdicts(_OSV.mesh(), syn, ce)
    @test v.settled_ac == [:no_value, :pass, :pass] && isnan(v.Δf_ac[1])
    @test v.settled[1] === :one_unjudged
    # A screen that claims a solved outcome with no number broke its contract: thrown.
    bad = GeneratorScreenComparison(syn.machines, syn.dc_outcome, [:secure, :secure, :secure],
                                    syn.dc_over, syn.ac_over, syn.class, syn.Δω_dc,
                                    [NaN, -0.001, -0.001], syn.reactive, syn.real)
    @test_throws ErrorException frequency_verdicts(_OSV.mesh(), bad, ce)
end

@testset "a part with no limit says so, and a pending part is never a pass" begin
    net = _OSV.mesh()
    g = _v_gens(net)
    v = frequency_verdicts(net, g, FrequencyLimits(; dip = 0.8))
    @test all(==(:no_limit), v.settled_dc) && all(==(:no_limit), v.settled_ac)
    @test all(==(:no_limit), v.settled) && all(==(:not_run), v.dip)
    @test v.Δf_dc == g.Δω_dc .* 50.0              # the numbers are reported regardless
    v = frequency_verdicts(net, g, FrequencyLimits(; rate = 1.0, rate_window = 0.5))
    @test all(==(:not_run), v.rate) && all(==(:no_limit), v.dip)
end

@testset "beside every row of the outage screen; a lone-source line carries its machine's" begin
    for loads in (:constant_power, :default)
        net = _OSV.case9(; loads)
        s = outage_screen(net)
        ce = continental_europe_limits()
        v = frequency_verdicts(net, s, ce)
        g = frequency_verdicts(net, s.generators, ce)
        @test v.id == s.id && v.kind == s.kind
        nb = length(net.branches)
        for r in eachindex(s.id)
            k = r > nb ? r - nb : (s.via[r] === :none ? 0 : findfirst(==(s.via[r]), g.id))
            if k == 0
                @test v.settled_dc[r] === v.settled_ac[r] === v.settled[r] === :not_applicable
                @test v.dip[r] === v.rate[r] === :not_applicable
                @test isnan(v.Δf_dc[r]) && isnan(v.Δf_ac[r])
            else
                @test (v.settled_dc[r], v.settled_ac[r], v.settled[r], v.dip[r]) ==
                      (g.settled_dc[k], g.settled_ac[k], g.settled[k], g.dip[k])
                @test v.Δf_dc[r] === g.Δf_dc[k] && v.Δf_ac[r] === g.Δf_ac[k]
            end
        end
        # case9's three generator lines, by name.
        @test [s.via[r] for r in 1:nb if s.via[r] !== :none] == [:G1, :G3, :G2]
    end
    # A screen of another model is refused, in both forms.
    net = _OSV.mesh()
    @test_throws ArgumentError frequency_verdicts(net, outage_screen(_OSV.case9()),
                                                  continental_europe_limits())
    @test_throws ArgumentError frequency_verdicts(net, _v_gens(_OSV.case9()),
                                                  continental_europe_limits())
end

end
