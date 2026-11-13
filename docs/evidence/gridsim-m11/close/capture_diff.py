import re,sys
sys.stdout.reconfigure(encoding="utf-8")
C=r'W:\temp\claude\gridsim-improve\captures'
num=re.compile(r'-?\d+\.\d+(?:e[-+]?\d+)?|-?\d+e[-+]?\d+')
for n in ('criterion','dips','verdict'):
    a=open(C+'\%s-HEAD.txt'%n,encoding='utf-8').read().splitlines()
    b=open(C+'\%s-FIX2.txt'%n,encoding='utf-8').read().splitlines()
    print('==',n,len(a),len(b))
    worst=[];nonnum=[]
    for i,(x,y) in enumerate(zip(a,b)):
        if x==y: continue
        xs=num.findall(x); ys=num.findall(y)
        if len(xs)!=len(ys) or num.sub('#',x)!=num.sub('#',y):
            nonnum.append((i+1,x[:150],y[:150])); continue
        m=0
        for p,q in zip(xs,ys):
            p=float(p);q=float(q)
            if p!=q: m=max(m,abs(p-q)/max(abs(p),abs(q),1e-300))
        worst.append((m,i+1,x[:110],y[:110]))
    worst.sort(reverse=True)
    print(' differing lines',len(worst)+len(nonnum),' non-numeric',len(nonnum))
    for w in worst[:6]: print('  rel %.2e L%d\n     %s\n     %s'%w)
    for w in nonnum[:8]: print('  NONNUM L%d\n     %s\n     %s'%w)
