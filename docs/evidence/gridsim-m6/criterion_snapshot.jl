# M6 step 1, gate claim (b): print M5's criterion numbers at FULL precision so
# "bit-identical" can be checked by comparison rather than inferred from a green
# suite whose assertions carry tolerances (m6-tasks.md step 1).
#
#   julia --project=. W:/temp/claude/gridsim-m6/criterion_snapshot.jl > <out>.txt
#
# `repr` on a Float64 is the shortest round-tripping decimal, so equality of two
# printed lines IS equality of the underlying bits.

module IB
include(raw"M:\claud_projects\GridSim\scripts\iberia_two_area.jl")
end

using Printf

p(label, v) = println(rpad(label, 46), " = ", repr(v))

println("== slip boundary (scan 2500:500:9000, as the criterion testset uses) ==")
b = IB.slip_boundary(; scan = 2_500.0:500.0:9_000.0)
p("boundary", b.boundary); p("monotone", b.monotone); p("saturated", b.saturated)
P = b.boundary

println("\n== classical cell at the boundary ==")
cl = IB.classical_cell(; P_max_mw = P)
for k in (:slipped, :dmax, :peak_export, :P_max, :over); p("cl.$k", getfield(cl, k)); end

function dump_cell(tag, c)
    for k in (:slipped, :dmax, :t90, :n_pole_slips, :peak_export, :P_max, :over,
              :exceeds, :ceiling_mw, :swing, :V_min, :V_max, :E′q_peak, :E′q_0,
              :Efd_peak, :Efd_over, :f_ib_min, :f_ce_min, :n_steps)
        p("$tag.$k", getfield(c, k))
    end
end

println("\n== frozen-flux control ==")
dump_cell("fr", IB.detailed_cell(; P_max_mw = P, detailed = NamedTuple()))

println("\n== flux-only cell ==")
dump_cell("fl", IB.detailed_cell(; P_max_mw = P, detailed = IB.MACH_DETAILED))

println("\n== the criterion cell (DETAILED_FULL) ==")
dump_cell("av", IB.detailed_cell(; P_max_mw = P, detailed = IB.DETAILED_FULL))

println("\n== the criterion cell at the looser tolerance ==")
dump_cell("av5", IB.detailed_cell(; P_max_mw = P, detailed = IB.DETAILED_FULL,
                                    reltol = 1e-3, abstol = 1e-6))

println("\n== the 14-cell one-axis-at-a-time walk (section 5d) ==")
nover = 0; ncell = 0
for (nm, key, vals) in IB.DET_AXES, v in vals
    d = merge(IB.DETAILED_FULL, NamedTuple{(key,)}((v,)))
    rr = IB.detailed_cell_retry(; P_max_mw = P, detailed = d)
    r = rr.cell
    global ncell += 1
    if r.exceeds && r.slipped
        global nover += 1
    end
    tag = "$(key)=$(repr(v))"
    p("$tag.retried",  rr.retried)
    p("$tag.slipped",  r.slipped)
    p("$tag.exceeds",  r.exceeds)
    p("$tag.over",     r.over)
    p("$tag.E′q_peak", r.E′q_peak)
    p("$tag.V_max",    r.V_max)
end
p("swept cells satisfying both halves", (nover, ncell))
