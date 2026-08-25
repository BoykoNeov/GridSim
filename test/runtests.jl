using GridSim
using Test
import CommonSolve
import OrdinaryDiffEq
import SciMLBase
import Observables          # the core→UI seam; also the positive control for the no-Makie test
import Graphs               # to re-derive the graph the SwingEngine builds (edge ordering)
import NetworkDynamics      # to read SwingEngine state symbolically, independently of its index vectors
import Pkg                  # to inspect the dependency closure (no-Makie invariant)

# The Iberian scenario script is a DELIVERABLE, so its claims are asserted below.
# Included as a module so the scenario data stays single-sourced (no second copy of
# the event times living in the test file) without leaking the script's constants
# into the suite's namespace. The script guards `main()` behind PROGRAM_FILE, so
# including it defines everything and runs nothing.
module Iberia
include(joinpath(@__DIR__, "..", "scripts", "iberia_2025_04_28.jl"))
end

# Scaffold-level tests: they exercise the durable contracts (data model, events,
# engine interface) that ship at initialization. The physics validation for M1
# (closed-form initial RoCoF and settling deviation, docs/SPEC.md §7.6) is added
# alongside FrequencyResponseEngine in the M1 code batch.

@testset "GridSim scaffold" begin

    # Returns the ArgumentError message a thunk throws, or a marker string. Used
    # instead of a bare `@test_throws ArgumentError` so a guard test cannot pass
    # because a *different* guard fired first — several of the invalid models
    # below violate more than one rule, and "it threw" would not distinguish them.
    argerr_msg(f) = try
        f()
        "NO ERROR THROWN"
    catch e
        e isa ArgumentError ? e.msg : "NOT-ArgumentError: $(typeof(e))"
    end

    @testset "domain model" begin
        sys = example_system()
        @test sys isa SystemModel
        @test sys.S_base == 550.0
        @test sys.f0 == 50.0
        @test length(sys.units) == 4
        @test all(u -> u isa GeneratingUnit, sys.units)
        # headroom is non-negative for every unit (Pmax ≥ P0)
        @test all(u -> u.Pmax ≥ u.P0, sys.units)
        # ids are unique
        @test length(unique(u.id for u in sys.units)) == length(sys.units)
    end

    @testset "events" begin
        @test TripGenerator(:G1) isa PerturbationEvent
        @test TripGenerator(:G1).id === :G1
        @test StepLoad(-0.1) isa PerturbationEvent
        @test StepLoad(-0.1).ΔP_pu == -0.1
    end

    @testset "engine interface exists" begin
        @test SimulationEngine isa Type
        # the interface verbs are defined as generic functions (no methods yet)
        for f in (init!, step!, solve!, current_state, state_series, inject!)
            @test f isa Function
        end
    end

    @testset "step!/solve! share CommonSolve's generic (no collision)" begin
        # The whole point of the fix: GridSim's exported `step!`/`solve!` ARE
        # CommonSolve's, so once a DiffEq package (which re-exports CommonSolve's
        # verbs) is `using`-ed in an engine module, there is one generic, not two
        # in conflict. Two `===` exported bindings cannot raise an export-
        # ambiguity warning.
        @test GridSim.step! === CommonSolve.step!
        @test GridSim.solve! === CommonSolve.solve!
        # `init!` stays uniquely ours — CommonSolve exports `init`, not `init!`.
        @test parentmodule(GridSim.init!) === GridSim
    end

    @testset "DiffEq dep loaded: shares one generic, no collision" begin
        # The empirical proof the scaffold's `import CommonSolve` fix actually
        # holds once a real SciML solver package is loaded (m1-tasks.md). Before
        # this, the `===` checks above only proved GridSim agrees with the
        # interface package; they could not prove OrdinaryDiffEq agrees too. Both
        # verbs matter: `step!` is the real-time path, `solve!` the playback path.
        @test OrdinaryDiffEq.step! === CommonSolve.step!
        @test OrdinaryDiffEq.solve! === CommonSolve.solve!
        # The transitive payoff — GridSim's exported verbs ARE the same generics
        # OrdinaryDiffEq drives its integrator with. Two `using`-imported bindings
        # that are `===` cannot raise an export-ambiguity warning, so an engine
        # doing `using GridSim, OrdinaryDiffEq` sees one `step!`/`solve!`, not two.
        @test GridSim.step! === OrdinaryDiffEq.step!
        @test GridSim.solve! === OrdinaryDiffEq.solve!
    end

    # --- the shared bounded trajectory recorder (src/engines/recorder.jl) -------
    #
    # Every engine records through this instead of growing its own vectors. The
    # retention rule is: a sample whose 1-based push index is `n` is kept iff
    # `(n-1) % keep_every == 0`, and `keep_every` doubles each time the buffer
    # fills. So the retained samples are always an arithmetic progression that
    # starts at the very first sample — which is the property these tests assert,
    # rather than a hand-traced sequence that would only prove one capacity.

    # Both entry points are swept, not just one. `record!` has a varargs form (arity
    # pinned by the type parameter) and a vector form for engines whose channel count
    # is only known at construction — and `SwingEngine` records *exclusively* through
    # the vector one, so a sweep of the varargs path alone would leave the newer
    # engine's actual code path unasserted. They share one retention decision
    # (`_accept!`), which is what this pair of sweeps is really checking stays true.
    RECORD_ENTRY_POINTS = (("varargs", (rec, t, x) -> GridSim.record!(rec, t, x)),
                           ("vector",  (rec, t, x) -> GridSim.record!(rec, t, [x])))

    @testset "TrajectoryRecorder: retention invariant, via $label" for
            (label, push_sample) in RECORD_ENTRY_POINTS
        # Odd capacities are where the stride bookkeeping goes off by one, so they
        # are in the sweep deliberately. Each property is checked after *every* one
        # of the 200 pushes but reported as one assertion per capacity, with the
        # offending push indices in the failure output.
        for cap in (2, 3, 4, 5, 8, 9)
            rec = GridSim.TrajectoryRecorder(:x; capacity = cap)
            over_capacity, lost_first, not_progression, ragged, unevenly_spaced =
                Int[], Int[], Int[], Int[], Int[]
            for n in 1:200
                push_sample(rec, 0.1 * n, Float64(n))
                tr = GridSim.series(rec)
                k = rec.keep_every
                GridSim.n_kept(rec) <= cap || push!(over_capacity, n)
                # The first sample must survive every halving — that is the whole
                # reason for decimating instead of dropping the oldest: the nadir
                # and the initial RoCoF both live at the start of a disturbance.
                tr.x[1] == 1.0 || push!(lost_first, n)
                # Retained samples are exactly the progression 1, 1+k, 1+2k, ...
                tr.x == collect(1.0:k:Float64(n)) || push!(not_progression, n)
                length(tr.t) == length(tr.x) == GridSim.n_kept(rec) || push!(ragged, n)
                # ...hence evenly spaced in time, which is what any consumer that
                # finite-differences or plots the series depends on.
                length(tr.t) >= 2 && !all(≈(0.1 * k), diff(tr.t)) &&
                    push!(unevenly_spaced, n)
            end
            @test over_capacity == Int[]
            @test lost_first == Int[]
            @test not_progression == Int[]
            @test ragged == Int[]
            @test unevenly_spaced == Int[]
            @test rec.n_seen == 200            # every sample was *offered*...
            @test GridSim.n_kept(rec) < 200    # ...and the buffer is bounded anyway
        end
    end

    @testset "TrajectoryRecorder: the capacity-4 trace, by hand" begin
        # The property test above generalises this, but a worked example pins the
        # intent: at capacity 4 the buffer halves at pushes 5, 9, 17, ...
        rec = GridSim.TrajectoryRecorder(:x; capacity = 4)
        got = Vector{Float64}[]
        for n in 1:9
            GridSim.record!(rec, Float64(n), Float64(n))
            push!(got, copy(GridSim.series(rec).x))
        end
        @test got[4] == [1.0, 2.0, 3.0, 4.0]      # full, stride still 1
        @test got[5] == [1.0, 3.0, 5.0]           # halved, stride 2, sample 5 kept
        @test got[7] == [1.0, 3.0, 5.0, 7.0]      # full again
        @test got[9] == [1.0, 5.0, 9.0]           # halved, stride 4, sample 9 kept
        @test rec.keep_every == 4
    end

    @testset "TrajectoryRecorder: shape, names, and guards" begin
        rec = GridSim.TrajectoryRecorder(:f, :RoCoF; capacity = 16)
        # `:t` is prepended by the recorder and comes first, so no consumer can be
        # handed data without the time base it needs to place the samples.
        @test propertynames(GridSim.series(rec)) == (:t, :f, :RoCoF)
        @test GridSim.n_kept(rec) == 0
        # Arity is pinned by the type parameter: a call with the wrong number of
        # channels fails at the call site, not as a length mismatch found later.
        @test_throws MethodError GridSim.record!(rec, 0.0, 1.0)
        @test_throws MethodError GridSim.record!(rec, 0.0, 1.0, 2.0, 3.0)
        @test occursin("prepended automatically",
                       argerr_msg(() -> GridSim.TrajectoryRecorder(:t, :f)))
        @test occursin("at least one channel",
                       argerr_msg(() -> GridSim.TrajectoryRecorder()))
        @test occursin("duplicate channel",
                       argerr_msg(() -> GridSim.TrajectoryRecorder(:f, :f)))
        @test occursin("capacity must be >= 2",
                       argerr_msg(() -> GridSim.TrajectoryRecorder(:f; capacity = 1)))
        # Concrete field types on the hot path (SPEC §4).
        @test isconcretetype(fieldtype(typeof(rec), :channels))
    end

    @testset "recorder: engine nadir survives decimation (summary ≠ buffer)" begin
        # The trap this guards: once the buffer decimates, `minimum(series.f)` is
        # the lowest *retained* sample, not the lowest that occurred. Running
        # summaries must therefore be tracked incrementally, outside the buffer.
        sys = example_system()
        run_engine(cap) = begin
            eng = init!(FrequencyResponseEngine, sys; dt = 0.02, capacity = cap)
            inject!(eng, TripGenerator(:G1))
            for _ in 1:3000; step!(eng, 0.02); end
            eng
        end
        small, big = run_engine(64), run_engine(200_000)
        @test GridSim.n_kept(small.traj) <= 64
        @test GridSim.n_kept(big.traj) == 3001          # nothing dropped at all
        # The nadir is identical either way — it is not read off the buffer.
        @test small.nadir ≈ big.nadir atol = 1e-12
        # And it had better not be, because the decimated buffer genuinely lost it:
        # the lowest retained sample is strictly above the true nadir.
        @test minimum(GridSim.series(small.traj).f) > small.nadir + 1e-9
        @test minimum(GridSim.series(big.traj).f) ≈ big.nadir atol = 1e-12
    end

    @testset "aggregates (COI, on system base) vs hand arithmetic" begin
        sys = example_system()   # S_base=550, D=1.5, Tg=8.0; all R=0.05
        all_ids = Set(u.id for u in sys.units)

        # All four online. H_sys = Σ Hᵢ·Sᵢ / S_base:
        #   (4.0·200 + 3.5·150 + 3.0·100 + 2.5·100)/550 = 1875/550.
        # 1/R_eq = Σ (1/Rᵢ)·(Sᵢ/S_base) = 20·(200+150+100+100)/550 = 20·1 = 20
        #   (ΣSᵢ == S_base here, so R_eq collapses to the common 0.05 droop).
        a = GridSim.aggregates(sys, all_ids)
        @test a.H_sys ≈ 1875 / 550
        @test a.R_eq ≈ 0.05
        @test a.D == 1.5            # system-wide pass-through
        @test a.Tg == 8.0
        # headroom = Σ(Pmaxᵢ−P0ᵢ)/S_base = (50+40+30+40)/550 = 160/550.
        @test a.headroom ≈ 160 / 550

        # Trip G1 (200 MVA, H=4): only G2,G3,G4 online.
        #   H_sys = (525+300+250)/550 = 1075/550.
        #   1/R_eq = 20·(150+100+100)/550 = 7000/550 → R_eq = 550/7000.
        b = GridSim.aggregates(sys, Set([:G2, :G3, :G4]))
        @test b.H_sys ≈ 1075 / 550
        @test b.R_eq ≈ 550 / 7000
        # Tripping G1 also takes G1's own 50 MW headroom out of the pool:
        #   headroom = (40+30+40)/550 = 110/550.
        @test b.headroom ≈ 110 / 550
        # Losing inertia lowers H_sys; losing a unit lowers droop gain ⇒ raises R_eq;
        # and removes that unit's reserve ⇒ lowers headroom.
        @test b.H_sys < a.H_sys
        @test b.R_eq > a.R_eq
        @test b.headroom < a.headroom

        # No units online ⇒ zero inertia, zero droop gain (R_eq = Inf, not NaN),
        # zero reserve.
        z = GridSim.aggregates(sys, Set{Symbol}())
        @test z.H_sys == 0.0
        @test z.R_eq == Inf
        @test z.headroom == 0.0
    end

    @testset "fr_rhs!: swing/governor RHS + headroom saturation in the derivative" begin
        # Hand-built params (not from a system) so each scenario is isolated.
        # H_sys=2, R_eq=0.05, D=1.5, Tg=8, a generation-loss imbalance, ceiling 0.2.
        mk(; ΔP_dist = -0.27, headroom = 0.2) =
            GridSim.FRParams(2.0, 0.05, 1.5, 8.0, ΔP_dist, headroom)
        du = zeros(2)

        # Initial RoCoF: at the trip instant the state is the origin, so the swing
        # equation collapses to dΔω/dt = ΔP_dist/(2·H_sys) (closed form, SPEC §7.6).
        p = mk()
        GridSim.fr_rhs!(du, [0.0, 0.0], p, 0.0)
        @test du[1] ≈ p.ΔP_dist / (2 * p.H_sys)
        @test du[2] == 0.0                      # −0/R_eq − 0 = 0
        # RHS is type-stable and non-allocating in the hot path.
        @test (@inferred GridSim.fr_rhs!(du, [0.0, 0.0], p, 0.0)) === nothing

        # Governor term below the ceiling, under-frequency (Δω<0) ⇒ ramp UP.
        #   dΔPm = (−(−0.02)/0.05 − 0.1)/8 = (0.4 − 0.1)/8 = 0.0375 > 0.
        GridSim.fr_rhs!(du, [-0.02, 0.1], mk(), 0.0)
        @test du[2] ≈ 0.0375
        @test du[2] > 0                         # not at the ceiling ⇒ free to rise

        # SATURATION BINDS: ΔPm already at headroom and the governor wants more.
        #   raw dΔPm = (0.4 − 0.2)/8 = 0.025 > 0 ⇒ zeroed.
        GridSim.fr_rhs!(du, [-0.02, 0.2], mk(), 0.0)
        @test du[2] == 0.0

        # RELEASE (the test a naive state-clamp fails): at the ceiling but Δω has
        # recovered (Δω>0), so the governor term is negative — ΔPm must be allowed
        # to come back DOWN. raw dΔPm = (−0.2 − 0.2)/8 = −0.05 < 0 ⇒ NOT zeroed.
        GridSim.fr_rhs!(du, [0.01, 0.2], mk(), 0.0)
        @test du[2] ≈ -0.05
        @test du[2] < 0

        # R_eq = Inf (no droop / no online droop) ⇒ −Δω/R_eq = 0, no NaN.
        q = GridSim.FRParams(2.0, Inf, 1.5, 8.0, -0.1, 0.2)
        GridSim.fr_rhs!(du, [-0.01, 0.0], q, 0.0)
        @test all(isfinite, du)
        @test du[2] == 0.0                      # (−0 − 0)/Tg = 0
    end

    @testset "FrequencyResponseEngine: build, step, trip, closed-form checks" begin
        sys = example_system()                  # S_base=550, f0=50, D=1.5, Tg=8

        # --- construction via the interface verb (Type dispatch ⇒ fresh engine) ---
        eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
        @test eng isa FrequencyResponseEngine
        # LOAD-BEARING: the integrator must hold the SAME params object the engine
        # mutates, or `inject!` would silently no-op the running integration.
        @test eng.integrator.p === eng.params
        @test eng.online == Set([:G1, :G2, :G3, :G4])

        # Pre-disturbance: sitting at the origin ⇒ f=f0, RoCoF=0, ΔPm=0.
        s0 = current_state(eng)
        @test s0.f ≈ sys.f0
        @test s0.Δω == 0.0
        @test s0.RoCoF == 0.0
        @test s0.ΔPm == 0.0
        # The parametric design pays off: `current_state` is type-stable.
        @inferred current_state(eng)

        # Stepping with no disturbance keeps us at the origin (ΔP_dist still 0).
        step!(eng, 0.02)
        @test current_state(eng).f ≈ sys.f0

        # --- trip G1 (P0=150) live: only G2,G3,G4 remain online ----------------
        inject!(eng, TripGenerator(:G1))
        @test eng.online == Set([:G2, :G3, :G4])
        a1 = GridSim.aggregates(sys, eng.online)
        @test eng.params.ΔP_dist ≈ -150 / 550          # lost generation, pu
        @test eng.params.H_sys ≈ a1.H_sys              # aggregates refreshed
        @test eng.params.headroom ≈ 110 / 550

        # Closed-form INITIAL RoCoF at the trip instant (state still the origin):
        #   RoCoF0 = f0·ΔP_dist/(2·H_sys) = 50·(−150/550)/(2·1075/550) = −7500/2150.
        s_trip = current_state(eng)
        @test s_trip.RoCoF ≈ 50 * (-150 / 550) / (2 * a1.H_sys)
        @test s_trip.RoCoF ≈ -7500 / 2150
        @test s_trip.RoCoF < 0                          # losing gen ⇒ frequency falls

        # Run it out and check the saturation invariant: G1's trip leaves only
        # 0.2 pu of headroom, which the droop demand exceeds — so ΔPm must pin at
        # the ceiling and NEVER cross it (the post-hoc-clamp landmine).
        for _ in 1:5000                                 # 100 s at dt=0.02
            step!(eng, 0.02)
        end
        @test maximum(state_series(eng).ΔPm) ≤ eng.params.headroom + 1e-6
        @test eng.nadir < sys.f0                         # frequency dipped
        @test current_state(eng).f < sys.f0              # and settles below nominal
        # Trajectory recorded one point per step (+ the seeded origin).
        traj = state_series(eng)
        @test length(traj.t) == length(traj.f) == length(traj.ΔPm)
        @test issorted(traj.t)

        # Tripping an already-offline unit is a no-op.
        d_before = eng.params.ΔP_dist
        inject!(eng, TripGenerator(:G1))
        @test eng.params.ΔP_dist == d_before

        # --- separate engine: a SMALL trip whose droop stays below headroom, so
        # the unsaturated settling closed form applies: Δω_ss = ΔP_dist/(D+1/R_eq).
        eng2 = init!(FrequencyResponseEngine, sys; dt = 0.02)
        inject!(eng2, TripGenerator(:G4))               # P0=60, small
        a2 = GridSim.aggregates(sys, eng2.online)
        for _ in 1:4000                                  # 80 s — well past settling
            step!(eng2, 0.02)
        end
        Δω_ss = (-60 / 550) / (a2.D + 1 / a2.R_eq)
        f_ss = sys.f0 * (1 + Δω_ss)
        @test isapprox(current_state(eng2).f, f_ss; atol = 0.02)
        @test current_state(eng2).ΔPm < a2.headroom      # never bound ⇒ clean settle
    end

    @testset "GeneratingUnit rejects negative headroom (Pmax < P0)" begin
        # A unit whose ceiling is below its output is negative reserve — it must
        # fail loud at construction, not silently poison the aggregate headroom.
        @test_throws ArgumentError GeneratingUnit(:bad, 100.0, 3.0, 80.0, 0.05, 50.0)
        # Pmax == P0 (zero headroom) is allowed.
        @test GeneratingUnit(:ok, 100.0, 3.0, 80.0, 0.05, 80.0) isa GeneratingUnit
    end

    @testset "inject!: tripping a non-existent unit throws (caller bug)" begin
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys)
        # The lookup runs BEFORE the online check, so an unknown id is reachable
        # and loud rather than a silent no-op.
        @test_throws KeyError inject!(eng, TripGenerator(:NOPE))
    end

    @testset "StepLoad sign: positive load lowers frequency" begin
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
        # StepLoad is named for LOAD: +0.1 pu adds load ⇒ negative imbalance ⇒ dip.
        inject!(eng, StepLoad(0.1))
        @test eng.params.ΔP_dist ≈ -0.1
        for _ in 1:3000                                  # 60 s — well past settling
            step!(eng, 0.02)
        end
        @test current_state(eng).f < sys.f0              # added load ⇒ frequency falls
        # And shedding load raises it (mirror check on a fresh engine).
        eng2 = init!(FrequencyResponseEngine, sys; dt = 0.02)
        inject!(eng2, StepLoad(-0.1))
        for _ in 1:3000
            step!(eng2, 0.02)
        end
        @test current_state(eng2).f > sys.f0
    end

    @testset "inject! invalidates the FSAL cache (no stale-derivative first step)" begin
        # Bug: Tsit5 is FSAL — it reuses the cached RHS at the current state as the
        # next step's first stage. If inject! mutates params without u_modified!, the
        # first post-trip step integrates from the stale (pre-trip, ==0) derivative.
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.001)
        step!(eng, 0.001)                                # seed a live (zero) FSAL cache
        @test current_state(eng).Δω == 0.0
        inject!(eng, TripGenerator(:G1))                 # true dΔω/dt jumps off zero
        a = GridSim.aggregates(sys, eng.online)
        dΔω0 = (-150 / 550) / (2 * a.H_sys)              # closed-form derivative at trip
        Δω0 = current_state(eng).Δω                      # still exactly 0 (state untouched)
        step!(eng, 0.001)
        # Realized average rate over the first post-trip step must match the true
        # derivative to O(dt); a stale-zero cache biases it low by ~10%, which this
        # tight rtol catches (the old atol=0.02 settling check absorbed it).
        rate = (current_state(eng).Δω - Δω0) / 0.001
        @test isapprox(rate, dΔω0; rtol = 2e-3)
    end

    @testset "second trip after saturation does not freeze the integrator" begin
        # Bug: inject! shrank headroom while leaving ΔPm pinned to the OLD ceiling,
        # so the isoutofdomain guard rejected every step until dt collapsed to an
        # abort — and step! then silently flatlined. The event-boundary re-init
        # (cap ΔPm to the new ceiling) plus the loud retcode check fix both halves.
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
        inject!(eng, TripGenerator(:G1))                 # big trip ⇒ ΔPm rides the ceiling
        for _ in 1:3000                                  # 60 s ⇒ ΔPm pins at headroom
            step!(eng, 0.02)
        end
        @test isapprox(current_state(eng).ΔPm, eng.params.headroom; atol = 1e-3)

        # Second trip: new headroom (110/550 → 80/550) is BELOW the pinned ΔPm.
        inject!(eng, TripGenerator(:G3))
        @test eng.params.headroom ≈ 80 / 550
        # Re-init'd down to the new ceiling at the event boundary (not left stranded).
        @test current_state(eng).ΔPm ≤ eng.params.headroom + 1e-9
        n = length(state_series(eng).ΔPm)
        t0 = eng.integrator.t
        for _ in 1:2000                                  # must keep advancing, not abort
            step!(eng, 0.02)
        end
        @test eng.integrator.t > t0 + 39.0               # ~40 s of real progress, no freeze
        @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
        # Post-trip trajectory never crosses the new (shrunken) ceiling.
        @test all(≤(eng.params.headroom + 1e-6), @view state_series(eng).ΔPm[n+1:end])
    end

    # --- M1 validation: closed forms + the low-inertia lesson (SPEC §7.6, §7.8)
    #
    # The engine-level testsets above prove the *mechanics* on one instance each.
    # These sweep the same closed forms across every unit, and add the acceptance
    # criterion the earlier tests do not touch at all: less online inertia ⇒
    # steeper RoCoF and deeper nadir (SPEC §7.8 AC #6).
    #
    # Two shared helpers, defined once for the block below.

    # Rebuild a system with every unit's inertia scaled by `k` and *nothing else*
    # touched. S_rated/P0/R/Pmax are carried through verbatim, so S_base, the
    # disturbance size, R_eq, D and the aggregate headroom are all identical
    # across scalings — which is what makes the comparison inertia-only rather
    # than a confounded "different system" comparison.
    scale_inertia(sys::SystemModel, k::Real) =
        SystemModel(sys.S_base, sys.f0, sys.D, sys.Tg,
                    [GeneratingUnit(u.id, u.S_rated, u.H * k, u.P0, u.R, u.Pmax)
                     for u in sys.units])

    # Trip one unit from a cold engine and run it out. Returns the readings the
    # closed forms and the ordering checks are stated in.
    function trip_and_run(sys::SystemModel, id::Symbol; dt = 0.02, T = 150.0)
        eng = init!(FrequencyResponseEngine, sys; dt = dt)
        inject!(eng, TripGenerator(id))
        RoCoF0 = current_state(eng).RoCoF        # read at the trip instant, un-stepped
        for _ in 1:round(Int, T / dt)
            step!(eng, dt)
        end
        s = current_state(eng)
        a = GridSim.aggregates(sys, eng.online)  # post-trip aggregates
        return (; RoCoF0, nadir = eng.nadir, Δω_end = s.Δω, f_end = s.f,
                ΔPm_end = s.ΔPm, ΔPm_max = maximum(state_series(eng).ΔPm), aggr = a)
    end

    P0_of(sys, id) = first(u.P0 for u in sys.units if u.id === id)

    @testset "closed form: initial RoCoF, swept over every single-unit trip" begin
        # SPEC §7.6 / §7.8 AC #4. RoCoF0 = −f0·(P_k/S_base)/(2·H_sys), where H_sys
        # is the POST-trip aggregate — the tripped unit's inertia is gone the
        # instant it goes offline, which is the whole reason the number is
        # interesting. The state is still exactly the origin (Δω=0, ΔPm=0), so the
        # swing equation collapses to this with no transient contribution; read it
        # with no intervening step! or the state has already moved off the origin.
        sys = example_system()
        for u in sys.units
            eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
            inject!(eng, TripGenerator(u.id))
            a = GridSim.aggregates(sys, eng.online)
            @test a.H_sys > 0                     # never the all-offline edge (RoCoF → ∓Inf)
            expected = -sys.f0 * (u.P0 / sys.S_base) / (2 * a.H_sys)
            s = current_state(eng)
            @test s.RoCoF ≈ expected              # exact closed form, default rtol
            @test s.RoCoF < 0                     # losing generation ⇒ frequency falls
            @test s.Δω == 0.0                     # still at the origin: no state jump
            @test s.ΔPm == 0.0                    # governors have not moved yet
        end
    end

    @testset "closed form: settling deviation, swept over every trip" begin
        # SPEC §7.6 / §7.8 AC #5. Δω_ss = ΔP_dist/(D + 1/R_eq) — but ONLY while the
        # governors are unsaturated; the formula assumes ΔPm can reach the droop
        # demand *at the fixed point*. G2/G3/G4 do, so they get a tolerance that
        # bites: rtol = 1e-6, ~4 orders tighter than the ±0.02 Hz used in the
        # engine testset above. (That looseness is what once absorbed the stale-
        # derivative bug — a closed-form check with a tolerance looser than the
        # physics deserves is where the next bug hides.)
        sys = example_system()
        for id in (:G2, :G3, :G4)
            r = trip_and_run(sys, id)
            Δω_ss = (-P0_of(sys, id) / sys.S_base) / (r.aggr.D + 1 / r.aggr.R_eq)
            # Precondition, asserted not assumed — and stated on the *equilibrium*,
            # which is what the closed form is about: at the fixed point the droop
            # demand ΔPm_ss = −Δω_ss/R_eq must sit strictly under the ceiling, so
            # the saturation branch is inactive there. G2's overshoot does briefly
            # touch the ceiling on the way (measured, not assumed: its ΔPm_max sits
            # exactly at headroom), which clips the transient but cannot move the
            # equilibrium — the saturation is switched off again by the time the
            # trajectory settles. Hence the transient peak is checked against the
            # ceiling, not against the precondition.
            @test r.ΔPm_end < r.aggr.headroom - 1e-3
            @test r.ΔPm_max ≤ r.aggr.headroom + 1e-9
            @test isapprox(r.Δω_end, Δω_ss; rtol = 1e-6)
            @test isapprox(r.f_end, sys.f0 * (1 + Δω_ss); rtol = 1e-6)
        end

        # G1 is the counter-case that proves the precondition is load-bearing, not
        # decoration: its droop demand exceeds the surviving reserve, ΔPm pins at
        # the ceiling, and the system settles *below* the unsaturated formula. A
        # test suite that only ever checked the formula would call this a failure;
        # it is the physics (reserve exhaustion), and the ceiling still holds.
        r1 = trip_and_run(sys, :G1)
        Δω_ss_unsat = (-P0_of(sys, :G1) / sys.S_base) / (r1.aggr.D + 1 / r1.aggr.R_eq)
        @test isapprox(r1.ΔPm_end, r1.aggr.headroom; atol = 1e-6)   # pinned
        @test r1.Δω_end < Δω_ss_unsat                               # deeper than the formula
        @test r1.ΔPm_max ≤ r1.aggr.headroom + 1e-9                  # ceiling never crossed
    end

    @testset "less inertia ⇒ steeper RoCoF and deeper nadir (inertia-only)" begin
        # SPEC §7.8 AC #6 — the low-inertia/renewables lesson, isolated. Only the
        # inertia moves; the disturbance, droop gain, damping and reserve are
        # identical across all four systems, so any difference in the response is
        # attributable to inertia and nothing else.
        base = example_system()
        ks = (2.0, 1.0, 0.5, 0.25)                   # decreasing inertia
        rs = [trip_and_run(scale_inertia(base, k), :G4) for k in ks]

        # Settling is inertia-FREE: Δω_ss = ΔP_dist/(D + 1/R_eq) has no H in it.
        # So every config must land on the SAME frequency and differ only in how
        # far it dipped on the way. Asserting the equality alongside the ordering
        # is a much sharper statement of the lesson than the ordering alone.
        # Mixing sources here is deliberate and safe: the disturbance comes from
        # `base` while D/R_eq come from the k=2.0 config's aggregates — legal
        # *because* droop, damping and reserve are invariant under inertia
        # scaling, which is the very premise this testset rests on. If
        # `scale_inertia` ever grows to touch a second field, that invariance is
        # gone and this line silently compares against the wrong baseline instead
        # of failing, so the two must move together.
        a = rs[1].aggr
        Δω_ss = (-P0_of(base, :G4) / base.S_base) / (a.D + 1 / a.R_eq)
        f_ss = base.f0 * (1 + Δω_ss)
        for r in rs
            @test isapprox(r.Δω_end, Δω_ss; rtol = 1e-4)
            # No confound: if the ceiling bound in the low-inertia configs but not
            # the high-inertia ones, the "deeper nadir" would be partly reserve
            # exhaustion rather than inertia. Fail loudly instead of quietly.
            @test r.ΔPm_max < r.aggr.headroom - 1e-3
            # Not a vacuous ordering: each config must genuinely undershoot its
            # settling value. If a future parameter edit overdamped the system the
            # nadir would collapse onto f_ss in every config and the ordering below
            # would start passing on floating-point noise with nothing behind it.
            @test r.nadir < f_ss - 0.1
        end

        # Initial RoCoF: strictly steeper as inertia falls, and exactly inversely
        # proportional to it (halving H doubles RoCoF0 — same ΔP over half the
        # inertia). The exact ratio is a stronger check than the ordering.
        @test issorted([r.RoCoF0 for r in rs]; rev = true)   # increasingly negative
        for i in 2:length(ks)
            @test isapprox(rs[i].RoCoF0 / rs[1].RoCoF0, ks[1] / ks[i]; rtol = 1e-9)
        end

        # Nadir: strictly deeper as inertia falls. Physically — with a slow
        # governor (Tg = 8 s) the early fall is governed by inertia alone, so a
        # lighter system plunges further toward the damping-only asymptote before
        # the governors arrive to arrest it.
        @test issorted([r.nadir for r in rs]; rev = true)     # monotonically lower
        @test rs[end].nadir < rs[1].nadir - 0.5               # a visible gap, not noise
    end

    @testset "fewer units online ⇒ steeper RoCoF and deeper dip (SPEC AC #6)" begin
        # The literal wording of AC #6 ("fewer/less-inertia units online"). This is
        # the DEMONSTRATION, not the isolation: taking a unit offline moves inertia
        # and droop gain and reserve together, so unlike the inertia-only testset
        # above the two configs do NOT settle to the same frequency. Both effects
        # push the same way, which is exactly the operational point.
        sys = example_system()

        # Same disturbance (trip G4) in a full system vs one already missing G3.
        # Measure the dip relative to the pre-trip frequency, since the depleted
        # system is already below nominal when the second trip lands.
        function dip_after(pretrips, id; dt = 0.02, T = 150.0)
            eng = init!(FrequencyResponseEngine, sys; dt = dt)
            for p in pretrips
                inject!(eng, TripGenerator(p))
                for _ in 1:round(Int, T / dt)      # let the pre-trip fully settle
                    step!(eng, dt)
                end
            end
            f_before = current_state(eng).f
            mark = length(state_series(eng).f)
            inject!(eng, TripGenerator(id))
            RoCoF0 = current_state(eng).RoCoF
            for _ in 1:round(Int, T / dt)
                step!(eng, dt)
            end
            tr = state_series(eng)
            tail = mark:length(tr.f)
            return (; RoCoF0, dip = f_before - minimum(@view tr.f[tail]),
                    ΔPm_max = maximum(@view tr.ΔPm[tail]),
                    headroom = GridSim.aggregates(sys, eng.online).headroom)
        end

        full = dip_after(Symbol[], :G4)
        thin = dip_after([:G3], :G4)

        @test thin.RoCoF0 < full.RoCoF0            # steeper (both negative)
        @test thin.dip > full.dip                  # deeper dip below the pre-trip point
        # And the second mechanism the depleted system exposes: its surviving
        # reserve is smaller, so the same trip now exhausts it. Ceiling still holds.
        @test full.ΔPm_max < full.headroom - 1e-3        # full system: reserve to spare
        @test isapprox(thin.ΔPm_max, thin.headroom; atol = 1e-6)   # depleted: pinned
        @test thin.ΔPm_max ≤ thin.headroom + 1e-9
    end

    # --- orchestration: event queue + real-time loop (docs/SPEC.md §7.5) ------
    #
    # Every loop test below terminates on its own: either a finite `duration` with
    # `rtf = Inf` (no sleeping, so it cannot outlive the assertion it supports), or
    # an explicit stopper wired to a state callback plus a wall-clock watchdog. A
    # `while running[]` loop with wall-clock pacing is the classic way to hang a
    # suite, and a hung suite is worse than a failing one.

    @testset "load shedding: latching, downward-only, root-found" begin
        # The ladder is an ARMED PROTECTION SCHEME, not a user-injected event: it
        # fires on the system's own state, at a root-found instant, once per stage.
        sys = example_system()
        stage = LoadShedStage(49.5, 0.02; label = :s1)
        eng = init!(FrequencyResponseEngine, sys; dt = 0.01, shed = [stage])
        @test isempty(shed_log(eng.ladder).t)            # nothing fires at build
        @test eng.ladder.armed == [true]
        inject!(eng, TripGenerator(:G4))                 # -60/550 pu => dips past 49.5
        for _ in 1:1500; step!(eng); end                 # 15 s
        lg = shed_log(eng.ladder)
        @test length(lg.t) == 1                          # fired exactly once
        @test lg.label == [:s1]
        @test eng.ladder.armed == [false]                # latched
        @test shed_total(eng.ladder) ≈ 0.02
        # Root-found, not step-quantised: the crossing instant is (almost surely)
        # NOT on the dt grid, and f at that instant is the threshold to solver tol.
        t_fire = lg.t[1]
        @test 0 < t_fire < 15
        @test !isapprox(t_fire / 0.01, round(t_fire / 0.01); atol = 1e-6)
        tr = state_series(eng)
        i = argmin(abs.(tr.t .- t_fire))
        @test isapprox(tr.f[i], 49.5; atol = 0.02)       # within one dt of the grid
        # And it actually helped: same scenario without the ladder settles lower.
        bare = init!(FrequencyResponseEngine, sys; dt = 0.01)
        inject!(bare, TripGenerator(:G4))
        for _ in 1:1500; step!(bare); end
        @test current_state(eng).f > current_state(bare).f
    end

    @testset "load shedding: downward crossings only (affect_neg! slot)" begin
        # Positional-argument hazard: `ContinuousCallback(cond, affect!, affect_neg!)`
        # — `affect!` is the UPcrossing, `affect_neg!` the DOWNcrossing. Wire the shed
        # into the wrong slot and it fires as frequency RISES through the threshold:
        # physically backwards, and silent. Assert both polarities, don't trust the
        # signature.
        #
        # `example_system` is underdamped (ζ ≈ 0.28), so a load shed sends frequency
        # up through a threshold and the swing brings it back down through the same
        # one ~6 s later. That gives both crossings in ONE run, in a known order.
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.01,
                    shed = [LoadShedStage(50.5, 0.02; label = :both_ways)])
        inject!(eng, StepLoad(-0.3))                     # shed load => f climbs
        for _ in 1:200; step!(eng); end                  # t = 2 s: f ≈ 52.8, well past 50.5
        @test current_state(eng).f > 50.5                # the UPcrossing really happened
        @test isempty(shed_log(eng.ladder).t)            # ...and it did NOT fire
        @test eng.ladder.armed == [true]
        for _ in 1:600; step!(eng); end                  # t = 8 s: the swing brings it back
        @test current_state(eng).f < 50.5                # now a DOWNcrossing
        @test length(shed_log(eng.ladder).t) == 1        # ...and it fired
        @test 2.0 < shed_log(eng.ladder).t[1] < 8.0      # on the way down, not the way up
    end

    @testset "load shedding: a fired stage never re-arms" begin
        # The latch sign is the subtle part: a disarmed stage's condition must keep
        # the sign it had just AFTER firing (negative). Return +1.0 instead and the
        # rootfinder sees a manufactured sign change at the disarm instant => double
        # shed. This drives frequency back up through the threshold and down again.
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.01,
                    shed = [LoadShedStage(49.5, 0.001; label = :once)])
        inject!(eng, TripGenerator(:G1))                 # deep dip => fires
        for _ in 1:500; step!(eng); end
        @test length(shed_log(eng.ladder).t) == 1
        inject!(eng, StepLoad(-0.6))                     # haul it back above 49.5
        for _ in 1:2000; step!(eng); end
        @test current_state(eng).f > 49.5
        inject!(eng, StepLoad(0.6))                      # and back down through it
        for _ in 1:2000; step!(eng); end
        @test current_state(eng).f < 49.5
        @test length(shed_log(eng.ladder).t) == 1        # still exactly one shed
        @test shed_total(eng.ladder) ≈ 0.001
    end

    @testset "shed sign == StepLoad(-dP): shedding load raises frequency" begin
        # Pins the convention against a future sign flip: `ΔP_dist += ΔP_pu` for a
        # shed must be the exact mirror of `StepLoad`'s `ΔP_dist -= ΔP_pu`.
        sys = example_system()
        shed_amt = 0.02
        # Fire the ladder at a threshold the trip is guaranteed to cross.
        a = init!(FrequencyResponseEngine, sys; dt = 0.005,
                  shed = [LoadShedStage(49.9, shed_amt; label = :x)])
        inject!(a, TripGenerator(:G4))
        for _ in 1:16000; step!(a); end                  # 80 s — well past settling
        @test length(shed_log(a.ladder).t) == 1
        # Equivalent hand-injected version: same trip, same shed as a StepLoad at the
        # root-found instant. Compare the SETTLING point, which is instant-independent.
        b = init!(FrequencyResponseEngine, sys; dt = 0.005)
        inject!(b, TripGenerator(:G4))
        inject!(b, StepLoad(-shed_amt))
        for _ in 1:16000; step!(b); end
        @test isapprox(a.params.ΔP_dist, b.params.ΔP_dist; rtol = 1e-12)
        # 80 s is ~3.5 damped periods past settling, so the two runs' different shed
        # INSTANTS have decayed out and only the shared fixed point is left. A flipped
        # sign would move that fixed point by ~0.11 Hz — 10⁴x this tolerance.
        @test isapprox(current_state(a).f, current_state(b).f; atol = 1e-5)
    end

    @testset "shed event is integrated, not just recorded (dt refinement)" begin
        # The shed affect! mutates `p` while leaving `u` alone — the stale-FSAL hazard
        # `inject!` arms against by hand. On the callback path DiffEqBase already sets
        # `derivative_discontinuity` before invoking the affect, so no explicit call is
        # needed there; this test is what keeps that true. It matters because the error
        # would be INVISIBLE to any readout assertion: `current_state` recomputes RoCoF
        # algebraically from `_dΔω`, so it would report the right post-shed value while
        # the integration drifted. Only refining dt and demanding convergence
        # discriminates.
        sys = example_system()
        stage = LoadShedStage(49.8, 0.05; label = :fsal)
        function run_to(dt, tend)
            eng = init!(FrequencyResponseEngine, sys; dt = dt, shed = [stage])
            inject!(eng, TripGenerator(:G1))
            for _ in 1:round(Int, tend / dt); step!(eng); end
            return eng
        end
        coarse = run_to(0.01, 3.0)
        fine   = run_to(0.001, 3.0)
        @test length(shed_log(coarse.ladder).t) == 1
        @test length(shed_log(fine.ladder).t) == 1
        # Root-found instant is a property of the trajectory, not of the sampling.
        @test isapprox(shed_log(coarse.ladder).t[1], shed_log(fine.ladder).t[1];
                       atol = 1e-4)
        # 10x refinement must not move the state: a stale-derivative step biases the
        # coarse run by ~dt*ΔP_shed/(2*H_sys), which this rtol rejects.
        @test isapprox(current_state(coarse).Δω, current_state(fine).Δω; rtol = 2e-3)
    end

    @testset "cumulative tripped MW counts generation only" begin
        # The second axis of report Figs 1-3 / 3-7 / 3-9 is tripped GENERATION.
        # Shed load is not generation and must not leak into it.
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.01,
                    shed = [LoadShedStage(49.5, 0.02; label = :s)])
        @test eng.tripped_mw == 0.0
        step!(eng)
        @test state_series(eng).tripped_mw[end] == 0.0
        inject!(eng, TripGenerator(:G1))                 # 150 MW
        step!(eng)
        @test eng.tripped_mw ≈ 150.0
        @test state_series(eng).tripped_mw[end] ≈ 150.0
        inject!(eng, TripGenerator(:G1))                 # already offline => no double count
        @test eng.tripped_mw ≈ 150.0
        inject!(eng, StepLoad(0.05))                     # load, not generation
        @test eng.tripped_mw ≈ 150.0
        inject!(eng, TripGenerator(:G3))                 # +70 MW
        for _ in 1:1500; step!(eng); end
        @test eng.tripped_mw ≈ 220.0
        @test !isempty(shed_log(eng.ladder).t)           # the ladder did fire...
        @test eng.tripped_mw ≈ 220.0                     # ...and did not touch the tally
        # The recorded series is aligned with the trajectory and non-decreasing.
        s = state_series(eng)
        @test length(s.tripped_mw) == length(s.t)
        @test issorted(s.tripped_mw)
        @test s.tripped_mw[end] ≈ 220.0
    end

    @testset "windowed_rocof: 500 ms sliding window, actual elapsed divisor" begin
        # Every RoCoF number in the ENTSO-E report is a 500 ms window (p.116); the
        # engine's `current_state` RoCoF is instantaneous. Different quantities.
        t = collect(0.0:0.01:2.0)
        f = 50.0 .- 2.0 .* t                             # exact -2 Hz/s ramp
        w = windowed_rocof(t, f)
        @test length(w) == length(t)
        @test all(isnan, w[t .< 0.5 - 1e-9])             # window not full yet => NaN
        @test all(x -> isapprox(x, -2.0; atol = 1e-9), filter(!isnan, w))
        @test count(!isnan, w) == count(>=(0.5 - 1e-9), t)
        # Non-uniform samples: the divisor is the ACTUAL elapsed time, not the
        # nominal window. Here the lookback lands 0.7 s back, not 0.5 s.
        tn = [0.0, 0.3, 1.0]
        fn = [50.0, 50.0, 49.0]
        wn = windowed_rocof(tn, fn)
        @test isnan(wn[1]) && isnan(wn[2])
        @test isapprox(wn[3], -1.0 / 0.7; atol = 1e-12)  # -1.4286, not -2.0
        # Window length is a knob.
        @test count(!isnan, windowed_rocof(t, f; window = 1.0)) < count(!isnan, w)
        @test_throws ArgumentError windowed_rocof(t, f[1:end-1])
        @test_throws ArgumentError windowed_rocof(t, f; window = 0.0)
        # NamedTuple method over a real trajectory: the windowed peak is strictly
        # shallower than the instantaneous one during a fast transient.
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.01)
        inject!(eng, TripGenerator(:G1))
        for _ in 1:1000; step!(eng); end
        s = state_series(eng)
        ww = windowed_rocof(s)
        @test ww.t === s.t
        @test length(ww.RoCoF) == length(s.t)
        @test minimum(filter(!isnan, ww.RoCoF)) > minimum(s.RoCoF)
    end

    @testset "inverter-based resources (H=0, R=Inf) give finite aggregates" begin
        # The Iberian scenario models the tripping blocks as IBR: zero inertia, no
        # droop, no headroom. This must stay expressible with no data-model change,
        # and must not produce NaN/Inf where a finite number belongs.
        pv = GeneratingUnit(:PV, 900.0, 0.0, 900.0, Inf, 900.0)
        sync = GeneratingUnit(:SYNC, 1000.0, 4.0, 600.0, 0.05, 800.0)
        sys = SystemModel(2000.0, 50.0, 1.5, 8.0, [sync, pv])
        a = GridSim.aggregates(sys, Set([:SYNC, :PV]))
        @test isfinite(a.H_sys) && a.H_sys ≈ 4.0 * 1000 / 2000     # PV adds no inertia
        @test isfinite(a.R_eq) && a.R_eq > 0                        # 1/Inf = 0, no NaN
        @test a.R_eq ≈ 1 / ((1 / 0.05) * 1000 / 2000)
        @test isfinite(a.headroom) && a.headroom ≈ (800 - 600) / 2000  # PV: zero reserve
        # An all-IBR set is the degenerate corner: no inertia, no droop, no NaN.
        b = GridSim.aggregates(sys, Set([:PV]))
        @test b.H_sys == 0.0 && b.R_eq == Inf && b.headroom == 0.0
        @test !isnan(b.H_sys) && !isnan(b.headroom)
        # And the engine runs with one in the mix: trip the PV, get a finite dip.
        eng = init!(FrequencyResponseEngine, sys; dt = 0.01)
        inject!(eng, TripGenerator(:PV))
        for _ in 1:1000; step!(eng); end
        st = current_state(eng)
        @test isfinite(st.f) && st.f < sys.f0
        @test all(isfinite, state_series(eng).f)
        @test eng.tripped_mw ≈ 900.0
    end

    @testset "Iberia scenario: the two-window structure, asserted not banded" begin
        # The headless script is a deliverable, so its claims are pinned here. It is
        # included as a MODULE so the scenario stays single-sourced (no second copy of
        # the event times in the test) without leaking its constants into the suite;
        # `main()` is guarded by PROGRAM_FILE, so including it runs nothing.
        #
        # THE TOLERANCES ENCODE A STRUCTURE, NOT A BAND. The model errs in opposite
        # directions on either side of ~12:33:17, and one symmetric "close enough"
        # band would hide both halves. So each window is asserted with its own SIGN.
        eng = Iberia.replay()
        s = state_series(eng)
        at(tq) = s.f[argmin(abs.(s.t .- tq))]

        # Window 1 — before loss of synchronism the model runs TOO DEEP, because
        # Iberia was still synchronously inside Continental Europe behind a finite
        # tie and was therefore stiffer than the isolated system modelled here.
        for (tq, fref) in ((55.0, 49.98), (60.0, 49.94), (76.9, 49.90), (77.9, 49.80))
            fm = at(tq)
            @test fm < fref                              # the SIGN is the claim
            @test fref - fm < 0.15                       # …and it stays small
        end

        # Window 2 — 12:33:20 is DELIBERATELY NOT BANDED. The centre-of-inertia model
        # cannot reproduce the last 5 s (plan doc §2): ~5,000 MW of the imbalance was
        # export swing from loss of synchronism, which a two-state swing + governor
        # model has no state for. With the real defence plan armed the model recovers
        # while reality collapsed, so this row is asserted as a KNOWN STRUCTURAL
        # FAILURE. It is not a target: closing it requires the two-area model, and
        # doing so must come with a conscious edit to this assertion — never with a
        # parameter tuned until the number matches.
        @test at(80.0) > 48.50 + 0.5
        @test eng.nadir > 49.0                           # the ladder arrests the fall

        # The defence plan fired the stages the report annotates, in threshold order.
        lg = shed_log(eng.ladder)
        @test length(lg.t) == 4
        @test lg.threshold_hz == [49.8, 49.7, 49.6, 49.5]
        @test issorted(lg.t)                             # in time order too
        @test isapprox(shed_total(eng.ladder) * eng.model.S_base, 3907.0; atol = 1.0)
        # Root-found, so the crossing instants are not on the dt grid.
        @test all(t -> !isapprox(t / 0.01, round(t / 0.01); atol = 1e-6), lg.t)
        # Reality did not reach 49.5 Hz until 12:33:20.133 (report p.174), i.e. AFTER
        # the fidelity boundary; the model gets there ~1.7 s early, the same too-deep
        # error as the waypoints above. Two-sided on purpose: a one-sided "more than
        # 1 s early" would also be satisfied by a run firing at 60 s for unrelated
        # reasons, which is not the claim being made.
        @test 78.0 < lg.t[end] < 79.0

        # Disarming the ladder must make it worse — the mechanism has to be load-bearing.
        # The armed nadir is pinned at the 49.5 Hz threshold (that stage arrests the
        # fall), the disarmed one lands at ~48.73, so the gap is ~0.77 Hz; 0.5 is a
        # deliberate margin under it, not a number that happened to pass. If the
        # ladder's contents change, this is the assertion that moves.
        bare = Iberia.replay(; shed = false)
        @test bare.nadir < eng.nadir - 0.5
        @test isempty(shed_log(bare.ladder).t)

        # Cumulative tripped generation: the scripted sequence, and a lower bound by
        # construction (the report calls the last cluster a floor).
        @test issorted(s.tripped_mw)
        @test s.tripped_mw[end] ≈ 355 + 725 + 930 + 2600

        # The one RoCoF claim that lies INSIDE the faithful window: the report states
        # |RoCoF| stayed within 1 Hz/s until 12:33:20.560 (p.116), measured over a
        # 500 ms sliding window. Instantaneous RoCoF is a different quantity and is
        # steeper by construction — asserted, so the two cannot be conflated later.
        w = windowed_rocof(s)
        inwin = findall(t -> t <= Iberia.T_BOUNDARY, s.t)
        wv = filter(!isnan, w.RoCoF[inwin])
        @test !isempty(wv)
        @test maximum(abs, wv) < 1.0                     # the report's claim
        @test maximum(abs, wv) > 0.2                     # non-vacuous
        @test maximum(abs, wv) < maximum(abs, s.RoCoF[inwin])
    end

    @testset "Iberia scenario: keying the base off KE makes RoCoF0 H-independent" begin
        # The report's 2.21–2.71 s inertia band is uncertainty about how to SPLIT the
        # measured kinetic energy between machines and motor load. `S_base = KE/H_tot`
        # makes f0·ΔP/(2·H_sys) collapse to f0·ΔP_MW/(2·KE), so that split cancels out
        # of the initial RoCoF exactly. The script prints this; here it is pinned, so
        # nobody later reads the identical column as an empirical insensitivity result.
        r_lo  = Iberia.rocof0(Iberia.H_LO, :E6)
        r_mid = Iberia.rocof0(Iberia.H_MID, :E6)
        r_hi  = Iberia.rocof0(Iberia.H_HI, :E6)
        @test isapprox(r_lo, r_mid; rtol = 1e-12)
        @test isapprox(r_hi, r_mid; rtol = 1e-12)
        @test isapprox(r_mid, -50.0 * 2600.0 / (2 * Iberia.KE); rtol = 1e-12)
        @test r_mid < 0                                  # a trip lowers frequency
    end

    @testset "EventQueue" begin
        q = EventQueue()
        @test isempty(q) && length(q) == 0
        @test isempty(drain!(q))                        # draining an empty queue is fine

        push!(q, TripGenerator(:G1))
        push!(q, StepLoad(0.05))
        @test length(q) == 2 && !isempty(q)

        evs = drain!(q)                                 # submission order preserved
        @test evs == [TripGenerator(:G1), StepLoad(0.05)]
        @test isempty(q)                                # …and the queue is now empty
        @test isempty(drain!(q))                        # a second drain yields nothing

        # The swap must hand out a *fresh* vector each time, not alias the one the
        # caller is still holding — otherwise a later push! would mutate it.
        push!(q, TripGenerator(:G2))
        @test length(evs) == 2                          # the earlier batch is untouched
        empty!(q)
        @test isempty(q)
    end

    @testset "timestep is the engine's own dt" begin
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.05)
        @test timestep(eng) == 0.05                     # what run_realtime! defaults to
    end

    @testset "UI accessors: system_inertia falls on a trip, is_online tracks it" begin
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys)
        # The indicator must agree with the aggregate, not merely be non-zero.
        @test system_inertia(eng) ≈ GridSim.aggregates(sys, Set(u.id for u in sys.units)).H_sys
        @test all(is_online(eng, u.id) for u in sys.units)
        @test !is_online(eng, :nope)                    # a button for a ghost unit, not a bug

        H_before = system_inertia(eng)
        inject!(eng, TripGenerator(:G1))
        @test !is_online(eng, :G1)
        @test is_online(eng, :G2)
        # Losing a unit removes its kinetic energy from the pool: strictly less inertia.
        @test system_inertia(eng) < H_before
        @test system_inertia(eng) ≈
            GridSim.aggregates(sys, Set([:G2, :G3, :G4])).H_sys
    end

    @testset "run_realtime! headless (rtf = Inf) with a queued trip" begin
        sys = example_system()
        eng = init!(FrequencyResponseEngine, sys; dt = 0.02)
        obs = Observables.Observable(current_state(eng))
        q = EventQueue()
        push!(q, TripGenerator(:G1))                    # applied at the first step boundary

        out = run_realtime!(eng, obs; rtf = Inf, queue = q, duration = 2.0)

        @test out.engine === eng                        # returns the handles it used
        @test out.queue === q
        @test out.control isa RealtimeControl
        @test isempty(q)                                # the loop drained it
        @test !(:G1 in eng.online)                      # …and injected it

        @test isapprox(current_state(eng).t, 2.0; atol = 0.021)   # ran the sim duration
        @test obs[] == current_state(eng)                # published the latest state
        s = state_series(eng)
        # Seed point + ~100 steps of 0.02. Deliberately a *range*: whether the loop
        # takes 100 or 101 steps turns on where 100 accumulated additions of 0.02
        # land relative to 2.0 in Float64 — not a property worth asserting, and an
        # exact count would fail mysteriously on an integrator bookkeeping change.
        @test 101 ≤ length(s.t) ≤ 102
        @test length(s.f) == length(s.t) == length(s.RoCoF) == length(s.ΔPm)
        @test minimum(s.f) < sys.f0 - 0.05               # losing 150 MW dips frequency
        @test eng.nadir == minimum(s.f)
    end

    @testset "run_realtime! stops when control.running[] is cleared" begin
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
        obs = Observables.Observable(current_state(eng))
        ctl = RealtimeControl(; rtf = Inf)
        # Stop from a state callback: deterministic (counts published states, so it
        # also proves one publish per step) and independent of wall-clock timing.
        published = Ref(0)
        Observables.on(obs) do _
            published[] += 1
            published[] == 10 && stop!(ctl)
        end
        # `duration = Inf` on purpose — the callback is what must end this loop.
        run_realtime!(eng, obs; control = ctl, duration = Inf)
        @test published[] == 10
        @test !ctl.running[]
        @test isapprox(current_state(eng).t, 0.2; atol = 1e-9)   # exactly 10 × dt
    end

    @testset "run_realtime! honours pause and resumes without catch-up sprint" begin
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
        ctl = RealtimeControl(; rtf = Inf, paused = true)
        task = @async run_realtime!(eng, nothing; control = ctl, duration = 1.0)
        # Watchdog: whatever happens, this loop is over within 10 s wall-clock, so a
        # regression in the pause branch fails the test instead of hanging the suite.
        @async (sleep(10.0); stop!(ctl))

        sleep(0.2)
        @test current_state(eng).t == 0.0               # frozen: sim time did not advance
        @test ctl.running[]                             # …but the loop is alive
        ctl.paused[] = false
        wait(task)
        @test isapprox(current_state(eng).t, 1.0; atol = 0.021)   # resumed and finished
    end

    @testset "run_realtime! paces to wall-clock at rtf = 1" begin
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
        t_wall = @elapsed run_realtime!(eng, nothing; rtf = 1.0, duration = 0.2)
        @test isapprox(current_state(eng).t, 0.2; atol = 0.021)
        # Lower bound is the real assertion (it did sleep rather than sprint); the
        # upper bound is deliberately loose — timer resolution and CI load are noisy.
        @test 0.15 < t_wall < 3.0
        # Twice the speed must take less wall-clock time for the same sim duration.
        eng2 = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
        t_wall2 = @elapsed run_realtime!(eng2, nothing; rtf = 4.0, duration = 0.2)
        @test t_wall2 < t_wall
    end

    @testset "run_realtime! picks up an rtf change mid-run" begin
        # The pacing reads control.rtf[] fresh on every pass precisely so the UI's
        # speed slider takes effect immediately. Pin that down: start paced (slow
        # enough to be unmistakably sleeping), then switch to Inf from a state
        # callback — if the loop had captured rtf once at entry, the remaining steps
        # would still crawl and the elapsed time would blow past the bound.
        eng = init!(FrequencyResponseEngine, example_system(); dt = 0.02)
        obs = Observables.Observable(current_state(eng))
        ctl = RealtimeControl(; rtf = 0.1)               # 0.2 s of sim ⇒ 2 s wall-clock
        Observables.on(_ -> (ctl.rtf[] = Inf), obs)      # …unless the first step frees it
        t_wall = @elapsed run_realtime!(eng, obs; control = ctl, duration = 0.2)
        @test isapprox(current_state(eng).t, 0.2; atol = 0.021)
        @test t_wall < 1.0                               # ≫ the ~1.8 s a stale rtf would cost
    end

    @testset "core dependency closure is UI-free (no Makie)" begin
        # The structural invariant (docs/SPEC.md §3.1): the core may reach Observables
        # — that is the seam live state crosses — but never a plotting package. The
        # positive half matters as much as the negative: without it this testset
        # would pass vacuously if `Pkg.dependencies()` ever returned nothing useful.
        names = [d.name for d in values(Pkg.dependencies())]
        @test "Observables" in names                     # positive control
        # The M2 network deps are named explicitly as *further* positive controls:
        # they arrived with ~60 transitive packages, and this scan is only evidence
        # about that closure if the closure it read actually contains them.
        @test "NetworkDynamics" in names
        @test "Graphs" in names
        @test !any(n -> occursin("Makie", n), names)     # the actual invariant
        # Makie is the invariant the SPEC names, but it is not the only way a UI
        # package could enter — a transitive plotting dep would violate §3.1 just
        # as much, and would not contain the string "Makie".
        @test !any(n -> n in ("Plots", "GR", "PyPlot", "PlotlyJS", "UnicodePlots"),
                   names)
    end


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

    # ---- M3 step 1: the governor state ------------------------------------------
    # Full validation of primary response is step 2 (V1–V4). What lives here is the
    # narrow set of claims about the *state-layout change itself* — that M2's models
    # still describe the systems they described, and that the one new failure mode
    # the change creates is closed. `governed_ring` is local to these testsets, not
    # a shipped fixture: step 1 deliberately adds no scenario.

    # The M2 ring with real droop on the two machines that survive a G1 trip.
    # `hr2` is G2's up-reserve in MW, so the same shape serves both the
    # "reserve is ample" and the "reserve runs out" cases.
    function governed_ring(; hr2 = 200.0, hr3 = 60.0, Tg = 5.0)
        buses = [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)]
        machines = [
            Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05,   80.0),               # no governor
            Machine(:G2, :B2, 200.0, 3.0, 2.0, 0.20, 1.03,   30.0, 0.05,   30.0 + hr2, Tg),
            Machine(:G3, :B3, 500.0, 5.0, 2.0, 0.50, 1.04, -110.0, 0.05, -110.0 + hr3, Tg),
        ]
        branches = [Branch(:L12, :B1, :B2, 0.25, 500.0),
                    Branch(:L23, :B2, :B3, 0.25, 500.0),
                    Branch(:L31, :B3, :B1, 0.25, 500.0)]
        return NetworkModel(100.0, 50.0, buses, branches, machines)
    end

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

    @testset "SwingEngine V6: a line trip settles on the closed-form equilibrium" begin
        # The sharper half of step 5, and why it leads. A GENERATOR trip breaks
        # `Σ Pm = 0` and this tier has no governors, so nothing settles (see the
        # test above). A LINE trip changes no `Pm` at all, so the surviving network
        # still has an equilibrium — and on the ring, cutting one line leaves a
        # radial path B1–B2–B3 whose steady state is a chain of `asin`s:
        #   L12 must carry everything machine 1 injects           → asin(Pm₁ / K₁₂)
        #   L23 must carry that plus machine 2's                  → asin((Pm₁+Pm₂) / K₂₃)
        # Both couplings are read from `branch_arrays`, i.e. through the same code
        # path the engine integrates against — copying a hand-computed number is
        # exactly how the D8 coupling error survived its first sitting.
        net = three_machine_ring()
        ma, ba = machine_arrays(net), branch_arrays(net)
        bidx(id) = findfirst(b -> b.id === id, net.branches)
        K12, K23, K31 = ba.K[bidx(:L12)], ba.K[bidx(:L23)], ba.K[bidx(:L31)]
        pred12 = asin(ma.Pm[1] / K12)
        pred23 = asin((ma.Pm[1] + ma.Pm[2]) / K23)

        eng = init!(SwingEngine, net; dt = 0.05)
        n_state = length(eng.integrator.u)
        Pm_before = [eng.params[i] for i in eng.Pm_pidx]
        @test is_online(eng, :B3, :B1)
        inject!(eng, TripLine(:B3, :B1))

        @test !is_online(eng, :B3, :B1)
        @test is_online(eng, :B1, :B2) && is_online(eng, :B2, :B3)
        @test length(eng.integrator.u) == n_state              # never resized
        # No mechanical power moved — which is *why* an equilibrium survives.
        @test [eng.params[i] for i in eng.Pm_pidx] == Pm_before
        # Exactly one coupling died, and it is the one that used to be K31. (The
        # parameter vector is in GRAPH edge order, which is not branch order — so
        # this also re-checks the mapping the header warns about.)
        live = [eng.params[i] for i in eng.K_pidx]
        @test count(iszero, live) == 1
        @test sort(filter(!iszero, live)) ≈ sort([K12, K23])

        for _ in 1:4800; step!(eng, 0.05); end              # 240 s, finite by construction
        st = current_state(eng)
        @test SciMLBase.successful_retcode(eng.integrator.sol.retcode)
        # Every machine back at rest — not merely the aggregate, which can sit at
        # zero while the machines run in opposite directions (see the split test).
        @test maximum(abs, st.ω) < 1e-9
        @test abs(st.ω_coi) < 1e-9
        # Angle DIFFERENCES only: absolute angles are gauge-dependent.
        @test st.δ[1] - st.δ[2] ≈ pred12 atol = 1e-9
        @test st.δ[2] - st.δ[3] ≈ pred23 atol = 1e-9
        # ...and the near misses, so the tolerance is doing work. Charging L23 with
        # machine 2's own injection instead of the cumulative flow lands 0.19 rad
        # out; using the wrong branch's coupling for the L12 leg lands 1.8e-3 out,
        # and that near one is what makes a loose tolerance a real risk.
        @test !isapprox(st.δ[2] - st.δ[3], asin(ma.Pm[2] / K23); atol = 1e-3)
        @test !isapprox(st.δ[1] - st.δ[2], asin(ma.Pm[1] / K31); atol = 1e-4)

        # Naming the line the other way round names the same line.
        other = init!(SwingEngine, net; dt = 0.05)
        inject!(other, TripLine(:B1, :B3))
        @test [other.params[i] for i in other.K_pidx] == live
        # Tripping it again is a no-op; a bus pair no branch joins is a caller bug;
        # a self-loop cannot be a branch and is refused by the event itself.
        @test inject!(eng, TripLine(:B3, :B1)) === eng
        @test_throws KeyError inject!(eng, TripLine(:B1, :B9))
        @test_throws ArgumentError TripLine(:B1, :B1)
    end

    @testset "SwingEngine: a line trip accelerates only its own two ends" begin
        # The second independent bite on the edge-ordering hazard, and one V2
        # cannot deliver: at the instant L31 opens, the machines at ITS ends jump by
        # ∓P₃₁/2H while the third machine's acceleration is exactly zero. Zero the
        # wrong edge and machine 2 moves. `P₃₁` is read off the fixpoint the engine
        # actually reached, so it comes through the real code path.
        net = three_machine_ring()
        ma, ba = machine_arrays(net), branch_arrays(net)
        b31 = findfirst(b -> b.id === :L31, net.branches)
        eng = init!(SwingEngine, net; dt = 0.01)
        δ0 = current_state(eng).δ
        src, dst = ba.src[b31], ba.dst[b31]                 # vertex indices, B3 → B1
        P31 = ba.K[b31] * sin(δ0[src] - δ0[dst])
        @test abs(P31) > 0.5                                # control: it carried real power

        inject!(eng, TripLine(:B3, :B1))
        du = similar(eng.integrator.u)
        eng.integrator.f(du, eng.integrator.u, eng.integrator.p, eng.integrator.t)
        acc = [du[i] for i in eng.ω_idx]
        # The end that was exporting P₃₁ keeps that power and speeds up; the end that
        # was receiving it loses it and slows down.
        @test acc[src] ≈ P31 / (2 * ma.H[src]) atol = 1e-12
        @test acc[dst] ≈ -P31 / (2 * ma.H[dst]) atol = 1e-12
        untouched = only(setdiff(1:3, [src, dst]))
        @test abs(acc[untouched]) < 1e-12
        # ...and that zero is not trivially small: the two ends jumped by ~1e-2.
        @test minimum(abs, acc[[src, dst]]) > 1e-3
    end

    @testset "SwingEngine: the event boundary drops the stale derivative" begin
        # Tsit5 is FSAL — it reuses the cached RHS at the current state as the next
        # step's first stage. Sitting on the fixpoint that cached derivative is
        # exactly zero, so an event that changes the system without telling the
        # integrator makes the first post-trip step start from a stale zero. The M1
        # version of this test is at "inject! invalidates the FSAL cache"; this is
        # the M2 pair of it, run over BOTH trip paths.
        #
        # MEASURED, so the tolerance is calibrated rather than guessed: with both
        # `derivative_discontinuity!` and `auto_dt_reset!` removed the realized first
        # step comes out 9.7% low (9.66% at dt=1e-3, 10.1% at dt=0.02) on every
        # machine that moves — so rtol 2e-3 separates them by a factor of ~50.
        #
        # RECORDED, not patched: the two calls are NOT separably observable here.
        # `auto_dt_reset!` re-evaluates the RHS as a side effect of re-estimating the
        # step, so either call alone suppresses the whole bias and only removing both
        # shows up. The test therefore asserts what is measurable and both calls stay
        # in `inject!` — see docs/plans/m2-context.md.
        net = three_machine_ring()
        for ev in (TripGenerator(:G1), TripLine(:B3, :B1))
            eng = init!(SwingEngine, net; dt = 0.001)
            step!(eng, 0.001)                       # seed a live (zero) FSAL cache
            @test maximum(abs, current_state(eng).ω) < 1e-12
            ω0 = copy(current_state(eng).ω)
            inject!(eng, ev)
            du = similar(eng.integrator.u)
            eng.integrator.f(du, eng.integrator.u, eng.integrator.p, eng.integrator.t)
            truth = [du[i] for i in eng.ω_idx]
            step!(eng, 0.001)
            rate = (current_state(eng).ω .- ω0) ./ 0.001
            moving = findall(a -> abs(a) > 1e-3, truth)
            @test length(moving) >= 2               # control: something has to move
            for i in moving
                @test isapprox(rate[i], truth[i]; rtol = 2e-3)
                # ...and the stale-cache answer is outside that band, so the
                # assertion above is not passing on slack.
                @test !isapprox(0.9034 * truth[i], truth[i]; rtol = 2e-3)
            end
        end
    end

    @testset "SwingEngine: a line trip may split the grid, and the aggregate lies" begin
        # Cutting the only line of the two-machine system leaves two islands. This
        # tier does not refuse that — it is a real event — but the single COI
        # read-out stops meaning anything: each island holds its own frequency, and
        # `ω_coi` is an inertia-weighted average of two unrelated numbers.
        net = two_machine_system()
        ma = machine_arrays(net)
        eng = init!(SwingEngine, net; dt = 0.02)
        br = only(net.branches)
        inject!(eng, TripLine(br.from, br.to))
        @test !is_online(eng, br.from, br.to)
        @test all(id -> is_online(eng, id), machine_ids(eng))   # no machine tripped
        @test all(iszero, [eng.params[i] for i in eng.K_pidx])

        for _ in 1:5000; step!(eng, 0.02); end                  # 100 s
        st = current_state(eng)
        # Decoupled and undriven, each machine runs until its own damping absorbs
        # its own injection: ωᵢ → Pmᵢ/Dᵢ. Opposite signs — one island speeds up by
        # 6% and the other slows by 3.75%, which is nothing like a power system and
        # everything like what this tier says happens.
        @test st.ω ≈ ma.Pm ./ ma.D atol = 1e-7
        @test st.ω[1] > 0.05 && st.ω[2] < -0.03
        # The aggregate is the inertia-weighted mean of those two, which is NOT zero
        # (it would be only if both machines shared an H/D ratio) and is NOT the
        # frequency of either island. Assert the derived value, and assert it is far
        # from both islands, because "≈ 0" would read as "nothing happened".
        pred = sum(ma.H .* (ma.Pm ./ ma.D)) / sum(ma.H)
        @test st.ω_coi ≈ pred atol = 1e-7
        @test abs(pred) > 1e-3
        @test abs(st.ω_coi - st.ω[1]) > 0.05 && abs(st.ω_coi - st.ω[2]) > 0.05
    end

    @testset "SwingEngine: a dead generator does not take its lines out of service" begin
        # `is_online` for a line is tracked, not inferred from "is K zero?" — because
        # a generator trip zeroes the coupling of every branch at its bus, and those
        # lines are still in service; they simply have nothing left to carry.
        net = three_machine_ring()
        eng = init!(SwingEngine, net; dt = 0.02)
        inject!(eng, TripGenerator(:G1))
        @test count(iszero, [eng.params[i] for i in eng.K_pidx]) == 2
        @test is_online(eng, :B1, :B2) && is_online(eng, :B3, :B1)
        @test !is_online(eng, :B1, :B9)          # unknown pair is false, not a throw
        # Tripping one of those lines afterwards is still a real state change.
        @test !is_online(inject!(eng, TripLine(:B1, :B2)), :B1, :B2)
    end

    @testset "SwingEngine: recording is bounded and the nadir is not read from it" begin
        net = two_machine_system()
        eng = init!(SwingEngine, net; dt = 0.02)
        # Pinned deliberately: the channel set of a running engine cannot be
        # changed afterwards, so it is a decision (step 7) rather than a detail.
        @test propertynames(state_series(eng)) ==
              (:t, :δ_G1, :δ_G2, :ω_G1, :ω_G2, :δ_coi, :f_coi)
        @test length(state_series(eng).t) == 1          # seeded pre-disturbance point
        inject!(eng, TripGenerator(:G1))
        for _ in 1:1000; step!(eng, 0.02); end
        @test length(state_series(eng).t) == 1001

        small = init!(SwingEngine, net; dt = 0.02, capacity = 64)
        inject!(small, TripGenerator(:G1))
        for _ in 1:1000; step!(small, 0.02); end
        @test GridSim.n_kept(small.traj) <= 64
        @test small.nadir ≈ eng.nadir atol = 1e-12      # summary, not a buffer read
        @test minimum(state_series(small).f_coi) > small.nadir + 1e-9
        # Wrong channel count is a named error, not a silent length mismatch.
        @test occursin("expected", argerr_msg(() ->
            GridSim.record!(small.traj, 0.0, [1.0, 2.0])))
    end

    # --- M2 step 7: what the UI needs before a line of drawing code -----------
    #
    # Three decisions the window depends on, asserted here rather than in `ui/`,
    # because they are core behaviour and the core suite is what would catch a
    # regression in them.

    @testset "SwingEngine: applied events are logged, the trajectory cannot say it" begin
        net = three_machine_ring()
        eng = init!(SwingEngine, net; dt = 0.02)
        @test isempty(event_log(eng))
        @test n_events_dropped(eng) == 0

        for _ in 1:50; step!(eng); end
        t_line = eng.integrator.t
        inject!(eng, TripLine(:B1, :B2))
        for _ in 1:50; step!(eng); end
        t_gen = eng.integrator.t
        inject!(eng, TripGenerator(:G2))

        log = event_log(eng)
        @test length(log) == 2
        # The cheap question a redraw asks every frame, answered without copying.
        @test n_events(eng) == length(log)
        # The timestamp is the integrator's own clock at the moment of injection —
        # not a wall clock, and not a time the caller supplied.
        @test log[1].t == t_line
        @test log[2].t == t_gen
        @test log[1].kind === :trip_line
        # Logged by the branch's bus names, so the argument order a caller happened
        # to use does not change what the record says happened.
        @test (log[1].a, log[1].b) == (:B1, :B2)
        @test log[2].kind === :trip_generator && log[2].a === :G2
        @test describe_event(log[1]) == "trip line B1–B2"
        @test describe_event(log[2]) == "trip G2"

        # The log records what CHANGED the system, not what was asked for: the
        # no-op paths of both `inject!` methods leave no entry behind.
        inject!(eng, TripLine(:B2, :B1))         # already open, either order
        inject!(eng, TripGenerator(:G2))         # already offline
        @test length(event_log(eng)) == 2
        # ...and neither does an event that throws before it applies anything.
        @test_throws KeyError inject!(eng, TripGenerator(:G9))
        @test_throws KeyError inject!(eng, TripLine(:B1, :B9))
        @test length(event_log(eng)) == 2

        # It is a copy: a caller may keep it without holding a handle on the engine.
        keep = event_log(eng)
        inject!(eng, TripLine(:B2, :B3))
        @test length(keep) == 2 && length(event_log(eng)) == 3

        # And the point of the whole thing: nothing in the recorded channels says a
        # line opened. Every channel is a smooth per-machine or aggregate quantity,
        # and none of them is the event marker a played-back run would need.
        @test !any(n -> occursin("trip", String(n)) || occursin("event", String(n)),
                   propertynames(state_series(eng)))
    end

    @testset "SwingEngine: the event log is bounded and says so" begin
        # Events are user clicks, so the cap is far above any session — but a
        # scripted driver must not turn this into the one vector that grows
        # forever. At the cap the EARLIEST events are kept (the same
        # start-is-what-matters choice the recorder makes when it decimates) and
        # the rest are counted rather than silently dropped.
        net = two_machine_system()
        eng = init!(SwingEngine, net; dt = 0.02)
        cap = GridSim._EVENT_LOG_CAP
        for k in 1:(cap + 10)
            # Straight at the log: a real trip is a no-op the second time, so the
            # cap is unreachable through `inject!` on a two-machine system.
            GridSim._log_event!(eng, :trip_generator, Symbol("G", k), Symbol(""))
        end
        log = event_log(eng)
        @test length(log) == cap
        @test n_events(eng) == cap               # the count stops at the cap too
        @test n_events_dropped(eng) == 10
        @test log[1].a === :G1                   # the start survives...
        @test log[end].a === Symbol("G", cap)    # ...and the tail is what was cut
    end

    @testset "SwingEngine: δ_coi is the gauge-free reference the angle traces need" begin
        net = three_machine_ring()
        eng = init!(SwingEngine, net; dt = 0.02)
        s = current_state(eng)

        # It is the same inertia-weighted mean as ω_coi, over the same live weights.
        @test s.δ_coi ≈ sum(eng.w .* s.δ) / sum(eng.w) atol = 1e-14

        # THE PROPERTY THAT MAKES IT THE RIGHT REFERENCE. `find_fixpoint` picks an
        # arbitrary gauge — shifting every angle by a constant is still the same
        # physical state — so an absolute angle is not a plottable quantity. Shift
        # the whole state and the aggregate shifts with it, leaving every machine's
        # angle *relative to it* untouched.
        rel_before = s.δ .- s.δ_coi
        for i in eng.δ_idx; eng.integrator.u[i] += 0.75; end
        s2 = current_state(eng)
        @test s2.δ_coi ≈ s.δ_coi + 0.75 atol = 1e-12
        @test s2.δ .- s2.δ_coi ≈ rel_before atol = 1e-12
        for i in eng.δ_idx; eng.integrator.u[i] -= 0.75; end   # put the gauge back

        # The recorded channel is the same number as the live read-out.
        step!(eng)
        tr = state_series(eng)
        @test tr.δ_coi[end] ≈ current_state(eng).δ_coi atol = 1e-14

        # A tripped machine leaves the reference, exactly as it leaves ω_coi: the
        # aggregate is the weighted mean over SURVIVORS, so it tracks the cluster
        # that is still running rather than being dragged by a decoupled rotor.
        inject!(eng, TripGenerator(:G1))
        for _ in 1:400; step!(eng); end
        s3 = current_state(eng)
        surv = [2, 3]
        @test s3.δ_coi ≈ sum(eng.w[surv] .* s3.δ[surv]) / sum(eng.w[surv]) atol = 1e-12
        # ...which is what keeps the picture readable: the survivors sit close to
        # the reference while the tripped machine visibly separates from it. Both
        # halves matter — a reference that drifted with the dead machine would push
        # the survivors off the axis instead.
        rel = s3.δ .- s3.δ_coi
        @test maximum(abs, rel[surv]) < 0.5           # survivors: on-screen
        @test abs(rel[1]) > 10 * maximum(abs, rel[surv])   # the tripped one: gone
    end

    @testset "SwingEngine: the bus-pair lookup is indexed, and both callers share it" begin
        net = three_machine_ring()
        eng = init!(SwingEngine, net; dt = 0.02)
        # One entry per branch, keyed by the unordered pair — so a branch cannot be
        # reachable under one bus order and missing under the other.
        @test length(eng.branch_of_buses) == length(net.branches)
        for (b, br) in pairs(net.branches)
            @test GridSim._find_branch(eng, br.from, br.to) == b
            @test GridSim._find_branch(eng, br.to, br.from) == b
            @test is_online(eng, br.from, br.to) && is_online(eng, br.to, br.from)
        end
        # The two callers still disagree only where they are meant to: a read-out
        # for a line that does not exist is `false`, injecting into one is a bug.
        @test GridSim._find_branch(eng, :B1, :B9) === nothing
        @test !is_online(eng, :B1, :B9)
        @test_throws KeyError inject!(eng, TripLine(:B1, :B9))
        # And the index still resolves the branch a trip must actually open.
        inject!(eng, TripLine(:B3, :B1))
        @test !is_online(eng, :B1, :B3)
        @test iszero(eng.params[eng.K_pidx[eng.branch_to_edge[3]]])   # L31, not another
    end



    # --- M2 step 6: the COI view, compiled down from the network model ---------
    #
    # `coi_model(net)` is what makes SPEC §3.2 true rather than aspirational: the
    # aggregate model M1's engine runs on is *derived* from M2's network model, not
    # hand-maintained beside it. The tests below are the cross-fidelity validation
    # (V4) and the no-dense-network claim (V5), plus a direct assertion on the
    # mapping itself — V4 alone lets a partially-wrong mapping through, because a
    # model wrong in both H and D can still track early and diverge late.

    # A ring shaped so the aggregate view's exactness condition can be switched on
    # and off. See the V4 testsets for the derivation; in short, the aggregate is
    # exact iff the tripped machine has `D = 0` (so the aggregate's fixed `D` does
    # not keep damping a machine that has left) and the survivors share `D/H` (so
    # `Σ Dᵢωᵢ = D_sys·ω_coi` even while they swing apart). `D/H` is base-independent
    # — both scale by the same `S_rated/S_base` — so the ratio can be read straight
    # off the machine data. Machines stay rated away from `S_base`, as everywhere
    # else here, so a missing per-unit conversion changes the answer.
    ratio_ring(; D1 = 0.0, D2 = 1.5, D3 = 2.5) = NetworkModel(100.0, 50.0,
        [Bus(:B1, 400.0), Bus(:B2, 400.0), Bus(:B3, 400.0)],
        [Branch(:L12, :B1, :B2, 0.25, 500.0), Branch(:L23, :B2, :B3, 0.25, 500.0),
         Branch(:L31, :B3, :B1, 0.25, 500.0)],
        #        id    bus   S_rated    H    D   Xd′    E′      P0
        [Machine(:G1, :B1,    300.0,  4.0, D1,  0.30,  1.05,   80.0),
         Machine(:G2, :B2,    200.0,  3.0, D2,  0.20,  1.03,   30.0),
         Machine(:G3, :B3,    500.0,  5.0, D3,  0.50,  1.04, -110.0)])

    # Drive both engines through the SAME trip in ONE lockstep loop, comparing the
    # live reads rather than the recorded series: `state_series` has a different
    # channel set per engine and both recorders decimate, so comparing trajectories
    # would be comparing two differently-sampled histories. Returns the aggregate
    # frequency gap and the *survivors'* speed spread (the tripped machine is
    # excluded — it is decoupled, so its speed is not inter-machine swing).
    function lockstep_coi(net, trip::Symbol; dt = 0.02, nsteps = 3000)
        sw = init!(SwingEngine, net; dt = dt)
        fr = init!(FrequencyResponseEngine, coi_model(net); dt = dt)
        inject!(sw, TripGenerator(trip))          # the same event, at the same t = 0
        inject!(fr, TripGenerator(trip))
        surv = [i for (i, id) in pairs(machine_ids(sw)) if id !== trip]
        s0 = current_state(sw); r0 = current_state(fr)
        t = [0.0]; gap = [abs(s0.f_coi - r0.f)]          # measured, not a seeded zero
        spread = [maximum(s0.ω[surv]) - minimum(s0.ω[surv])]; f_sw = [s0.f_coi]
        for _ in 1:nsteps
            s = step!(sw, dt); r = step!(fr, dt)
            push!(t, s.t); push!(gap, abs(s.f_coi - r.f)); push!(f_sw, s.f_coi)
            push!(spread, maximum(s.ω[surv]) - minimum(s.ω[surv]))
        end
        return (; t, gap, spread, f_sw, sw, fr)
    end

    @testset "coi_model: the mapping, and the wrong conversions by name" begin
        net = three_machine_ring()
        cm  = coi_model(net)
        ma  = machine_arrays(net)
        @test cm isa SystemModel
        @test (cm.S_base, cm.f0) == (net.S_base, net.f0)
        @test [u.id for u in cm.units] == machine_ids(init!(SwingEngine, net))  # bus order

        # H and S_rated go through RAW (on the machine's own base) because
        # `aggregates` applies `S_rated/S_base` itself; D is summed AFTER conversion
        # because `SystemModel.D` is already a system-base scalar. That asymmetry is
        # the trap in this function, so both halves are asserted against the wrong
        # conversions by name and not merely against the right one.
        a = GridSim.aggregates(cm, Set(u.id for u in cm.units))
        @test a.H_sys ≈ sum(ma.H) atol = 1e-12                  # = 43.0 s
        @test !isapprox(a.H_sys, sum(m.H for m in net.machines))            # unweighted: 12.0
        @test !isapprox(a.H_sys, sum(m.H * net.S_base / m.S_rated for m in net.machines))  # inverted: 3.83
        @test cm.D ≈ sum(ma.D) atol = 1e-12                     # = 20.0 pu/pu
        @test !isapprox(cm.D, sum(m.D for m in net.machines))               # unweighted: 6.0
        @test !isapprox(cm.D, sum(m.D * net.S_base / m.S_rated for m in net.machines))     # inverted: 2.07
        @test a.D == cm.D                                       # passed through, not re-weighted

        # Governor-free, because `three_machine_ring`'s machines are — NOT because
        # `coi_model` hard-codes it any more (M3 step 1). The distinction matters:
        # M2 deleted the governor on the way through so the two tiers differed by
        # inter-machine dynamics alone, and a view that deletes a property of the
        # canonical model is not a compiled view of it (SPEC §3.2). Now the droop
        # comes through and this fixture simply has none.
        @test all(u -> u.R == Inf, cm.units)
        @test a.R_eq == Inf
        @test all(u -> u.Pmax == u.P0, cm.units)
        @test a.headroom == 0.0
        @test cm.Tg == 1.0                                      # the no-droop fallback

        # …and with real droop it is passed through rather than discarded, on both
        # bases: `R` raw on the machine base (`aggregates` applies the weight) and
        # `Pmax` in MW. G2 alone has a governor here, so the aggregate gain is its
        # gain and the aggregate lag is its lag — the weighted mean's one case with
        # an unambiguous answer.
        one_gov = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
            [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05,   80.0),
             Machine(:G2, :B2, 200.0, 3.0, 2.0, 0.20, 1.03,   30.0, 0.05, 130.0, 7.0),
             Machine(:G3, :B3, 500.0, 5.0, 2.0, 0.50, 1.04, -110.0)])
        cg = coi_model(one_gov)
        ag = GridSim.aggregates(cg, Set(u.id for u in cg.units))
        @test [u.R for u in cg.units] == [Inf, 0.05, Inf]        # raw, machine base
        @test [u.Pmax for u in cg.units] == [80.0, 130.0, -110.0]
        @test 1 / ag.R_eq ≈ (1 / 0.05) * (200.0 / 100.0) ≈ 40.0  # gain carries the weight
        @test ag.headroom ≈ (130.0 - 30.0) / 100 ≈ 1.0
        @test cg.Tg == 7.0                                       # only voter, so it wins
        # The lag is weighted by droop GAIN, not by MVA and not unweighted: a machine
        # that does not respond gets no say in how fast the aggregate responds. With
        # two governors of unequal gain the three answers are different numbers, and
        # this is the one that ships (a choice with no oracle — see `coi_model`).
        two_gov = NetworkModel(net.S_base, net.f0, net.buses, net.branches,
            [Machine(:G1, :B1, 300.0, 4.0, 2.0, 0.30, 1.05,   80.0),
             Machine(:G2, :B2, 200.0, 3.0, 2.0, 0.20, 1.03,   30.0, 0.05, 130.0,  2.0),
             Machine(:G3, :B3, 500.0, 5.0, 2.0, 0.50, 1.04, -110.0, 0.10, -10.0, 10.0)])
        g2, g3 = (1 / 0.05) * 2.0, (1 / 0.10) * 5.0              # 40.0 and 50.0
        @test coi_model(two_gov).Tg ≈ (g2 * 2.0 + g3 * 10.0) / (g2 + g3)
        @test coi_model(two_gov).Tg ≉ (2.0 + 10.0) / 2           # unweighted
        @test coi_model(two_gov).Tg ≉ (200.0 * 2.0 + 500.0 * 10.0) / 700.0   # MVA-weighted

        # P0 stays in engineering units (MW) and keeps its sign: a load is a machine
        # with negative P0, and it compiles to a unit with negative P0 *and* negative
        # Pmax (which `GeneratingUnit`'s headroom guard accepts, since Pmax ≥ P0).
        @test [u.P0 for u in cm.units] == [m.P0 for m in net.machines] == [80.0, 30.0, -110.0]
        @test [u.S_rated for u in cm.units] == [m.S_rated for m in net.machines]

        # The compiled units carry the *rotating* inertia of every machine, load
        # buses included — so the aggregate H is over all three, not over the two
        # net generators.
        @test a.H_sys ≈ 43.0 && a.H_sys > sum(ma.H[1:2])

        # Two machines is a different shape, same rules.
        cm2 = coi_model(two_machine_system())
        @test length(cm2.units) == 2
        @test cm2.D ≈ sum(machine_arrays(two_machine_system()).D) ≈ 13.0
    end

    @testset "coi_model: Tg is unobservable, and both reasons are asserted" begin
        # `Tg = 1.0` is arbitrary only because the governor state is identically
        # zero, which needs BOTH `R_eq = Inf` (no droop command) and `ΔPm(0) = 0`
        # (M1's state is a deviation).
        #
        # Scope, after M3 step 1: this is a property of a GOVERNOR-FREE model, not of
        # `coi_model` in general. `three_machine_ring` has no droop, so the fallback
        # fires and `Tg` is genuinely unobservable here. Compile a governed network
        # and `Tg` becomes load-bearing — and the aggregation that produces it is a
        # modelling choice nothing in this suite can distinguish (see `coi_model`).
        #
        # Assert the invariance rather than the comment:
        # a second model differing ONLY in Tg must give the same trajectory.
        net = three_machine_ring()
        cm  = coi_model(net)
        slow = SystemModel(cm.S_base, cm.f0, cm.D, 100.0, cm.units)
        a = init!(FrequencyResponseEngine, cm; dt = 0.02)
        b = init!(FrequencyResponseEngine, slow; dt = 0.02)
        inject!(a, TripGenerator(:G1)); inject!(b, TripGenerator(:G1))
        same = true
        for _ in 1:500
            sa = step!(a, 0.02); sb = step!(b, 0.02)
            same &= (sa.f == sb.f)                   # bit-identical, not merely close
        end
        @test same
        @test current_state(a).ΔPm == 0.0            # the governor never moved...
        @test current_state(a).f < 49.0              # ...but the frequency did
    end

    @testset "V4a: the aggregate view is EXACT where the tier's assumption holds" begin
        # The COI of the swing model obeys, exactly (the network terms cancel — the
        # branches are lossless):
        #     2·Σ_online H · dω_coi/dt = Σ_online Pm − Σ_online Dᵢ·ωᵢ
        # M1's aggregate obeys `2·H_sys·dΔω/dt = ΔP_dist − D_sys·Δω`. The two are the
        # SAME scalar ODE when (i) the tripped machine has D = 0, so the aggregate's
        # fixed D_sys equals Σ_online Dᵢ, and (ii) the survivors share D/H, so
        # Σ Dᵢωᵢ = D_sys·ω_coi even while they swing apart. Both hold here by
        # construction, so the two engines must agree for the WHOLE run — not just
        # early — and any error in the H or D mapping breaks it immediately: dropping
        # the weight on D here gives 4.0 instead of 15.5, so the aggregate would
        # settle at 40.0 Hz against the swing model's 47.42.
        net = ratio_ring()                            # D_G1 = 0; survivors D/H = 0.5
        ma  = machine_arrays(net)
        @test ma.D[1] == 0.0
        @test ma.D[2] / ma.H[2] ≈ ma.D[3] / ma.H[3] ≈ 0.5
        @test coi_model(net).D ≈ sum(ma.D) ≈ 15.5     # = Σ_online D, since D_G1 = 0

        r = lockstep_coi(net, :G1; nsteps = 3000)     # 60 s
        @test maximum(r.gap) < 1e-11                  # measured 7.1e-15 Hz

        # Not vacuous: the run is a real disturbance and the machines really do swing
        # against one another — the agreement is exactness, not stillness.
        @test r.f_sw[end] ≈ 50.0 * (1 + (sum(ma.Pm) - ma.Pm[1]) / sum(ma.D)) atol = 1e-3
        @test r.f_sw[end] < 47.5
        @test maximum(r.spread) > 1e-5                # measured 7.5e-5 pu ≈ 3.8 mHz
        # Inertia bookkeeping survives the event on both sides of the compile.
        @test system_inertia(r.sw) ≈ system_inertia(r.fr) ≈ sum(ma.H) - ma.H[1]
    end

    @testset "V4b: what the aggregate averages away, isolated and measured" begin
        # Same fixture, but the survivors' D/H ratios are no longer equal, so
        # condition (ii) above fails while (i) still holds. The two models therefore
        # start identical (same initial RoCoF) and settle identical (same ω_∞), and
        # the ONLY difference is the transient — which is exactly the inter-machine
        # swing content the aggregate model averages away. This is the number the
        # step-6 plan promised; V4c is where that promise does not hold.
        net = ratio_ring(; D3 = 2.0)                  # D/H = 0.5 vs 0.4
        ma  = machine_arrays(net)
        @test !isapprox(ma.D[2] / ma.H[2], ma.D[3] / ma.H[3])
        @test coi_model(net).D ≈ sum(ma.D) ≈ 13.0

        r = lockstep_coi(net, :G1; nsteps = 3000)     # 60 s
        peak, ipeak = findmax(r.gap)
        # Measured: 4.4325e-6 Hz at t = 0.26 s. Stable to 8 significant figures
        # from the solver's default tolerance down to reltol 1e-12 (see m2-context.md),
        # so it is the physics
        # and not integration error — which matters, because it sits BELOW the
        # solver's own default abstol and would otherwise be indistinguishable.
        @test peak ≈ 4.4325e-6 rtol = 5e-3
        @test 0.2 < r.t[ipeak] < 0.35
        # Both ends pinned: agree at the disturbance, agree at the new steady state.
        @test r.gap[2] < 1e-7                          # first post-trip sample
        @test r.gap[end] < 1e-8                        # 60 s, measured 1.2e-10

        # The "so what": the machines are 3.9 mHz apart from each other at the peak
        # of the swing, and only 4.4 µHz of that reaches the aggregate — a factor of
        # nearly 900 averaged away. Asserting the ratio is what makes this a
        # statement about the model rather than a small number with no scale.
        @test maximum(r.spread) * 50.0 / peak > 500
    end

    @testset "V4c: on the shipped ring the DAMPING gap dominates (the finding)" begin
        # The step-6 plan says the late divergence is "inter-machine swings the
        # aggregate averages away". On `three_machine_ring` that is not true, and the
        # test says so rather than quietly asserting a band that happens to pass.
        # M1's `D` is ONE system-wide constant that `aggregates` passes through
        # unchanged, so the aggregate keeps damping a machine that has tripped, while
        # the network model's damping leaves with it. The two therefore settle at
        # different frequencies, and that gap is ~200 000× the swing content V4b
        # isolated. Recorded as a finding in docs/plans/m2-context.md.
        net = three_machine_ring()
        ma  = machine_arrays(net)
        r = lockstep_coi(net, :G1; nsteps = 3000)     # 60 s

        # They DO track early: the initial RoCoF is analytically identical, because
        # `Σ P0 = 0` at construction makes `Σ Pm_online` equal M1's `ΔP_dist`, and
        # both models drop the tripped machine's inertia.
        @test r.gap[2] < 1e-4                          # first post-trip sample: 1.2e-5
        early = maximum(r.gap[r.t .<= 0.1])
        @test early < 5e-4                             # measured 3.0e-4 Hz at 0.1 s

        # And they DO diverge later — asserting only the tracking would pass
        # vacuously if `coi_model` ever returned something trivial. The ratio is the
        # honest statement of "track early, diverge later": ~2800× apart, measured.
        @test r.gap[end] > 0.8
        @test r.gap[end] / early > 1000

        # The divergence is a DERIVED number, not a band: Σ Pm_online over the
        # surviving damping, against the same numerator over the *whole* damping.
        ΣPm_online = sum(ma.Pm) - ma.Pm[1]             # = −Pm_G1, since Σ P0 = 0
        f_swing = 50.0 * (1 + ΣPm_online / (sum(ma.D) - ma.D[1]))   # 47.142857 Hz
        f_coi   = 50.0 * (1 + ΣPm_online / sum(ma.D))               # 48.0 Hz
        @test f_swing ≈ 47.142857 atol = 1e-5
        @test f_coi ≈ 48.0 atol = 1e-12
        @test r.gap[end] ≈ f_coi - f_swing atol = 1e-5   # residual 3.7e-6 is settling
        @test r.gap[end] < f_coi - f_swing               # ...and it approaches from below

        # The aggregate view has no line to trip at all: a `SystemModel` has no
        # branches, so `TripLine` is not merely inaccurate on it, it is unexpressible.
        # That is the honest boundary of the compiled view, and it is why step 5's
        # split-grid case has no cross-fidelity counterpart.
        @test_throws MethodError inject!(r.fr, TripLine(:B1, :B2))
    end

    @testset "V5: no n² structure anywhere the engine owns" begin
        # SPEC §4 forbids a dense admittance matrix. Under D3 the engine never
        # assembles *any* admittance matrix, so "assert it is not dense" is a
        # checkbox that cannot fail. The version with teeth is a count: coupling
        # lives on graph edges, so every array the engine owns must be linear in
        # (machines + branches), and a single dense Y-bus would break that by itself.
        #
        # Scope, stated: this covers the engine's own fields AND NetworkDynamics'
        # flat state/parameter arrays (which the engine shares, so their lengths are
        # upstream's storage, not ours). It does not reach inside the compiled
        # `Network` object. There, D3 holds by construction rather than by this test.
        #
        # `Base.summarysize` scaling was measured as an alternative and DROPPED: the
        # fixed per-machine overhead of the compiled network is ~2.4 kB, so a dense
        # n×n Float64 matrix does not overtake it until n ≈ 300. It would have passed
        # without discriminating, which is worse than an absent test.
        function big_ring(n)                 # even n, alternating ±P so Σ P0 = 0
            buses = [Bus(Symbol("B", i), 400.0) for i in 1:n]
            machines = [Machine(Symbol("G", i), Symbol("B", i), 200.0, 4.0, 2.0, 0.3,
                                1.05, isodd(i) ? 40.0 : -40.0) for i in 1:n]
            branches = [Branch(Symbol("L", i), Symbol("B", i), Symbol("B", mod1(i + 1, n)),
                               0.25, 500.0) for i in 1:n]
            return NetworkModel(100.0, 50.0, buses, branches, machines)
        end

        # Total elements across every container the engine holds. `incident` is a
        # vector of vectors, so its inner lengths are what count — that is where an
        # all-pairs structure would hide most naturally.
        #
        # `AbstractDict` is counted too, and that is not decoration: step 7 added a
        # bus-pair index, and a `Dict` is not an `AbstractArray`, so an array-only
        # sweep would have let an all-pairs *dictionary* be added later without
        # moving these counts or the slope beside them. Exactly the shape of this
        # file's own edge-order lesson — if no test would fail, write one.
        function array_elems(eng)
            tot = 0
            for f in fieldnames(SwingEngine)
                x = getfield(eng, f)
                if x isa AbstractDict
                    tot += length(x)
                    continue
                end
                x isa AbstractArray || continue
                @test !(x isa AbstractMatrix)          # nothing two-dimensional at all
                tot += eltype(x) <: AbstractArray ? sum(length, x) : length(x)
            end
            return tot
        end

        counts = Int[]
        for n in (4, 10, 40)
            net = big_ring(n)
            eng = init!(SwingEngine, net; dt = 0.02)
            nb, ne = length(net.buses), length(net.branches)
            @test length(eng.params) == 7nb + ne       # 7 per machine, 1 per branch
            @test length(eng.integrator.u) == 3nb      # (δ, ω, ΔPm) per machine
            @test sum(length, eng.incident) == 2ne     # each branch at exactly 2 buses
            @test length(eng.K_pidx) == ne
            @test length(eng.branch_of_buses) == ne     # one key per branch at EVERY n
            push!(counts, array_elems(eng))
        end
        # A tripwire, not a correctness claim: a legitimate new per-machine array
        # field changes these deliberately. The two assertions below are the claim.
        # Moved at M2 step 7, deliberately and by exactly the right amount: `δ_coi`
        # adds ONE element to the sample buffer regardless of n (17n+1 → 17n+2),
        # and counting the bus-pair index adds one key per branch, i.e. one per
        # machine on this ring (17n+2 → 18n+2). A per-machine mistake in the first
        # or an all-pairs structure in the second would have shifted the slope,
        # which the next assertion is what catches.
        #
        # Moved again at M3 step 1, by exactly 6n — and the whole point of the
        # tripwire is that the move has to be accounted for rather than re-pinned:
        # three new vertex parameters (`invR`, `headroom`, `Tg`) add 3n to the
        # shared parameter vector, and three new index vectors (`ΔPm_idx`,
        # `invR_pidx`, `hr_pidx`) add n each. 18n + 2 → 24n + 2. The recorder is
        # deliberately NOT in that list: `ΔPm` is read through `current_state`
        # rather than recorded as 1 channel per machine, which would have added
        # another n to the sample buffer and a per-machine trace nothing asked for.
        @test counts == [98, 242, 962]                 # exactly 24n + 2

        # Linear, asserted as such: equal slope over both intervals. A dense n×n
        # anywhere would make the second slope 30× the first.
        @test (counts[2] - counts[1]) / (10 - 4) == (counts[3] - counts[2]) / (40 - 10)
        # The positive control, stated as a number: at n = 40 the engine's ENTIRE
        # array storage is 962 elements, while one dense Y-bus alone would be 1600.
        # The margin narrowed when the governor state landed (it was 722), which is
        # the honest reading — a linear model with a bigger constant is still linear,
        # and the slope assertion above is what actually rules out the n² structure.
        @test counts[3] < 40^2
    end

end
