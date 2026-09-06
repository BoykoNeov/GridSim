# M3 steps 1-5 - the governor state, primary response, the machine-bound shed
# ladder, the out-of-step tie relay, and generation lost as a ramp.
#
# This file sits BETWEEN the two halves of M2 because that is where these testsets
# ran before the split: M3 inserted them ahead of M2's own tail (89c7074). The
# order is preserved deliberately - see runtests.jl.


# ---- M3 step 1: the governor state ------------------------------------------
# Full validation of primary response is step 2 (V1–V4). What lives here is the
# narrow set of claims about the *state-layout change itself* — that M2's models
# still describe the systems they described, and that the one new failure mode
# the change creates is closed. `governed_ring` is local to these testsets, not
# a shipped fixture: step 1 deliberately adds no scenario.

@testset "M3 step 1: a governor-free machine is still governor-free" begin
    # The defaulted constructor arguments are what let every M2 call site keep
    # working, so the thing to assert is that what they build is the machine it
    # always was — not merely that the code compiles.
    for net in (two_machine_system(), three_machine_ring())
        @test all(m -> m.R == Inf, net.machines)
        @test all(m -> m.Pmax == m.P0, net.machines)      # zero headroom
        @test all(m -> m.Tg > 0, net.machines)            # validated even when unread
        ma = machine_arrays(net)
        @test all(iszero, ma.invR) && all(iszero, ma.headroom)

        # And the state stays at zero through a real disturbance, which is the
        # claim that matters: `dΔPm/dt = (−ω·0 − ΔPm)/Tg` never leaves a zero
        # start. The bound is the fixpoint solver's own precision and not exact
        # zero, for the same reason V1 bounds `ω` that way rather than asserting
        # `== 0`: the start is SOLVED for, not assigned. Twenty seconds of a real
        # frequency collapse must not grow it by a single order of magnitude —
        # which is what "droop leaked in" would look like.
        eng = init!(SwingEngine, net; dt = 0.01)
        @test maximum(abs, current_state(eng).ΔPm) < 1e-20
        inject!(eng, TripGenerator(first(machine_ids(eng))))
        for _ in 1:2000; step!(eng, 0.01); end             # 20 s, finite by construction
        @test maximum(abs, current_state(eng).ΔPm) < 1e-20
        @test current_state(eng).f_coi < net.f0 - 1.0      # …and it really did collapse
        @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    end
end

@testset "M3 step 1: the third state is a control state, not a new tier" begin
    net = governed_ring()
    eng = init!(SwingEngine, net; dt = 0.02)
    nb = length(net.buses)
    s = NetworkDynamics.NWState(eng.integrator)
    u = eng.integrator.u
    # Resolved symbolically like every other index — nothing assumes a stride.
    for i in 1:nb
        @test u[eng.ΔPm_idx[i]] == s.v[i, :ΔPm]
        @test eng.params[eng.invR_pidx[i]] == s.p.v[i, :invR]
        @test eng.params[eng.hr_pidx[i]] == s.p.v[i, :headroom]
    end
    @test allunique(vcat(eng.δ_idx, eng.ω_idx, eng.ΔPm_idx))
    @test allunique(vcat(eng.Pm_pidx, eng.K_pidx, eng.invR_pidx, eng.hr_pidx))

    # The electrical tier is untouched: the vertex still exports its ANGLE to the
    # network and nothing else. If `ΔPm` ever reached an edge, the coupling would
    # stop being `K·sin(Δδ)` and this would no longer be the classical tier.
    @test NetworkDynamics.outsym(eng.nw[NetworkDynamics.VIndex(1)]) == [:δ]

    # Flat start survives the extra state — the acceptance criterion, re-checked
    # on a GOVERNED model because that is where the fixpoint solve is new.
    du = similar(u); eng.nw(du, u, eng.params, 0.0)
    @test maximum(abs, du) < 1e-10
    @test maximum(abs, current_state(eng).ΔPm) < 1e-20
    @test current_state(eng).f_coi ≈ net.f0 atol = 1e-12
end

@testset "M3 step 1: headroom saturates in the derivative, and releases" begin
    # The M1 landmine, re-stated per machine. Give G2 5 MW of reserve — far less
    # than droop would command after losing G1 — and it must stop AT the ceiling,
    # not above it, with the integration never rejected into a stall.
    # G3 gets a deliberately large reserve so that "G2 is on its ceiling and G3
    # is not" is a statement about per-machine saturation. With the shipped 60 MW
    # G3 hits its own ceiling too — a pooled-reserve reading would call that a
    # pass, which is exactly the conflation the per-machine ceiling exists to
    # prevent.
    net = governed_ring(; hr2 = 5.0, hr3 = 300.0)
    ma = machine_arrays(net)
    eng = init!(SwingEngine, net; dt = 0.01)
    inject!(eng, TripGenerator(:G1))
    for _ in 1:20000; step!(eng, 0.01); end              # 200 s, finite by construction
    s = current_state(eng)
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    @test s.ΔPm[2] ≈ ma.headroom[2] atol = 1e-9
    # Above the ceiling only by adaptive-step roundoff, inside the guard's own
    # slack — which is why the guard never fires and never collapses the step.
    @test s.ΔPm[2] - ma.headroom[2] < 1e-10
    # G3 has ample reserve and is NOT on its ceiling: the saturation is per
    # machine, not a pooled system limit.
    @test s.ΔPm[3] < ma.headroom[3] - 0.05

    # The predicate itself: it must ignore δ and ω entirely. Post-trip the angles
    # drift forever by design, so a predicate that grew a δ term would reject
    # every step of a correct run — and would look like "the solver got slow",
    # not like a failure. Asserted directly against a large drifted angle.
    pred = GridSim._swing_outofdomain(eng.ΔPm_idx, eng.hr_pidx)
    u = copy(eng.integrator.u)
    @test !pred(u, eng.params, 0.0)                       # the real, saturated state
    for i in eachindex(eng.δ_idx)
        u[eng.δ_idx[i]] = 1.0e6                           # a wildly drifted rotor angle
        u[eng.ω_idx[i]] = -0.5                            # and a speed nowhere near nominal
    end
    @test !pred(u, eng.params, 0.0)
    # …and it does fire on the one thing it is for.
    u[eng.ΔPm_idx[2]] = eng.params[eng.hr_pidx[2]] + 1e-6
    @test pred(u, eng.params, 0.0)
end

@testset "M3 step 1: zero reserve with a real governor is a legal machine" begin
    # `Pmax == P0` with FINITE `R` is explicitly legal (m3-context.md D4: zero
    # reserve is legal, negative is not) and it is the one configuration where
    # the saturation branch is live AT the equilibrium — `ΔPm >= headroom` is
    # `0 >= 0`, i.e. true, on the very state `find_fixpoint` is solving for. If
    # that ever gave the solve a zero row it would be a step-6 landmine, since
    # a sweep cell setting an area's reserve to zero is an obvious thing to try.
    # So it is initialised here rather than only constructed.
    net = governed_ring(; hr2 = 0.0)
    @test machine_arrays(net).headroom[2] == 0.0
    @test machine_arrays(net).invR[2] > 0            # …and it does have a governor
    eng = init!(SwingEngine, net; dt = 0.01)
    du = similar(eng.integrator.u)
    eng.nw(du, eng.integrator.u, eng.params, 0.0)
    @test maximum(abs, du) < 1e-10                   # flat start survives it
    @test current_state(eng).f_coi ≈ net.f0 atol = 1e-12

    # And it holds at exactly zero while droop is commanding it upward — the
    # ceiling binds from the first instant rather than after a ramp.
    inject!(eng, TripGenerator(:G1))
    for _ in 1:5000; step!(eng, 0.01); end           # 50 s, finite by construction
    s = current_state(eng)
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    @test s.ΔPm[2] == 0.0                            # pinned, exactly
    @test s.f_coi < net.f0 - 0.2                     # …with a real deficit to answer
    @test s.ΔPm[3] > 0.1                             # …that the machine with reserve took
end

@testset "M3 step 1: the guard is attached, not merely defined" begin
    # Every other test here would pass with `isoutofdomain` deleted from the
    # `init` call: the predicate tests construct the predicate themselves, the
    # saturation bound is met by the DERIVATIVE saturation alone, and the trip
    # hazard is closed by `inject!`'s re-seat rather than by the guard. If no
    # test would fail, write one — this file's own V5 rule.
    #
    # So: strand `ΔPm` above its ceiling by moving the ceiling directly, which
    # is precisely the state a trip would leave behind if the re-seat were
    # missing. With the guard attached every proposed step is out of domain and
    # the integration aborts; without it the run continues (the derivative
    # saturation simply parks `ΔPm` where it is). The abort is the assertion.
    eng = init!(SwingEngine, governed_ring(); dt = 0.01)
    inject!(eng, TripGenerator(:G1))
    for _ in 1:1000; step!(eng, 0.01); end           # 10 s: the governor ramps up
    stranded = current_state(eng).ΔPm[2]
    @test stranded > 0.1                             # not a vacuous setup
    eng.params[eng.hr_pidx[2]] = 0.0                 # ceiling drops below the state
    @test_throws ErrorException begin
        for _ in 1:200; step!(eng, 0.01); end        # 2 s, finite by construction
    end
    # It aborted where the guard says it should, not by drifting off somewhere.
    @test !SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    @test current_state(eng).t < 12.1
    # This is the mirror of the re-seat test above, and both are worth having:
    # that one proves `inject!`'s re-seat is load-bearing, this one proves the
    # guard it protects against is actually installed.
end

@testset "M3 step 1: a trip that shrinks the ceiling does not freeze the solver" begin
    # The failure mode the state-layout change creates, and the reason `inject!`
    # re-seats `ΔPm` at the event boundary. A trip zeroes that machine's headroom
    # while its `ΔPm` is above zero; without the re-seat every proposed step is
    # out of domain, `dt` collapses, and the run aborts. M1 has this exact test
    # ("second trip after saturation does not freeze the integrator") — this is
    # its multi-machine counterpart, and it lives beside the code that creates
    # the hazard rather than waiting for the validation step.
    eng = init!(SwingEngine, governed_ring(); dt = 0.01)
    inject!(eng, TripGenerator(:G1))
    for _ in 1:1000; step!(eng, 0.01); end                # 10 s: G2's governor ramps up
    before = current_state(eng).ΔPm[2]
    @test before > 0.1                                    # not a vacuous test
    @test eng.params[eng.hr_pidx[2]] > before             # …and it is below its ceiling

    inject!(eng, TripGenerator(:G2))
    @test eng.params[eng.invR_pidx[2]] == 0.0             # the governor left with it
    @test eng.params[eng.hr_pidx[2]] == 0.0
    @test eng.integrator.u[eng.ΔPm_idx[2]] == 0.0         # …re-seated, not stranded
    # A tripped machine produces NOTHING, not merely nothing extra: `Pm` and
    # `ΔPm` go to zero together.
    @test eng.params[eng.Pm_pidx[2]] == 0.0

    for _ in 1:2000; step!(eng, 0.01); end                # 20 s past the second trip
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    @test current_state(eng).t ≈ 30.0 atol = 1e-6         # it really did advance
    @test current_state(eng).ΔPm[2] == 0.0                # and stays put, undriven
    # The survivor picks the deficit up — the run is a real disturbance, not a
    # frozen state that trivially satisfies the assertions above.
    @test current_state(eng).ΔPm[3] > 0.1
end

# ---------------------------------------------------------------------
# M3 step 2 — VALIDATION OF PRIMARY RESPONSE (V1–V4, m3-plan.md).
#
# No new mechanism and no `src/` change: step 1 built the governor state,
# this is what it is asserted to *do*. Fixtures stay local for the same
# reason step 1's did — step 2 ships no scenario either.
# ---------------------------------------------------------------------

@testset "M3 step 2 V1: governor-free is invariant to every governor parameter" begin
    # M2's closed forms are already asserted against the running engine
    # ("two-machine closed form" and "SwingEngine V3" above), and they are
    # asserted against DERIVED numbers — `K = 4.284`, `δ₀ = 0.140518`,
    # `f_osc = 1.5911075` — precisely so that step 1's re-pinning could not
    # define its own success. (Step 1 then measured that the re-pin was not
    # needed at all; the discipline still stands, because the baseline COULD
    # have moved and the check must not depend on it having not.)
    #
    # What is NOT yet asserted, and is the non-redundant half of V1: with
    # `R = Inf` those numbers are invariant to every *governor* parameter.
    # `Tg` and `Pmax` are now read by the fixpoint solve and by the RHS, so
    # "they cannot matter" is a claim about the code, not a tautology.
    twomach(; Tg = 1.0, extra_hr = 0.0) = NetworkModel(100.0, 50.0,
        [Bus(:B1, 400.0), Bus(:B2, 400.0)],
        [Branch(:L12, :B1, :B2, 0.25, 500.0)],
        [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05,  60.0, Inf,  60.0 + extra_hr, Tg),
         Machine(:G2, :B2, 400.0, 5.0, 2.0, 0.30, 1.02, -60.0, Inf, -60.0 + extra_hr, Tg)])

    # The same small-signal excitation "SwingEngine V3" uses, reduced to the
    # gauge-free trace and the largest `|ΔPm|` seen anywhere in the window.
    function swingrun(net)
        eng = init!(SwingEngine, net; dt = 0.002)
        eng.integrator.u[eng.δ_idx[1]] += 0.01          # 10 mrad, small-signal
        SciMLBase.derivative_discontinuity!(eng.integrator, true)
        ys, mx = Float64[], 0.0
        for _ in 1:6000                                  # 12 s, finite by construction
            s = step!(eng, 0.002)
            push!(ys, s.δ[1] - s.δ[2])
            mx = max(mx, maximum(abs, s.ΔPm))
        end
        return ys, mx, eng.integrator.stats.nreject
    end

    base, base_mx, base_nrej = swingrun(two_machine_system())
    @test base_mx < 1e-20                    # the third state is inert, as V1 needs
    @test base_nrej == 0
    # The closed form, on this very trace — so the invariance below is an
    # invariance of something already known to be right, not of an artefact.
    δ₀ = asin(machine_arrays(two_machine_system()).Pm[1] /
              branch_arrays(two_machine_system()).K[1])
    @test δ₀ ≈ 0.1405180 atol = 1e-6

    # `Tg` over three decades and headroom from zero to 500 MW. Note the two
    # headroom variants take DIFFERENT branches of the saturation: at the
    # equilibrium `ΔPm >= headroom` is `0 >= 0` (true, saturated) when
    # `Pmax == P0` and false when there is reserve. They agree only because the
    # droop command is identically zero, so `min(0, 0) == 0` either way — worth
    # saying, or the agreement reads as an untested coincidence.
    for (Tg, extra_hr) in ((0.1, 0.0), (100.0, 0.0), (1.0, 500.0), (0.1, 500.0))
        ys, mx, nrej = swingrun(twomach(; Tg, extra_hr))
        @test mx < 1e-20                                  # still inert
        @test nrej == 0
        # Measured: three of the four are BIT-identical to the shipped fixture;
        # `Tg = 100` differs by 6.4e-16 — about 4 ulp on a 0.14 rad quantity.
        @test maximum(abs, ys .- base) < 1e-14
    end

    # And that 6.4e-16 is not `Tg` doing something. What actually differs
    # between those four models at `t = 0` is the fixpoint's ARBITRARY GAUGE:
    # the absolute angles land up to 0.11 rad apart while the difference
    # `δ₁ − δ₂` is bit-identical in all four. Shifting only the gauge, on ONE
    # model with `Tg` held fixed, reproduces the residual — which is step 1's
    # D1 finding again, in a second place.
    function gauge_shifted(shift)
        eng = init!(SwingEngine, two_machine_system(); dt = 0.002)
        for i in eng.δ_idx; eng.integrator.u[i] += shift; end
        eng.integrator.u[eng.δ_idx[1]] += 0.01
        SciMLBase.derivative_discontinuity!(eng.integrator, true)
        ys = Float64[]
        for _ in 1:6000
            s = step!(eng, 0.002)
            push!(ys, s.δ[1] - s.δ[2])
        end
        return ys
    end
    @test gauge_shifted(0.0018) == base                   # a small shift: bit-identical
    # A shift the size of the Tg=100 model's gauge offset reproduces the
    # residual, in the same order of magnitude and with no governor involved.
    big = maximum(abs, gauge_shifted(0.108) .- base)
    @test 1e-16 < big < 1e-14
end

@testset "M3 step 2 V2: droop settles on the closed form, on the running engine" begin
    # THE DENOMINATOR IS THE FINDING (m3-context.md D11). `m3-plan.md` states
    # V2 as M1's `Δω = −ΔP/(1/R_eq + D)`, where `D` is ONE system-wide load
    # damping that a trip does not change. On the network tier `D` is per
    # machine and attached to a rotor, so "which machines are in the sum?" is a
    # real question with two plausible answers — and they differ by 3.75 % here,
    # which is far too big to hide inside a tolerance.
    #
    # The answer is SURVIVORS ONLY, and the reason is not that `inject!` zeroes
    # the dead machine's `D` (it does not — `D` is not even a mutable parameter).
    # It is that `inject!` zeroes the coupling of every branch incident to that
    # bus, which electrically ISLANDS the dead rotor: it can draw nothing from
    # the survivors to feed its own damping. So summing the antisymmetric edge
    # terms over the survivors alone still gives zero, and the balance closes
    # over the survivors alone.
    net = governed_ring(; hr2 = 5000.0, hr3 = 5000.0)   # see the headroom note below
    ma = machine_arrays(net)
    surv = [2, 3]                                        # G1 is the one tripped
    ω_ss    = sum(ma.Pm[surv]) / (sum(ma.invR[surv]) + sum(ma.D[surv]))
    ω_all_D = sum(ma.Pm[surv]) / (sum(ma.invR[surv]) + sum(ma.D))       # the wrong one
    ω_no_R  = sum(ma.Pm[surv]) / sum(ma.D[surv])            # no governors at all (M2)
    ω_no_D  = sum(ma.Pm[surv]) / sum(ma.invR[surv])         # droop alone, no damping
    @test ω_ss ≈ -0.8 / 154 atol = 1e-15

    eng = init!(SwingEngine, net; dt = 0.01)
    inject!(eng, TripGenerator(:G1))
    peak = zeros(3)
    for _ in 1:15000                                     # 150 s, finite by construction
        s = step!(eng, 0.01)
        for i in 1:3; peak[i] = max(peak[i], s.ΔPm[i]); end
    end
    s = current_state(eng)
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)

    # THE PRECONDITION, ASSERTED RATHER THAN ASSUMED: no machine touched its
    # ceiling at any point in the run. The binding constraint is the PEAK
    # command during the dip, not the settled one — measured peaks are 0.284 and
    # 0.712 pu against settled 0.208 and 0.519, which is why the fixture carries
    # 50 pu of reserve rather than the shipped `governed_ring` defaults (step 1's
    # own saturation test records that 60 MW puts G3 on its ceiling). Without
    # this the closed form could be asserted straight through a saturated
    # transient and would mean much less than it looks like it means.
    @test peak[2] < 0.5 * ma.headroom[2]
    @test peak[3] < 0.5 * ma.headroom[3]
    @test peak[2] > 0.25 && peak[3] > 0.6                # …and it was a real excursion

    # The settling speed. Measured relative error at 150 s: 8.7e-14.
    @test s.ω_coi ≈ ω_ss rtol = 1e-9
    # Every machine is at the SAME speed — the common drift the tier predicts,
    # not an average over two machines doing different things.
    @test s.ω[2] ≈ ω_ss rtol = 1e-9
    @test s.ω[3] ≈ ω_ss rtol = 1e-9

    # Discriminating power, by name. All three near misses are physically
    # plausible readings of the same sentence and all three land far outside.
    for wrong in (ω_all_D, ω_no_R, ω_no_D)
        @test abs(s.ω_coi - wrong) > 1e-4                # ≥ 3.75 % of ω_ss
    end

    # Mechanical power rises by exactly `−Δω/R`, per machine. This is the half
    # of V2 that pins the GAIN conversion (`machine_arrays` weights `1/R` by the
    # MVA ratio) all the way through to a running trajectory.
    @test s.ΔPm[2] ≈ -ω_ss * ma.invR[2] atol = 1e-9
    @test s.ΔPm[3] ≈ -ω_ss * ma.invR[3] atol = 1e-9
    @test s.ΔPm[1] == 0.0                                # the tripped machine: re-seated
    # Not an aggregate read-out: G3 supplies 2.5× what G2 does, because its
    # gain is 2.5× larger. A pooled figure would have hidden that.
    @test s.ΔPm[3] / s.ΔPm[2] ≈ ma.invR[3] / ma.invR[2] rtol = 1e-6

    # It never came close to stalling: the guard is attached and rejected
    # nothing over 15,000 steps (measured: 0 rejections, one accepted step per
    # `dt`), which is what "governors are acting and the solver is fine" looks
    # like from outside.
    @test eng.integrator.stats.nreject == 0
end

@testset "M3 step 2 V3: angle differences settle, the common mode does not" begin
    # The tested form of the correction `m3-plan.md` is written against:
    # droop does NOT give a post-trip equilibrium. `Δω` settles at a NON-zero
    # value, so `dδ/dt = ω₀·Δω` is non-zero forever and every absolute angle
    # grows without bound — while the DIFFERENCES between synchronised machines
    # stop moving. Both halves are asserted here, because asserting only the
    # first would also pass on a model that had quietly reached a fixpoint.
    net = governed_ring(; hr2 = 5000.0, hr3 = 5000.0)
    ma = machine_arrays(net)
    ω_ss = sum(ma.Pm[2:3]) / (sum(ma.invR[2:3]) + sum(ma.D[2:3]))
    ω₀ = 2π * net.f0

    eng = init!(SwingEngine, net; dt = 0.01)
    inject!(eng, TripGenerator(:G1))
    for _ in 1:14000; step!(eng, 0.01); end              # 140 s, finite by construction
    a = current_state(eng)
    for _ in 1:1000; step!(eng, 0.01); end               # …plus a 10 s measuring window
    b = current_state(eng)
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    Δt = b.t - a.t

    # The common mode: `δ_coi` (over ONLINE machines) drifts at exactly `ω₀·Δω`.
    # Measured as a finite difference over a whole 10 s window, not from one
    # sample. Measured relative error: 1.0e-13.
    drift = (b.δ_coi - a.δ_coi) / Δt
    @test drift ≈ ω₀ * ω_ss rtol = 1e-6
    @test drift < -1.6                                   # …and it is a real drift
    # Over 140 s that has taken the absolute angles a long way from anywhere a
    # fixpoint solver could have put them — which is the standing "never call
    # `find_fixpoint` post-trip, never assert on an absolute angle" rule, shown.
    @test abs(b.δ_coi) > 100.0

    # The synchronised pair: the difference between the two machines that are
    # still coupled has stopped moving. Measured rate: 1.5e-13 rad/s.
    d23 = (b.δ[2] - b.δ[3]) - (a.δ[2] - a.δ[3])
    @test abs(d23 / Δt) < 1e-9
    @test abs(b.δ[2] - b.δ[3]) > 0.1                     # a real angle, not zero

    # AND THE TRIPPED MACHINE IS NOT IN THAT SET, which is worth its own
    # assertion because "angle differences settle" is only true of the
    # connected, online ones. `inject!` zeroes the dead rotor's couplings, so
    # nothing drives it: from a flat start its speed stays exactly zero, its
    # angle freezes, and its difference against the survivors therefore grows
    # at the full drift rate.
    @test b.ω[1] == 0.0
    @test b.δ[1] == a.δ[1]
    d12 = ((b.δ[1] - b.δ[2]) - (a.δ[1] - a.δ[2])) / Δt
    @test d12 ≈ -ω₀ * ω_ss rtol = 1e-6                   # opposite sign: δ₁ is the still one
end

@testset "M3 step 2 V4: the ceiling holds, releases unaided, and never stalls" begin
    # Step 1 asserted that a machine STOPS at its ceiling. The two halves V4
    # adds are the ones the header claims and nothing yet measured: it comes
    # back OFF the ceiling unaided when frequency recovers, and the guard does
    # not stall the integration while it is pinned.
    net = governed_ring(; hr2 = 5.0, hr3 = 300.0)        # G2: 5 MW of reserve
    ma = machine_arrays(net)
    eng = init!(SwingEngine, net; dt = 0.01)
    pred = GridSim._swing_outofdomain(eng.ΔPm_idx, eng.hr_pidx)

    inject!(eng, TripGenerator(:G1))
    fired, over = 0, -Inf
    for _ in 1:10000                                     # 100 s, finite by construction
        s = step!(eng, 0.01)
        pred(eng.integrator.u, eng.params, s.t) && (fired += 1)
        over = max(over, s.ΔPm[2] - ma.headroom[2])
    end
    pinned = current_state(eng)
    @test pinned.ΔPm[2] ≈ ma.headroom[2] atol = 1e-9     # pinned, the step 1 property
    @test pinned.ΔPm[3] < ma.headroom[3]                 # G3 is not: it is per machine
    @test pinned.f_coi < net.f0 - 0.3                    # …with a real deficit driving it

    # WHY IT CANNOT FIRE, measured rather than argued: the largest excursion
    # above the ceiling over the whole run is 2.4e-11, inside the predicate's
    # own 1e-10 roundoff slack. The derivative saturation is what holds the
    # solution AT the ceiling; the guard only has to absorb adaptive-step
    # overshoot, and here there was none worth absorbing.
    @test 0 < over < 1e-10

    # Recovery, unaided: trip G3 (`P0 = −110 MW`, the net LOAD of the ring) and
    # the remaining machine is left in surplus. Frequency rises, the droop
    # command turns negative, and `ΔPm` comes off the ceiling on its own — no
    # clamp released, no state written. It then keeps going negative, which is
    # legal and deliberate: this tier has no down-regulation floor (swing.jl).
    inject!(eng, TripGenerator(:G3))
    for k in 1:20000                                     # 200 s, finite by construction
        s = step!(eng, 0.01)
        pred(eng.integrator.u, eng.params, s.t) && (fired += 1)
        k == 100 && @test s.ΔPm[2] < -0.01               # off the ceiling within 1 s
    end
    r = current_state(eng)
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    @test r.f_coi > net.f0                               # it really did recover
    # G2 alone, decoupled from everything: `ω → Pm/(1/R + D)` and `ΔPm = −ω/R`.
    ω_r = ma.Pm[2] / (ma.invR[2] + ma.D[2])
    @test r.ω[2] ≈ ω_r rtol = 1e-9
    @test r.ΔPm[2] ≈ -ω_r * ma.invR[2] atol = 1e-9       # measured: −0.2727272727
    @test r.ΔPm[2] < -0.25                               # a long way below the ceiling

    # What is actually observable about the guard, worded to the assertion and
    # no further: the predicate is FALSE on every one of the 30,016 accepted
    # states, and the run rejected 20 steps in total — error control, not a
    # collapsing `dt`. This does NOT establish "the predicate never returned
    # true" inside the solver; that cannot be seen from outside `init!`, and
    # this file has already paid once for a check claimed before it was run.
    #
    # `naccept` is deliberately NOT asserted. It measured 30,016 — the 16 above
    # one-step-per-`dt` being the two `auto_dt_reset!` calls re-estimating after
    # each trip — and pinning a solver statistic to a 0.05 % margin would go red
    # on a patch release that changed that re-estimation, reading as "V4 broke".
    # The claim it would have made is `r.t` at `dt = 0.01`, asserted below.
    @test fired == 0
    @test eng.integrator.stats.nreject < 100
    @test r.t ≈ 300.0 atol = 1e-6                        # …it advanced the whole way
end

# ============ M3 step 3 — the shedding ladder, bound to a machine ============
#
# The refactor's oracle is M1's own shed testsets above, which are unchanged and
# still green; what follows is the half M1 cannot see, because M1 has exactly one
# frequency and one power imbalance, so "which one?" has no wrong answer there.
@testset "M3 step 3 V5: the ladder reads its OWN machine, not the average" begin
    net = _split_speed_net()
    thr, dt = 49.5, 0.01
    iA, iB = 1, 3                     # bus order B1,B2,B3 ⇒ machines A, C, B
    @test [m.id for m in net.machines][[iA, iB]] == [:A, :B]

    # --- what each candidate signal actually does, with nothing armed --------
    bare = init!(SwingEngine, net; dt = dt)
    inject!(bare, TripGenerator(:C))
    t_cross_A = NaN; prev_A = Float64(bare.f0)
    min_A = Inf; min_B = Inf; min_coi = Inf
    for _ in 1:6000                   # 60 s, a fixed step count and not a condition
        st = step!(bare)
        fA = bare.f0 * (1 + st.ω[iA]); fB = bare.f0 * (1 + st.ω[iB])
        if isnan(t_cross_A) && prev_A >= thr > fA
            t_cross_A = st.t
        end
        prev_A = fA
        min_A = min(min_A, fA); min_B = min(min_B, fB)
        min_coi = min(min_coi, st.f_coi)
    end
    # THE DISCRIMINATING FACT, and the whole reason this fixture exists: over the
    # entire run the bound machine goes 6.5 Hz BELOW the threshold while the COI
    # average stays 0.09 Hz ABOVE it. So the two candidate signals do not merely
    # cross at different instants — a ladder driven by `f_coi` fires ZERO times
    # here, where the correctly-bound one fires. No near-coincidence can make the
    # assertions below pass for the wrong reason.
    @test min_A < thr - 5.0                       # measured 42.979 Hz
    @test min_coi > thr + 0.05                    # measured 49.595 Hz
    @test min_B > thr + 0.05                      # measured 49.814 Hz — nor does B
    @test 1.0 < t_cross_A < 2.0                   # measured in (1.740, 1.750]

    # --- the armed run: a ladder on A, and an identical one on B -------------
    stage() = [LoadShedStage(thr, 0.10; label = :s1)]
    eng = init!(SwingEngine, net; dt = dt, shed = [:A => stage(), :B => stage()])
    @test [l.machine for l in eng.ladders] == [:A, :B]     # caller's order, not a Dict's
    inject!(eng, TripGenerator(:C))
    for _ in 1:600; step!(eng); end               # 6 s
    lgA = shed_log(shed_ladder(eng, :A))
    @test length(lgA.t) == 1
    @test lgA.label == [:s1]
    @test shed_ladder(eng, :A).armed == [false]   # latched
    # It fired at A's OWN crossing: inside the one-`dt` bracket the bare run
    # brackets that crossing to, and off the `dt` grid, i.e. root-found.
    @test t_cross_A - dt < lgA.t[1] <= t_cross_A
    @test !isapprox(lgA.t[1] / dt, round(lgA.t[1] / dt); atol = 1e-6)
    # …and B's identical ladder did not fire — not "not yet", but never: the
    # counterfactual below runs B's ladder over the whole 60 s.
    @test isempty(shed_log(shed_ladder(eng, :B)).t)
    @test shed_ladder(eng, :B).armed == [true]

    b_only = init!(SwingEngine, net; dt = dt, shed = [:B => stage()])
    inject!(b_only, TripGenerator(:C))
    for _ in 1:6000; step!(b_only); end           # the full 60 s
    @test isempty(shed_log(shed_ladder(b_only, :B)).t)
end

@testset "M3 step 3 V5: the bound machine's power moves, and no other's" begin
    # The second half of D5: not just *when* it fires but *what it steps*. On this
    # tier `Pm` is a net injection, so disconnecting load raises it by exactly the
    # block — the same sign as M1's `ΔP_dist += ΔP_pu` and for the same reason.
    net = _split_speed_net()
    dt = 0.01
    iA, iC, iB = 1, 2, 3
    eng = init!(SwingEngine, net; dt = dt,
                shed = [:A => [LoadShedStage(49.5, 0.10; label = :s1)],
                        :B => [LoadShedStage(49.5, 0.10; label = :s1)]])
    PmA0 = eng.params[eng.Pm_pidx[iA]]
    PmB0 = eng.params[eng.Pm_pidx[iB]]
    @test PmA0 ≈ -0.35 && PmB0 ≈ -0.10          # the model's own per-unit values
    inject!(eng, TripGenerator(:C))
    for _ in 1:600; step!(eng); end
    @test eng.params[eng.Pm_pidx[iA]] - PmA0 ≈ 0.10   # exactly the block, upward
    @test eng.params[eng.Pm_pidx[iB]] == PmB0         # untouched, to the bit
    @test eng.params[eng.Pm_pidx[iC]] == 0.0          # tripped, and still tripped
    @test shed_total(shed_ladder(eng, :A)) ≈ 0.10
    @test shed_total(shed_ladder(eng, :B)) == 0.0
    # A machine with no ladder is a caller bug to ask about, not a silent empty one.
    @test_throws KeyError shed_ladder(eng, :C)
    @test isempty(init!(SwingEngine, net; dt = dt).ladders)
end

@testset "M3 step 3: a generator trip disarms that machine's ladder" begin
    # THE CHOICE, and it is a choice: a ladder bound to a machine that has just
    # tripped is latched without firing. Its rotor is islanded and undriven, so
    # its `ω` is no longer the frequency of anything, and its affect would step
    # the `Pm` the trip has just zeroed — a dead machine injecting power.
    net = GridSim.three_machine_ring()
    dt = 0.01
    eng = init!(SwingEngine, net; dt = dt, shed = [:G2 => [LoadShedStage(49.0, 0.05)]])
    l2 = shed_ladder(eng, :G2)
    @test l2.armed == [true]
    inject!(eng, TripGenerator(:G2))
    @test l2.armed == [false]                    # latched…
    @test isempty(shed_log(l2).t)                # …without firing, and the log is
    @test shed_total(l2) == 0.0                  #    a record of what actually shed

    # AND THE FINDING, because a defensive branch with no counterfactual is the
    # thing this milestone keeps having to catch: for a genuine UNDER-frequency
    # stage the disarm cannot change anything, and that is provable rather than
    # hopeful. After a trip the machine has `Pm = 0`, every incident `K = 0`,
    # `invR = 0` and `ΔPm` re-seated, so its rotor obeys `dω/dt = −Dω/2H` and
    # decays MONOTONICALLY back toward nominal. A machine tripped below a
    # threshold has therefore already fired; one tripped above it only moves
    # away. Measured here, and the re-armed counterfactual is bit-identical.
    function ring_run(rearm::Bool)
        e = init!(SwingEngine, net; dt = dt,
                  shed = [:G3 => [LoadShedStage(49.0, 0.05)]])
        inject!(e, TripGenerator(:G1))
        for _ in 1:300; step!(e); end            # 3 s: the ring is well down
        f3 = e.f0 * (1 + current_state(e).ω[3])
        inject!(e, TripGenerator(:G3))
        rearm && fill!(shed_ladder(e, :G3).armed, true)
        fs = Float64[]
        for _ in 1:5000; push!(fs, e.f0 * (1 + step!(e).ω[3])); end
        return (; e, f3, fs)
    end
    armed_off = ring_run(false); armed_on = ring_run(true)
    @test armed_off.f3 < 49.0                    # measured 48.633 Hz at its own trip
    # …which is the point: being below the threshold at the trip instant means the
    # stage had ALREADY fired, at t ≈ 1.91 s, well before the machine died.
    lg_on = shed_log(shed_ladder(armed_on.e, :G3))
    @test length(lg_on.t) == 1 && lg_on.t[1] < 3.0
    @test issorted(armed_on.fs)                  # monotone rise, the whole 50 s
    @test armed_on.fs[end] > 49.99               # …back to nominal, so nothing left
    @test shed_log(shed_ladder(armed_off.e, :G3)).t == lg_on.t   # re-arming added none
    @test current_state(armed_off.e).ω == current_state(armed_on.e).ω  # bit-identical
    @test current_state(armed_off.e).δ == current_state(armed_on.e).δ

    # THE CONSTRUCTION THAT DOES REACH IT, so the disarm is not untested code. A
    # dead rotor decaying toward nominal FROM ABOVE crosses every threshold
    # between where it was and 50 Hz, downward. `LoadShedStage` does not forbid a
    # threshold above nominal — M1's own crossing-polarity test uses 50.5 — so
    # this is a legal ladder, and without the disarm a machine that has been
    # offline for seven seconds sheds load and starts injecting.
    function over_run(rearm::Bool)
        e = init!(SwingEngine, net; dt = dt,
                  shed = [:G2 => [LoadShedStage(50.2, 0.05)]])
        inject!(e, TripGenerator(:G3))           # a load machine: frequency RISES
        for _ in 1:200; step!(e); end
        f2 = e.f0 * (1 + current_state(e).ω[2])
        inject!(e, TripGenerator(:G2))
        rearm && fill!(shed_ladder(e, :G2).armed, true)
        for _ in 1:3000; step!(e); end
        return (; e, f2, log = shed_log(shed_ladder(e, :G2)))
    end
    kept = over_run(false); undone = over_run(true)
    @test kept.f2 > 50.2                         # measured 52.363 Hz at its trip
    @test isempty(kept.log.t)                    # disarmed: nothing fires
    @test kept.e.params[kept.e.Pm_pidx[2]] == 0.0        # …and it stays dead
    @test length(undone.log.t) == 1              # counterfactual: it DOES fire
    @test undone.log.t[1] > 2.0                  # measured t ≈ 9.41 s, long dead
    @test undone.e.params[undone.e.Pm_pidx[2]] ≈ 0.05    # a dead rotor injecting
end

@testset "M3 step 3: shed binding guards, one message each" begin
    # Each guard provoked ALONE and asserted by its own wording, the step-1
    # discipline: a bad `shed` argument usually breaks more than one rule and
    # "it threw" would not show which.
    net = GridSim.three_machine_ring()
    st() = [LoadShedStage(49.5, 0.05)]
    @test occursin("sentinel", argerr_msg(
        () -> init!(SwingEngine, net; shed = [GridSim.AGGREGATE_MACHINE => st()])))
    @test occursin("no machine named", argerr_msg(
        () -> init!(SwingEngine, net; shed = [:NOPE => st()])))
    @test occursin("two ladders bound", argerr_msg(
        () -> init!(SwingEngine, net; shed = [:G1 => st(), :G1 => st()])))
    # The duplicate guard exists because two ladders on one machine shed its
    # blocks twice at the same threshold, which reads as a working defence plan.
    @test occursin("shed twice", argerr_msg(
        () -> init!(SwingEngine, net; shed = [:G1 => st(), :G1 => st()])))
end

@testset "M3 step 3: the network shed is integrated, not just recorded" begin
    # The same stale-FSAL hazard M1's refinement test pins, re-pinned for THIS
    # engine, because it is a different path: `p` is a flat `Vector` and the
    # affect writes an index, not a field of a mutable parameter struct. The
    # error would again be invisible to a readout assertion, so only refining
    # `dt` and demanding convergence discriminates.
    net = GridSim.three_machine_ring()
    function run_to(dt, tend)
        e = init!(SwingEngine, net; dt = dt,
                  shed = [:G2 => [LoadShedStage(49.5, 0.20; label = :fsal)]])
        inject!(e, TripGenerator(:G1))
        for _ in 1:round(Int, tend / dt); step!(e); end
        return e
    end
    coarse = run_to(0.01, 3.0); fine = run_to(0.001, 3.0)
    lc = shed_log(shed_ladder(coarse, :G2)); lf = shed_log(shed_ladder(fine, :G2))
    @test length(lc.t) == 1 && length(lf.t) == 1
    @test isapprox(lc.t[1], lf.t[1]; atol = 1e-8)        # measured 1.3e-11
    # A single stale-derivative step would bias `ω_G2` by about `dt·ΔP/(2H)` =
    # 1.7e-4, five orders above this tolerance; the runs agree to 4.9e-10.
    @test isapprox(current_state(coarse).ω[2], current_state(fine).ω[2]; rtol = 1e-8)
    # Non-vacuous: the shed has to have changed the answer for the agreement to
    # be worth anything. Without it the same run sits ~0.0055 pu lower.
    bare = init!(SwingEngine, net; dt = 0.01)
    inject!(bare, TripGenerator(:G1))
    for _ in 1:300; step!(bare); end
    @test current_state(bare).ω[2] < current_state(coarse).ω[2] - 0.004
end

@testset "M3 step 3: droop and a ladder on the SAME machine compose" begin
    # Every other step-3 test runs governor-free machines, so the configuration
    # step 6 actually needs — an area with primary response AND a defence plan —
    # had never been run. It is worth its own test because it is where two
    # independently-made decisions meet: a shed steps `Pm` upward and leaves
    # `headroom` alone. That composes correctly only because D4 defines `Pmax` as
    # a NET-INJECTION ceiling, so disconnecting load raises the ceiling by exactly
    # the block shed and a constant `headroom` on a raised `Pm` is the right new
    # limit. Reinterpret `Pmax` as a generation nameplate later and this breaks
    # silently, which is what the ceiling assertion below is for.
    gov_ring() =
        NetworkModel(100.0, 50.0,
                     [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)],
                     [Branch(:L12, :B1, :B2, 0.25, 500.0),
                      Branch(:L23, :B2, :B3, 0.25, 500.0),
                      Branch(:L31, :B3, :B1, 0.25, 500.0)],
                     #       id    bus  S_rated    H    D   Xd′    E′      P0    R   Pmax  Tg
                     [Machine(:G1, :B1,  300.0,  4.0, 2.0, 0.30, 1.05,   80.0),
                      Machine(:G2, :B2,  200.0,  3.0, 2.0, 0.20, 1.03,   30.0, 0.5, 36.0, 1.0),
                      Machine(:G3, :B3,  500.0,  5.0, 2.0, 0.50, 1.04, -110.0)])
    net = gov_ring()
    ma = machine_arrays(net)
    @test ma.invR == [0.0, 4.0, 0.0]          # only G2 is governed…
    @test ma.headroom == [0.0, 0.06, 0.0]     # …and its reserve is 6 MW

    block = 0.60
    function run(armed)
        e = init!(SwingEngine, net; dt = 0.01,
                  shed = armed ? [:G2 => [LoadShedStage(48.0, block; label = :g)]] :
                                 Pair{Symbol,Vector{LoadShedStage}}[])
        hr0 = e.params[e.hr_pidx[2]]; pm0 = e.params[e.Pm_pidx[2]]
        inject!(e, TripGenerator(:G1))
        peak = -Inf; on_ceiling = false; at_fire = NaN
        for _ in 1:12000                       # 120 s, a fixed count
            st = step!(e)
            peak = max(peak, st.ΔPm[2])
            on_ceiling |= st.ΔPm[2] >= hr0 - 1e-9
            if armed && isnan(at_fire) && !isempty(shed_ladder(e, :G2).t_fired)
                at_fire = st.ΔPm[2]
            end
        end
        return (; e, hr0, pm0, peak, on_ceiling, at_fire, st = current_state(e))
    end
    bare = run(false); armed = run(true)

    # --- the composition, which is the point of the test ---------------------
    @test armed.e.params[armed.e.hr_pidx[2]] == armed.hr0        # headroom untouched…
    @test armed.e.params[armed.e.Pm_pidx[2]] - armed.pm0 ≈ block # …while Pm rose
    # …so the net-injection ceiling `Pm + headroom` rose by exactly the block.
    @test (armed.e.params[armed.e.Pm_pidx[2]] + armed.e.params[armed.e.hr_pidx[2]]) -
          (armed.pm0 + armed.hr0) ≈ block

    # --- saturated when it fired, and off the ceiling afterwards -------------
    @test armed.on_ceiling                       # it really did run out of reserve
    @test armed.at_fire >= armed.hr0 - 1e-9      # …and was still out of it at the shed
    @test armed.peak <= armed.hr0 + 1e-10        # never above the guard's own slack
    # Step 2's release test drove the recovery with a load trip; here the shed's
    # own block is the cause, which is the case step 6 will actually run.
    @test armed.st.ΔPm[2] < armed.hr0 - 0.01
    # And it settles on the droop closed form, with step 2's correction to the
    # denominator: the sum is over the SURVIVORS, G2 and G3.
    ΣPm = ma.Pm[2] + block + ma.Pm[3]
    ω_ss = ΣPm / (ma.D[2] + ma.D[3] + ma.invR[2] + ma.invR[3])
    @test isapprox(armed.st.ω[2], ω_ss; rtol = 1e-8)
    @test isapprox(armed.st.ΔPm[2], -ω_ss * ma.invR[2]; rtol = 1e-8)

    # --- the counterfactual: with no ladder it stays pinned, forever ---------
    @test bare.st.ΔPm[2] >= bare.hr0 - 1e-9
    @test bare.st.ω[2] < armed.st.ω[2] - 0.03    # 47.36 Hz against 49.44 Hz

    # --- and the step-rejecting guard behaves as step 1 measured -------------
    # It DOES reject here — that is the guard absorbing adaptive-step overshoot
    # at a live ceiling, which step 1 measured to be load-bearing — but boundedly,
    # and the run still advances its whole span rather than collapsing `dt`.
    @test 0 < armed.e.integrator.stats.nreject < 500
    @test armed.e.integrator.stats.naccept > 12_000
    @test isapprox(armed.e.integrator.t, 120.0; atol = 1e-9)
end

@testset "M3 step 3: M1's aggregate ladder is the one-machine case" begin
    # The refactor's premise. M1 has one speed and one imbalance, so its ladder
    # carries the sentinel rather than a bus name, and `SwingEngine` refuses that
    # sentinel (asserted with the other guards above). M1's shed testsets earlier
    # in this file are the behavioural oracle and are unchanged.
    sys = example_system()
    eng = init!(FrequencyResponseEngine, sys; dt = 0.01,
                shed = [LoadShedStage(49.5, 0.02; label = :s1)])
    @test eng.ladder.machine === GridSim.AGGREGATE_MACHINE
    @test GridSim.AGGREGATE_MACHINE === :system
    @test ShedLadder(LoadShedStage[]).machine === GridSim.AGGREGATE_MACHINE
    @test ShedLadder(:ES, LoadShedStage[]).machine === :ES
    # `disarm!` latches without firing and without touching the log — the
    # operation the generator trip performs.
    l = ShedLadder(:ES, [LoadShedStage(49.5, 0.02)])
    @test l.armed == [true]
    @test GridSim.disarm!(l) === l
    @test l.armed == [false]
    @test isempty(shed_log(l).t) && shed_total(l) == 0.0
end


# ======================= M3 step 4 — out-of-step protection ===================
@testset "M3 step 4 V6: the separation instant is a root, not a step" begin
    net = _pole_slip_net()
    ba = branch_arrays(net)
    K13 = ba.K[2]
    @test isapprox(K13, 0.270375; atol = 1e-9)      # the tie's maximum transfer
    @test isapprox(machine_arrays(net).Pm[1], -0.40; atol = 1e-12)
    @test K13 < abs(machine_arrays(net).Pm[1])      # ⇒ no post-trip equilibrium

    # --- the bare run: where the crossing is, with nothing armed -------------
    dt = 0.01
    bare = init!(SwingEngine, net; dt = dt)
    d0 = (s -> s.δ[1] - s.δ[3])(current_state(bare))
    @test isapprox(K13 * sin(d0), 0.10; atol = 1e-9)   # pre-fault: 10 MW exported
    inject!(bare, TripGenerator(:ESG))
    t_bracket = NaN
    prevd = d0
    for _ in 1:600                                    # 6 s, a fixed step count
        s = step!(bare)
        d = s.δ[1] - s.δ[3]
        isnan(t_bracket) && abs(prevd) < _SLIP_THR <= abs(d) && (t_bracket = s.t)
        prevd = d
    end
    @test 2.93 < t_bracket <= 2.94                    # measured 2.94, one `dt` wide

    # --- the armed run ------------------------------------------------------
    eng = init!(SwingEngine, net; dt = dt,
                out_of_step = [(:B1, :B3) => OutOfStepTrip(_SLIP_THR; label = :tie)])
    inject!(eng, TripGenerator(:ESG))
    for _ in 1:600; step!(eng); end
    lg = out_of_step_log(out_of_step_relay(eng, :B1, :B3))
    @test lg.tripped && lg.label === :tie && !lg.armed
    # Inside the one-`dt` bracket the bare run puts the crossing in, and OFF the
    # `dt` grid — i.e. root-found, not detected at a step boundary.
    @test t_bracket - dt < lg.t <= t_bracket
    @test !isapprox(lg.t / dt, round(lg.t / dt); atol = 1e-6)
    # The root was found on the intended quantity: the angle at the firing
    # instant IS the threshold. Measured exact, asserted with slack.
    @test isapprox(abs(lg.δ), _SLIP_THR; atol = 1e-12)
    # …and it really opened the branch, through the ordinary `TripLine` path, so
    # the read-out and the event log both know. The event stamp is the root-found
    # instant here — unlike a shed, which is why a shed keeps its own log and this
    # does not need one (`protection/load_shedding.jl`, `out_of_step.jl`).
    @test !is_online(eng, :B1, :B3)
    evs = event_log(eng)
    @test [e.kind for e in evs] == [:trip_generator, :trip_line]
    @test (evs[2].a, evs[2].b) == (:B1, :B3)
    @test evs[2].t == lg.t

    # --- V6's first clause: refine `dt` 10x and the instant does not move ----
    function trip_at(dtx)
        e = init!(SwingEngine, net; dt = dtx,
                  out_of_step = [(:B1, :B3) => OutOfStepTrip(_SLIP_THR)])
        inject!(e, TripGenerator(:ESG))
        for _ in 1:round(Int, 6.0 / dtx); step!(e); end
        return out_of_step_log(out_of_step_relay(e, :B1, :B3)), current_state(e)
    end
    lc, sc = trip_at(0.01)
    lf, sf = trip_at(0.001)
    @test isapprox(lc.t, lf.t; atol = 1e-10)          # measured 4.4e-15
    @test isapprox(sc.ω[1], sf.ω[1]; rtol = 1e-8)
    @test isapprox(sc.ω[3], sf.ω[3]; rtol = 1e-8)
    # Non-vacuous: a `dt`-quantised trip would have moved by up to a whole step,
    # which is seven orders above that tolerance.
    @test 0.001 > 1e-10
end

@testset "M3 step 4 V6: the tie's power reverses before the relay fires" begin
    # The report's export swing, and the physical reason a *threshold on the
    # angle* is the right detector. Pre-fault the area EXPORTS 10 MW. Losing its
    # generation reverses that inside a second — the same tie now imports —
    # and only later does the angle run away far enough to be a slip. So the
    # reversal is a precondition the relay passes straight through, not the thing
    # it triggers on: an `abs` has a kink at zero, and this asserts the kink is
    # crossed harmlessly (it is a MAXIMUM of the condition, so it carries no sign
    # change for the rootfinder to mistake for a crossing).
    net = _pole_slip_net()
    K13 = branch_arrays(net).K[2]
    eng = init!(SwingEngine, net; dt = 0.01,
                out_of_step = [(:B1, :B3) => OutOfStepTrip(_SLIP_THR)])
    P(s) = K13 * sin(s.δ[1] - s.δ[3])
    @test isapprox(P(current_state(eng)), 0.10; atol = 1e-9)     # exporting
    inject!(eng, TripGenerator(:ESG))
    t_rev = NaN
    prevP = P(current_state(eng))
    peak_import = 0.0
    for _ in 1:600
        s = step!(eng)
        p = P(s)
        isnan(t_rev) && prevP > 0 >= p && (t_rev = s.t)
        prevP = p
        is_online(eng, :B1, :B3) && (peak_import = min(peak_import, p))
    end
    lg = out_of_step_log(out_of_step_relay(eng, :B1, :B3))
    @test !isnan(t_rev)
    @test 0.90 < t_rev < 0.92                       # measured 0.91
    @test t_rev < lg.t                              # …and well before the trip
    @test lg.t - t_rev > 1.5                        # measured 2.02 s apart
    # The swing is a real reversal, not a graze: it imports essentially the whole
    # of what the tie can carry before the angle runs away.
    @test peak_import < -0.9 * K13                  # measured -0.2704, i.e. -K
end

@testset "M3 step 4 V6: two islands, and what does NOT tell them apart" begin
    # THE FINDING, and it is why this testset does not assert what the plan's V6
    # line says on its own. "The trip leaves two islands, each holding its own
    # frequency" is TRUE — but it is *also* true of the unarmed run, to five
    # decimal places, because a fully slipping tie transfers almost no NET power:
    # `K·sin` of a monotonically growing angle averages to zero. So the islanded
    # closed forms alone cannot tell an opened tie from one that is still there
    # and slipping. Both are asserted, and so is the thing that DOES discriminate.
    net = _pole_slip_net()
    ma = machine_arrays(net)
    K13 = branch_arrays(net).K[2]
    # Per-island closed forms, with step 2's D11 correction applied: the sum runs
    # over the SURVIVORS of that island. `:ESG` is tripped, so its damping enters
    # nobody's balance, and island {B1,B2} is `:ES` alone.
    isl_ES, isl_FR = ma.Pm[1] / ma.D[1], ma.Pm[3] / ma.D[3]
    @test isapprox(isl_ES, -0.04; atol = 1e-12)      # 48.00 Hz
    @test isapprox(isl_FR, -0.005; atol = 1e-12)     # 49.75 Hz
    function trace(armed)
        kw = armed ?
            (out_of_step = [(:B1, :B3) => OutOfStepTrip(_SLIP_THR)],) : NamedTuple()
        e = init!(SwingEngine, net; dt = 0.01, kw...)
        inject!(e, TripGenerator(:ESG))
        wES = Float64[]; wFR = Float64[]; Pt = Float64[]
        Klive() = e.params[e.K_pidx[e.branch_to_edge[2]]]
        for _ in 1:30000                             # 300 s, a fixed step count
            s = step!(e)
            push!(wES, s.ω[1]); push!(wFR, s.ω[3])
            push!(Pt, Klive() * sin(s.δ[1] - s.δ[3]))
        end
        return (; wES, wFR, Pt, e)
    end
    A, U = trace(true), trace(false)
    late = 28001:30000                               # the last 20 s
    p2p(v) = maximum(v) - minimum(v)

    # --- what IS true of the armed run --------------------------------------
    @test isapprox(A.wES[end], isl_ES; atol = 1e-8)   # measured 3.0e-10 off
    @test isapprox(A.wFR[end], isl_FR; atol = 1e-8)   # measured 1.3e-9 off
    @test p2p(A.wES[late]) < 1e-7                     # measured 7.6e-10: flat
    @test p2p(A.wFR[late]) < 1e-7                     # measured 2.1e-9
    # The tripped machine is in NEITHER island's balance: nothing drives it.
    @test current_state(A.e).ω[2] == 0.0
    # Separated means separated: the tie transfers exactly zero, to the bit.
    @test all(==(0.0), A.Pt[3000:end])

    # --- and the half that does NOT discriminate ----------------------------
    # The unarmed run reaches the same two island frequencies to ~3e-5. An
    # assertion on the closed forms alone would have passed with the relay
    # removed entirely, which is step 3's V5 trap.
    @test isapprox(U.wES[end], isl_ES; atol = 1e-4)
    @test isapprox(U.wFR[end], isl_FR; atol = 1e-4)

    # --- what DOES discriminate, by four orders of magnitude -----------------
    # 300 s in, the two areas are still grinding against each other at the full
    # coupling: the tie swings the whole way from +K to −K and never decays.
    @test maximum(abs, U.Pt[late]) > 0.99 * K13       # measured 0.27037 = K
    @test p2p(U.Pt[late]) > 1.9 * K13                 # measured 0.5407 = 2K
    @test p2p(U.wES[late]) > 1e-5                     # measured 3.1e-4
    @test p2p(U.wFR[late]) > 1e-5                     # measured 1.2e-4
    @test p2p(U.wES[late]) > 1e4 * p2p(A.wES[late])   # measured 4.1e5x
    @test p2p(U.wFR[late]) > 1e4 * p2p(A.wFR[late])   # measured 5.7e4x
    @test is_online(U.e, :B1, :B3) && !is_online(A.e, :B1, :B3)
end

@testset "M3 step 4: the trip is the UPcrossing of |δ|, in the branch's own sense" begin
    # Two hazards in one fixture, because one construction settles both.
    #
    # POLARITY. `ContinuousCallback(cond, affect!, affect_neg!)` — `affect!` is
    # the UPcrossing of the condition and `affect_neg!` the DOWNcrossing, and the
    # condition here is `threshold − |δ|`, so exceeding the threshold is a DOWN
    # crossing. Wire it into the other slot and the relay opens the tie when the
    # areas come back INTO step, which is silent and exactly backwards. The
    # construction guard (below) forces the condition to start positive, so the
    # first crossing is necessarily the one that matters — which makes a scenario
    # where the angle overshoots and recovers the discriminating one.
    #
    # ORIENTATION. `three_machine_ring`'s L31 is declared `:B3 → :B1`, while
    # `Graphs` holds that edge as `(1, 3)`. The two orientations differ by a sign,
    # and the relay logs the BRANCH's, from `branch_arrays`. `|δ|` cannot see the
    # difference, so only the signed log bites.
    net = three_machine_ring()
    dt = 0.005
    bare = init!(SwingEngine, net; dt = dt)
    d0 = (s -> s.δ[3] - s.δ[1])(current_state(bare))
    @test isapprox(abs(d0), 0.146222745876; atol = 1e-9)
    inject!(bare, TripLine(:B2, :B3))
    peak = 0.0; t_peak = 0.0; settled = 0.0
    for _ in 1:4000                                  # 20 s, a fixed step count
        s = step!(bare)
        d = abs(s.δ[3] - s.δ[1])
        d > peak && (peak = d; t_peak = s.t)
        settled = d
    end
    # The window this test needs: pre-fault < settled < threshold < peak, so the
    # threshold is crossed once on the way up and would be crossed again on the
    # way down if the relay were still armed and wired to the wrong slot.
    @test abs(d0) < settled < 0.35 < peak
    @test isapprox(peak, 0.398864511; atol = 1e-8)
    @test isapprox(t_peak, 0.435; atol = 1e-9)

    eng = init!(SwingEngine, net; dt = dt,
                out_of_step = [(:B3, :B1) => OutOfStepTrip(0.35; label = :L31)])
    inject!(eng, TripLine(:B2, :B3))
    for _ in 1:4000; step!(eng); end
    r = out_of_step_relay(eng, :B3, :B1)
    @test out_of_step_relay(eng, :B1, :B3) === r     # either bus order, one relay
    lg = out_of_step_log(r)
    @test lg.tripped
    @test lg.t < t_peak                              # on the way UP: measured 0.333
    @test isapprox(lg.t, 0.333020558927; atol = 1e-9)
    # THE SIGN. `δ_B3 − δ_B1` is negative here, so the branch's orientation gives
    # −0.35 and the graph's would give +0.35. Both have the same magnitude, which
    # is why the threshold itself cannot catch a swapped orientation.
    @test isapprox(lg.δ, -0.35; atol = 1e-12)
    @test lg.δ < 0
    @test (r.from, r.to) == (:B3, :B1)               # the branch's own names

    # A threshold above the peak is never reached: still armed after the full run,
    # so "it did not fire" is a property of the whole trace, not of a short one.
    far = init!(SwingEngine, net; dt = dt, out_of_step = [(:B3, :B1) => 0.45])
    inject!(far, TripLine(:B2, :B3))
    for _ in 1:4000; step!(far); end
    lf = out_of_step_log(out_of_step_relay(far, :B3, :B1))
    @test !lf.tripped && lf.armed && isnan(lf.t)
    @test is_online(far, :B3, :B1)
    @test lf.threshold_rad == 0.45                   # a bare number is a threshold
    @test lf.label === :out_of_step                  # …and gets the default label
end

@testset "M3 step 4: opening the branch disarms the relay, whoever opens it" begin
    # The hazard the plan's three V6 bullets do not mention. `inject!(::TripLine)`
    # no-ops on a branch that is already open — so a relay left armed on one would
    # root-find a crossing, run its affect, change nothing, and then log a
    # protection operation that never happened. The engine's own rule is that
    # `_log_event!` records what changed the system, not what was asked for, and
    # this is the same rule one level up.
    #
    # The answer is structural: opening a branch latches every relay on it, so the
    # user's trip, another relay's trip and the relay's own all go through one
    # line. Provoked here by the case that has no other cover — a hand trip first.
    net = _pole_slip_net()
    dt = 0.01
    eng = init!(SwingEngine, net; dt = dt,
                out_of_step = [(:B1, :B3) => OutOfStepTrip(_SLIP_THR)])
    r = out_of_step_relay(eng, :B1, :B3)
    @test r.armed
    inject!(eng, TripGenerator(:ESG))
    for _ in 1:100; step!(eng); end                  # t = 1 s, well before 2.93
    @test r.armed                                    # a GENERATOR trip elsewhere
    inject!(eng, TripLine(:B1, :B3))                 # …and now the user's own
    @test !r.armed                                   # latched…
    @test !out_of_step_log(r).tripped                # …without firing
    for _ in 1:3000; step!(eng); end                 # 30 s more, past the crossing
    @test !out_of_step_log(r).tripped
    @test count(e -> e.kind === :trip_line, event_log(eng)) == 1

    # NON-VACUOUS: the threshold really is crossed after that hand trip, so "it
    # never fired" is not "nothing ever happened". Measured on a relay-free run of
    # the identical scenario.
    b = init!(SwingEngine, net; dt = dt)
    inject!(b, TripGenerator(:ESG))
    for _ in 1:100; step!(b); end
    inject!(b, TripLine(:B1, :B3))
    crossed = NaN
    for _ in 1:3000
        s = step!(b)
        isnan(crossed) && abs(s.δ[1] - s.δ[3]) >= _SLIP_THR && (crossed = s.t)
    end
    @test !isnan(crossed) && crossed < 3.0           # measured 2.53 s
end

@testset "M3 step 4: a generator trip at either end disarms the relay" begin
    # The second hazard the plan's bullets do not mention, and the one that would
    # have shipped. Step 2's V3 measured what a generator trip does to a rotor:
    # `inject!` zeroes every coupling incident to that bus, so nothing drives it,
    # its `ω` stays exactly 0.0 and its `δ` FREEZES — while the survivors' common
    # mode drifts on forever at `ω₀·ω_ss`. The angle across a branch with one dead
    # end therefore grows at the FULL drift rate and crosses any threshold
    # whatever, on a branch whose coupling that same trip set to zero.
    #
    # Same asymmetry as the shedding ladder, in the same direction: a LINE trip is
    # what a relay exists for, a GENERATOR trip is what makes its signal
    # meaningless.
    net = _pole_slip_net()
    dt = 0.01
    eng = init!(SwingEngine, net; dt = dt,
                out_of_step = [(:B1, :B2) => OutOfStepTrip(_SLIP_THR; label = :inner),
                               (:B1, :B3) => OutOfStepTrip(_SLIP_THR; label = :tie)])
    inner = out_of_step_relay(eng, :B1, :B2)
    tie = out_of_step_relay(eng, :B1, :B3)
    @test [x.label for x in eng.relays] == [:inner, :tie]   # caller's order, not a Dict's
    inject!(eng, TripGenerator(:ESG))                # :ESG sits at B2
    @test !inner.armed                               # incident to B2 ⇒ latched…
    @test !out_of_step_log(inner).tripped            # …without firing
    # …and the disarm is SELECTIVE, not a blanket: L13 does not touch B2.
    @test tie.armed
    for _ in 1:3000; step!(eng); end                 # 30 s
    @test !out_of_step_log(inner).tripped
    @test is_online(eng, :B1, :B2)                   # the inner line is still in service
    @test out_of_step_log(tie).tripped               # the tie's relay still works

    # NON-VACUOUS, and this is the whole point: on a relay-free run of the same
    # scenario the inner branch's angle blows through the threshold at t ≈ 2.36 s
    # and reaches ~199 rad by 30 s — while that branch's coupling has been exactly
    # zero since the trip. Without the disarm the relay opens a line that has
    # carried nothing for over two seconds, and calls it a pole slip.
    b = init!(SwingEngine, net; dt = dt)
    inject!(b, TripGenerator(:ESG))
    k12 = b.branch_to_edge[1]
    @test b.params[b.K_pidx[k12]] == 0.0
    crossed = NaN
    for _ in 1:3000
        s = step!(b)
        isnan(crossed) && abs(s.δ[1] - s.δ[2]) >= _SLIP_THR && (crossed = s.t)
    end
    @test !isnan(crossed) && 2.3 < crossed < 2.4     # measured 2.36
    @test abs((s -> s.δ[1] - s.δ[2])(current_state(b))) > 100.0   # measured 199
    @test b.params[b.K_pidx[k12]] == 0.0             # still carrying nothing
end

@testset "M3 step 4: relay construction guards, one message each" begin
    # Each provoked ALONE and asserted by its own wording — the step-1 discipline.
    net = _pole_slip_net()
    @test occursin("must be > 0 rad", argerr_msg(() -> OutOfStepTrip(0.0)))
    @test occursin("must be > 0 rad", argerr_msg(() -> OutOfStepTrip(-1.0)))
    @test occursin("no branch joins", argerr_msg(
        () -> init!(SwingEngine, net; out_of_step = [(:B2, :B3) => 1.0])))
    @test occursin("two relays on the branch", argerr_msg(
        () -> init!(SwingEngine, net;
                    out_of_step = [(:B1, :B3) => 1.0, (:B3, :B1) => 1.0])))
    # The fourth guard needs the steady state, so it lives past `find_fixpoint`:
    # a threshold below the pre-fault transfer angle could never fire, because the
    # trip is a downward crossing and the condition would start below zero. Silent
    # otherwise — the trace would read as a defence plan that simply never operated.
    @test occursin("protects nothing", argerr_msg(
        () -> init!(SwingEngine, net; out_of_step = [(:B1, :B3) => 0.3])))
    # THE GUARD'S REASON, MEASURED — AND THE MEASUREMENT OVERTURNED IT. The
    # obvious justification is "such a relay can never fire: the condition starts
    # negative and a downward crossing needs a positive side to fall from." That
    # is a claim about the rootfinder that nothing here observes (the wording step
    # 2's V4 already had to rewrite once), so it is checked instead of asserted —
    # and it is false. `|δ|` is not monotone: the export swing carries the angle
    # down THROUGH ZERO first, so the condition goes positive at t ≈ 0.41 s and
    # then falls back through zero at t ≈ 1.25 s. A relay set below the operating
    # point therefore trips a healthy tie 1.7 s before the genuine slip, and looks
    # like it worked. The guard prevents that, not an inert relay.
    b0 = init!(SwingEngine, net; dt = 0.01)
    r0 = OutOfStepRelay(:B1, :B3, OutOfStepTrip(0.3))
    # The angle across the branch, resolved the way the engine resolves it — off
    # `branch_arrays`' own `src`/`dst` and the engine's symbolically-resolved flat
    # indices, not off an assumed state layout. (It is not the obvious one: the
    # three states of a vertex are NOT contiguous.)
    ba0 = branch_arrays(net)
    i, j = b0.δ_idx[ba0.src[2]], b0.δ_idx[ba0.dst[2]]
    cb = GridSim._out_of_step_callback(r0, u -> u[i] - u[j], _ -> nothing)
    gcond() = cb.condition(b0.integrator.u, b0.integrator.t, b0.integrator)
    ts = [b0.integrator.t]; g = [gcond()]
    inject!(b0, TripGenerator(:ESG))
    for _ in 1:600                                   # 6 s, a fixed step count
        s = step!(b0); push!(ts, s.t); push!(g, gcond())
    end
    @test isapprox(g[1], -0.0788547578; atol = 1e-8)  # starts below zero, as argued
    # …and then does exactly what the argument says it cannot.
    up = [ts[k] for k in 2:length(g) if g[k-1] < 0 <= g[k]]
    dn = [ts[k] for k in 2:length(g) if g[k-1] >= 0 > g[k]]
    @test length(up) == 1 && isapprox(up[1], 0.41; atol = 1e-9)
    @test length(dn) == 1 && isapprox(dn[1], 1.25; atol = 1e-9)
    # The spurious trip lands 1.7 s before the genuine one (2.9336 s, pinned by the
    # V6 testset above), which is what makes it dangerous rather than merely wrong:
    # it would read as protection that worked.
    @test dn[1] < 2.9335882899 - 1.5
    # …and it is a real boundary, not a blanket refusal: the steady-state angle is
    # 0.3789 rad, so 0.38 is legal and 0.30 is not.
    @test init!(SwingEngine, net; out_of_step = [(:B1, :B3) => 0.38]) isa SwingEngine
    # Asking about a branch that was never armed is a caller bug, not a silent
    # nothing — the contract `shed_ladder` sets for machines.
    e = init!(SwingEngine, net; out_of_step = [(:B1, :B3) => 1.0])
    @test_throws KeyError out_of_step_relay(e, :B1, :B2)
    @test isempty(init!(SwingEngine, net).relays)
    # `disarm!` latches without firing and without touching the log.
    r = OutOfStepRelay(:B1, :B3, OutOfStepTrip(1.0; label = :x))
    @test r.armed && isnan(r.t_tripped)
    @test GridSim.disarm!(r) === r
    @test !r.armed && !out_of_step_log(r).tripped
end

@testset "M3 step 4: a ladder and a relay in one engine, both firing" begin
    # Where the two protection schemes meet, which nothing had run: step 6 arms a
    # defence plan AND a tie relay on the same area. They are independent by
    # design and this is the assertion that they stay so — in particular that the
    # relay's LINE trip does not disarm the ladder, which is the asymmetry
    # `inject!(::TripGenerator)` documents (a line trip can island a live machine,
    # and that is exactly the situation the ladder exists for).
    net = _pole_slip_net()
    eng = init!(SwingEngine, net; dt = 0.01,
                shed = [:ES => [LoadShedStage(49.5, 0.05; label = :es1)]],
                out_of_step = [(:B1, :B3) => OutOfStepTrip(_SLIP_THR; label = :tie)])
    Pm0 = eng.params[eng.Pm_pidx[1]]
    inject!(eng, TripGenerator(:ESG))
    for _ in 1:6000; step!(eng); end                 # 60 s
    sl = shed_log(shed_ladder(eng, :ES))
    rl = out_of_step_log(out_of_step_relay(eng, :B1, :B3))
    @test length(sl.t) == 1 && sl.label == [:es1]
    @test rl.tripped
    # THE ORDER, and it is the opposite of what this test first assumed. The tie
    # separates at 2.93 s and the area only falls through 49.5 Hz at 5.51 s — so
    # the ladder operates on an area that is ALREADY islanded, which is the
    # sequence the report describes (separation, then the island's defence plan)
    # rather than a defence plan that saves the tie. Asserted as measured.
    @test isapprox(rl.t, 2.9335882899; atol = 1e-8)
    @test isapprox(sl.t[1], 5.5143632378; atol = 1e-8)
    @test rl.t < sl.t[1]
    @test !is_online(eng, :B1, :B3)                  # …islanded when it shed
    @test isapprox(eng.params[eng.Pm_pidx[1]] - Pm0, 0.05; atol = 1e-12)
    # Both logs are separate and neither is the event log: the line trip is in the
    # event log (topology a played-back trace cannot reconstruct), the shed is not.
    @test [e.kind for e in event_log(eng)] == [:trip_generator, :trip_line]
end

# ---- M3 step 5: generation lost as a ramp, not an instant --------------------
# `governed_ring` (above) is the fixture throughout, with the reserve opened up
# where the closed form needs no saturation. The ramp is always on G1 — the one
# machine with NO governor — so the response the survivors mount is unambiguously
# primary response to the ramp and not the ramped machine partly answering itself.

@testset "M3 step 5: a zero-rate ramp is the un-ramped machine, to the bit" begin
    # The parameter addition must not have perturbed a single existing scenario,
    # and "the tests still pass" is far too weak a bar for that (M2 step 6's
    # lesson, re-applied at M3 step 1). The bar is BIT identity, `naccept`
    # included — and the comparison is between two engines built in THIS process,
    # which is what makes it a real check rather than the stale-precompile
    # artefact a cross-process "bit-identical" can be.
    function ramprun(net; ramp = Pair{Symbol,GenerationRamp}[], n = 1500, dt = 0.01)
        eng = init!(SwingEngine, net; dt = dt, ramp = ramp)
        for _ in 1:n; step!(eng, dt); end
        return eng
    end
    bare  = ramprun(governed_ring())
    zeroR = ramprun(governed_ring(); ramp = [:G2 => GenerationRamp(0.0, 1.0, 2.0)])
    @test zeroR.integrator.u == bare.integrator.u                 # every digit
    @test zeroR.integrator.stats.naccept == bare.integrator.stats.naccept
    @test state_series(zeroR).f_coi == state_series(bare).f_coi
    # …and it is zero-rate that does it, not zero-*duration*: the ramp above has
    # a real 2 s window and a real start, and is still exactly nothing.
    @test generation_ramp(zeroR, :G2).duration == 2.0

    # An un-ramped machine carries `rate = 0` in the live parameter vector, which
    # is what makes `Pm + rate·clamp(…)` arithmetically `Pm`.
    for net in (two_machine_system(), three_machine_ring(), governed_ring())
        eng = init!(SwingEngine, net; dt = 0.02)
        @test all(iszero, eng.params[eng.rate_pidx])
        @test_throws KeyError generation_ramp(eng, first(machine_ids(eng)))
    end

    # WHY THE CONSTRUCTOR PINS `find_fixpoint`'s TIME, asserted rather than left
    # in a comment. NetworkDynamics defaults that solve to `t = NaN`, which was
    # harmless while no vertex RHS read `t` and is fatal the moment one does:
    # `clamp(NaN − t_start, 0, d)` is `NaN` and `0.0 * NaN` is `NaN`, so a
    # ZERO-rate machine is enough to NaN the whole steady-state solve. The default
    # is not a defence — this is what would break if `t = t0f` were ever dropped.
    dv = zeros(3)
    pv = [1.0, 2.0, 3.0, 314.0, 0.0, 0.0, 5.0, 0.0, 0.0, 0.0]
    GridSim.swing_vertex!(dv, [0.0, 0.0, 0.0], [0.0], pv, NaN)
    @test isnan(dv[2])                       # …at t = NaN, with rate = 0
    GridSim.swing_vertex!(dv, [0.0, 0.0, 0.0], [0.0], pv, 0.0)
    @test dv[2] == 1.0 / (2 * 2.0)           # …and finite at a real time
end

@testset "M3 step 5: the ramp delivers rate*duration, and the path does not matter" begin
    # The strongest claim available about a ramp on this tier: where the system
    # SETTLES depends only on the total delivered `rate·duration`, never on how it
    # was delivered. So one closed form validates the magnitude AND the shape at
    # once — a ramp that leaked, double-counted, or failed to stop at its own end
    # would land somewhere else.
    #
    # The closed form is step 2's V2 with the ramp as the imbalance:
    #   Δω = ΔP / (Σ 1/Rᵢ + Σ Dᵢ)   over the machines still online (D11)
    # and nothing trips here, so both sums run over all three.
    net = governed_ring(; hr2 = 5000.0, hr3 = 5000.0)
    ma  = machine_arrays(net)
    pred = (-1.5) / (sum(ma.invR) + sum(ma.D))
    @test isapprox(pred, -0.009375; atol = 1e-12)
    for (rate, dur) in ((-0.5, 3.0), (-1.5, 1.0), (-0.15, 10.0))
        @test rate * dur ≈ -1.5                       # same magnitude, three shapes
        eng = init!(SwingEngine, net; dt = 0.01,
                    ramp = [:G1 => GenerationRamp(rate, 1.0, dur)])
        peak = 0.0
        for _ in 1:20_000
            step!(eng, 0.01)
            peak = max(peak, maximum(current_state(eng).ΔPm))
        end
        @test isapprox(current_state(eng).ω_coi, pred; rtol = 1e-9)
        # THE PRECONDITION, SIZED AGAINST THE PEAK AND NOT THE SETTLED VALUE
        # (step 2's lesson). The governor overshoots on the way in: G3 settles at
        # 0.9375 pu of extra power but PEAKS near 1.19 pu, 26 % higher. A headroom
        # chosen from the settled figure would silently saturate the run and the
        # closed form above would then be asserting the ceiling, not the droop.
        @test peak > 1.0                              # …the overshoot is real
        @test peak < minimum(ma.headroom[2:3])        # …and well inside the reserve
        @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
    end
end

@testset "M3 step 5: the ramp is inert at the fixpoint solve (flat start survives)" begin
    # M2's acceptance criterion, carried into a right-hand side that now depends
    # on `t`: a model placed off its own equilibrium rings from `t = 0` with a
    # plausible oscillation that is pure initialisation artefact. The ramp is the
    # first thing in the repo that could seed that quietly.
    net = governed_ring()
    bare = init!(SwingEngine, net; dt = 0.01)
    eng  = init!(SwingEngine, net; dt = 0.01,
                 ramp = [:G1 => GenerationRamp(-0.5, 2.0, 3.0)])
    @test eng.integrator.u == bare.integrator.u        # same steady state, to the bit
    @test maximum(abs, current_state(eng).ω) == 0.0    # …and it is flat
    # The armed ramp really is in the live system — the identity above is inertness
    # at the solve, not a ramp that failed to arm.
    @test eng.params[eng.rate_pidx[1]] == -0.5
    @test generation_ramp(eng, :G1) == GenerationRamp(-0.5, 2.0, 3.0)
    # Nothing happens until `t_start`, to the bit; and then something does.
    for _ in 1:199; step!(eng, 0.01); step!(bare, 0.01); end
    @test eng.integrator.u == bare.integrator.u        # t = 1.99 s, still identical
    for _ in 1:200; step!(eng, 0.01); step!(bare, 0.01); end
    @test current_state(eng).f_coi < current_state(bare).f_coi - 0.01
end

@testset "M3 step 5: ramp guards, one message each" begin
    # Each rule gets its own asserted message, the M2/M3 discipline: a bad ramp
    # usually breaks more than one at once and "it threw" would not say which.
    @test_throws "rate (Inf) must be finite"     GenerationRamp(Inf, 1.0, 2.0)
    @test_throws "rate (NaN) must be finite"     GenerationRamp(NaN, 1.0, 2.0)
    @test_throws "t_start (Inf) must be finite"  GenerationRamp(-0.5, Inf, 2.0)
    @test_throws "duration (0.0) must be > 0"    GenerationRamp(-0.5, 1.0, 0.0)
    @test_throws "duration (-2.0) must be > 0"   GenerationRamp(-0.5, 1.0, -2.0)
    @test_throws "duration (Inf) must be finite" GenerationRamp(-0.5, 1.0, Inf)
    # A zero RATE is legal and is the whole point of the identity test above.
    @test GenerationRamp(0.0, 1.0, 2.0).rate == 0.0

    net = governed_ring()
    @test_throws "no machine named `:G9`" init!(SwingEngine, net;
        ramp = [:G9 => GenerationRamp(-0.5, 1.0, 2.0)])
    @test_throws "two ramps on machine `:G1`" init!(SwingEngine, net;
        ramp = [:G1 => GenerationRamp(-0.5, 1.0, 2.0),
                :G1 => GenerationRamp(-0.2, 3.0, 2.0)])
    # THE MIS-SIGNED START, which is the one that would not have thrown anything:
    # a ramp already under way at `t0` is folded into the steady state and the run
    # rings from the first step with an artefact that looks like physics.
    @test_throws "before the run's own t0" init!(SwingEngine, net;
        ramp = [:G1 => GenerationRamp(-0.5, -1.0, 2.0)])
    # …and it is measured against the run's OWN `t0`, not against zero.
    @test_throws "before the run's own t0" init!(SwingEngine, net; t0 = 5.0,
        ramp = [:G1 => GenerationRamp(-0.5, 1.0, 2.0)])
    e = init!(SwingEngine, net; t0 = 5.0,
              ramp = [:G1 => GenerationRamp(-0.5, 5.0, 2.0)])
    @test maximum(abs, current_state(e).ω) == 0.0      # t_start == t0 is legal and flat
end

@testset "M3 step 5: the ramp's ends are corners, and protection root-finds through them" begin
    # `clamp` makes `Pm_eff` continuous with a KINK in its slope at `t_start` and
    # at `t_start + duration` — a corner, never a jump. That is the whole reason
    # D7 rejected a staircase of N discrete trips: a jump would put a root in the
    # very signal the shed ladder and the out-of-step relay are root-finding on,
    # and the instants they report would be artefacts of N.
    #
    # The check with teeth is NOT "arm protection that never fires and watch it not
    # fire" — that passes with the ramp deleted from the RHS. It is a ladder whose
    # threshold the ramp DOES cross, at a time that must come out of the crossing
    # and not out of a corner.
    R = GenerationRamp(-0.5, 1.0, 3.0)                 # corners at t = 1.0 and 4.0
    function fire_at(dt, th)
        eng = init!(SwingEngine, governed_ring(; hr2 = 5000.0, hr3 = 5000.0); dt = dt,
                    ramp = [:G1 => R],
                    shed = [:G2 => [LoadShedStage(th, 0.02; label = :s1)]])
        for _ in 1:round(Int, 15.0 / dt); step!(eng, dt); end
        return eng, shed_log(shed_ladder(eng, :G2))
    end
    # 49.15 Hz is deliberately chosen so the crossing lands 10 ms BEFORE the ramp's
    # far corner — as close to it as the trace allows without being it. If the
    # corner were leaking a root, this is where it would show.
    eng, lg = fire_at(0.01, 49.15)
    @test length(lg.t) == 1
    @test isapprox(lg.t[1], 3.989737027; atol = 1e-7)
    @test abs(lg.t[1] - 4.0) > 1e-2                    # …near the corner, not at it
    @test abs(lg.t[1] - 1.0) > 1.0
    # It is the crossing of the recorded trace, to the recorder's own linear
    # interpolation error — the shed is where the frequency actually got there.
    s  = state_series(eng)
    f2 = eng.model.f0 .* (1 .+ s.ω_G2)
    k  = findfirst(i -> f2[i] >= 49.15 > f2[i + 1], 1:length(f2) - 1)
    tx = s.t[k] + (f2[k] - 49.15) / (f2[k] - f2[k + 1]) * (s.t[k + 1] - s.t[k])
    @test isapprox(lg.t[1], tx; atol = 1e-3)
    # …and 100× closer to that crossing than to the corner it nearly touches.
    @test abs(lg.t[1] - tx) < abs(lg.t[1] - 4.0) / 100

    # V6's own discriminator, applied to the corners: a root-found instant must not
    # move with the OUTER step size. Measured at four thresholds spanning before,
    # straddling and after both corners; worst movement over a 4× change in `dt` is
    # 6.2e-8 s. That measurement is also why NO `tstops` are pinned at the corners:
    # there is nothing left for them to buy, and pinning them would change the step
    # sequence and destroy the zero-rate bit-identity above.
    for th in (49.9, 49.15, 49.0, 48.9)
        _, a = fire_at(0.02, th)
        _, b = fire_at(0.005, th)
        @test length(a.t) == 1 && length(b.t) == 1
        @test abs(a.t[1] - b.t[1]) < 1e-6
        @test abs(a.t[1] - 1.0) > 1e-3 && abs(a.t[1] - 4.0) > 1e-3
    end

    # And an out-of-step relay live across both corners, on the branch the ramp
    # swings HARDEST: |δ_B1 − δ_B2| starts at 0.0378 rad and is driven to 0.1177 —
    # a 3× excursion that comes within 10 % of the 0.13 rad threshold and must not
    # cross it. A corner that leaked a root would fire it regardless of the margin.
    eng2 = init!(SwingEngine, governed_ring(; hr2 = 5000.0, hr3 = 5000.0); dt = 0.01,
                 ramp = [:G1 => R], out_of_step = [(:B1, :B2) => OutOfStepTrip(0.13)])
    peak = 0.0
    for _ in 1:2000
        st = step!(eng2, 0.01)
        peak = max(peak, abs(st.δ[1] - st.δ[2]))
    end
    @test isapprox(peak, 0.117655; atol = 1e-4)        # …the excursion is real
    @test peak < 0.13 && peak > 0.9 * 0.13             # …and it came within 10 %
    rl = out_of_step_log(out_of_step_relay(eng2, :B1, :B2))
    @test !rl.tripped && rl.armed
    @test is_online(eng2, :B1, :B2)
    @test isempty(event_log(eng2))
end

@testset "M3 step 5: a ramp on a GOVERNED machine — the ceiling, and a ladder on top" begin
    # Everything above runs its ramp on G1, the governor-free machine, so the
    # response is unambiguously the survivors'. That leaves the configuration
    # step 6 actually needs untested: ONE machine carrying the cascade, its own
    # droop, and its own defence plan — which is the Iberian shape exactly. Step
    # 3's rule ("test the configuration the NEXT step needs, not just the one
    # this step changed") applies here rather than after step 6 goes wrong.
    #
    # It is also the counterfactual for a claim `GenerationRamp`'s docstring
    # makes in prose and nothing else asserted: **headroom does not move with the
    # ramp.** The governor still saturates at `Pmax − P0`, so the machine's TOTAL
    # mechanical ceiling travels down with the generation that is leaving, ending
    # at `Pmax + rate·duration`. If anyone later "fixes" headroom to track
    # `Pm_eff`, this is what goes red.
    net = governed_ring(; hr2 = 20.0, hr3 = 5000.0)   # G2: 20 MW of reserve only
    ma  = machine_arrays(net)
    R   = GenerationRamp(-0.5, 1.0, 3.0)              # −1.5 pu, all of it on G2
    @test ma.headroom[2] == 0.2

    eng = init!(SwingEngine, net; dt = 0.01, ramp = [:G2 => R])
    for _ in 1:20_000; step!(eng, 0.01); end          # 200 s — well past settling
    st = current_state(eng)
    # G2's droop would command `−ω·invR = 0.433 pu`; it holds at its 0.2 pu
    # ceiling, and the rest of the deficit goes to G3 and to damping:
    #   −1.5 + headroom₂ + (−ω)(invR₃ + ΣD) = 0  ⇒  ω = −1.3/120
    @test isapprox(st.ω_coi, -1.3 / 120; rtol = 1e-9)
    @test -st.ω_coi * ma.invR[2] > 2 * ma.headroom[2]   # …it really is saturated
    @test isapprox(st.ΔPm[2], ma.headroom[2]; atol = 1e-10)
    @test st.ΔPm[2] <= ma.headroom[2] + 1e-10           # the step-rejecting slack
    # THE CEILING TRAVELLED WITH THE LOSS. Total mechanical power is
    # `Pm_eff + ΔPm`, and at settle that is exactly `Pmax + rate·duration` — the
    # machine ends up ABSORBING 1.0 pu, which is the right physics for a fleet
    # that lost 150 MW of plant and has 20 MW of reserve left to answer with.
    total = (ma.Pm[2] + R.rate * R.duration) + st.ΔPm[2]
    @test isapprox(total, (ma.Pm[2] + ma.headroom[2]) + R.rate * R.duration; atol = 1e-10)
    @test isapprox(total, -1.0; atol = 1e-10)
    @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)

    # …and now the ladder on that same machine. A shed steps `Pm`; the ramp adds
    # to `Pm`; headroom sits on `P0` and moves with neither. Three independent
    # decisions, and it is their AGREEMENT that would break silently — so it is
    # asserted rather than reasoned. The block lands at 2.84 s, i.e. while the
    # ramp is still running, which is the case worth covering.
    eng2 = init!(SwingEngine, net; dt = 0.01, ramp = [:G2 => R],
                 shed = [:G2 => [LoadShedStage(49.6, 0.3; label = :s1)]])
    for _ in 1:20_000; step!(eng2, 0.01); end
    st2 = current_state(eng2)
    lg  = shed_log(shed_ladder(eng2, :G2))
    @test length(lg.t) == 1
    @test R.t_start < lg.t[1] < R.t_start + R.duration   # …fired mid-ramp
    @test isapprox(eng2.params[eng2.Pm_pidx[2]], ma.Pm[2] + 0.3; atol = 1e-12)
    # The ramp still delivered exactly `rate·duration`: the shed moved the settling
    # point by its own block over the same denominator and by nothing else.
    @test isapprox(st2.ω_coi, -1.0 / 120; rtol = 1e-9)
    @test isapprox(st2.ω_coi - st.ω_coi, 0.3 / 120; rtol = 1e-7)
    # …and the ceiling is untouched by the shed, which is the decision that would
    # break silently if a shed ever adjusted headroom along with `Pm`.
    @test eng2.params[eng2.hr_pidx[2]] == ma.headroom[2]
    @test isapprox(st2.ΔPm[2], ma.headroom[2]; atol = 1e-10)
end

@testset "M3 step 5: a generator trip takes its ramp with it" begin
    # `Pm_eff = Pm + rate·clamp(…)`, so zeroing `Pm` alone would leave the ramp
    # standing: a machine that is offline, decoupled from every branch and undriven
    # would go on being injected into. `m3-context.md` predicted exactly this
    # re-opening — explicit `t`-dependence in the vertex RHS puts the "a dead
    # machine injects power" case back on the table that step 3 found unreachable.
    #
    # Observed from OUTSIDE the parameter vector, deliberately: reading `rate` back
    # would pass even if the RHS ignored it. What is asserted is the dead rotor's
    # own motion. Once tripped it is islanded (its couplings are zero) and undriven,
    # so it obeys `dω/dt = −Dω/2H` exactly — a pure decay with time constant
    # `2H/D = 2·12/6 = 4 s` on this machine's system-base values. A ramp still
    # running would drive it instead, and by t = 20 s that is not a subtle difference.
    net = governed_ring(; hr2 = 5000.0, hr3 = 5000.0)
    eng = init!(SwingEngine, net; dt = 0.01,
                ramp = [:G1 => GenerationRamp(-0.5, 1.0, 3.0)])
    for _ in 1:200; step!(eng, 0.01); end              # t = 2.0 s, mid-ramp
    @test eng.params[eng.rate_pidx[1]] == -0.5
    inject!(eng, TripGenerator(:G1))
    ω_trip = current_state(eng).ω[1]
    @test ω_trip < -1e-3                               # the ramp had already bitten
    ma = machine_arrays(net)
    τ  = 2 * ma.H[1] / ma.D[1]
    @test isapprox(τ, 4.0; atol = 1e-12)
    for _ in 1:1800; step!(eng, 0.01); end             # t = 20 s
    st = current_state(eng)
    @test isapprox(st.ω[1], ω_trip * exp(-(st.t - 2.0) / τ); rtol = 1e-6)
    @test abs(st.ω[1]) < abs(ω_trip)                   # …decayed, not driven
    # THE DISCRIMINATING NUMBER, stated rather than left implicit. Had the ramp
    # survived the trip it would have finished delivering its full −1.5 pu into a
    # rotor with nowhere to send it, and that rotor would have settled at
    # `−ΔP/D = −1.5/6 = −0.25` pu. What is actually here is four orders of
    # magnitude smaller — this is not a tolerance, it is a different outcome.
    @test abs(st.ω[1]) < 1e-4
    # The other half of the picture, deliberately labelled as the half that CANNOT
    # tell the two runs apart (step 4's V6 lesson): the survivors settle on the
    # post-trip closed form either way, because a tripped machine's power reaches
    # nobody — its branches are already open. Only the dead rotor discriminates.
    for _ in 1:8000; step!(eng, 0.01); end             # t = 100 s
    surv = -0.8 / (sum(ma.invR[2:3]) + sum(ma.D[2:3]))
    @test isapprox(current_state(eng).ω_coi, surv; rtol = 1e-8)
end
