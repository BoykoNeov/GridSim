# M7 step 8 sabotages: each edit must turn the editor tests red. Restores from a backup.
import subprocess, shutil, os
R = r"W:\Claude_projects\GridSim"
E = "ui/src/editor.jl"; W = "ui/src/editor_window.jl"; N = "ui/src/network_window.jl"
C = "src/model/network_model.jl"
muts = {
 "S8-1 power_balance ignores inverters": (E,
   "    sum(i.P0 for i in ed.inverters; init = 0.0) - sum(l.P0 for l in ed.loads; init = 0.0)",
   "    0.0 - sum(l.P0 for l in ed.loads; init = 0.0)"),
 "S8-2 effective_slack in insertion order": (E,
   """    for b in ed.buses
        any(i -> i.bus === b.id && i.mode === :grid_forming, ed.inverters) && return b.id
    end""",
   """    for i in ed.inverters
        i.mode === :grid_forming && return i.bus
    end"""),
 "S8-3 remove!(bus) keeps its inverters": (E,
   "        filter!(i -> i.bus !== id, ed.inverters)\n", ""),
 "S8-4 rename!(bus) does not rewrite inverters": (E,
   "            i.bus === id && (ed.inverters[k] = _with(i, :bus, new_id))",
   "            nothing"),
 "S8-5 _inverter_with drops τ_pll": (C,
   "    kw = (n => g(n) for n in fieldnames(Inverter) if !(n in _INVERTER_POSITIONAL))",
   "    kw = (n => g(n) for n in fieldnames(Inverter) if !(n in _INVERTER_POSITIONAL) && n !== :τ_pll)"),
 "S8-6 load! does not carry inverters": (E,
   "    empty!(ed.inverters); append!(ed.inverters, sc.net.inverters)\n", ""),
 "S8-7 apply field by field": (W,
   "            set_fields!(ed, kind, id, NamedTuple{fs}(vals))",
   "            for (f, v) in zip(fs, vals); set_field!(ed, kind, id, f, v); end"),
 "S8-8 mode switch does not rebuild the panel": (W,
   "                last_sel[] = :unset          # the panel's fields are the other mode's now\n", ""),
 "S8-9 solve schedule ignores inverters": (W,
   "                    sum((i.P0 for i in ed.inverters if i.bus === s.slack); init = 0.0)",
   "                    0.0"),
 "S8-10 network window: no inverter trip buttons": (N,
   """               [(i.id, @sprintf("%s  —  %+.0f MW  (inverter)", i.id, i.P0))
                for i in net.inverters]]""",
   """               Tuple{Symbol,String}[]]"""),
 "S8-11 taken id checked only after the fields are written": (W,
   "                _assert_fresh(ed, new_id)\n", ""),
}
env = dict(os.environ, GRIDSIM_UI_PRECOMPILE="0", PYTHONIOENCODING="utf-8")
import sys
skip = set(sys.argv[1:])
for name, (f, a, b) in muts.items():
    if name.split()[0] in skip: continue
    p = os.path.join(R, f); s = open(p, encoding="utf-8").read()
    assert s.count(a) == 1, name
    shutil.copy(p, p + ".bak")
    open(p, "w", encoding="utf-8", newline="\n").write(s.replace(a, b))
    try:
        out = subprocess.run(["julia", "--project=W:/Claude_projects/GridSim/ui",
                              "W:/temp/claude/m7/step8/run_editor.jl"],
                             capture_output=True, text=True, encoding="utf-8",
                             errors="replace", env=env).stdout
        summ = [l for l in out.splitlines() if l.startswith("editor only") or
                ("|" in l and ("Fail" in l or "Error" in l or l.rstrip().endswith("s")) and
                 any(c.isdigit() for c in l) and ("Fail" in l or "Error" in l))]
        red = any(("Fail" in l or "Error" in l) for l in out.splitlines() if "|" in l) or \
              "ERROR" in out
        open(os.path.join("W:/temp/claude/m7/step8", name.split()[0] + ".log"), "w",
             encoding="utf-8").write(out)
        print("==", name, "| red" if red else "| GREEN (vacuous!)", flush=True)
        for l in out.splitlines():
            if l.startswith("editor only"): print("   ", l)
    finally:
        shutil.move(p + ".bak", p)
