# M9 step 6 sabotages (results: docs/plans/m9-context.md D10, results.txt here).
# Apply one named mutation to src, run the focused step-4/5/6 tests, restore.
#   bash mutate_all.sh R1_window_ignored ...
# usage: python mutate.py NAME | restore
# Paths as forward slashes (a backslash-t in a Windows path became a TAB three times in step 2).
import sys, shutil, os
DIPS = 'W:/Claude_projects/GridSim/src/steadystate/generator_dips.jl'
VERD = 'W:/Claude_projects/GridSim/src/steadystate/frequency_verdict.jl'
DET = 'W:/Claude_projects/GridSim/src/engines/detailed.jl'
NETM = 'W:/Claude_projects/GridSim/src/model/network_model.jl'
TMP = 'W:/temp/claude/gridsim-m9-step6/orig'
M = {
 # The plan's first: the verdict ignores the limit's window (reads 500 ms whatever it says).
 'R1_window_ignored': (VERD,
    "    r = generator_rates(dips; window = limits.rate_window)",
    "    r = generator_rates(dips; window = 0.5)"),
 # The plan's second: H left on the machine base.
 'R2_H_machine_base': (NETM,
    "        H[v]  = m.H * w",
    "        H[v]  = m.H"),
 # The plan's third: the lost machine's inertia left in the sum after the trip.
 'R3_lost_inertia_kept': (DET,
    "        eng.w[k] = 0.0\n        for l in eng.ladders",
    "        for l in eng.ladders"),
 # `abs` dropped: a falling (negative) rate is always below the limit.
 'R4_no_abs': (VERD,
    "    f, c = abs(fine) <= lim, abs(coarse) <= lim",
    "    f, c = fine <= lim, coarse <= lim"),
 # The half-sample guard dropped: the window handed to windowed_rocof as is.
 'R5_no_half_sample': (DIPS,
    "    r = windowed_rocof(t, f; window = window - _DIP_DT / 2)",
    "    r = windowed_rocof(t, f; window = window)"),
 # The COI rate judged in place of the machines.
 'R6_coi_for_machines': (DIPS,
    "        worst[k], rw[k] = d.machines[jw], rm[k][jw]",
    "        worst[k], rw[k] = d.machines[jw], rc[k]"),
 # Only the fine run judged.
 'R7_fine_only': (VERD,
    "    return f == c ? (f ? :pass : :fail) : :tolerance_dependent",
    "    return f ? :pass : :fail"),
 # A run that measured nothing passes.
 'R8_nothing_passes': (VERD,
    "    outcome === :measured || return outcome",
    "    outcome === :measured || return :pass"),
 # A window off the output grid accepted.
 'R9_offgrid_window': (DIPS,
    "    (isfinite(w) && round(m) >= 1 && abs(m - round(m)) <= 1e-9 * m) || throw(ArgumentError(",
    "    (isfinite(w) && round(m) >= 1) || throw(ArgumentError("),
 # The horizon check dropped: a run that could fill the recorder is started.
 'R10_no_horizon_check': (DIPS,
    "        n <= _TRAJ_CAPACITY || throw(ArgumentError(",
    "        true || throw(ArgumentError("),
 # The decimation guard dropped: a thinned trace is differenced.
 'R11_no_decimation_guard': (DIPS,
    "    eng.traj.keep_every == 1 || error(",
    "    true || error("),
}
if sys.argv[1] == 'restore':
    for f in (DIPS, VERD, DET, NETM):
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
