# ─────────────────────────────────────────────────────────────────────────────
# M11 step 5 — the reference machine's up-reserve, measured from what it produces
# (m11-context.md D12, the user's choice).
#
# `NetworkModel` balances the schedule at nominal voltage, so the reference bus's machine
# is scheduled without the losses its solve then makes it carry. Its governor's up-reserve
# was `Pmax − P0` everywhere; from step 5 it is `Pmax` less what it produces in the solve a
# run or a screen starts from, floored at zero — in the detailed tier, the swing tier, the
# AC generator-outage settle and M10's AC screens. Every other machine keeps its number to
# the bit.
#
# The centre is the last testset: a reference governor driven onto its cap must stop AT
# `Pmax` (plus, in the settle, its damping term) — under the old rule it stopped above it
# by exactly the losses the base had put on it.
# ─────────────────────────────────────────────────────────────────────────────

_hr_fixtures() = [("$nm $(ld === :default ? "def" : "cp")", f(; loads = ld))
                  for (nm, f) in (("case9", OutageScreenScript.case9),
                                  ("mesh", OutageScreenScript.mesh))
                  for ld in (:constant_power, :default)]

# case9 on the DEFAULT loads with G1 (the reference) given 10 MW of up-reserve on its
# schedule. The base there puts G1 14.08 MW BELOW its schedule (the sagging loads draw less
# than the losses add), so its real reserve is ~24 MW, and losing G2 asks its governor for
# more, in the settle and in the detailed run. Default loads because the detailed tier refuses G2's trip on constant-power loads at
# the trip itself (a bus leaves the band, M9's report claim f).
function _hr_capped_case9()
    net = OutageScreenScript.case9(; loads = :default)
    ms = [k == 1 ? GridSim._machine_with(m; Pmax = m.P0 + 10.0) : m
          for (k, m) in pairs(net.machines)]
    return NetworkModel(net.S_base, net.f0, net.buses, net.branches, ms, net.loads;
                        slack = net.slack)
end

# The M10 snapshot's governed five-bus mesh (loads as negative machines, so the swing tier
# takes it), made lossy with R = 0.3·X: a governed reference with losses to carry.
function _hr_swing_mesh()
    ms = [Machine(:G1, :A, 300.0, 5.0, 1.0, 0.25, 1.05, 150.0, 0.05, 220.0, 0.5),
          Machine(:LB, :B, 100.0, 1.0, 2.0, 0.25, 1.00, -130.0),
          Machine(:G2, :C, 150.0, 4.0, 2.0, 0.25, 1.04, 60.0, 0.04, 100.0, 0.4),
          Machine(:LD, :D, 100.0, 1.0, 1.5, 0.25, 1.00, -120.0),
          Machine(:G3, :E, 120.0, 3.5, 1.5, 0.25, 1.02, 40.0, 0.06, 45.0, 0.6)]
    br = [Branch(id, f, t, x, 500.0; R = 0.3x) for (id, f, t, x) in
          ((:AB, :A, :B, 0.10), (:AC, :A, :C, 0.20), (:BC, :B, :C, 0.15), (:BD, :B, :D, 0.25),
           (:CD, :C, :D, 0.30), (:DE, :D, :E, 0.10), (:BE, :B, :E, 0.20))]
    return NetworkModel(100.0, 50.0, [Bus(s, 230.0) for s in (:A, :B, :C, :D, :E)], br, ms;
                        slack = :A)
end

@testset "M11 step 5 — the reference machine's up-reserve (D12)" begin

@testset "the detailed tier and the AC screen agree on it: $name" for (name, net) in _hr_fixtures()
    base = ac_powerflow(net)
    ma = machine_arrays(net)
    vs = net.bus_index[net.slack]
    ks = only(net.machines_at_bus[vs])
    out = base.Pgen[vs]                                 # no grid-following source here
    m = net.machines[ks]
    @test abs(out - m.P0 / net.S_base) > 1e-3          # the base really moved it (≥ 0.1 MW)
    # The screen's responders.
    r0 = GridSim._responders(net)
    r = GridSim._responders(net, base)
    @test r.shift[ks] == out - ma.Pm[ks]
    @test r.h[ks] == max(0.0, ma.headroom[ks] - r.shift[ks])
    @test abs(r.h[ks] - (m.Pmax / net.S_base - out)) ≤ 1e-14
    @test all(r.h[j] === r0.h[j] && r.shift[j] == 0.0 for j in eachindex(r.h) if j != ks)
    @test r.P == r0.P                                   # the schedule, as before
    # The detailed tier seeded from the same flow: the same number.
    eng = init!(DetailedEngine, net; powerflow = base)
    hr = [eng.params[i] for i in eng.hr_pidx]
    @test abs(hr[ks] - r.h[ks]) ≤ 1e-12
    @test all(hr[j] === ma.headroom[j] for j in eachindex(hr) if j != ks)
    # From its OWN solve, which holds each machine's E′ rather than its V_set — a different
    # operating point (on case9 it leaves the band, which is why M9 seeds from the flow): the
    # reserve is measured from the output THAT solve gives (Ra = 0: mechanical = terminal).
    if startswith(name, "mesh")
        e2 = init!(DetailedEngine, net)
        hr2 = [e2.params[i] for i in e2.hr_pidx]
        Pm2 = [e2.params[i] for i in e2.Pm_pidx]
        @test abs(Pm2[ks] - base.Pgen[vs]) > 1e-4      # not the flow's point
        @test abs(hr2[ks] - max(0.0, ma.headroom[ks] - (Pm2[ks] - ma.Pm[ks]))) ≤ 1e-12
        @test all(hr2[j] === ma.headroom[j] for j in eachindex(hr2) if j != ks)
    end
end

@testset "the swing tier: measured from the output its lossy solve gives" begin
    net = _hr_swing_mesh()
    ma = machine_arrays(net)
    @test any(>(0), ma.headroom) && any(>(0), ma.invR)  # governed, so there is a cap to read
    eng = SwingEngine(net; reltol = 1e-10, abstol = 1e-12)
    vref = net.bus_index[net.slack]
    sv = GridSim._swing_vertices(net)
    Pm = eng.params[eng.Pm_pidx]
    hr = eng.params[eng.hr_pidx]
    @test Pm[vref] - sv.Pm[vref] > 1e-4                 # it carries the losses
    @test hr[vref] == max(0.0, sv.headroom[vref] - (Pm[vref] - sv.Pm[vref]))
    @test all(hr[v] === sv.headroom[v] for v in eachindex(hr) if v != vref)
    # A lossless model never runs the reference solve: its number is the schedule's.
    lossless = NetworkModel(net.S_base, net.f0, net.buses,
                            [Branch(b.id, b.from, b.to, b.X, b.rating) for b in net.branches],
                            net.machines; slack = net.slack)
    e0 = SwingEngine(lossless)
    @test e0.params[e0.hr_pidx] == GridSim._swing_vertices(lossless).headroom
end

@testset "floored at zero: a governor-free reference keeps none" begin
    net = _r_pair()                                     # lossy, no governor: Pmax = P0
    @test all(iszero, machine_arrays(net).headroom)
    eng = SwingEngine(net)
    @test all(iszero, eng.params[eng.hr_pidx])
    d = init!(DetailedEngine, net)
    @test all(iszero, [d.params[i] for i in d.hr_pidx])
    @test GridSim._reference_headroom(0.0, 0.04) === 0.0
    @test GridSim._reference_headroom(0.3, -0.1) == 0.3 + 0.1
    @test GridSim._reference_headroom(0.3, 0.0) === 0.3
end

@testset "a capped reference stops AT its ceiling, not the base's losses above it" begin
    net = _hr_capped_case9()
    base = ac_powerflow(net)
    vs = net.bus_index[net.slack]
    g1 = net.machines[1]
    S = net.S_base
    shift = base.Pgen[vs] - g1.P0 / S
    @test shift * S < -10.0                             # the base put G1 BELOW its schedule
    # The AC settle: G1's governor capped, so its output is Pmax plus its damping term.
    s = ac_generator_outages(net)
    k2 = findfirst(m -> m.id === :G2, net.machines)
    @test s.outcome[k2] === :secure
    @test s.capped[k2][1]
    out = base.Pgen[vs] + s.pickup[k2][1]
    D1 = machine_arrays(net).D[1]
    @test abs(out - (g1.Pmax / S - s.Δω[k2] * D1)) ≤ 1e-9
    # The detailed tier: G1's governor runs onto its cap, and its mechanical power ends at
    # Pmax (Ra = 0, so the terminal and the mechanical power are one number).
    eng = init!(DetailedEngine, net; powerflow = base)
    hr1 = eng.params[eng.hr_pidx[1]]
    Pm1 = eng.params[eng.Pm_pidx[1]]
    @test abs(Pm1 + hr1 - g1.Pmax / S) ≤ 1e-12
    solve!(eng, (0.0, 1.0))
    inject!(eng, TripGenerator(:G2))
    solve!(eng, (1.0, 30.0))
    st = current_state(eng)
    # ON its cap, to the bit: since D13's fix a governor lands on its cap (next testset).
    # Under the old headroom rule G1's cap sat 14.08 MW (0.1408 pu) higher, never reached.
    @test st.ΔPm[1] == hr1
    @test abs(Pm1 + st.ΔPm[1] - g1.Pmax / S) ≤ 1e-12   # at Pmax
end

# ─────────────────────────────────────────────────────────────────────────────
# D13 (m11-context.md), fixed 2026-11-13: the detailed tier's governor LANDS on its cap.
#
# Before: the saturation in the derivative stopped `ΔPm` rising once it was at `headroom`
# but could not bring back the solver step that crossed it, so a capped governor sat ABOVE
# its cap for the rest of the run — measured on this fixture 0.0075 pu with Rodas5P, up to
# 0.011 with FBDF (0.75–1.1 MW). Now a root-finding callback stops the step at the
# crossing and puts `ΔPm` exactly on the cap (`_governor_cap_callbacks`).
#
# The bounds below were measured AFTER the fix and are what it leaves: exactly 0 with
# Rodas5P (a one-step method starts clean from the landed state); 1.1e-5 with FBDF's own
# steps and 2.2e-7 at `dtmax = 0.01` (a multistep method's history still carries the
# upward slope for a step or two after the landing, and the landed root is latched, so it
# is not landed twice — three orders below what it was). Without the callback every
# bound here is red (executed 2026-11-13, in the order below: 0.0028, 2.0e-9, 0.0065, 0.0014).
# ─────────────────────────────────────────────────────────────────────────────
@testset "D13 — a governor lands on its cap, and lets go of it" begin
    net = _hr_capped_case9()
    base = ac_powerflow(net)
    @testset "never above the cap: $name" for (name, kw, bound) in (
            ("Rodas5P", (;), 0.0),
            ("Rodas5P, tight", (; reltol = 1e-10, abstol = 1e-12), 0.0),
            ("FBDF", (; solver = OrdinaryDiffEq.FBDF()), 1e-4),
            ("FBDF, dtmax 0.01", (; solver = OrdinaryDiffEq.FBDF(), dtmax = 0.01), 1e-5))
        eng = init!(DetailedEngine, net; powerflow = base, kw...)
        hr1 = eng.params[eng.hr_pidx[1]]
        solve!(eng, (0.0, 1.0))
        inject!(eng, TripGenerator(:G2))
        over = -Inf; st = current_state(eng)
        for T in 1.5:0.5:60.0
            solve!(eng, (T - 0.5, T))
            st = current_state(eng)
            over = max(over, st.ΔPm[1] - hr1)
        end
        @test over ≤ bound                              # was 0.0075–0.011
        @test st.ΔPm[1] ≥ hr1 - 1e-12                   # and it IS capped (anti-vacuity)
        # The command is far above the cap, so this is a cap held, not a governor at rest.
        @test -st.ω[1] * eng.params[eng.invR_pidx[1]] - hr1 > 0.1
        # The machines that never cap are not touched: G3's governor follows its droop.
        @test st.ΔPm[3] < eng.params[eng.hr_pidx[3]]
    end

    @testset "released unaided when frequency recovers" begin
        # G3 ramps up 80 MW from t = 40 s; frequency rises and G1's command falls back
        # below its cap. Landing must not latch: G1 leaves the cap and settles on its droop.
        eng = init!(DetailedEngine, net; powerflow = base,
                    ramp = [:G3 => GenerationRamp(0.08, 40.0, 10.0)])
        hr1 = eng.params[eng.hr_pidx[1]]; invR1 = eng.params[eng.invR_pidx[1]]
        solve!(eng, (0.0, 1.0))
        inject!(eng, TripGenerator(:G2))
        solve!(eng, (1.0, 39.0))
        @test current_state(eng).ΔPm[1] == hr1          # capped before the ramp
        solve!(eng, (39.0, 150.0))
        st = current_state(eng)
        @test st.ΔPm[1] < hr1 - 0.2                     # well off the cap (measured 0.2202)
        @test abs(st.ΔPm[1] + st.ω[1] * invR1) < 1e-5   # on its droop line (measured 1.1e-6)
    end

    @testset "one upward root per machine; a governor-free machine has none" begin
        cs = GridSim._governor_cap_callbacks([1, 2], [1, 2], [3, 4])
        @test length(cs.continuous_callbacks) == 2
        fake = (; p = [0.2, 0.1, 0.0, 20.0])            # headrooms 0.2, 0.1; invR 0, 20
        # Machine 1: invR == 0 — a constant −1 whatever its state, never a crossing.
        @test cs.continuous_callbacks[1].condition([0.5, 0.0], 0.0, fake) === -1.0
        # Machine 2: ΔPm − headroom.
        @test cs.continuous_callbacks[2].condition([0.5, 0.3], 0.0, fake) ≈ 0.2
        @test all(cb -> cb.affect_neg! === nothing, cs.continuous_callbacks)   # upward only
    end
end

end
