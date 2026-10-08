"""M8 — the reactive-limit switching branch itself.

The mutation the first run's table listed and never executed: nothing in the set so
far touched the switching test or `_ac_residual!`. With the qlimit fixture moved off
the single-precision grid, this is the mutation that proves the binding-limit
testset is not vacuous.
"""
import subprocess, shutil, re

REPO = r"W:/Claude_projects/GridSim"
TMP = r"W:/temp/claude/gridsim-m6-oracleb"
AC = REPO + "/src/steadystate/ac_powerflow.jl"
TEST = TMP + "/m6_only.jl"

shutil.copyfile(AC, TMP + "/pristine3_ac_powerflow.jl")
def restore():
    shutil.copyfile(TMP + "/pristine3_ac_powerflow.jl", AC)

MUTATIONS = [
    # The bind test itself: a bus that should switch no longer does.
    ("M8a switching: Q_max test never fires",
     "if Qgen[v] > sch.Q_max[v] + _AC_QLIM_TOL",
     "if Qgen[v] > sch.Q_max[v] + _AC_QLIM_TOL + 1.0e6"),
    # The bus switches, but is held at the WRONG limit.
    ("M8b switching: held at Q_min instead of Q_max",
     "                Qheld[v] = sch.Q_max[v]",
     "                Qheld[v] = sch.Q_min[v]"),
    # The reactive residual loses its ZIP scaling.
    ("M9 _ac_residual!: reactive load unscaled",
     "        F[off + i] = Q[v] - (c.Qgen_held[v] - c.Ql[v] * z)",
     "        F[off + i] = Q[v] - (c.Qgen_held[v] - c.Ql[v])"),
]

def run_tests():
    r = subprocess.run(["julia", "--project=" + REPO + "/reference", TEST],
                       capture_output=True, text=True, timeout=3000)
    out = r.stdout + r.stderr
    nf = len(re.findall(r"Test Failed", out))
    ne = len(re.findall(r"Error During", out))
    return (nf == 0 and ne == 0), nf, ne, out

restore()
ok, nf, ne, out = run_tests()
print(f"baseline: green={ok} fail={nf} err={ne}")

for name, old, new in MUTATIONS:
    restore()
    s = open(AC, encoding="utf-8").read()
    n = s.count(old)
    if n != 1:
        print(f"{name}: pattern occurs {n} times -- SKIPPED")
        continue
    open(AC, "w", encoding="utf-8").write(s.replace(old, new))
    ok, nf, ne, out = run_tests()
    print(f"{name}: " + ("NOT CAUGHT (green)" if ok else f"caught: {nf} failed, {ne} errored"))
    sets = sorted(set(re.findall(r"^([a-zA-Z][^:\n]*): Test Failed", out, re.M)))
    for t in sets:
        print(f"      by: {t}")
    open(TMP + f"/mut_{name.split()[0]}.log", "w", encoding="utf-8").write(out)

restore()
print("restored")
