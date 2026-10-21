# M11 step 2 sabotages (step2_predictions.md). `python sabotage.py apply NAME` backs the
# file up to scratch and mutates it; `python sabotage.py restore NAME` puts it back.
# Every mutant also gets a HiGHS time limit in the OPF solve (step 1's lesson); Ipopt's
# 120 s wall-time limit is always set by the oracle.
import shutil, sys, os
R = 'W:/Claude_projects/GridSim/'
B = 'W:/temp/claude/gridsim-m11-step2/backup/'
S = {
 'SA1': ('scripts/outage_screen.jl', '(:L89, 8, 9, 0.032, 0.161, 250.0)', '(:L89, 8, 9, 0.032, 0.116, 250.0)'),
 'SA2': ('scripts/outage_screen.jl', '(c2 = 0.085, c1 = 1.2, c0 = 600.0, Pmin = 10.0)', '(c2 = 0.085, c1 = 1.25, c0 = 600.0, Pmin = 10.0)'),
 'SB':  ('reference/src/opf_oracle.jl', 'c[6] = c[7] = c[8] = string(Float64(rate[ft]))', 'c[6] = c[7] = c[8] = string(Float64(rate[ft]) / 100)'),
}
TL = ('ext/GridSimDispatchExt.jl', 'JuMP.fix(θ[prob.slack], 0.0; force = true)',
      'JuMP.fix(θ[prob.slack], 0.0; force = true); JuMP.set_attribute(model, "time_limit", 120.0)')
def mutate(f, old, new):
    s = open(R + f, encoding='utf-8').read(); assert s.count(old) == 1, (f, s.count(old))
    open(R + f, 'w', encoding='utf-8', newline='').write(s.replace(old, new))
act, name = sys.argv[1], sys.argv[2]
files = [S[name][0], TL[0]]
os.makedirs(B, exist_ok=True)
if act == 'apply':
    for f in files: shutil.copyfile(R + f, B + f.replace('/', '__'))
    mutate(*S[name]); mutate(*TL); print('applied', name)
else:
    for f in files: shutil.copyfile(B + f.replace('/', '__'), R + f)
    print('restored', name)
