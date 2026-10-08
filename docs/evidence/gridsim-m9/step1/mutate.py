# M9 step 1 sabotages (predictions in predictions.md, written first). Each is applied to
# the MAIN tree, the focused M9 runner is run, and the file is restored.
#   python W:/temp/claude/gridsim-m9/step1/mutate.py [S1 S2 ...]
import subprocess, sys, re
DT = r'W:/Claude_projects/GridSim/src/engines/detailed.jl'
MUTS = {
 'S1 R-sign': [(DT, '        e[1] = status * (a * R + b * X) / z2\n        e[2] = status * (b * R - a * X) / z2\n',
                    '        e[1] = status * (-a * R + b * X) / z2\n        e[2] = status * (-b * R - a * X) / z2\n')],
 'S2 receiving-end-negated': [(DT, '    return R == 0 ? -real(Vf * conj(I)) : real(Vt * conj(-I))\n',
                                  '    return -real(Vf * conj(I))\n')],
 'S3 R-on-machine-base': [
    (DT, '        sp[sR_pidx[e]]      = bt.R[e]\n', '        sp[sR_pidx[e]]      = bt.R[e] * net.S_base / net.machines[1].S_rated\n'),
    (DT, '        p0[R_pidx[e]]      = bt.R[e]\n', '        p0[R_pidx[e]]      = bt.R[e] * net.S_base / net.machines[1].S_rated\n')],
 'S4 R-dynamic-only': [(DT, '        sp[sR_pidx[e]]      = bt.R[e]\n', '        sp[sR_pidx[e]]      = 0.0\n')],
 'S5 R-static-only': [(DT, '        p0[R_pidx[e]]      = bt.R[e]\n', '        p0[R_pidx[e]]      = 0.0\n')],
}
def run():
    p = subprocess.run(['cmd', '/v:on', '/c',
        'start /belownormal /b /wait julia --project=W:/temp/claude/gridsim-m8/testenv '
        'W:/temp/claude/gridsim-m9/step1/run_m9.jl & exit !errorlevel!'],
        capture_output=True, text=True, encoding='utf-8', errors='replace')
    out = p.stdout + p.stderr
    fails = sorted(set(int(x) for x in re.findall(r'(?:Test Failed|Error During Test) at .*?m9_line_resistance\.jl:(\d+)', out)))
    i = out.find('Test Summary')
    summ = [l for l in out[i:].splitlines() if '|' in l][:20] if i >= 0 else ['(no summary)']
    return fails, summ, out
only = sys.argv[1:]
for name, edits in MUTS.items():
    if only and name.split()[0] not in only:
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
        fails, summ, out = run()
        open(f'W:/temp/claude/gridsim-m9/step1/mut-{name.split()[0]}.log', 'w', encoding='utf-8').write(out)
        print(f'== {name}: red lines {fails}', flush=True)
        for l in summ: print('   ', l, flush=True)
    finally:
        for f, s in orig.items():
            open(f, 'w', encoding='utf-8', newline='').write(s)
