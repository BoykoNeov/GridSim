import subprocess, shutil, sys
R=r"W:\Claude_projects\GridSim"
muts = {
 "M11 K_p left on the inverter's own base": ("src/engines/swing.jl",
   "        K_p[v] = inv.K_p * net.S_base / inv.S_rated", "        K_p[v] = inv.K_p"),
 "M12 power filter (nearly) removed": ("src/engines/swing.jl",
   "    dv[2] = (P_meas - P_filt) / τ_p", "    dv[2] = (P_meas - P_filt) / 1e-3"),
 "M13 speed read as the raw state": ("src/engines/swing.jl",
   "    @inbounds return d == 0.0 ? u[eng.ω_idx[i]] :", "    @inbounds return true ? u[eng.ω_idx[i]] :"),
 "M14 virtual inertia not weighted to the system base": ("src/engines/swing.jl",
   "        H[v] = inv.τ_p / (2 * inv.K_p) * (inv.S_rated / net.S_base)", "        H[v] = inv.τ_p / (2 * inv.K_p)"),
}
for name,(f,a,b) in muts.items():
    p=R+"\\"+f; s=open(p,encoding='utf-8').read()
    assert s.count(a)==1, name
    shutil.copy(p, p+".bak")
    open(p,'w',encoding='utf-8',newline='\n').write(s.replace(a,b))
    try:
        out=subprocess.run(["julia","--project=W:/temp/claude/m7/testenv","W:/temp/claude/m7/run_m7.jl"],capture_output=True,text=True,encoding='utf-8',errors='replace').stdout
        summ=[l for l in out.splitlines() if ("Test Summary" in l) or l.startswith("M7 step")]
        print("==",name, "| red" if ("Fail" in out or "Error" in out) else "| GREEN (vacuous!)")
        for l in summ: print("   ",l)
    finally:
        shutil.move(p+".bak", p)
