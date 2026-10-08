"""The two admittance-sign mutations, run separately.

`inv(complex(br.R, br.X))` appears TWICE in `ac_powerflow.jl` and that is
deliberate: the branch-flow read-out recomputes the series admittance rather than
reading it back out of `Y`, so that step 3's losses identity compares two numbers
built from different data. One pattern therefore hits two sites, and each gets its
own mutation.
"""
import subprocess, shutil, os, re

REPO = r"W:/Claude_projects/GridSim"
TMP = r"W:/temp/claude/gridsim-m6-oracleb"
AC = REPO + "/src/steadystate/ac_powerflow.jl"
TEST = TMP + "/m6_only.jl"

shutil.copyfile(AC, TMP + "/pristine2_ac_powerflow.jl")
def restore():
    shutil.copyfile(TMP + "/pristine2_ac_powerflow.jl", AC)

LINE_ASSEMBLY = "        y = inv(complex(br.R, br.X))     # X > 0 is enforced by `Branch`, so never 1/0\n"
LINE_READOUT = "        y = inv(complex(br.R, br.X))\n"

MUTATIONS = [
    ("M1a _ac_admittance: sign of the reactance",
     LINE_ASSEMBLY, "        y = inv(complex(br.R, -br.X))\n"),
    ("M1b branch-flow read-out: sign of the reactance",
     LINE_READOUT, "        y = inv(complex(br.R, -br.X))\n"),
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
    open(TMP + f"/mut_{name.split()[0]}.log", "w", encoding="utf-8").write(out)

restore()
print("restored")
