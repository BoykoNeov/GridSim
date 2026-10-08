# M9 step 2 sabotages (predictions in predictions.md, written first). Each is applied to
# the MAIN tree, the focused M9 runner (or the captures, for S6) is run, and the file is
# restored.   python W:/temp/claude/gridsim-m9/step2/mutate.py [S1 S2 ...]
import subprocess, sys, re
SW = r'W:/Claude_projects/GridSim/src/engines/swing.jl'
D = 'W:/temp/claude/gridsim-m9/step2/'
MUTS = {
 'S1 self-term-dropped': [(SW, '    return G_a - Kc * c + K * s\n', '    return -Kc * c + K * s\n')],
 'S2 G-sign': [(SW, '    g, b = R / z2, X / z2\n', '    g, b = -R / z2, X / z2\n')],
 'S3 cos-sin-swapped': [(SW, '    return G_a - Kc * c + K * s\n', '    return G_a - Kc * s + K * s\n')],
 'S4 trip-zeroes-K-only': [(SW, '    if _is_lossy(eng)\n        p[eng.loss.Kc_pidx[e]] = 0.0\n',
                                '    if false\n        p[eng.loss.Kc_pidx[e]] = 0.0\n')],
 'S5 self-terms-by-branch-ends': [(SW, '            c = _lossy_coeffs(E_v[i], E_v[j], br.R, br.X)\n',
    '            c = _lossy_coeffs(E_v[net.bus_index[br.from]], E_v[net.bus_index[br.to]], br.R, br.X)\n')],
 'S6 lossless-path-removed': [(SW, '    lossy = _swing_lossy(net)\n    E_v = ', '    lossy = true\n    E_v = ')],
}
def sh(c):
    p = subprocess.run(['cmd', '/v:on', '/c', 'start /belownormal /b /wait ' + c + ' & exit !errorlevel!'],
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    return p.stdout + p.stderr
def run_tests():
    out = sh('julia --project=W:/temp/claude/gridsim-m8/testenv ' + D + 'run_m9.jl')
    fails = sorted(set(int(x) for x in re.findall(r'(?:Test Failed|Error During Test) at .*?m9_line_resistance\.jl:(\d+)', out)))
    i = out.find('Test Summary')
    summ = [l for l in out[i:].splitlines() if '|' in l][:4] if i >= 0 else ['(no summary)']
    return fails, summ, out
def run_caps(tag):
    res = []
    for name, script in (('swing', D + 'swing_snapshot.jl'), ('criterion', 'W:/temp/claude/gridsim-m8/criterion_snapshot.jl')):
        sh(f'julia --project=W:/Claude_projects/GridSim {script} > {D}{name}-{tag}.txt 2> {D}{name}-{tag}.err')
        a = open(f'{D}{name}-HEAD.txt', encoding='utf-8').read().splitlines()
        b = open(f'{D}{name}-{tag}.txt', encoding='utf-8').read().splitlines()
        res.append(f'{name}: {sum(x != y for x, y in zip(a, b))} of {len(a)} lines differ (len {len(a)} vs {len(b)})')
    return res
only = sys.argv[1:]
for name, edits in MUTS.items():
    key = name.split()[0]
    if only and key not in only:
        continue
    orig = {}
    try:
        for f, a, b in edits:
            raw = open(f, encoding='utf-8', newline='').read()
            orig.setdefault(f, raw)
            crlf = '\r\n' in raw
            cur = raw.replace('\r\n', '\n')
            assert cur.count(a) == 1, (name, a[:60], cur.count(a))
            cur = cur.replace(a, b)
            open(f, 'w', encoding='utf-8', newline='').write(cur.replace('\n', '\r\n') if crlf else cur)
        if key == 'S6':
            for l in run_caps('S6'): print(f'== {name}: {l}', flush=True)
        fails, summ, out = run_tests()
        open(f'{D}mut-{key}.log', 'w', encoding='utf-8').write(out)
        print(f'== {name}: red lines {fails}', flush=True)
        for l in summ: print('   ', l, flush=True)
    finally:
        for f, s in orig.items():
            open(f, 'w', encoding='utf-8', newline='').write(s)
