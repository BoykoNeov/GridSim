# M11 step 2 — PowerModels' DC OPF as the outside check on `dc_opf` (Hurdle 23;
# docs/plans/m11-plan.md step 2, m11-context.md D2.5, D7).
#
# THE INPUT IS MATPOWER TEXT, NEVER A `NetworkModel`. Everything else in this package is
# COMPILED from our model (D5 of M4), which is why it cannot see a conversion mistake
# upstream of the compile. This oracle is the opposite shape, on purpose (Hurdle 23.2):
# its data is case9's rows typed from MATPOWER's file into the reference test, read by
# PowerModels' OWN reader (`parse_matpower`), so its per-unit conversion, its cost
# scaling and its angles are theirs and share nothing with ours. A literal wrong on our
# side only is then a disagreement, and the step-2 sabotages show it is seen.
#
# Edits for the invented fixtures go INTO THE TEXT (`matpower_edit`), in the units the
# file uses (MVA), for the same reason: a hand-built PowerModels dictionary would be a
# third conversion, checked by nothing.
#
# R = 0 (D2.5, the user's choice). PowerModels' DC branch strength is `x/(r² + x²)`, ours
# `1/X`; with `R` zeroed in the text the two are the same formula and the comparison can
# be strict. The difference with `R` left in is measured and printed by the test (23.1),
# never used as a band.
#
# Their reader adds a constraint we do not have: it tightens case9's ±360° branch angle
# bounds to ±60° (`correct_voltage_angle_differences!`). The test asserts it is present
# and never binding.
#
# M11 step 4 adds the AC side (`oracle_ac_opf`, Hurdle 24's outside check), on the same
# text through the same reader, with three more edits: line charging zeroed (our case9
# has none), each generator bus's voltage held by Vmin = Vmax = its gen row's `Vg` (their
# AC OPF never reads `Vg`), and the loads scaled. `R` is KEPT: in AC both sides write the
# same physics. Both sides solve with Ipopt, so this checks the formulation, not the
# solver.

import PowerModels as PM
import Ipopt
import JuMP

"""
    matpower_edit(text; r0 = false, rate = Dict(), b0 = false, held = false, load = 1)
        -> String

MATPOWER case text with its rows edited, in the file's own columns and units:

  - `r0 = true` sets every branch's `r` (column 3) to 0;
  - `rate[(f, t)] = MVA` replaces that branch's rateA, rateB and rateC (columns 6–8).
    Branches are named by their `(fbus, tbus)` as the file writes them; a key that
    matches no row is refused;
  - `b0 = true` sets every branch's line charging `b` (column 5) to 0;
  - `held = true` sets each generator bus's Vmax and Vmin (bus columns 12, 13) both to
    its generator's `Vg` (gen column 6), READ FROM THE TEXT'S OWN GEN ROWS. PowerModels'
    AC OPF never reads `Vg`; the bus bounds are the only way to hold a voltage there.
    Two generators on one bus with different `Vg` are refused;
  - `load = s` multiplies every bus's `Pd` and `Qd` (bus columns 3, 4) by `s`.

Every edit is off by default, and a row no edit touches keeps its text.
"""
function matpower_edit(text::AbstractString; r0::Bool = false,
                       rate::AbstractDict = Dict{Tuple{Int,Int},Float64}(),
                       b0::Bool = false, held::Bool = false, load::Real = 1)
    lines = split(text, '\n')
    cols(ln) = String.(split(strip(ln, [' ', '\t', ';'])))
    row(c) = "\t" * join(c, '\t') * ";"
    # Each data line, by the block it sits in.
    block = fill(:none, length(lines))
    cur = :none
    for (i, ln) in pairs(lines)
        s = strip(ln)
        if startswith(s, "mpc.bus ") || startswith(s, "mpc.bus=")
            cur = :bus
        elseif startswith(s, "mpc.gen ") || startswith(s, "mpc.gen=")
            cur = :gen
        elseif startswith(s, "mpc.branch")
            cur = :branch
        elseif cur !== :none && startswith(s, "];")
            cur = :none
        elseif cur !== :none && !isempty(s)
            block[i] = cur
        end
    end
    # The held voltages, from the gen rows.
    vg = Dict{Int,String}()
    if held
        for i in eachindex(lines)
            block[i] === :gen || continue
            c = cols(lines[i])
            b = parse(Int, c[1])
            haskey(vg, b) && parse(Float64, vg[b]) != parse(Float64, c[6]) &&
                throw(ArgumentError("matpower_edit: bus $b carries generators with " *
                                    "different Vg ($(vg[b]) and $(c[6]))."))
            vg[b] = c[6]
        end
    end
    out = String[]
    seen = Set{Tuple{Int,Int}}()
    for (i, ln) in pairs(lines)
        if block[i] === :branch
            c = cols(ln)
            ft = (parse(Int, c[1]), parse(Int, c[2]))
            r0 && (c[3] = "0")
            b0 && (c[5] = "0")
            if haskey(rate, ft)
                c[6] = c[7] = c[8] = string(Float64(rate[ft]))
                push!(seen, ft)
            end
            ln = row(c)
        elseif block[i] === :bus && (held || load != 1)
            c = cols(ln)
            if load != 1
                c[3] = string(parse(Float64, c[3]) * load)
                c[4] = string(parse(Float64, c[4]) * load)
            end
            b = parse(Int, c[1])
            haskey(vg, b) && (c[12] = c[13] = vg[b])
            ln = row(c)
        end
        push!(out, ln)
    end
    absent = setdiff(Set(keys(rate)), seen)
    isempty(absent) || throw(ArgumentError(
        "matpower_edit: no branch row ($(join(sort(collect(absent)), ", "))) in the text."))
    return join(out, '\n')
end

"""
    oracle_dc_opf(text; tol = 1e-8) -> NamedTuple

PowerModels' DC OPF (`DCPPowerModel`) on MATPOWER case `text`, read by
`PowerModels.parse_matpower`, solved by Ipopt with `tol`, `constr_viol_tol`,
`dual_inf_tol` and `compl_inf_tol` all at `tol`, `bound_relax_factor = 0` (Ipopt's default
relaxes every bound by ~1e-8, which lets an answer sit OUTSIDE a rating) and a 120 s
wall-time limit.

Fields: `status`, `primal` (Ipopt's words, as strings), `solved` (LOCALLY_SOLVED with a
feasible point), and in their units — pu on `baseMVA`, radians, \$/h — `gen_bus`, `pg`
(file order), `f_bus`, `t_bus`, `pf` (from-end flow, as THEY report it), `angmin`,
`angmax` (after their reader), `va` (by bus number), `cost` (their objective); `data`,
the parsed dictionary. Unsolved: the vectors are `NaN`.
"""
function oracle_dc_opf(text::AbstractString; tol::Real = 1.0e-8)
    PM.silence()
    data = PM.parse_matpower(IOBuffer(text))
    opt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0,
        "tol" => Float64(tol), "constr_viol_tol" => Float64(tol),
        "dual_inf_tol" => Float64(tol), "compl_inf_tol" => Float64(tol),
        "bound_relax_factor" => 0.0, "max_wall_time" => 120.0)
    r = PM.solve_opf(data, PM.DCPPowerModel, opt)
    ng, nb, nl = length(data["gen"]), length(data["bus"]), length(data["branch"])
    gen(i) = data["gen"][string(i)]
    br(i) = data["branch"][string(i)]
    solved = r["termination_status"] == JuMP.LOCALLY_SOLVED &&
             r["primal_status"] == JuMP.FEASIBLE_POINT
    s = solved ? r["solution"] : nothing
    pick(n, f) = solved ? Float64[f(i) for i in 1:n] : fill(NaN, n)
    return (; status = string(r["termination_status"]), primal = string(r["primal_status"]),
              solved,
              gen_bus = Int[gen(i)["gen_bus"] for i in 1:ng],
              pg = pick(ng, i -> s["gen"][string(i)]["pg"]),
              f_bus = Int[br(i)["f_bus"] for i in 1:nl],
              t_bus = Int[br(i)["t_bus"] for i in 1:nl],
              pf = pick(nl, i -> s["branch"][string(i)]["pf"]),
              angmin = Float64[br(i)["angmin"] for i in 1:nl],
              angmax = Float64[br(i)["angmax"] for i in 1:nl],
              va = pick(nb, i -> s["bus"][string(i)]["va"]),
              cost = solved ? Float64(r["objective"]) : NaN,
              data)
end

"""
    oracle_ac_opf(text; tol = 1e-8) -> NamedTuple

PowerModels' AC OPF in polar form (`ACPPowerModel`) on MATPOWER case `text`, read by
`PowerModels.parse_matpower` and solved by Ipopt with the settings of
[`oracle_dc_opf`](@ref) (every convergence measure at `tol`, `bound_relax_factor = 0`,
120 s wall time). **The same solver as our `ac_opf`**: agreement checks the formulation,
not Ipopt.

The text carries the problem: held voltages, line charging, load level and invented
ratings are edits to it ([`matpower_edit`](@ref)), never to the parsed dictionary.

Fields as `oracle_dc_opf`'s, plus `qg` (file order), `vm` (by bus number), and the
branch flows at both ends as THEY report them — `pf`, `qf` at the from end, `pt`, `qt`
at the to end, each the power entering the branch from that end — pu on `baseMVA`.
"""
function oracle_ac_opf(text::AbstractString; tol::Real = 1.0e-8)
    PM.silence()
    data = PM.parse_matpower(IOBuffer(text))
    opt = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0,
        "tol" => Float64(tol), "constr_viol_tol" => Float64(tol),
        "dual_inf_tol" => Float64(tol), "compl_inf_tol" => Float64(tol),
        "bound_relax_factor" => 0.0, "max_wall_time" => 120.0)
    r = PM.solve_opf(data, PM.ACPPowerModel, opt)
    ng, nb, nl = length(data["gen"]), length(data["bus"]), length(data["branch"])
    gen(i) = data["gen"][string(i)]
    br(i) = data["branch"][string(i)]
    solved = r["termination_status"] == JuMP.LOCALLY_SOLVED &&
             r["primal_status"] == JuMP.FEASIBLE_POINT
    s = solved ? r["solution"] : nothing
    pick(n, f) = solved ? Float64[f(i) for i in 1:n] : fill(NaN, n)
    sb(i, k) = s["branch"][string(i)][k]
    return (; status = string(r["termination_status"]), primal = string(r["primal_status"]),
              solved,
              gen_bus = Int[gen(i)["gen_bus"] for i in 1:ng],
              pg = pick(ng, i -> s["gen"][string(i)]["pg"]),
              qg = pick(ng, i -> s["gen"][string(i)]["qg"]),
              f_bus = Int[br(i)["f_bus"] for i in 1:nl],
              t_bus = Int[br(i)["t_bus"] for i in 1:nl],
              pf = pick(nl, i -> sb(i, "pf")), qf = pick(nl, i -> sb(i, "qf")),
              pt = pick(nl, i -> sb(i, "pt")), qt = pick(nl, i -> sb(i, "qt")),
              angmin = Float64[br(i)["angmin"] for i in 1:nl],
              angmax = Float64[br(i)["angmax"] for i in 1:nl],
              vm = pick(nb, i -> s["bus"][string(i)]["vm"]),
              va = pick(nb, i -> s["bus"][string(i)]["va"]),
              cost = solved ? Float64(r["objective"]) : NaN,
              data)
end
