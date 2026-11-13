import re,sys
def load(p):
    d={};name=None
    for ln in open(p,encoding='utf-8'):
        m=re.match(r'\[\[deps\.(.+)\]\]',ln)
        if m: name=m.group(1); d.setdefault(name,None)
        m=re.match(r'version = "(.+)"',ln)
        if m and name: d[name]=m.group(1)
    return d
B=r'W:\temp\claude\gridsim-improve\manifests-before'
R=r'W:\Claude_projects\GridSim'
for n,new in (('root',R+r'\Manifest.toml'),('reference',R+r'\reference\Manifest.toml'),('ui',R+r'\ui\Manifest.toml')):
    a=load(B+chr(92)+n+'-Manifest.toml'); b=load(new)
    moved=[(k,a[k],b[k]) for k in a if k in b and a[k]!=b[k]]
    print('==',n,len(a),'->',len(b),'moved',len(moved),'added',sorted(set(b)-set(a)),'removed',sorted(set(a)-set(b)))
    for k,x,y in moved: print('   ',k,x,'->',y)
