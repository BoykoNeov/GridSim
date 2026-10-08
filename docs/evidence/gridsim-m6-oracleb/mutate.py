"""Drive the oracle-B anti-vacuity mutation set.

Each mutation is applied to OUR side only (src/), the extracted M6 testset is run,
and the file is restored from a pristine copy. Reverting is from a byte copy taken
before anything ran, never by re-applying the edit backwards.
"""
import subprocess, shutil, os, re, sys

REPO = r"W:/Claude_projects/GridSim"
TMP = r"W:/temp/claude/gridsim-m6-oracleb"
AC = REPO + "/src/steadystate/ac_powerflow.jl"
NM = REPO + "/src/model/network_model.jl"
DE = REPO + "/src/engines/detailed.jl"
TEST = TMP + "/m6_only.jl"

# Pristine copies, taken once.
for f in (AC, NM, DE):
    shutil.copyfile(f, TMP + "/pristine_" + os.path.basename(f))

def restore():
    for f in (AC, NM, DE):
        shutil.copyfile(TMP + "/pristine_" + os.path.basename(f), f)

MUTATIONS = [
    ("M1a admittance assembly: sign of the reactance", AC,
     "y = inv(complex(br.R, br.X))     # X > 0 is enforced by",
     "y = inv(complex(br.R, -br.X))    # X > 0 is enforced by"),
    ("M1b branch-flow read-out: sign of the reactance", AC,
     "        y = inv(complex(br.R, br.X))
",
     "        y = inv(complex(br.R, -br.X))
"),
]

def run_tests():
    r = subprocess.run(["julia", "--project=" + REPO + "/reference", TEST],
                       capture_output=True, text=True, timeout=3000)
    out = r.stdout + r.stderr
    m = re.findall(r"oracle B[^|]*\|\s*(\d+)?\s*(\d+)?\s*(\d+)?\s*(\d+)\s", out)
    passed = len(re.findall(r"Test Failed|Error During", out)) == 0
    nfail = len(re.findall(r"Test Failed", out))
    nerr = len(re.findall(r"Error During", out))
    npass = 0
    mm = re.search(r"oracle B[^\n]*?\|\s+(\d+)", out)
    if mm: npass = int(mm.group(1))
    return passed, npass, nfail, nerr, out

print("=== baseline (no mutation) ===")
restore()
ok, np_, nf, ne, out = run_tests()
print(f"baseline: green={ok} pass={np_} fail={nf} err={ne}")
if not ok:
    print(out[-3000:]); sys.exit(1)

rows = []
for name, path, old, new in MUTATIONS:
    restore()
    s = open(path, encoding="utf-8").read()
    n = s.count(old)
    if n != 1:
        rows.append((name, f"SKIPPED: pattern occurs {n} times"))
        print(f"{name}: pattern count {n} -- skipped")
        continue
    open(path, "w", encoding="utf-8").write(s.replace(old, new))
    ok, np_, nf, ne, out = run_tests()
    verdict = "NOT CAUGHT (green)" if ok else f"caught: {nf} failed, {ne} errored"
    rows.append((name, verdict))
    print(f"{name}: {verdict}")
    open(TMP + f"/mut_{name.split()[0]}.log", "w", encoding="utf-8").write(out)

restore()
print("\n=== summary ===")
for name, v in rows:
    print(f"  {name:55s} {v}")
