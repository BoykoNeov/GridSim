# M9 step 5 sabotages (results: docs/plans/m9-context.md D9, results.txt here).
# Apply one named mutation to src, run the focused step-4/5 tests, restore.
#   bash mutate_all.sh D1_extremes_from_recorder ...
# usage: python mutate.py NAME | restore
# Paths as forward slashes (a backslash-t in a Windows path became a TAB three times in step 2).
import sys, shutil, os
DIPS = 'W:/Claude_projects/GridSim/src/steadystate/generator_dips.jl'
VERD = 'W:/Claude_projects/GridSim/src/steadystate/frequency_verdict.jl'
DET = 'W:/Claude_projects/GridSim/src/engines/detailed.jl'
TMP = 'W:/temp/claude/gridsim-m9-step5/orig'
M = {
 # The minimum read from the recorder (the plan's first): speed_extremes off the series.
 'D1_extremes_from_recorder': (DET,
    "speed_extremes(eng::DetailedEngine) =\n    (; ids = copy(eng.ids), Δf_min = eng.ω_min .* eng.f0, Δf_max = eng.ω_max .* eng.f0)",
    "speed_extremes(eng::DetailedEngine) = (s = state_series(eng);\n    (; ids = copy(eng.ids), Δf_min = [minimum(getproperty(s, Symbol(:ω_, i))) * eng.f0 for i in eng.ids], Δf_max = [maximum(getproperty(s, Symbol(:ω_, i))) * eng.f0 for i in eng.ids]))"),
 # The COI read in place of every machine (the plan's second).
 'D2_coi_for_machines': (DIPS,
    "            worst[k], Δf_worst[k] = ids[jw], Δf_mach[k][jw]",
    "            worst[k], Δf_worst[k] = ids[jw], ef.nadir - net.f0"),
 # The last sample reported when the horizon runs out (the plan's third).
 'D3_last_sample': (DIPS,
    "    return until === nothing ? (:not_reached, :horizon, eng, NaN) : (:ran, :none, eng, t)",
    "    return until === nothing ? (:settled, :none, eng, t) : (:ran, :none, eng, t)"),
 # A single tolerance (the plan's fourth): the coarse run at the fine setting.
 'D4_one_tolerance': (DIPS,
    "const _DIP_TOLERANCES = ((1.0e-6, 1.0e-8), (1.0e-8, 1.0e-10))",
    "const _DIP_TOLERANCES = ((1.0e-8, 1.0e-10), (1.0e-8, 1.0e-10))"),
 # No hold: stop at the first quiet read.
 'D5_no_hold': (DIPS,
    "            t - quiet >= τ && return (:settled, :none, eng, t)",
    "            return (:settled, :none, eng, t)"),
 # The shortfall bound x100.
 'D6_loose_shortfall': (DIPS,
    "const _DIP_SHORTFALL = 1.0e-5   # Hz",
    "const _DIP_SHORTFALL = 1.0e-3   # Hz"),
 # The coarse run settles on its own (undo "the fine run alone decides").
 'D7_coarse_settles_itself': (DIPS,
    "        sc, why_c, ec, _  = _dip_run(net, base, ids[k], tt, τ, rc, ac; until = span)",
    "        sc, why_c, ec, _  = _dip_run(net, base, ids[k], tt, τ, rc, ac; horizon,\n                                     until = sf === :settled ? nothing : span)"),
 # A voltage refusal at the trip classified as a solver failure.
 'D8_refusal_as_failure': (DIPS,
    "    reason in (:voltage, :rating) && return (:refused, reason, eng, NaN)",
    "    reason in (:rating,) && return (:refused, reason, eng, NaN)"),
 # A stall classified as a refusal.
 'D9_stall_as_refusal': (DIPS,
    "    reason in (:voltage, :rating) && return (:refused, reason, eng, NaN)",
    "    reason in (:voltage, :rating, :stalled) && return (:refused, reason, eng, NaN)"),
 # `<` for `<=` in the dip verdict.
 'D10_strict': (VERD,
    "    f, c = abs(d.Δf_worst[k]) <= lim, abs(d.Δf_worst_coarse[k]) <= lim",
    "    f, c = abs(d.Δf_worst[k]) < lim, abs(d.Δf_worst_coarse[k]) < lim"),
 # The dip runs' model check dropped.
 'D11_no_identity': (VERD,
    "        (dips.machines == ids && dips.branches == Symbol[b.id for b in net.branches] &&\n         dips.f0 === net.f0) || throw(",
    "        true || throw("),
 # The extremes include a tripped machine's undriven rotor.
 'D12_tripped_counted': (DET,
    "        eng.w[k] > 0 || continue\n        x = u[eng.ω_idx[k]]",
    "        x = u[eng.ω_idx[k]]"),
 # Only the fine run judged (the coarse verdict ignored).
 'D13_fine_only': (VERD,
    "    return f == c ? (f ? :pass : :fail) : :tolerance_dependent",
    "    return f ? :pass : :fail"),
 # A run that measured nothing is passed.
 'D14_nothing_passes': (VERD,
    "    d.outcome[k] === :measured || return d.outcome[k]",
    "    d.outcome[k] === :measured || return :pass"),
}
if sys.argv[1] == 'restore':
    for f in (DIPS, VERD, DET):
        o = TMP + '/' + os.path.basename(f)
        if os.path.exists(o):
            shutil.copy(o, f); os.remove(o)
    sys.exit(0)
name = sys.argv[1]; f, old, new = M[name]
src = open(f, encoding='utf-8').read()
assert src.count(old) == 1, (name, src.count(old))
os.makedirs(TMP, exist_ok=True)
shutil.copy(f, TMP + '/' + os.path.basename(f))
open(f, 'w', encoding='utf-8', newline='').write(src.replace(old, new))
