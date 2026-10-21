# M11 step 4 sabotages (step4_predictions.md). `python sabotage.py apply NAME` backs the
# files up to scratch and mutates them; `python sabotage.py restore NAME` puts them back.
# Every mutant also gets Ipopt's 120 s CPU limit on OUR side (step 3's patch); the oracle
# sets a 120 s wall-time limit always.
import shutil, sys, os
R = 'W:/Claude_projects/GridSim/'
B = 'W:/temp/claude/gridsim-m11-step4/backup/'
S = {
 # SQ (the plan's): a reactive limit typed wrong on OUR side only — 100 MVAr, not 300.
 'SQ': ('scripts/outage_screen.jl', 'Q_min = -3.0, Q_max = 3.0', 'Q_min = -3.0, Q_max = 1.0'),
 # SC: THEIR side only — line charging left in (the comparison's text without `b0`).
 'SC': ('reference/test/m11_ac_opf_oracle.jl',
        'matpower_edit(C9_MATPOWER; b0, held = true, load, rate)',
        'matpower_edit(C9_MATPOWER; b0 = false, held = true, load, rate)'),
}
TL = ('ext/GridSimOPFExt.jl', '    JuMP.set_attribute(model, "max_iter", max_iter)\n',
      '    JuMP.set_attribute(model, "max_iter", max_iter)\n    JuMP.set_attribute(model, "max_cpu_time", 120.0)\n')
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
