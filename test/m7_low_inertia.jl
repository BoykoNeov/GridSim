# ─────────────────────────────────────────────────────────────────────────────
# M7 step 7 — the low-inertia study (`scripts/low_inertia.jl`, m7-context.md D16)
#
# The script is a deliverable, so its claims are asserted here, against the script's
# own functions (the `LowInertia` module in `runtests.jl`), never against a second copy
# of its fixture. Every claim was written AFTER the tables were read, and three that
# were drafted first did not survive them (D16, "What the study measured").
#
# Short horizons wherever the assertion is about t⁺: the instant after the trip is
# fixed by the algebraic re-solve, so a run of 0.1 s past it carries the whole answer.
# ─────────────────────────────────────────────────────────────────────────────

const _LI = LowInertia
const _T_PLUS = _LI.T_TRIP + 0.1

@testset "M7 step 7 — the low-inertia study" begin

    @testset "positive control: zero share reproduces M1's recorded RoCoF₀, both layouts" begin
        # Constant-power loads, where the closed form is exact; M1's number is read off
        # M1's own engine running `example_system()` — the fixture this study is built from.
        for c in _LI.m1_control()
            @test abs(c.gap) < 1e-11
        end
        # …and the two recorded values themselves, so a change to M1 cannot move both
        # sides of the comparison at once.
        cs = _LI.m1_control(; topologies = (:ring,))
        @test cs[1].m1 ≈ -7500 / 2150 && cs[2].m1 ≈ -3000 / 3250
    end

    @testset "matched dispatch: every row of a sweep starts from the same operating point" begin
        # The design claim in the script's header. A grid-forming inverter holds the bus
        # voltage the machine left, a grid-following one injects the machine's P and Q,
        # so the displaced network solves to the SAME point — whatever differs after the
        # trip is the displacement and nothing else.
        for (topology, event) in ((:ring, :G4), (:chain, :G1))
            m = _LI.matched_dispatch(topology; slack = _LI._slack(event))
            V0 = _LI.study_cell(topology, event, :machine, 0; T = _T_PLUS, match = m).V_pre
            for kind in (:grid_following, :grid_forming), n in 1:3
                r = _LI.study_cell(topology, event, kind, n; T = _T_PLUS, match = m)
                isempty(r.V_pre) && continue        # refused at init: nothing to compare
                @test maximum(abs, r.V_pre .- V0) < 1e-8
            end
        end
    end

    @testset "RoCoF₀ on default loads is accounted for EXACTLY: lost power, load relief, GFL change" begin
        # Lossless network, so at t⁺ the survivors' inertia sees exactly
        #     Σ 2H·ω̇ = −P_lost + (P_load⁻ − P_load⁺) + (P_gfl⁺ − P_gfl⁻)
        # with every term read from bus voltages (the step-7 trip test's correction, plus
        # the load term the default constant-impedance load brings). This is what turns
        # the gap between the formula and network columns into an accounting.
        cells = ((:ring, :G1, :machine, 0), (:ring, :G1, :grid_following, 1),
                 (:ring, :G4, :grid_following, 2), (:chain, :G4, :grid_following, 1),
                 (:chain, :G1, :grid_forming, 2))
        for (topology, event, kind, n) in cells
            r = _LI.study_cell(topology, event, kind, n; T = _T_PLUS)
            @test r.status === :ok
            @test isapprox(r.imbalance, -r.P_lost + r.relief + r.ΔP_gfl; rtol = 1e-8)
        end
        # The relief is the thing that RANKS the two inverter kinds the other way round
        # from the formula: grid-following gives no voltage support, the dip at t⁺ is
        # deeper, more load sheds, and its network RoCoF₀ comes out SHALLOWER than the
        # grid-forming one at the same share, though it has less inertia.
        for (topology, event, n) in ((:ring, :G1, 1), (:ring, :G4, 1), (:ring, :G4, 2),
                                     (:chain, :G1, 1), (:chain, :G4, 1))
            fl = _LI.study_cell(topology, event, :grid_following, n; T = _T_PLUS)
            fm = _LI.study_cell(topology, event, :grid_forming, n; T = _T_PLUS)
            @test fl.H_post < fm.H_post                        # less inertia online…
            @test fl.rocof_cf < fm.rocof_cf                    # …so the formula is steeper…
            @test fl.relief > fm.relief                        # …but more load sheds…
            @test fl.rocof_inst > fm.rocof_inst                # …and the network is not
        end
        # The extreme case, measured: on the chain, ONE grid-following swap makes the
        # network RoCoF₀ shallower than with no inverters at all.
        z = _LI.study_cell(:chain, :G4, :machine, 0; T = _T_PLUS)
        g = _LI.study_cell(:chain, :G4, :grid_following, 1; T = _T_PLUS)
        @test g.H_post < z.H_post && g.rocof_inst > z.rocof_inst
    end

    @testset "anti-vacuity: τ_p → 0 removes exactly the virtual inertia, and nothing else at t⁺" begin
        # The t⁺ re-solve does not read τ_p, so the power imbalance there is IDENTICAL
        # with and without the filter; only the inertia it is divided by changes. Read on
        # the NETWORK column — the formula column computes H from τ_p and would be
        # checking its own input.
        for (topology, event, n) in ((:ring, :G1, 1), (:ring, :G1, 2), (:chain, :G4, 2))
            plain = _LI.study_cell(topology, event, :grid_forming, n; T = _T_PLUS)
            fast  = _LI.study_cell(topology, event, :grid_forming, n; T = _T_PLUS, τ_p = 0.001)
            @test isapprox(fast.imbalance, plain.imbalance; rtol = 1e-9)
            @test isapprox(fast.rocof_inst * fast.H_post, plain.rocof_inst * plain.H_post; rtol = 1e-9)
            @test fast.rocof_inst < plain.rocof_inst          # the inertia benefit, gone
        end
    end

    @testset "what the grid-forming benefit is made of: the droop, not the virtual inertia" begin
        # Ring, small trip, every unit but the tripped one grid-forming — the cell that
        # stays WITHIN its rating (peak 0.97 S_rated), so the missing current limit (D8)
        # cannot be what this measures.
        plain = _LI.study_cell(:ring, :G4, :grid_forming, 3; T = 8.0)
        fast  = _LI.study_cell(:ring, :G4, :grid_forming, 3; T = 8.0, τ_p = 0.001)
        zero  = _LI.study_cell(:ring, :G4, :machine, 0)
        @test plain.gfm_peak < 1.0
        @test abs(fast.nadir - plain.nadir) < 0.05          # nadir: virtual inertia irrelevant
        @test plain.nadir > zero.nadir + 0.5                # …and far shallower than machines'
        @test fast.rocof_inst < 50 * plain.rocof_inst       # while RoCoF₀ explodes without it
    end

    @testset "grid-forming n = 3 and n = 4 rows coincide (the two trip paths agree)" begin
        # Row 4 trips the same unit as row 3, but as a grid-forming inverter instead of a
        # machine. Once it is gone, what it WAS cannot matter: same survivors, same
        # pre-trip state, both injecting nothing. A consistency check of the machine and
        # inverter trip paths, true by construction if both are right.
        #
        # After t⁺ the two runs integrate DIFFERENT state vectors (a dead rotor's states
        # against a dead inverter's), so their adaptive steps differ and the gap is the
        # solver's — measured to fall with the tolerance, 1.9e-5 Hz at the engines'
        # real-time 1e-3, 1.3e-11 at the study's 1e-6, round-off at 1e-8, never banded.
        for (topology, event) in ((:ring, :G1), (:chain, :G4))
            a = _LI.study_cell(topology, event, :grid_forming, 3; T = 4.0)
            b = _LI.study_cell(topology, event, :grid_forming, 4; T = 4.0)
            @test isapprox(a.rocof_inst, b.rocof_inst; rtol = 1e-8)
            @test abs(a.f_end - b.f_end) < 1e-9
            loose(n) = _LI.study_cell(topology, event, :grid_forming, n; T = 4.0,
                                      reltol = 1e-3, abstol = 1e-5)
            @test abs(loose(3).f_end - loose(4).f_end) > 100 * abs(a.f_end - b.f_end)
        end
    end

    @testset "the refusals say which wall they hit" begin
        @test occursin("below the 0.9 band", _LI.study_cell(:ring, :G1, :grid_following, 2; T = _T_PLUS).reason)
        @test occursin("no voltage source would be left",
                       _LI.study_cell(:ring, :G1, :grid_following, 3; T = _T_PLUS).reason)
        @test occursin("nothing to follow", _LI.study_cell(:ring, :G1, :grid_following, 4; T = _T_PLUS).reason)
        # The robust layout contrast is a VOLTAGE, not the chain's refusal (which sits at
        # 0.899 against the 0.9 band and flips on a thousandth): the same 46 % grid-
        # following share holds the ring at 0.963 pu and drops the chain below 0.9.
        # Asserted as the GAP, never as the refusal: pinning `:refused` at 0.899 against
        # 0.9 would turn red on a thousandth of a pu moved by a solver or a manifest.
        ring = _LI.study_cell(:ring, :G4, :grid_following, 2)
        @test ring.status === :ok
        chain = _LI.study_cell(:chain, :G4, :grid_following, 2; T = _T_PLUS)
        m = match(r"= ([0-9.]+) pu at t⁺", chain.reason)
        V_chain = m === nothing ? chain.V_min : parse(Float64, m[1])
        @test V_chain < 0.91
        @test ring.V_min - V_chain > 0.05
    end

    @testset "the claims, on the printed tables (both layouts, both events)" begin
        # The script's section 4, cell by cell, on the SAME sweeps it prints.
        for topology in (:ring, :chain), event in (:G1, :G4)
            rows = _LI.sweep(topology, event)
            row(kind, n) = rows[findfirst(r -> r.kind === kind && r.n == n, rows)]
            z = row(:machine, 0)
            @test all(r -> r.status !== :ok || r.synchronous, rows)
            # (b) grid-forming: RoCoF₀ steeper, nadir SHALLOWER, at every share.
            for n in 1:3
                r = row(:grid_forming, n)
                @test r.status === :ok && r.rocof_inst < z.rocof_inst && r.nadir > z.nadir
            end
            # (c) RoCoF₀ steepens ~4× while the relay's windowed reading stays within
            # −20 %…+5 % of where it started.
            g3 = row(:grid_forming, 3)
            @test 3.5 < g3.rocof_inst / z.rocof_inst < 5.0
            @test -0.20 < g3.rocof_coi / z.rocof_coi - 1 < 0.05
            # (d) grid-following: nadir DEEPER in every cell that ran; on the big trip
            # the second swap leaves the band, and the first settles with no recovery.
            for n in 1:2
                r = row(:grid_following, n)
                r.status === :ok && @test r.nadir < z.nadir
            end
            if event === :G1
                @test occursin("band", row(:grid_following, 2).reason)
                @test !row(:grid_following, 1).falling   # a settle, not a fall (see below)
            end
        end
    end

    @testset "(c) without virtual inertia the relay reads 5–15 % more while machines remain" begin
        for (topology, event) in ((:ring, :G1), (:chain, :G4)), n in 1:3
            plain = _LI.study_cell(topology, event, :grid_forming, n; T = 3.0)
            fast  = _LI.study_cell(topology, event, :grid_forming, n; T = 3.0, τ_p = 0.001)
            rise = fast.rocof_coi / plain.rocof_coi - 1
            @test n < 3 ? (0.04 < rise < 0.16) : (0.0 <= rise < 0.02)
        end
    end

    @testset "a monotone settle is not 'still falling', and its 30 s value is its settle" begin
        # Big trip with one grid-following swap: the reserve is gone and the frequency
        # sinks with no recovery. The first version of the flag called this "still
        # falling" because the minimum was the last sample; run on it SETTLES — 44.30 Hz
        # on the ring, 44.66 on the chain, the same at 120 s and at 240 s — and the 30 s
        # value is within a few mHz of it. The flag now reads the slope over the last
        # second.
        for (topology, f_settle) in ((:ring, 44.30), (:chain, 44.66))
            r = _LI.study_cell(topology, :G1, :grid_following, 1)
            long = _LI.study_cell(topology, :G1, :grid_following, 1; T = 120.0)
            @test r.status === :ok && !r.falling && !long.falling
            @test abs(long.f_end - f_settle) < 0.01
            @test abs(r.f_end - long.f_end) < 0.005
        end
        # …and the flag can fire: the same cell cut off at 3 s IS still falling.
        @test _LI.study_cell(:ring, :G1, :grid_following, 1; T = 3.0).falling
    end
end
