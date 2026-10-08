import subprocess, shutil, sys, re
R=r"W:\Claude_projects\GridSim"
D="src/engines/detailed.jl"
muts = {
 "S6-1 PLL averaged into ω_coi (D6)": [(D,
   "@inline _ω_coi(eng::DetailedEngine, u) = _coi(eng, u, eng.ω_idx, j -> _gfm_ω(eng, u, j))",
   "@inline _ω_coi(eng::DetailedEngine, u) = (eng.Σw * _coi(eng, u, eng.ω_idx, j -> _gfm_ω(eng, u, j)) + sum(u[eng.gfl.Δω_idx] ./ eng.ω₀; init = 0.0)) / (eng.Σw + length(eng.gfl.ids))")],
 "S6-2 meter re-seeded to the new bus angle at re-initialisation": [(D,
   "    for v in eachindex(eng.Vre_idx)\n        u[eng.Vre_idx[v]] = real(V[v])\n        u[eng.Vim_idx[v]] = imag(V[v])\n    end\n",
   "    for v in eachindex(eng.Vre_idx)\n        u[eng.Vre_idx[v]] = real(V[v])\n        u[eng.Vim_idx[v]] = imag(V[v])\n    end\n    for j in eachindex(eng.meters.bus); u[eng.meters.θ_idx[j]] = angle(V[eng.meters.bus[j]]); end\n")],
 "S6-3 meter attached to the neighbouring bus": [(D,
   "        metered[v] && throw(ArgumentError(",
   "        v = mod1(v + 1, nb)\n        metered[v] && throw(ArgumentError("),
   (D, "    mbus = Int[net.bus_index[m.bus] for m in meters]",
       "    mbus = Int[mod1(net.bus_index[m.bus] + 1, nb) for m in meters]")],
 "S6-4 PLL error normalised by |V|": [(D,
   "@inline _pll_error(Vre, Vim, θ) = -sin(θ) * Vre + cos(θ) * Vim",
   "@inline _pll_error(Vre, Vim, θ) = (-sin(θ) * Vre + cos(θ) * Vim) / hypot(Vre, Vim)")],
 "S6-5 detailed coi_rocof: grid-forming term sign flipped": [(D,
   "        acc += g.H[j] * _gfm_speed(g.K_p[j], du[g.Pf_idx[j]], 0.0)",
   "        acc -= g.H[j] * _gfm_speed(g.K_p[j], du[g.Pf_idx[j]], 0.0)")],
 "S6-6 swing coi_rocof: inverter rate read as the raw state rate": [("src/engines/swing.jl",
   "    @inbounds return d == 0.0 ? du[eng.ω_idx[i]] : -d * du[eng.ω_idx[i]]",
   "    @inbounds return du[eng.ω_idx[i]]")],
 "S6-7 rocof_readouts: zero-weight guard removed": [("src/analysis/postprocess.jl",
   "    k === nothing || throw(ArgumentError(\n        \"rocof_readouts:",
   "    true || throw(ArgumentError(\n        \"rocof_readouts:")],
 "S6-8 rocof_readouts: PLL frequency not scaled to Hz": [("src/analysis/postprocess.jl",
   "windowed_rocof(series.t, f0 .* (1 .+ getfield(series, c)); window = window)",
   "windowed_rocof(series.t, 1 .+ getfield(series, c); window = window)")],
}
only = sys.argv[1:]
for name, edits in muts.items():
    if only and not any(name.startswith(o) for o in only): continue
    files = sorted({f for f,_,_ in edits})
    for f in files: shutil.copy(R+"\\"+f, R+"\\"+f+".bak")
    try:
        for f,a,b in edits:
            p=R+"\\"+f; s=open(p,encoding='utf-8').read()
            assert s.count(a)==1, (name, a[:60], s.count(a))
            open(p,'w',encoding='utf-8',newline='\n').write(s.replace(a,b))
        out=subprocess.run(["julia","--project=W:/temp/claude/m7/testenv","W:/temp/claude/m7/run_m7.jl"],capture_output=True,text=True,encoding='utf-8',errors='replace').stdout
        summ=[l for l in out.splitlines() if "M7 step 6" in l or ("M7 step" in l and ("Fail" in l or "Error" in l))]
        fails=[l.strip() for l in out.splitlines() if "Test Failed" in l or "Error During Test" in l]
        print("==",name, "| red" if ("Fail" in out or "Error" in out) else "| GREEN (vacuous!)", flush=True)
        for l in summ: print("   ",l.strip(), flush=True)
        for l in fails[:6]: print("      ",l[:160], flush=True)
    finally:
        for f in files: shutil.move(R+"\\"+f+".bak", R+"\\"+f)
