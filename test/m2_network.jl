# M2 (first half) - the canonical network model, and the SwingEngine's build,
# conformance, flat start, injection sign convention and closed-form swing.

# ================= M2 — the canonical network model =====================
# docs/plans/m2-tasks.md step 2. These tests carry the whole per-unit burden
# of the model layer: `machine_arrays`/`branch_arrays` are the only place the
# conversion to the system base happens, so if they are right nothing
# downstream has to redo it, and if they are wrong every downstream number is
# plausible and wrong.

@testset "network model: shape, ids, and bus ordering" begin
    net = two_machine_system()
    @test net isa NetworkModel
    @test net.S_base == 100.0
    @test net.f0 == 50.0
    @test length(net.buses) == 2
    @test length(net.machines) == 2
    @test length(net.branches) == 1
    @test net.bus_index == Dict(:B1 => 1, :B2 => 2)
    # machines are stored in BUS order, so one index addresses vertex, bus and
    # machine together — the property the engine's vertex indexing relies on.
    @test [m.bus for m in net.machines] == [b.id for b in net.buses]
    @test machine_at(net, :B2).id === :G2
    @test occursin("no bus", argerr_msg(() -> machine_at(net, :NOPE)))

    ring = three_machine_ring()
    @test length(ring.buses) == 3 && length(ring.branches) == 3
    @test [m.id for m in ring.machines] == [:G1, :G2, :G3]
    @test [m.bus for m in ring.machines] == [b.id for b in ring.buses]
    # +80 / +30 / −110 MW: two generators and a load, summing to zero.
    @test sum(m.P0 for m in ring.machines) == 0.0
    @test count(m -> m.P0 < 0, ring.machines) == 1

    # The constructor reorders whatever order it is handed. Feeding the
    # machines in reverse must produce the same model, not a transposed one —
    # otherwise vertex 1's parameters could belong to bus 2.
    shuffled = NetworkModel(; S_base = ring.S_base, f0 = ring.f0,
                            buses = ring.buses, branches = ring.branches,
                            machines = reverse(ring.machines))
    @test [m.id for m in shuffled.machines] == [:G1, :G2, :G3]
    @test machine_arrays(shuffled).H == machine_arrays(ring).H
end

@testset "machine_arrays: per-unit conversion vs hand arithmetic" begin
    net = two_machine_system()
    ma = machine_arrays(net)
    # G1: 250 MVA on a 100 MVA base ⇒ power weight w = 2.5.
    #     H 4.0·2.5 = 10.0 s;  D 2.0·2.5 = 5.0;  P 60/100 = 0.6 pu
    #     X′d 0.25/2.5 = 0.10 pu — the INVERSE weight (impedance scales the
    #     other way from power). This is the one line where the conversion
    #     can be written backwards and still look reasonable.
    @test ma.H  ≈ [10.0, 20.0]
    @test ma.D  ≈ [5.0, 8.0]
    @test ma.Pm ≈ [0.6, -0.6]
    @test ma.E  ≈ [1.05, 1.02]
    @test ma.Xd ≈ [0.10, 0.075]
    # The inverted conversion, named explicitly so the test fails loudly
    # rather than by a mysterious number: X′d·w instead of X′d/w.
    @test ma.Xd ≉ [0.25 * 2.5, 0.30 * 4.0]
    # …and the missing conversion (raw machine-base values passed through).
    @test ma.Xd ≉ [0.25, 0.30]
    @test ma.H  ≉ [4.0, 5.0]

    # Derived on call, never stored: two calls give equal arrays that are not
    # the same object. This is the SPEC §3.2 claim ("compiled views, not a
    # second copy") made checkable — a cached copy could go stale, this cannot.
    @test machine_arrays(net).H == ma.H
    @test machine_arrays(net).H !== ma.H

    # Everything is a plain contiguous Float64 vector (SPEC §4, struct-of-arrays).
    @test all(a -> a isa Vector{Float64}, (ma.H, ma.D, ma.Pm, ma.E, ma.Xd,
                                           ma.invR, ma.headroom, ma.Tg))

    # Governor conversions (M3 step 1). `two_machine_system` is governor-free,
    # so its gain is zero and its reserve is zero — and `1/Inf` is `0.0`, which
    # is the whole reason no special case is needed anywhere downstream.
    @test ma.invR == [0.0, 0.0]
    @test ma.headroom == [0.0, 0.0]
    @test !any(isnan, ma.invR)
    @test ma.Tg == [1.0, 1.0]

    # …and against hand arithmetic on a governed pair. It is the GAIN 1/R that
    # carries the power weight, not the droop: G1 is 250 MVA on a 100 MVA base,
    # so w = 2.5 and (1/0.05)·2.5 = 50. Reserve is (Pmax − P0)/S_base.
    gov = NetworkModel(100.0, 50.0, net.buses, net.branches,
                       [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05,  60.0, 0.05, 110.0, 8.0),
                        Machine(:G2, :B2, 400.0, 5.0, 2.0, 0.30, 1.02, -60.0, 0.04, -20.0, 6.0)])
    mg = machine_arrays(gov)
    @test mg.invR ≈ [(1 / 0.05) * 2.5, (1 / 0.04) * 4.0] ≈ [50.0, 100.0]
    @test mg.headroom ≈ [(110.0 - 60.0) / 100, (-20.0 - -60.0) / 100] ≈ [0.5, 0.4]
    @test mg.Tg == [8.0, 6.0]                       # seconds, base-independent
    # The two ways to get the gain conversion wrong, by name: converting the
    # DROOP instead of the gain (the mirror image of the Xd′ mistake above), and
    # forgetting the weight entirely. Both give plausible numbers.
    @test mg.invR ≉ [1 / (0.05 * 2.5), 1 / (0.04 * 4.0)]
    @test mg.invR ≉ [1 / 0.05, 1 / 0.04]

    # The reason this conversion lives here and only here: summing the per-machine
    # gains must reproduce M1's aggregate droop EXACTLY, because `aggregates`
    # applies the identical weight to `1/Rᵢ`. If the two ever disagreed, the
    # cross-fidelity comparison would be measuring a per-unit bug.
    a = GridSim.aggregates(coi_model(gov), Set([:G1, :G2]))
    @test 1 / a.R_eq ≈ sum(mg.invR) ≈ 150.0
    @test a.headroom ≈ sum(mg.headroom) ≈ 0.9
end

@testset "branch_arrays: coupling K through the real code path" begin
    net = two_machine_system()
    ba = branch_arrays(net)
    @test ba.src == [1] && ba.dst == [2]        # vertex indices, not bus ids
    @test ba.X ≈ [0.25]                          # the branch's own reactance, as given
    # K = E′₁·E′₂ / X, and nothing else: 1.05·1.02 / 0.25 = 1.071/0.25 = 4.284 pu.
    @test ba.K ≈ [4.284]
    # The two ways to get this wrong, asserted against by name. Both produce a
    # perfectly plausible coupling, which is the whole danger.
    # (a) folding X′d in on the SYSTEM base — 1.071/(0.10+0.25+0.075). Exact for
    #     this radial pair, but wrong the moment a machine has two lines, which
    #     is why M2a does not do it anywhere (see network_model.jl, tier note 2).
    @test ba.K[1] ≉ 1.071 / 0.425
    # (b) folding X′d in without converting it off the machine base at all.
    @test ba.K[1] ≉ 1.071 / 0.80

    # X′d is carried data in M2a, not dynamics. Changing it must not move K by
    # one bit — this is the regression test against quietly folding it back in.
    # NOTE (M3 step 1): this 8-argument form is a LOSSY copy now — it drops
    # `R`, `Pmax` and `Tg` back to the governor-free defaults. Harmless here,
    # because `two_machine_system`'s machines are governor-free to begin with,
    # and deliberately not "fixed" by spelling all eleven arguments out: the
    # point of this fixture is that changing `Xd′` alone must not move `K`.
    # But a rebuild-a-machine loop written this way in step 5's ramp or step 6's
    # sweep would silently disarm every governor it touched.
    stiffer = NetworkModel(100.0, 50.0, net.buses, net.branches,
                           [Machine(m.id, m.bus, m.S_rated, m.H, m.D,
                                    10 * m.Xd′, m.E′, m.P0) for m in net.machines])
    @test branch_arrays(stiffer).K == ba.K
    @test machine_arrays(stiffer).Xd ≈ 10 .* machine_arrays(net).Xd   # …and it did change

    ring = three_machine_ring()
    br = branch_arrays(ring)
    @test br.src == [1, 2, 3] && br.dst == [2, 3, 1]
    @test br.K ≈ [1.05 * 1.03, 1.03 * 1.04, 1.04 * 1.05] ./ 0.25
    @test length(br.K) == length(ring.branches)   # one coupling per branch, not n²
    # Every machine in the ring has branch degree 2 — the topology on which the
    # fold-in would have counted one rotor's internal reactance twice.
    deg = zeros(Int, length(ring.buses))
    for b in ring.branches
        deg[ring.bus_index[b.from]] += 1
        deg[ring.bus_index[b.to]] += 1
    end
    @test deg == [2, 2, 2]
    # X′d is still carried, on the system base, ready for M2b: three different
    # machine bases (0.30/300, 0.20/200, 0.50/500) all land on 0.10 pu.
    @test machine_arrays(ring).Xd ≈ [0.10, 0.10, 0.10]
end

@testset "two-machine closed form: the target step 4 must hit" begin
    # V3 (m2-plan.md) is measured against the running engine in step 4. What
    # is pinned *here* is the prediction the example system implies, computed
    # through the same `machine_arrays`/`branch_arrays` the engine will use —
    # so if anyone edits `two_machine_system`'s numbers, this fails and the
    # closed form gets re-derived instead of silently going stale.
    net = two_machine_system()
    ma, ba = machine_arrays(net), branch_arrays(net)
    K, P = ba.K[1], ma.Pm[1]
    δ₀ = asin(P / K)                       # equilibrium angle difference
    ω₀ = 2π * net.f0
    f_osc = sqrt(ω₀ * K * cos(δ₀) * (1 / (2ma.H[1]) + 1 / (2ma.H[2]))) / 2π
    @test δ₀ ≈ 0.1405180 atol = 1e-6
    @test f_osc ≈ 1.5911075 atol = 1e-6
    # Sanity: this is an inter-machine mode, not a system-frequency swing —
    # roughly 1–2 Hz, orders above M1's aggregate response.
    @test 1.0 < f_osc < 2.0
end

@testset "network model: concrete field types (SPEC §4)" begin
    # Abstractly-typed fields are Julia's biggest performance cliff, and the
    # RHS reads these on every step. Asserted rather than trusted.
    for T in (Bus, Branch, Machine, NetworkModel)
        @test all(isconcretetype, fieldtypes(T))
    end
end

@testset "network model guards: per-component" begin
    @test occursin("V_base", argerr_msg(() -> Bus(:B, 0.0)))
    @test occursin("S_rated", argerr_msg(() -> Machine(:G, :B, 0.0, 4.0, 2.0, 0.25, 1.05, 0.0)))
    # H is strict because it sits in a denominator (2H), so zero is a division
    # by zero rather than a degenerate-but-valid machine. X′d is strict even
    # though M2a's dynamics never read it — validating carried data now is what
    # makes it trustworthy when M2b's reduction starts consuming it.
    @test occursin("divides by 2H", argerr_msg(() -> Machine(:G, :B, 100.0, 0.0, 2.0, 0.25, 1.05, 0.0)))
    @test occursin("Xd′", argerr_msg(() -> Machine(:G, :B, 100.0, 4.0, 2.0, 0.0, 1.05, 0.0)))
    @test occursin("E′", argerr_msg(() -> Machine(:G, :B, 100.0, 4.0, 2.0, 0.25, 0.0, 0.0)))
    @test occursin("anti-physical", argerr_msg(() -> Machine(:G, :B, 100.0, 4.0, -1.0, 0.25, 1.05, 0.0)))
    # Governor data (M3 step 1). Each guard is provoked ALONE and asserted by
    # its own wording: an invalid machine usually breaks more than one rule at
    # once, so "it threw an ArgumentError" would not prove the intended guard is
    # the one that fired.
    #                                     S_rated  H    D    Xd′   E′   P0     R     Pmax  Tg
    @test occursin("droop is a divisor",
          argerr_msg(() -> Machine(:G, :B, 100.0, 4.0, 2.0, 0.25, 1.05, 0.0,  0.0,   0.0, 1.0)))
    @test occursin("governor lag's denominator",
          argerr_msg(() -> Machine(:G, :B, 100.0, 4.0, 2.0, 0.25, 1.05, 0.0, 0.05,   0.0, 0.0)))
    @test occursin("headroom < 0",
          argerr_msg(() -> Machine(:G, :B, 100.0, 4.0, 2.0, 0.25, 1.05, 0.0, 0.05,  -1.0, 1.0)))
    # …and the ones that must NOT throw: R = Inf is the sanctioned way to say
    # "no governor" and satisfies `R > 0`; zero reserve (Pmax == P0) is legal,
    # only negative reserve is not; and a NEGATIVE P0 with a negative ceiling
    # above it is the aggregated-area case (D4) — an importing area whose net
    # injection is negative still has up-reserve.
    @test Machine(:G, :B, 100.0, 4.0, 2.0, 0.25, 1.05, 0.0, Inf, 0.0, 1.0).R == Inf
    @test Machine(:G, :B, 100.0, 4.0, 2.0, 0.25, 1.05, 10.0, 0.05, 10.0, 1.0).Pmax == 10.0
    @test Machine(:G, :B, 100.0, 4.0, 2.0, 0.25, 1.05, -10.0, 0.05, -4.0, 1.0).Pmax == -4.0
    @test occursin("self-loop", argerr_msg(() -> Branch(:L, :B1, :B1, 0.1, 500.0)))
    @test occursin("denominator", argerr_msg(() -> Branch(:L, :B1, :B2, 0.0, 500.0)))
    @test occursin("rating", argerr_msg(() -> Branch(:L, :B1, :B2, 0.1, 0.0)))
    # NOTE on the H > 0 rejection: zero inertia is a real device, and M1's
    # aggregate model does support it (see the "inverter-based resources
    # (H=0, R=Inf)" testset above). It is rejected *here* only because a
    # zero-inertia vertex carries no differential state, which is a different
    # fidelity tier — not because inverters are unsupported.
end

@testset "network model guards: whole-model invariants" begin
    b(id) = Bus(id, 400.0)
    m(id, bus, P) = Machine(id, bus, 100.0, 4.0, 2.0, 0.20, 1.0, P)
    L(id, f, t) = Branch(id, f, t, 0.50, 500.0)
    buses = [b(:B1), b(:B2)]
    machines = [m(:G1, :B1, 50.0), m(:G2, :B2, -50.0)]
    branches = [L(:L12, :B1, :B2)]
    # the baseline these mutate is itself valid, so each failure below is
    # attributable to the one thing that was changed
    @test NetworkModel(100.0, 50.0, buses, branches, machines) isa NetworkModel

    @test occursin("S_base", argerr_msg(() -> NetworkModel(0.0, 50.0, buses, branches, machines)))
    @test occursin("f0", argerr_msg(() -> NetworkModel(100.0, 0.0, buses, branches, machines)))
    @test occursin("at least one bus", argerr_msg(() -> NetworkModel(100.0, 50.0, Bus[], Branch[], Machine[])))

    @test occursin("duplicate bus", argerr_msg(() ->
        NetworkModel(100.0, 50.0, [b(:B1), b(:B1)], branches, machines)))
    @test occursin("duplicate branch", argerr_msg(() ->
        NetworkModel(100.0, 50.0, buses, [L(:L12, :B1, :B2), L(:L12, :B2, :B1)], machines)))
    @test occursin("duplicate machine", argerr_msg(() ->
        NetworkModel(100.0, 50.0, buses, branches, [m(:G1, :B1, 50.0), m(:G1, :B2, -50.0)])))

    @test occursin("not in the model", argerr_msg(() ->
        NetworkModel(100.0, 50.0, buses, branches, [m(:G1, :B1, 50.0), m(:G2, :B9, -50.0)])))
    @test occursin("not in the model", argerr_msg(() ->
        NetworkModel(100.0, 50.0, buses, [L(:L19, :B1, :B9)], machines)))

    # --- the tier boundary: exactly one machine per bus ---
    @test occursin("two machines", argerr_msg(() ->
        NetworkModel(100.0, 50.0, buses, branches,
                     [m(:G1, :B1, 50.0), m(:G2, :B1, -25.0), m(:G3, :B1, -25.0)])))
    @test occursin("carries no machine", argerr_msg(() ->
        NetworkModel(100.0, 50.0, [b(:B1), b(:B2), b(:B3)],
                     [L(:L12, :B1, :B2), L(:L23, :B2, :B3)], machines)))

    # --- at most one branch per bus pair ---
    # A SimpleGraph silently drops the second edge, so without this guard the
    # second circuit's coupling would vanish with no error at all.
    @test occursin("second circuit", argerr_msg(() ->
        NetworkModel(100.0, 50.0, buses, [L(:L12, :B1, :B2), L(:L12b, :B1, :B2)], machines)))
    # …and it is the *pair* that is rejected, in either orientation.
    @test occursin("second circuit", argerr_msg(() ->
        NetworkModel(100.0, 50.0, buses, [L(:L12, :B1, :B2), L(:L21, :B2, :B1)], machines)))

    # --- one island ---
    @test occursin("not connected", argerr_msg(() ->
        NetworkModel(100.0, 50.0, buses, Branch[], [m(:G1, :B1, 0.0), m(:G2, :B2, 0.0)])))

    # --- lossless network ⇒ Σ P0 = 0 ---
    @test occursin("no equilibrium", argerr_msg(() ->
        NetworkModel(100.0, 50.0, buses, branches, [m(:G1, :B1, 60.0), m(:G2, :B2, -50.0)])))
    # …and the tolerance is tight enough that a 1 MW slip on a 100 MVA base is
    # caught rather than absorbed.
    @test occursin("no equilibrium", argerr_msg(() ->
        NetworkModel(100.0, 50.0, buses, branches, [m(:G1, :B1, 51.0), m(:G2, :B2, -50.0)])))

    # --- injection within reach of the incident coupling ---
    # K here is 1.0·1.0/0.50 = 2.0 pu = 200 MW, so ±250 MW cannot be delivered
    # at any angle: P = K·sin(Δδ) ≤ K.
    @test occursin("exceeds the total", argerr_msg(() ->
        NetworkModel(100.0, 50.0, buses, branches, [m(:G1, :B1, 250.0), m(:G2, :B2, -250.0)])))
    # …but 199 MW, just under the ceiling, is accepted — the guard rules out
    # the impossible, it does not quietly narrow the model's range.
    @test NetworkModel(100.0, 50.0, buses, branches,
                       [m(:G1, :B1, 199.0), m(:G2, :B2, -199.0)]) isa NetworkModel
end


# --- M2 step 3/4: the SwingEngine ------------------------------------------
#
# Scope note: `find_fixpoint`-based initialization and its two acceptance
# criteria (V1 flat start, V2 injection/sign convention) live here rather than
# in a later batch, because the engine cannot be smoke-tested at all without a
# start state — a model placed off-equilibrium rings from t = 0 and produces a
# plausible oscillation that is pure artifact. V3 (the *running* engine hitting
# the closed-form swing frequency) is the separate step-4 test.

@testset "SwingEngine: conformance to the SimulationEngine contract" begin
    # M1 had one engine, so `interface.jl` had never been asked to hold a
    # second. It needed **no changes** — recorded here as an assertion rather
    # than a claim in a document. Every verb resolves on the new engine, and
    # `init!` dispatches on the type exactly as M1's does.
    net = two_machine_system()
    @test SwingEngine <: SimulationEngine
    eng = init!(SwingEngine, net)
    @test eng isa SwingEngine
    for verb in (current_state, state_series, timestep)
        @test hasmethod(verb, Tuple{SwingEngine})
    end
    @test hasmethod(step!, Tuple{SwingEngine})
    @test hasmethod(inject!, Tuple{SwingEngine,TripGenerator})
    @test hasmethod(init!, Tuple{Type{SwingEngine},NetworkModel})
    # The one place the abstraction *does* strain: `state_series` returns a
    # different set of channels per engine. Both are NamedTuples of equal-length
    # named series — the contract interface.jl actually states — so a consumer
    # that reads by name works against either, but one that assumes a fixed set
    # of channels does not. Written down as a finding in m2-context.md.
    m1 = init!(FrequencyResponseEngine, example_system())
    @test propertynames(state_series(m1)) != propertynames(state_series(eng))
    @test first(propertynames(state_series(m1))) === :t          # ...but both
    @test first(propertynames(state_series(eng))) === :t         # lead with time
    # Shared-mutable-parameter identity, inherited from NetworkDynamics rather
    # than assumed: this is what lets an event change the system without
    # disturbing the continuous state.
    @test eng.params === eng.integrator.p
    @test NetworkDynamics.pflat(NetworkDynamics.NWParameter(eng.integrator)) === eng.integrator.p
end

@testset "SwingEngine V1: flat start, and it stays flat" begin
    # Acceptance criterion, not a nicety (m2-plan.md "Validation").
    for net in (two_machine_system(), three_machine_ring())
        eng = init!(SwingEngine, net; dt = 0.02)
        du = similar(eng.integrator.u)
        eng.nw(du, eng.integrator.u, eng.params, 0.0)
        @test maximum(abs, du) < 1e-10
        s0 = current_state(eng)
        # At rest to the fixpoint solver's own precision — not exactly zero,
        # because ω is solved for rather than assigned, and it lands ~1e-28.
        @test maximum(abs, s0.ω) < 1e-20
        @test abs(s0.ω_coi) < 1e-20
        @test s0.f_coi ≈ net.f0 atol = 1e-12
        # A 2 s pre-disturbance window must not drift or ring.
        for _ in 1:100; step!(eng, 0.02); end
        s = current_state(eng)
        @test maximum(abs, s.δ .- s0.δ) < 1e-9
        @test maximum(abs, s.ω) < 1e-9
        @test s.f_coi ≈ net.f0 atol = 1e-9
    end
end

@testset "SwingEngine V2: injections reproduce (the sign-convention test)" begin
    # A flipped coupling sign still oscillates, still settles, still has a
    # nadir — this is the test that catches it. `Pe` is recomputed here from
    # the *model's* couplings, independently of what the engine handed
    # NetworkDynamics.
    for net in (two_machine_system(), three_machine_ring())
        eng = init!(SwingEngine, net)
        δ = current_state(eng).δ
        ma, ba = machine_arrays(net), branch_arrays(net)
        for i in eachindex(ma.Pm)
            Pe = 0.0
            for e in eachindex(ba.K)
                ba.src[e] == i && (Pe += ba.K[e] * sin(δ[i] - δ[ba.dst[e]]))
                ba.dst[e] == i && (Pe += ba.K[e] * sin(δ[i] - δ[ba.src[e]]))
            end
            @test Pe ≈ ma.Pm[i] atol = 1e-8      # generation == export
        end
    end
end

@testset "SwingEngine V3: the running engine hits the closed-form swing frequency" begin
    # Step 2 pinned the *prediction* through the real code path; this is where
    # the running engine has to produce it. Excitation is a small displacement
    # of one rotor angle from the fixpoint — not a trip, because a trip removes
    # the equilibrium the oscillation would be about (see swing.jl's header).
    net = two_machine_system()
    ma, ba = machine_arrays(net), branch_arrays(net)
    K, P = ba.K[1], ma.Pm[1]
    δ₀ = asin(P / K)
    ω₀ = 2π * net.f0
    f_pred = sqrt(ω₀ * K * cos(δ₀) * (1 / (2ma.H[1]) + 1 / (2ma.H[2]))) / 2π
    @test f_pred ≈ 1.5911075 atol = 1e-6            # the number step 2 pinned

    eng = init!(SwingEngine, net; dt = 0.002)
    eng.integrator.u[eng.δ_idx[1]] += 0.01          # 10 mrad, small-signal
    SciMLBase.derivative_discontinuity!(eng.integrator, true)
    ts, ys = Float64[], Float64[]
    for _ in 1:6000                                  # 12 s, finite by construction
        s = step!(eng, 0.002)
        push!(ts, s.t)
        push!(ys, (s.δ[1] - s.δ[2]) - δ₀)
    end
    # Period from linearly-interpolated upward zero crossings, averaged over
    # every cycle in the window — not from a peak index, which would quantise
    # the answer to the step size.
    cross = Float64[]
    for i in 2:length(ys)
        ys[i-1] < 0 <= ys[i] &&
            push!(cross, ts[i-1] + (ts[i] - ts[i-1]) * (-ys[i-1]) / (ys[i] - ys[i-1]))
    end
    @test length(cross) >= 15                        # a long enough window to average
    f_meas = (length(cross) - 1) / (cross[end] - cross[1])
    @test f_meas ≈ f_pred atol = 5e-4

    # The residual is understood, not slop: the closed form is the *undamped*
    # natural frequency, and this system has D > 0, so the measured frequency
    # must come out slightly LOW — by the ~1e-4 Hz that a damping ratio of
    # about 0.012 implies, and no more.
    @test f_meas < f_pred
    @test f_pred - f_meas < 2.0e-4
    # It is genuinely a damped oscillation about the fixpoint, not a drift:
    # the envelope decays and the swing stays centred.
    @test maximum(abs, @view ys[end-500:end]) < 0.5 * maximum(abs, @view ys[1:500])
    # Centred on the fixpoint, not riding an offset: averaged over a WHOLE
    # number of the last cycles (delimited by the crossing times, so the
    # oscillation itself cancels) the residual is ~1% of the local amplitude.
    i1 = findlast(t -> t <= cross[end-4], ts)
    i2 = findlast(t -> t <= cross[end], ts)
    local_amp = maximum(abs, @view ys[i1:i2])
    @test abs(sum(@view ys[i1:i2]) / (i2 - i1 + 1)) < 0.05 * local_amp

    # Discriminating power, stated rather than assumed: three ways of getting
    # this formula wrong all land outside the tolerance above. (Dropping cos δ₀
    # is the near miss — 8e-3 Hz — which is why the tolerance is 5e-4 and not
    # something comfortable.)
    no_cos    = sqrt(ω₀ * K * (1 / (2ma.H[1]) + 1 / (2ma.H[2]))) / 2π
    coi_H     = sqrt(ω₀ * K * cos(δ₀) / (2 * (ma.H[1] + ma.H[2]))) / 2π
    one_machine = sqrt(ω₀ * K * cos(δ₀) / (2ma.H[1])) / 2π
    for wrong in (no_cos, coi_H, one_machine)
        @test abs(f_meas - wrong) > 5e-4
    end
end

@testset "SwingEngine: angles are gauge-dependent, differences are not" begin
    # Shift every δ by a constant and it is still an equilibrium, so
    # `find_fixpoint` returns an arbitrary gauge — on the ring it happens to
    # land near 2.1 rad, nowhere near zero. Only differences may be asserted.
    net = two_machine_system()
    eng = init!(SwingEngine, net)
    ma, ba = machine_arrays(net), branch_arrays(net)
    δ = current_state(eng).δ
    # The static half of the closed form pinned in step 2: δ₀ = asin(P/K).
    @test δ[1] - δ[2] ≈ asin(ma.Pm[1] / ba.K[1]) atol = 1e-9
    @test δ[1] - δ[2] ≈ 0.1405180 atol = 1e-6
    # The symmetry itself, asserted rather than assumed: shift every angle by
    # the same constant and the residual is still zero. That is *why* absolute
    # angles carry no information — and it is a property of the model, not of
    # wherever this particular solver run happened to land.
    ring = init!(SwingEngine, three_machine_ring())
    u = copy(ring.integrator.u)
    for i in ring.δ_idx; u[i] += 0.7; end
    du = similar(u); ring.nw(du, u, ring.params, 0.0)
    @test maximum(abs, du) < 1e-10
    # The ring has no closed form (that is why it is the second system), so its
    # angle differences are pinned as a regression value, not derived.
    δr = current_state(ring).δ
    @test δr[2] - δr[1] ≈ -0.0378207 atol = 1e-6
    @test δr[3] - δr[1] ≈ -0.1462231 atol = 1e-6
end

@testset "SwingEngine: branch↦edge mapping (what V2 provably cannot catch)" begin
    # `Graphs.SimpleGraph` iterates edges in sorted (src,dst) order, not in the
    # order branches were added, and NetworkDynamics indexes edge parameters by
    # position in that list. V2 cannot catch a permutation here: `find_fixpoint`
    # converges on whatever self-consistent (wrong) network it is handed, and
    # `Pe` recomputed from the same wrong couplings still equals `Pm`. So the
    # mapping gets its own direct assertion.
    net = three_machine_ring()
    eng = init!(SwingEngine, net)
    ba = branch_arrays(net)
    nb = length(net.buses)
    g = Graphs.SimpleGraph(nb)
    for e in eachindex(ba.src); Graphs.add_edge!(g, ba.src[e], ba.dst[e]); end
    edge_pairs = [(Graphs.src(e), Graphs.dst(e)) for e in Graphs.edges(g)]

    # 1. The hazard is real on this system: branch order and edge order differ,
    #    so a "branch k ↦ edge k" implementation would mis-assign two of three.
    @test edge_pairs == [(1, 2), (1, 3), (2, 3)]
    @test [minmax(ba.src[e], ba.dst[e]) for e in eachindex(ba.src)] !=
          [minmax(p...) for p in edge_pairs]
    @test eng.branch_to_edge == [1, 3, 2]        # explicitly not the identity

    # 2. It is a permutation — this is what catches two branches collapsing
    #    onto one edge, which a bus-pair keying can otherwise do silently.
    @test sort(eng.branch_to_edge) == collect(1:length(ba.K))

    # 3. Each edge actually holds the coupling of the branch joining its two
    #    buses. The ring's three couplings are all distinct, so this bites.
    held = [eng.params[i] for i in eng.K_pidx]
    @test length(unique(round.(ba.K; digits = 6))) == 3    # distinct ⇒ detectable
    for (bi, ei) in pairs(eng.branch_to_edge)
        @test held[ei] ≈ ba.K[bi] atol = 1e-12
        @test minmax(ba.src[bi], ba.dst[bi]) == minmax(edge_pairs[ei]...)
    end
    # And in edge order the held couplings are a genuine reordering of the
    # branch-order ones — the assertion that would fail under the naive map.
    @test held != ba.K
    @test sort(held) ≈ sort(ba.K)
end

@testset "SwingEngine: flat indices come from the symbolic interface" begin
    # The engine never assumes a memory layout; it resolves flat positions
    # through NetworkDynamics' symbolic indexing once, at construction. If that
    # upstream layout ever moves, this test says so rather than the physics
    # going quietly wrong.
    net = three_machine_ring()
    eng = init!(SwingEngine, net)
    s = NetworkDynamics.NWState(eng.integrator)
    u = eng.integrator.u
    for i in 1:length(net.buses)
        @test u[eng.δ_idx[i]] == s.v[i, :δ]
        @test u[eng.ω_idx[i]] == s.v[i, :ω]
        @test eng.params[eng.Pm_pidx[i]] == s.p.v[i, :Pm]
    end
    @test allunique(vcat(eng.δ_idx, eng.ω_idx))
    @test allunique(vcat(eng.Pm_pidx, eng.K_pidx))
end

@testset "SwingEngine: per-machine speed is not the aggregate" begin
    # `ωᵢ` (one machine's per-unit deviation) and `ω_coi` (the inertia-weighted
    # mean) are different quantities under different names — the confusion
    # m2-plan.md flags. Assert that they are genuinely different numbers during
    # a transient, and that the aggregate is the weighted mean it claims to be.
    net = three_machine_ring()
    eng = init!(SwingEngine, net; dt = 0.01)
    inject!(eng, TripGenerator(:G2))
    spread_seen = false
    for _ in 1:500
        s = step!(eng, 0.01)
        H = eng.w                                   # 0 for the tripped machine
        @test s.ω_coi ≈ sum(H .* s.ω) / sum(H) atol = 1e-12
        maximum(s.ω) - minimum(s.ω) > 1e-4 && (spread_seen = true)
    end
    # The machines really do swing against each other — otherwise the equality
    # above would hold trivially and prove nothing.
    @test spread_seen
end

@testset "SwingEngine: a trip zeroes coupling without resizing the state" begin
    net = three_machine_ring()
    eng = init!(SwingEngine, net; dt = 0.01)
    n_state = length(eng.integrator.u)
    H_before = system_inertia(eng)
    @test all(id -> is_online(eng, id), machine_ids(eng))

    v = findfirst(==(:G1), machine_ids(eng))
    inject!(eng, TripGenerator(:G1))
    @test length(eng.integrator.u) == n_state       # never resized
    @test !is_online(eng, :G1)
    @test eng.params[eng.Pm_pidx[v]] == 0.0
    @test all(e -> eng.params[eng.K_pidx[e]] == 0.0, eng.incident[v])
    # …and only the incident branches: on a 3-ring G1 touches two of three.
    @test count(i -> eng.params[i] == 0.0, eng.K_pidx) == 2
    @test system_inertia(eng) < H_before
    @test system_inertia(eng) ≈ H_before - machine_arrays(net).H[v] atol = 1e-12

    # Tripping again is a no-op; tripping a machine that does not exist is a
    # caller bug, and the lookup happens first so the error is reachable.
    @test inject!(eng, TripGenerator(:G1)) === eng
    @test_throws KeyError inject!(eng, TripGenerator(:NOPE))

    # Post-trip there is NO equilibrium (no governors, so ΣPm ≠ 0 now): speed
    # falls until damping balances the shortfall. Assert that limit rather than
    # any absolute angle, which drifts forever by design.
    for _ in 1:4000; step!(eng, 0.01); end
    ma = machine_arrays(net)
    others = [i for i in eachindex(ma.Pm) if i != v]
    @test current_state(eng).ω_coi ≈ sum(ma.Pm[others]) / sum(ma.D[others]) atol = 1e-4
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    # The tripped machine keeps integrating harmlessly — undriven and decoupled,
    # it damps to rest — and is excluded from the aggregate read-out.
    @test abs(current_state(eng).ω[v]) < 1e-6
    @test eng.w[v] == 0.0
end
