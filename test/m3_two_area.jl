# M3 step 6 - the two-area Iberian case and its sweep.

# =========== M3 step 6 — the two-area Iberian case and its sweep ===========
#
# The acceptance criterion for this step is the SWEEP, not the trace
# (m3-context.md D10): the throwaway probe this replaces printed three tuned
# numbers, and a port that prints three tuned numbers again has recreated the
# problem the milestone was chosen to close. So what is asserted below is the
# derivation that produces the input, the per-unit conversions that produce the
# model, the closed-form reference check, and the SHAPE of the grid — never a
# cell value a solver version could move.
@testset "M3 step 6: Iberian two-area case" begin
    IB = IberiaTwoArea

    @testset "V7a — the cascade magnitude is RE-DERIVED from Table 3-1" begin
        # This is the step's first checklist item and it is arithmetic, so it is
        # tested as arithmetic. The document being replaced quotes two figures
        # for this one quantity that differ by 1.87x, and the sweep's own finding
        # is that the slip boundary tracks magnitude hard — so an inherited
        # number here would move every result downstream of it.
        @test IB.gen_pre() == 563.0                    # clusters 2 + 3, gone by 12:32:57
        @test IB.gen_cascade_floor() == 4907.0         # clusters 4a…13, a FLOOR
        @test IB.cascade_magnitude() == 5187.0         # 5,750 (p.119) − 563
        @test IB.cascade_duration() ≈ 4.100 atol = 1e-9

        # NEITHER of the two figures carried in the old notes is what the ramp
        # uses, and the assertion is written both ways round so a future edit
        # that quietly re-inherits one goes red rather than merely looking odd.
        @test IB.cascade_magnitude() != IB.MAG_OLD_UNSOURCED   # 2,773, unsourced
        @test IB.cascade_magnitude() != IB.MAG_OLD_CUMULATIVE  # 5,750, double-counts
        @test IB.MAG_OLD_CUMULATIVE - IB.cascade_magnitude() == IB.gen_pre()

        # The bottom-up floor corroborates the top-down figure: it is short, and
        # the shortfall sits inside the report's own ">=2,600 MW" on the 7–13 row.
        # Asserted as an INEQUALITY with a named slack, not as an equality with a
        # tolerance, because "a floor is below the total" is the actual claim.
        short = IB.cascade_magnitude() - IB.gen_cascade_floor()
        @test 0 < short < 2600.0
        # …and the same itemisation is short at the report's EARLIER checkpoint,
        # which is what makes the shortfall a property of Table 3-1's coverage
        # rather than of this particular subtraction (report §5: sub-1 MW
        # generation has no real-time reporting obligation).
        @test IB.gen_pre() + 582 + 145 + 930 < IB.REPORT_CUMULATIVE_1802
    end

    @testset "V7b — the model's per-unit conversions, on a base nothing equals" begin
        net = IB.two_area_model()
        ma, ba = machine_arrays(net), branch_arrays(net)
        @test net.S_base == 10_000.0
        # Both machines rated AWAY from the system base and from each other, so
        # a missing or inverted conversion changes the answer instead of hiding
        # behind a weight of 1 (the M2 discipline, and m3-context.md D8).
        @test net.machines[1].S_rated != net.S_base
        @test net.machines[2].S_rated != net.S_base
        @test net.machines[1].S_rated != net.machines[2].S_rated
        # The conversion is right exactly when H on the SYSTEM base is the
        # machine's kinetic energy over the system base — an identity the arrays
        # must reproduce, not a tolerance.
        @test ma.H[1] ≈ IB.KE_IB / net.S_base rtol = 1e-12
        @test ma.H[2] ≈ IB.KE_CE / net.S_base rtol = 1e-12
        # Tie strength expressed as the reactance it is (D9): K = E′₁E′₂/X with
        # E′ = 1 at both ends, so X = S_base/P_max and K = P_max/S_base. Asserted
        # through `branch_arrays`, i.e. the path the engine integrates against.
        @test ba.X[1] ≈ net.S_base / IB.P_MAX_NOMINAL rtol = 1e-12
        @test ba.K[1] ≈ IB.P_MAX_NOMINAL / net.S_base rtol = 1e-12
        # Lossless network: the constructor requires it, and it is what makes the
        # tie flow equal the machines' net injection.
        @test sum(m.P0 for m in net.machines) == 0.0
        # The flat start is an acceptance criterion, not a nicety. Asserted
        # gauge-free (the DIFFERENCE) and against the two-machine closed form,
        # including the branch: `find_fixpoint` must land on the STABLE
        # equilibrium asin(P/K) and not on its π-complement.
        eng = SwingEngine(net)
        st = current_state(eng)
        @test st.f_coi ≈ net.f0 atol = 1e-12
        @test all(iszero, st.ω)
        @test st.δ[1] - st.δ[2] ≈ asin(ma.Pm[1] / ba.K[1]) rtol = 1e-9
    end

    @testset "V7c — reference check: the inter-area mode against its closed form" begin
        # SPEC §6 wants a closed-form check per engine, and §7.5(2) supplies one
        # for this topology. Governor-free and undamped, which is what the closed
        # form describes; the scenario's own machines ring ~5 % faster because a
        # slow governor adds synchronising stiffness.
        gf(P) = IB.two_area_model(; P_max_mw = P, R = Inf, D = 0.0,
                                    reserve_ib = 0.0, reserve_ce = 0.0)
        cf1, m1 = IB.small_signal_mode(gf(2_500.0)), IB.measure_mode(gf(2_500.0))
        cf2, m2 = IB.small_signal_mode(gf(8_000.0)), IB.measure_mode(gf(8_000.0))
        @test cf1 ≈ 0.296147 atol = 1e-6
        @test cf2 ≈ 0.551192 atol = 1e-6
        @test m1.f ≈ cf1 rtol = 1e-3
        @test m2.f ≈ cf2 rtol = 1e-3
        # AND THE RESIDUAL IS IDENTIFIED, not merely bounded. A tolerance alone
        # would pass just as happily on a per-unit error of the same size. The
        # measured mode is BELOW the closed form in both cells (a pendulum's
        # period lengthens with amplitude) and the gap SHRINKS with the swing
        # amplitude — which is finite-amplitude nonlinearity and is not something
        # a coupling or conversion error would track.
        @test m1.f < cf1 && m2.f < cf2
        @test m2.amplitude < m1.amplitude
        @test (cf2 - m2.f) / cf2 < (cf1 - m1.f) / cf1
    end

    @testset "V7d — the construction guard at the WEAKEST swept cell" begin
        # The sweep's lower edge must be legal by margin, and one step outside it
        # must be a CONSTRUCTION error rather than a wrong number — which is the
        # good failure mode for a carelessly widened sweep (D9).
        weakest = first(IB.P_MAX_SCAN)
        @test weakest == 2_500.0
        deepest = minimum(IB.P_TIE0_CELLS)
        net = IB.two_area_model(; P_max_mw = weakest, P_tie0_mw = deepest)
        ba, ma = branch_arrays(net), machine_arrays(net)
        @test abs(ma.Pm[1]) < ba.K[1]                       # |P0| ≤ ΣK, with margin
        @test rad2deg(asin(ma.Pm[1] / ba.K[1])) ≈ -53.13 atol = 0.01
        # …and the guard is real: a tie that cannot carry the pre-event flow is
        # rejected at construction, by its own wording.
        @test occursin("no steady state",
              argerr_msg(() -> IB.two_area_model(; P_max_mw = 1_500.0,
                                                   P_tie0_mw = -2_000.0)))
    end

    @testset "V7e — the sweep's SHAPE (not a cell value)" begin
        # Coarse scan: this is a shape assertion, so resolution beyond one step
        # of the boundary buys nothing and costs suite time. The script's own
        # scan is five times finer.
        scan = 2_500.0:500.0:9_000.0
        b = IB.slip_boundary(; scan = scan)

        # THE POSITIVE CONTROL, FIRST. Every clause below is about ordering
        # slipping cells against non-slipping ones, and all of them are
        # vacuously true if nothing slips — which is exactly what happens if the
        # ramp term is deleted from the vertex RHS. So: the weakest scanned tie
        # must slip, and the stiffest must not, or there is no boundary to be
        # right about.
        @test b.slipped[1] === true
        @test b.slipped[end] === false

        # THE ANTI-VACUITY CONTROL. With the cascade set to zero the SAME sweep
        # must find no boundary at all — nothing slips anywhere. This is what
        # distinguishes "the model reproduces a separation" from "the assertion
        # above happens to hold".
        z = IB.slip_boundary(; scan = scan, magnitude_mw = 0.0)
        @test !any(z.slipped)

        # Monotone in tie strength: no tie STIFFER than a non-slipping one slips.
        # This is the property that makes a single boundary number meaningful,
        # and it is measured by scanning rather than assumed by bisecting.
        @test b.monotone
        @test 2_500.0 < b.boundary < 9_000.0

        # Stiffer tie ⇒ LATER slip, asserted strictly INSIDE the slipping band.
        # The boundary cell itself is excluded: a solver version that nudged one
        # cell across the boundary would otherwise break this for a reason that
        # has nothing to do with the claim.
        inside = [P for P in scan if P < b.boundary]
        t90s = [IB.run_cell(; P_max_mw = P).t90 for P in inside]
        @test length(inside) >= 4
        @test all(!isnan, t90s)
        @test issorted(t90s)
        @test t90s[end] - t90s[1] > 1.0        # non-vacuous ordering, not ties

        # The boundary tracks cascade MAGNITUDE — the finding that made
        # re-deriving it a checklist item. Asserted as an ordering over the four
        # profiles of section 2, so it cannot pass on a coincidence of one cell.
        bmag = [IB.slip_boundary(; scan = scan, magnitude_mw = m).boundary
                for m in (IB.MAG_OLD_UNSOURCED, IB.gen_cascade_floor(),
                          IB.cascade_magnitude(), IB.MAG_OLD_CUMULATIVE)]
        @test issorted(bmag)
        # …and the old unsourced figure's boundary is strictly BELOW the derived
        # one, i.e. the correction moved the answer rather than re-labelling it.
        @test bmag[1] < bmag[3]

        # THE SCAN'S OWN EDGE CASE, exercised rather than merely coded. A scan
        # whose cells ALL slip has not found a boundary — it has hit its own top
        # end — and reporting that number bare would be the same class of error as
        # the figures this whole step exists to replace. `saturated` is false by
        # construction in the scan above (its last cell does not slip), so the flag
        # and its ">=" rendering would otherwise ship untested.
        narrow = IB.slip_boundary(; scan = 2_500.0:500.0:3_500.0)
        @test all(narrow.slipped)
        @test narrow.saturated === true
        @test narrow.boundary == 3_500.0
        @test startswith(IB.show_boundary(narrow), ">=")
        @test !b.saturated && !startswith(IB.show_boundary(b), ">=")

        # Duration, by contrast, barely moves it — measured, and it is worth
        # asserting because the reasoning pointed the other way: at the derived
        # magnitude the cascade is still arriving when synchronism is lost.
        bdur = [IB.slip_boundary(; scan = scan, duration_s = d).boundary
                for d in (1.5, 4.1, 6.0)]
        @test maximum(bdur) - minimum(bdur) <= 2 * step(scan)
        @test maximum(bdur) - minimum(bdur) < (bmag[end] - bmag[1]) / 4
    end

    @testset "V7f — why the defence plan cannot save this separation" begin
        # The mechanism, not the outcome. At the nominal cell the ladder's first
        # stage arms at 49.8 Hz and the area does not reach 49.8 Hz until AFTER
        # the angle has passed 90°, so arming the full Fig 3-67 ladder cannot
        # change the crossing — asserted as an ORDER between two root-found
        # instants and as the crossing being identical to far inside one step.
        bare  = IB.run_cell()
        armed = IB.run_cell(; shed = true)
        lg = shed_log(shed_ladder(armed.eng, :IB))
        @test !isempty(lg.t)                       # the ladder does fire…
        @test first(lg.t) > bare.t90               # …but only after the crossing
        @test armed.t90 ≈ bare.t90 atol = 1e-9     # so the crossing does not move
        @test armed.slipped && bare.slipped
        # And the ladder is doing real work on the quantity it CAN affect, which
        # is what makes the line above a statement about timing rather than about
        # a ladder that failed to fire: nearly 3 Hz of frequency nadir.
        @test armed.f_ib_min - bare.f_ib_min > 2.5
        # Arresting the frequency and holding synchronism are different things.
        @test armed.n_pole_slips >= 1
    end

    @testset "V7g — the pre-event tie flow is the parameter the ceiling turns on" begin
        # §7.3(d) of entsoe-iberia-reproduction.md concluded that a
        # constant-voltage two-area reduction can reproduce the separation OR the
        # report's ~5,000 MW export swing, never both. That conclusion is a
        # function of the pre-event tie flow's SIGN, which m3-context.md D8 and
        # §7.3(d)'s own arithmetic disagree about and the report (as extracted)
        # states only the CHANGE in. Asserted both ways round so neither reading
        # can be quietly adopted later without this going red.
        scan = 2_500.0:500.0:9_000.0
        swing_needs(p0) = 5_000.0 + p0        # peak export is P_max; swing = P_max − p0
        # THE PREMISE FIRST, measured. Both lines below rest on the peak tie
        # export being P_max in a slipping cell — true once the angle passes 3π/2,
        # but reasoned rather than observed unless it is asserted. `run_cell`
        # already returns it, so tie the arithmetic to the measurement.
        probe = IB.run_cell(; P_max_mw = 4_000.0)
        @test probe.slipped
        @test probe.peak_export ≈ 4_000.0 rtol = 1e-6
        @test probe.swing ≈ 4_000.0 - probe.net.machines[1].P0 rtol = 1e-6

        imp  = IB.slip_boundary(; scan = scan, P_tie0_mw = -1_000.0).boundary
        exp_ = IB.slip_boundary(; scan = scan, P_tie0_mw = +1_000.0).boundary
        @test swing_needs(-1_000.0) < imp     # importing: BOTH reproducible
        @test swing_needs(+1_000.0) > exp_    # exporting: the §7.3(d) ceiling holds
        # The direction of the effect, so the two lines above cannot both pass on
        # a boundary that ignored `P_tie0_mw` altogether.
        @test imp > exp_
    end
end
