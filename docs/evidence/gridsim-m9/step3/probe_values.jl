# M9 step 3: the measured values behind m9-context.md D7's table (gaps, bands,
# controls, the residual's coefficient). Self-contained: the reference suite's
# helpers concatenated with the probe.
#   julia --project=W:/Claude_projects/GridSim/reference probe_values.jl
# GridSimReference — the external-oracle suite (docs/plans/m4-tasks.md step 4).
#
# Every check here is ours against SOMEBODY ELSE'S implementation. That is the
# one thing no earlier milestone could do: M1's closed forms, M2's cross-fidelity
# overlay and M3's degeneration checks are all ours against ours, and they cannot
# tell "the simple model drops swings" apart from "our model has a bug" (D2).
#
# THREE RULES THIS FILE KEEPS, INHERITED FROM M1–M3 AND NOT RE-ARGUED:
#
#   1. Every band is stated before the gap is seen. Here that is structural
#      rather than disciplinary: `oracle_band` is computed from each side's OWN
#      convergence and never looks at the other side (see its docstring).
#   2. Every check ships with a positive control (it can read agreement when
#      agreement is real) AND an anti-vacuity control (it can read disagreement).
#      Five planned checks in M3 would each have passed against the very bug they
#      targeted; this is what that cost bought.
#   3. A number below the solver's own tolerance is not a result until it survives
#      the tolerance changing.
#
# WHAT THIS SUITE CANNOT CATCH, SAID ONCE AND TESTED FOR AT THE BOTTOM. The case
# is COMPILED from `NetworkModel` (D5), so both sides read the same
# `machine_arrays` / `branch_arrays` / `_coupling`. A bug in those is handed
# identically to both and every check here goes green. That is the price of not
# hand-maintaining a parallel model, it is the right price, and it is why the
# anti-vacuity mutation must be made in `swing_vertex!` and never in the shared
# data path.

using Test
using GridSim
using GridSimReference
using PowerDynamics: set_fbase!, set_Sbase!
# M6 step 4, oracle B. Same aliases the module itself uses and for the same reason:
# `ACPowerFlow` and `DCPowerFlow` are names GridSim already owns, and a `using` on
# either package would make both ambiguous here.
import PowerSystems as PSY
import PowerFlows as PF

# ---------------------------------------------------------------------------
# Fixtures and helpers
# ---------------------------------------------------------------------------

# A model on NEITHER of the repo's two fixture bases. `two_machine_system()` and
# `three_machine_ring()` are both 100 MVA / 50 Hz, so any check that the builder
# takes the bases FROM THE MODEL — rather than from whatever PowerDynamics'
# process-global state happens to hold — is vacuous against them.
#
# It doubles as the fixture for the negative-reduction guard: `X′d` comes to
# 0.2333 + 0.1600 = 0.3933 pu on the system base against a 0.20 pu tie, so there
# is no line left to put between the two internal nodes.
function base_250_60()
    NetworkModel(250.0, 60.0,
                 [Bus(:BA, 230.0), Bus(:BB, 230.0)],
                 [Branch(:LAB, :BA, :BB, 0.20, 800.0)],
                 [Machine(:GA, :BA, 300.0, 3.5, 1.5, 0.28, 1.04,  150.0),
                  Machine(:GB, :BB, 500.0, 6.0, 2.5, 0.32, 1.01, -150.0)])
end

# A radial pair at a chosen loading, so the `ClassicalMachine` residual can be
# read against the one thing it is supposed to scale with.
function loaded_pair(P0_MW)
    NetworkModel(100.0, 50.0,
                 [Bus(:B1, 400.0), Bus(:B2, 400.0)],
                 [Branch(:L12, :B1, :B2, 0.25, 500.0)],
                 [Machine(:G1, :B1, 250.0, 4.0, 2.0, 0.25, 1.05,  P0_MW),
                  Machine(:G2, :B2, 400.0, 5.0, 2.0, 0.30, 1.02, -P0_MW)])
end

# The message of an `ArgumentError` a call is expected to throw. Defined here
# rather than imported: `test/helpers.jl` belongs to the core suite, and neither
# `reference/test/` nor `ui/test/` reaches into it (checked in M5 step 0b, and
# the reason a hoisted helper could break a suite nobody ran).
function argerr_msg(f)
    try
        f()
    catch e
        e isa ArgumentError && return e.msg
        rethrow()
    end
    error("expected an ArgumentError, but the call returned normally")
end

# The gauge-free channel: an angle DIFFERENCE. A raw `δ` is arbitrary up to a
# common shift on both sides, so it is never the thing compared.
δ12(s) = s.δ_G1 .- s.δ_G2

# One GridSim run and one PowerDynamics run of the same scenario on ONE grid.
# The grid is fixed before either solve because `divergence` refuses two grids
# and nothing anywhere resamples (M4 step 2, D10).
function both(net, tspan, grid; tier = :swing, perturbations = (),
              reltol = 1.0e-9, abstol = 1.0e-12, step_power = nothing)
    eng = SwingEngine(net; reltol = reltol, abstol = abstol)
    case = build_oracle(net; tier = tier, perturbations = perturbations)
    if step_power !== nothing
        id, Pm = step_power
        # Reaching past the engine's own interface, deliberately and for a stated
        # reason: a mechanical-power step is bus-local, works on any topology and
        # needs no new event type, and PARAMETERS are the sanctioned perturbation
        # channel (SPEC §6 — `inject!` writes exactly this vector). Seeding a
        # non-equilibrium STATE instead would be a second way to place an
        # engine's initial condition, which is the shape D4 and D8 forbid.
        v = findfirst(m -> m.id === id, net.machines)::Int
        eng.params[eng.Pm_pidx[v]] = Pm
        set_mechanical_power!(case, id, Pm)
    end
    ours = solve!(eng, tspan; perturbations = perturbations, saveat = grid)
    theirs = oracle_solve(case, tspan; saveat = grid, reltol = reltol, abstol = abstol)
    return ours, theirs
end

# Fixtures and helpers for the detailed tier (M5 steps 3 and 4)
# ---------------------------------------------------------------------------
#
# These four sat INSIDE the step-3 testset until step 4 needed them too, and a
# `@testset` block is a scope: a function defined in one is invisible to its
# sibling. Hoisting rather than copying is M5 step 0b's rule applied to this file —
# the alternative is two copies of the one helper that decides what "the same
# scenario on both sides" means. Nothing in them changed in the move; step 3's
# testsets below still call them and its counts are unchanged.

# `detailed_pair()` — the machine carrying REAL detailed data — was a local here
# until M5 step 4, and it MOVED INTO `GridSim` itself (`src/model/network_model.jl`,
# beside `two_machine_system` and friends). Step 4's core suite needs the same
# fixture for the `T′ → 0` limit and for the first flat run whose flux fixpoint is
# a real condition, and a fixture maintained in two files is the forked-data hazard
# SPEC §3.2 forbids. Its numbers, its scanned `|V|` and the reason they were scanned
# are in its docstring; nothing about the fixture changed in the move.

# One GridSim run and one PowerDynamics run of the same scenario on ONE grid, at
# the detailed tier. Same shape as `both` above and for the same reasons; it is
# separate because the engine, the tier and the perturbation channel all differ.
function both_detailed(net, tspan, grid; perturbations = (), reltol = 1.0e-9,
                       abstol = 1.0e-12, ΔPm = nothing, X_ls_frac = 0.5,
                       ψ_scale = 1.0, mutate = identity)
    eng  = init!(DetailedEngine, mutate(net); reltol = reltol, abstol = abstol)
    case = build_oracle(net; tier = :sauer_pai, perturbations = perturbations,
                        X_ls_frac = X_ls_frac)
    if ψ_scale != 1.0
        # Their two sub-transient states, seeded DELIBERATELY WRONG. See the
        # "drives nothing" testset: this is the sharp form of that claim.
        for k in eachindex(case.mach_bus)
            v = case.mach_bus[k]
            case.s0.v[v, :mach₊ψ″_d] *= ψ_scale
            case.s0.v[v, :mach₊ψ″_q] = case.s0.v[v, :mach₊ψ″_q] * ψ_scale - 0.1
        end
    end
    if ΔPm !== nothing
        # A mechanical-power step: bus-local, valid on any topology, no new event
        # type, and PARAMETERS are the sanctioned perturbation channel (SPEC §6).
        # The base value is read off the engine rather than from `Machine.P0`,
        # because at this tier the dispatch comes from the POWER FLOW.
        id, ΔP = ΔPm
        k = findfirst(m -> m.id === id, net.machines)::Int
        Pm = eng.params[eng.Pm_pidx[k]] + ΔP
        eng.params[eng.Pm_pidx[k]] = Pm
        set_mechanical_power!(case, id, Pm)
    end
    ours   = solve!(eng, tspan; perturbations = perturbations, saveat = grid)
    theirs = oracle_solve(case, tspan; saveat = grid, reltol = reltol, abstol = abstol)
    return ours, theirs
end

gap(a, b, k) = maximum(abs, getproperty(a, k) .- getproperty(b, k))
peak_slip(s, ids) = maximum(abs, vcat((getproperty(s, Symbol(:ω_, i)) for i in ids)...))
chan(k) = s -> getproperty(s, k)

# ===========================================================================
# M5 step 3 — the detailed tier against PowerDynamics, flux frozen on BOTH sides
# ===========================================================================
# M9 step 3 — line resistance reaches PowerDynamics (Hurdle 17.5)
# ===========================================================================
#
# Steps 1–2 taught both dynamic tiers `R`, and every check they shipped is ours
# against ours: the detailed tier against the AC power flow, the swing tier against
# a formula written in the test, the two tiers against each other. A resistance
# misread the SAME way by every one of our readers would pass all of them. Here
# `build_oracle` hands `Branch.R` to PowerDynamics' `PiLine` itself — current
# `(V₁ − V₂)/(R + jX)`, read from their source — so their network is lossy by their
# own arithmetic, and our steady state and transient are judged against it.
#
# Mapped at `:swing` and `:sauer_pai`, the two tiers M9 taught `R`; `:classical`
# (its line reduction was derived lossless) and `:sauer_pai_avr` still refuse it,
# by name.
#
# THE DISPATCH IS OURS AS WELL AS THE ANGLES. On a lossy grid the reference bus
# picks up the losses (step 2, both tiers), so its `Pm` is NOT `Machine.P0`. The
# swing-tier builder seeded `Pm` from the schedule until this step; it now reads
# our engine's, as the detailed tier always did. C2 below is the control that
# says the seed matters.
#
# THE DETAILED TIER IS NOT JUDGED BY A BAND ON ITS TRANSIENT. Lossless, its
# transient sits outside its convergence band by design — the stator-ω residual
# (M5 step 3) — so on that tier the sharp checks are the flat run, per state, and
# the residual's signature, which must survive the resistance unchanged.

# The ring with a DIFFERENT resistance on each branch, so no uniform rescaling of
# `R` is a symmetry of the fixture. Meshed, governor-free, load-free: valid at both
# mapped tiers.
const M9_R = (0.05, 0.08, 0.10)
function m9_lossy_ring(Rs = M9_R)
    n = three_machine_ring()
    NetworkModel(n.S_base, n.f0, n.buses,
                 [Branch(b.id, b.from, b.to, b.X, b.rating; R = r)
                  for (b, r) in zip(n.branches, Rs)], n.machines)
end
m9_flat_gap(s, ch::Function) = (a = ch(s); maximum(abs, a .- a[1]))
m9_flat_gap(s, k::Symbol) = m9_flat_gap(s, chan(k))

net = m9_lossy_ring(); vref = net.bus_index[net.slack]
eng = SwingEngine(net; reltol=1e-9, abstol=1e-12)
println("swing ref Pm extra (losses) = ", eng.params[eng.Pm_pidx[vref]] - machine_arrays(net).Pm[vref])
grid = collect(0.0:0.05:5.0)
flat = oracle_solve(build_oracle(net), (0.0,5.0); saveat=grid)
println("swing flat: ω gaps ", [m9_flat_gap(flat, Symbol(:ω_, i)) for i in (:G1,:G2,:G3)], " δ12 ", m9_flat_gap(flat, δ12), " fcoi ", m9_flat_gap(flat, :f_coi))
c1 = build_oracle(net); for e in 1:3; c1.s0.p.e[e, :pibranch₊R] = 0.0; end
println("C1 swing δ12 move ", m9_flat_gap(oracle_solve(c1,(0.0,5.0);saveat=grid), δ12))
c2 = build_oracle(net); c2.s0.p.v[vref, :mach₊Pm] = machine_arrays(net).Pm[vref]
t2 = oracle_solve(c2,(0.0,5.0);saveat=grid); println("C2 swing fcoi move ", maximum(abs, t2.f_coi .- net.f0))
grid = collect(0.0:0.02:10.0)
for pert in ([1.0 => TripLine(:B3, :B1)], [1.0 => TripGenerator(:G2)])
    o, t = both(net, (0.0,10.0), grid; perturbations=pert)
    of, tf = both(net, (0.0,10.0), grid; perturbations=pert, reltol=1e-12, abstol=1e-15)
    for (nm, ch) in (("fcoi", chan(:f_coi)), ("δ13", s -> s.δ_G1 .- s.δ_G3), ("ωG1", chan(:ω_G1)), ("ωG3", chan(:ω_G3)))
        b = oracle_band(o, of, t, tf; channel=ch); d = divergence(o, t; band=b, channel=ch)
        println(pert[1][2], " ", nm, " band=", b, " gap=", d.max, " ratio=", d.max/b)
    end
    ol, _ = both(three_machine_ring(), (0.0,10.0), grid; perturbations=pert)
    b = oracle_band(o, of, t, tf)
    println("  lossless vs lossy fcoi ", divergence(o, ol; band=b).max, " ratio to band ", divergence(o, ol; band=b).max/b, "  fcoi excursion ", maximum(abs, o.f_coi .- net.f0))
end
grid = collect(0.0:0.02:5.0)
o, t = both_detailed(net, (0.0,5.0), grid)
println("detailed flat worst |ours-theirs| ", maximum(maximum(abs, getproperty(o,k) .- getproperty(t,k)) for k in keys(o) if k !== :t))
de = init!(DetailedEngine, net); k1 = findfirst(m -> m.bus === net.slack, net.machines)
println("detailed ref Pm extra ", de.params[de.Pm_pidx[k1]] - machine_arrays(net).Pm[k1])
case = build_oracle(net; tier=:sauer_pai); for e in 1:3; case.s0.p.e[e, :pibranch₊R] = 0.0; end
println("C1 detailed V_B1 move ", m9_flat_gap(oracle_solve(case,(0.0,5.0);saveat=grid,reltol=1e-9,abstol=1e-12), :V_B1))
ids = [m.id for m in net.machines]
for ΔP in (0.02,0.04,0.08)
    o, t = both_detailed(net,(0.0,5.0),grid; ΔPm=(:G1,ΔP)); s = peak_slip(o, ids); g = gap(o,t,:V_B1)
    println("ΔP=$ΔP slip=$s gapV=$g coeff=", g/s, " gapω=", gap(o,t,:ω_G1), " V_B1=", o.V_B1[1])
end
