import sys
R='W:/Claude_projects/GridSim/'
S={
 'S1a':('ext/GridSimDispatchExt.jl','JuMP.@constraint(model, -prob.limit[e] <= flow[e] <= prob.limit[e])','JuMP.@constraint(model, flow[e] <= prob.limit[e])'),
 'S1b':('ext/GridSimDispatchExt.jl','JuMP.@constraint(model, -prob.limit[e] <= flow[e] <= prob.limit[e])','JuMP.@constraint(model, -prob.limit[e] <= flow[e])'),
 'S2':('src/steadystate/dc_opf.jl','br.rating * (1 - margin) / net.S_base','br.rating * (1 - margin)'),
 'S3':('src/steadystate/dc_opf.jl','b = inv.(topo.X),','b = topo.X,'),
 'S4':('ext/GridSimDispatchExt.jl','JuMP.@constraint(model, [v = 1:n], gen[v] - out[v] == prob.load[v])','JuMP.@constraint(model, sum(gen) - sum(out) == sum(prob.load))'),
}
f,old,new=S[sys.argv[1]]
s=open(R+f,encoding='utf-8').read(); assert s.count(old)==1, (sys.argv[1], s.count(old))
open(R+f,'w',encoding='utf-8',newline='').write(s.replace(old,new)); print('applied',sys.argv[1],'to',f)
# Every mutant also gets a solver time limit in the OPF solve alone, so a mutant that
# makes HiGHS spin ends as a thrown error instead of hanging the run (S4 did, 2 h).
f='ext/GridSimDispatchExt.jl'; a='JuMP.fix(θ[prob.slack], 0.0; force = true)'
s=open(R+f,encoding='utf-8').read(); assert s.count(a)==1
open(R+f,'w',encoding='utf-8',newline='').write(s.replace(a,a+'; JuMP.set_attribute(model, "time_limit", 120.0)')); print('time limit added')
