# M10 step 4 sabotages: apply one mutation to the source, run step 4's testset alone
# (step4_run.jl), record the summary, restore the original. Usage: python step4_mutate.py
# [names] (no names: all six). Predictions (which testsets go red) are in
# step4_predictions.md, written before any of these ran.
# Bytes in, bytes out: `write_text` on Windows would turn the files' LF into CRLF.
import pathlib, subprocess, sys
sys.stdout.reconfigure(encoding="utf-8")
SRC = pathlib.Path(r"W:\Claude_projects\GridSim\src")
DET, OOS = SRC / "engines" / "detailed.jl", SRC / "protection" / "out_of_step.jl"
OUT = pathlib.Path(r"W:\temp\claude\gridsim-m10-step4\mutations")   # scratch logs only
OUT.mkdir(parents=True, exist_ok=True)
orig = {p: p.read_bytes().decode("utf-8") for p in (DET, OOS)}
MUT = {
 # S1: a refused event's writes are not put back.
 "S1_no_restore": [(DET,
   "    err === nothing || _restore!(eng, s)\n", "")],
 # S2: the intermediate network — a re-solve after each line of the event.
 "S2_intermediate": [(DET,
   "                rl.from === br.from && rl.to === br.to && disarm!(rl)\n            end\n        end\n",
   "                rl.from === br.from && rl.to === br.to && disarm!(rl)\n            end\n"
   "            r1, e1 = _reinitialise_outcome!(eng)\n            e1 === nothing || return (r1, e1)\n"
   "        end\n")],
 # S3: no de-energising — a dead bus is left to the solve, as before M10.
 "S3_no_deenergise": [(DET,
   "function _deenergise!(eng::DetailedEngine, v::Int)\n",
   "function _deenergise!(eng::DetailedEngine, v::Int)\n    return nothing\n")],
 # S4: a source cut off alone is left online.
 "S4_cutoff_left_online": [(DET,
   "    auto = Symbol[r.ids[q] for q in eachindex(r.ids) if !lost[q] && !live[piece[r.bus[q]]]]\n"
   "    append!(auto, Symbol[fa.id[q] for q in fon if !live[piece[fa.bus[q]]]])\n",
   "    auto = Symbol[]\n")],
 # S5: the relay's record is not put back when its trip is refused.
 "S5_relay_record": [(OOS,
   "        try\n            trip!(integrator)\n        catch\n"
   "            r.t_tripped, r.δ_tripped = t_was, δ_was\n            rethrow()\n        end\n",
   "        trip!(integrator)\n")],
 # S6: a refusal from inside the solver does not stop the run.
 "S6_no_halt": [(DET,
   "        eng.halted = sprint(showerror, err)\n", "")],
}
try:
    for name, reps in MUT.items():
        if len(sys.argv) > 1 and name not in sys.argv[1:]:
            continue
        txt = dict(orig)
        for p, a, b in reps:
            assert txt[p].count(a) == 1, (name, a)
            txt[p] = txt[p].replace(a, b)
        for p, t in txt.items():
            p.write_bytes(t.encode("utf-8"))
        log = OUT / f"mut_{name}.txt"
        cmd = (r'start /belownormal /b /wait julia --project=W:\Claude_projects\GridSim\docs\evidence\gridsim-m9\harness\testenv '
               r'W:\Claude_projects\GridSim\docs\evidence\gridsim-m10\step4_run.jl > ' + str(log) + ' 2>&1')
        subprocess.run(["cmd", "/c", cmd])
        print("==", name)
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
        i = max((j for j, l in enumerate(lines) if l.startswith("Test Summary")), default=None)
        print("\n".join(lines[i:] if i is not None else lines[-15:]))
finally:
    for p, t in orig.items():
        p.write_bytes(t.encode("utf-8"))
print("restored:", all(p.read_bytes().decode("utf-8") == t for p, t in orig.items()))
