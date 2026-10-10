# M9 step 4 sabotages, as run on 2026-10-10 (results: docs/plans/m9-context.md D8).
# Record, not a working copy: paths point at the scratch folder it ran from.
# Run: bash mutate_all.sh M1_no_abs ... (applies one, runs run_v.sh, restores).
# Apply one named mutation to src/steadystate/frequency_verdict.jl, run the verdict
# tests, restore. usage: python mutate.py NAME
import subprocess, sys, shutil
F = r'W:\Claude_projects\GridSim\src\steadystate\frequency_verdict.jl'
M = {
 'M1_no_abs':      ('return abs(Δf) <= lim ? :pass : :fail', 'return Δf <= lim ? :pass : :fail'),
 'M2_strict':      ('return abs(Δf) <= lim ? :pass : :fail', 'return abs(Δf) < lim ? :pass : :fail'),
 'M3_no_f0':       ('gens.Δω_dc[k] * net.f0 : NaN', 'gens.Δω_dc[k] : NaN'),
 'M4_f0_is_50':    ('gens.Δω_dc[k] * net.f0 : NaN', 'gens.Δω_dc[k] * 50.0 : NaN'),
 'M5_no_guard':    ('    has_value || return :no_value\n', ''),
 'M6_cross_read':  ('gens.Δω_dc[k] * net.f0 : NaN', 'gens.Δω_ac[k] * net.f0 : NaN'),
 'M7_falls_only':  ('return abs(Δf) <= lim ? :pass : :fail', 'return -Δf <= lim ? :pass : :fail'),
 'M8_judge_nosol': ('const _AC_SETTLED = (:secure, :overload, :voltage)', 'const _AC_SETTLED = (:secure, :overload, :voltage, :no_solution)'),
 'M9_dip_settled': ('fill(_pending(limits.dip), nm)', 'copy(settled_dc)'),
 'M10_ignore_via': ('(s.via[r] === :none ? 0 : findfirst(==(s.via[r]), g.id))', '0'),
 'M11_ids_only':   ('(gens.machines == ids && all(v -> isempty(v) || length(v) == nb, gens.reactive))', '(gens.machines == ids)'),
}
ORIG = 'W:/temp/claude/gridsim-m9-step4/frequency_verdict.jl.orig'
if sys.argv[1] == 'restore':
    shutil.copy(ORIG, F); sys.exit(0)
name = sys.argv[1]; old, new = M[name]
src = open(F, encoding='utf-8').read()
assert src.count(old) == 1, (name, src.count(old))
shutil.copy(F, ORIG)
open(F, 'w', encoding='utf-8', newline='').write(src.replace(old, new))
