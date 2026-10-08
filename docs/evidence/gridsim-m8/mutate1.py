import subprocess, sys, re
AC = r'W:/Claude_projects/GridSim/src/steadystate/ac_powerflow.jl'
DT = r'W:/Claude_projects/GridSim/src/engines/detailed.jl'

BAND = '''    low = _voltage_band_violations(net, Vm)
    isempty(low) || return _ac_failed(:voltage,
        [(bus = net.buses[v].id, Vm = Vm[v]) for v in low],
        _voltage_band_error(net, Vm, first(low), what))
'''
OVER_END = '''                err = _branch_rating_error(net, mva, first(over), what))
    end
'''
MUTS = {
    'S1 ratings before band': [(AC, BAND, ''), (AC, OVER_END, OVER_END + BAND)],
    'S2 band check names last': [(DT, 'throw(_voltage_band_error(net, Vm, first(bad), what))',
                                  'throw(_voltage_band_error(net, Vm, last(bad), what))')],
    'S3 ratings piece returns first only': [(DT,
        '[e for (e, br) in pairs(net.branches) if !(flows[e] * net.S_base <= br.rating)]',
        '[e for (e, br) in pairs(net.branches) if !(flows[e] * net.S_base <= br.rating)][1:min(end, 1)]')],
    'S4 switching skipped': [(AC, '        isempty(newly) && break\n', '        break\n')],
    'S5 voltage detail first bus only': [(AC, '[(bus = net.buses[v].id, Vm = Vm[v]) for v in low]',
                                          '[(bus = net.buses[v].id, Vm = Vm[v]) for v in low[1:1]]')],
}

def run():
    p = subprocess.run(['cmd', '/v:on', '/c',
        'start /belownormal /b /wait julia --project=W:/temp/claude/gridsim-m8/testenv '
        'W:/temp/claude/gridsim-m8/run_m8only.jl & exit !errorlevel!'],
        capture_output=True, text=True, encoding='utf-8', errors='replace')
    out = p.stdout + p.stderr
    fails = sorted(set(re.findall(r'Test Failed at .*?m8_screening\.jl:(\d+)', out)))
    summ = [l for l in out.splitlines() if l.startswith('m8 ') or 'Test Summary' in l]
    return fails, summ, out

for name, edits in MUTS.items():
    orig = {}
    for f, _, _ in edits:
        if f not in orig:
            orig[f] = open(f, encoding='utf-8', newline='').read()
    cur = dict(orig)
    try:
        for f, a, b in edits:
            a2, b2 = a.replace('\n', '\r\n'), b.replace('\n', '\r\n')
            assert cur[f].count(a2) == 1, (name, a)
            cur[f] = cur[f].replace(a2, b2)
        for f in cur:
            open(f, 'w', encoding='utf-8', newline='').write(cur[f])
        fails, summ, out = run()
        print(f'== {name}: failing lines {fails}')
        for l in summ: print('   ', l)
        if not fails and not any('Fail' in l or 'Error' in l for l in summ):
            print('   GREEN')
        open(r'W:/temp/claude/gridsim-m8/mut-' + name.split()[0] + '.log', 'w', encoding='utf-8').write(out)
    finally:
        for f in orig:
            open(f, 'w', encoding='utf-8', newline='').write(orig[f])
    sys.stdout.flush()
