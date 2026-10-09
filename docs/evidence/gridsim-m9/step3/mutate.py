# M9 step 3 sabotages (predictions in predictions.md, written first). Each is applied
# to the MAIN tree, the listed runs are made, and every file is restored.
#   python W:/Claude_projects/GridSim/docs/evidence/gridsim-m9/step3/mutate.py [T1 T2 ...]
# Runs: 'm9' = core M9 testsets (harness run_m9.jl), 's3' = the reference step-3
# testsets with the helpers they need, 'oB' = the reference M6 oracle-B testsets,
# 'core' = the whole core Pkg.test(). The two reference runners are cut from
# reference/test/runtests.jl into scratch (see the step-3 notes in m9-context.md D7).
import subprocess, sys, re
sys.stdout.reconfigure(encoding='utf-8')
R = 'W:/Claude_projects/GridSim/'
DT, AC, SW, TF = R + 'src/engines/detailed.jl', R + 'src/steadystate/ac_powerflow.jl', \
    R + 'src/engines/swing.jl', R + 'test/m9_line_resistance.jl'
S = 'W:/temp/claude/gridsim-m9/step3/'
H = R + 'docs/evidence/gridsim-m9/harness/'
T1 = [(DT, '    X, status, R = p[1], p[2], p[3]\n', '    X, status, R = p[1], p[2], 2 * p[3]\n'),
      (DT, '    status * d / complex(R, X)\n', '    status * d / complex(2R, X)\n'),
      (AC, 'y = inv(complex(br.R, br.X))', 'y = inv(complex(2br.R, br.X))')]
T2 = [(SW, '            c = _lossy_coeffs(E_v[i], E_v[j], br.R, br.X)\n',
           '            c = _lossy_coeffs(E_v[i], E_v[j], 2br.R, br.X)\n'),
      (SW, '_lossy_reach(sv.E, bt.src, bt.dst, bt.R, bt.X)', '_lossy_reach(sv.E, bt.src, bt.dst, 2 .* bt.R, bt.X)')]
T4 = [(SW, '    g, b = R / z2, X / z2\n', '    g, b = -R / z2, X / z2\n'),
      (TF, 'real(Va * conj((Va - Vb) / complex(R, X)))', 'real(Va * conj((Va - Vb) / complex(-R, X)))')]
# T1b: T1 at x1.1 rather than x2 — x2 pushes some report-grid outages past having a
# steady state at all, so a check can go red by refusal without its identity seeing it.
T1b = [(f, o, n.replace('2 * p[3]', '1.1 * p[3]').replace('2R', '1.1R').replace('2br.R', '1.1br.R'))
       for f, o, n in T1]
MUTS = {'T1': (T1, ['m9', 's3', 'oB', 'core']), 'T1b': (T1b, ['m9', 's3']), 'T2': (T2, ['m9', 's3']),
        'T3': (T1 + T2, ['m9', 's3', 'oB', 'core']), 'T4': (T4, ['m9', 's3']),
        # T5: T3 at x1.1 AND the test's own end formula misreading R the same way.
        'T5': (T1b + [(f, o, n.replace('2br.R', '1.1br.R').replace('2 .* bt.R', '1.1 .* bt.R'))
                      for f, o, n in T2] +
               [(TF, 'real(Va * conj((Va - Vb) / complex(R, X)))',
                     'real(Va * conj((Va - Vb) / complex(1.1R, X)))')], ['m9', 's3'])}
RUNS = {
 'm9':   ('julia --project=' + H + 'testenv ' + H + 'run_m9.jl', r'm9_line_resistance\.jl:(\d+)'),
 's3':   ('julia --project=' + R + 'reference ' + S + 'run_s3.jl', r'run_s3\.jl:(\d+)'),
 'oB':   ('julia --project=' + R + 'reference ' + S + 'run_oracleB.jl', r'run_oracleB\.jl:(\d+)'),
 'core': ('julia --project=' + R + ' ' + H + 'pkgtest.jl', r'test[\\/](\w+\.jl):(\d+)'),
}
def sh(c):
    p = subprocess.run(['cmd', '/v:on', '/c', 'start /belownormal /b /wait ' + c + ' & exit !errorlevel!'],
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    return p.stdout + p.stderr
# Arguments: KEY or KEY=run,run (a subset of that sabotage's runs).
only = dict((a.split('=') + [''])[:2] for a in sys.argv[1:])
for key, (edits, runs) in MUTS.items():
    if only and key not in only:
        continue
    if only.get(key):
        runs = only[key].split(',')
    orig = {}
    for path, old, new in edits:
        txt = orig.setdefault(path, open(path, encoding='utf-8').read())
        cur = open(path, encoding='utf-8').read()
        assert old in cur, (key, path, old)
        open(path, 'w', encoding='utf-8', newline='\n').write(cur.replace(old, new))
    try:
        for r in runs:
            cmd, pat = RUNS[r]
            out = sh(cmd)
            open(f'{S}mut-{key}-{r}.log', 'w', encoding='utf-8').write(out)
            fails = re.findall(r'(?:Test Failed|Error During Test) at .*?' + pat, out)
            fails = sorted(set(':'.join(f) if isinstance(f, tuple) else f for f in fails))
            summ = [l for l in out.splitlines() if re.search(r'\|\s+\d+', l)][-6:]
            print(f'== {key} {r}: red at {fails if fails else "nothing"}')
            for l in summ:
                print('   ', l)
            sys.stdout.flush()
    finally:
        for path, txt in orig.items():
            open(path, 'w', encoding='utf-8', newline='\n').write(txt)
