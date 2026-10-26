import numpy as np, trimesh, manifold3d as mf
from paths import ASSETS
W=str(ASSETS)+'/'
R0,K,CL,T=25.17,0.1065,0.35,2.6
Z0,Z1=14.0,64.0; H=Z1-Z0; ZB=Z0-T/2
ri=lambda z:R0+K*z+CL
ro=lambda z:ri(z)+T
def toM(t): return mf.Manifold(mf.Mesh64(vert_properties=np.asarray(t.vertices,np.float64),tri_verts=np.asarray(t.faces,np.uint64)))
def fromM(M):
    m=M.to_mesh64(); return trimesh.Trimesh(np.asarray(m.vert_properties)[:,:3].astype(np.float64),np.asarray(m.tri_verts),process=False)
def fix(m):
    if m.volume<0: m.invert()
    return m
def core_sleeve():
    n=24; prof=[(ri(Z0),Z0)]
    c=(ri(Z1)+T/2,Z1)
    for a in np.linspace(np.pi,0,n): prof.append((c[0]+T/2*np.cos(a),c[1]+T/2*np.sin(a)))
    prof.append((ri(Z0)+T,Z0)); c=(ri(Z0)+T/2,Z0)
    for a in np.linspace(0,-np.pi,n)[1:-1]: prof.append((c[0]+T/2*np.cos(a),c[1]+T/2*np.sin(a)))
    prof.append(prof[0]); return fix(trimesh.creation.revolve(np.array(prof)[::-1],sections=397))
def smoothstep(e0,e1,x):
    t=np.clip((x-e0)/(e1-e0),0,1); return t*t*(3-2*t)
def handle_relief(th):            # 0 behind the handle, 1 elsewhere (th in radians, handle at 0)
    a=np.abs((np.asarray(th)+np.pi)%(2*np.pi)-np.pi)
    return 0.12+0.88*smoothstep(np.radians(13),np.radians(30),a)
def grid_skin(TH,ZZ,Rout,Rin,alt=True):
    """closed solid between two periodic (in theta) surfaces sampled on the same (i,j) grid.
       TH,ZZ,Rout,Rin: arrays (NI,NJ); column i wraps to 0."""
    NI,NJ=TH.shape
    def P(R): return np.stack([R*np.cos(TH),R*np.sin(TH),ZZ],-1).reshape(-1,3)
    V=np.vstack([P(Rout),P(Rin)]); off=NI*NJ
    idx=lambda i,j:(i%NI)*NJ+j
    F=[]
    for i in range(NI):
        for j in range(NJ-1):
            a,b,c,d=idx(i,j),idx(i+1,j),idx(i+1,j+1),idx(i,j+1)
            # diagonal choice: alternate for symmetric creases
            if (not alt) or (i+j)%2==0: F+=[[a,b,c],[a,c,d]]
            else: F+=[[a,b,d],[b,c,d]]
            F+=[[a+off,c+off,b+off],[a+off,d+off,c+off]] if ((not alt) or (i+j)%2==0) else [[a+off,d+off,b+off],[b+off,d+off,c+off]]
    for i in range(NI):   # bottom (j=0) and top (j=NJ-1) closing strips
        a,b=idx(i,0),idx(i+1,0); F+=[[a,a+off,b],[b,a+off,b+off]]
        a,b=idx(i,NJ-1),idx(i+1,NJ-1); F+=[[a,b,a+off],[b,b+off,a+off]]
    m=trimesh.Trimesh(V,np.array(F),process=False)
    return fix(m)
def frame_bands(depth=2.2):
    # chamfered framing rings at top and bottom (45deg chamfers -> printable)
    out=[]
    for zb,zt,up in [(Z0+0.05,Z0+4.0,True),(Z1-4.0,Z1-0.05,False)]:
        if up:  prof=[(ri(zb)+1.0,zb),(ro(zb)+depth,zb),(ro(zt-depth)+depth,zt-depth),(ro(zt),zt),(ri(zt)+1.0,zt)]
        else:   prof=[(ri(zb)+1.0,zb),(ro(zb),zb),(ro(zb+depth)+depth,zb+depth),(ro(zt)+depth,zt),(ri(zt)+1.0,zt)]
        prof.append(prof[0]); out.append(fix(trimesh.creation.revolve(np.array(prof)[::-1],sections=347)))
    return out
def hex_handle(dx=0.0):
    P=np.array([(ri(58.5)+1.6,58.5),(53.5+dx,58.5),(62.0+dx,50.0),(62.0+dx,31.5),(53.5+dx,23.0),(ri(23.0)+1.6,23.0)])
    P3=np.c_[P[:,0],np.zeros(len(P)),P[:,1]]
    sec=np.array([(4.5,2.7),(0.0,5.6),(-4.5,2.7),(-4.5,-2.7),(0.0,-5.6),(4.5,-2.7)])   # (n,y): flats face in/out
    Y=np.array([0,1.0,0])
    rings=[]
    for k in range(len(P3)):
        if k==0: t=P3[1]-P3[0]; sc=1.0
        elif k==len(P3)-1: t=P3[-1]-P3[-2]; sc=1.0
        else:
            t1=(P3[k]-P3[k-1]); t1/=np.linalg.norm(t1); t2=(P3[k+1]-P3[k]); t2/=np.linalg.norm(t2)
            t=t1+t2; sc=1/np.cos(np.arccos(np.clip(t1@t2,-1,1))/2)
        t=t/np.linalg.norm(t); n=np.cross(t,Y)
        rings.append(np.array([P3[k]+n*a*sc+Y*b for a,b in sec]))
    V=np.vstack(rings); m=len(sec); F=[]
    for k in range(len(rings)-1):
        for j in range(m):
            a,b,c,d=k*m+j,k*m+(j+1)%m,(k+1)*m+(j+1)%m,(k+1)*m+j
            F+=[[a,b,c],[a,c,d]]
    c0=len(V); c1=c0+1; V=np.vstack([V,rings[0].mean(0),rings[-1].mean(0)])
    L=(len(rings)-1)*m
    for j in range(m): F+=[[c0,(j+1)%m,j],[c1,L+j,L+(j+1)%m]]
    return fix(trimesh.Trimesh(V,np.array(F),process=False))
def finish(name,parts,cuts=()):
    M=mf.Manifold.batch_boolean([toM(p) for p in parts],mf.OpType.Add)
    if cuts: M=M-mf.Manifold.batch_boolean([toM(p) for p in cuts],mf.OpType.Add)
    m=fromM(M); m.export(W+f'holder_{name}_in_place.stl')
    V=np.asarray(m.vertices).copy(); V[:,2]-=V[:,2].min()
    trimesh.Trimesh(V,m.faces,process=False).export(W+f'cup_holder_{name}.stl')
    check(name)
def check(name):
    from trimesh import boolean
    from collections import Counter
    c=trimesh.load(W+'cup.stl'); a=trimesh.load(W+f'holder_{name}_in_place.stl'); b=trimesh.load(W+f'cup_holder_{name}.stl')
    e=Counter(map(tuple,a.edges_sorted)); bad=sum(1 for v in e.values() if v!=2)
    ov=boolean.intersection([a,c],engine='manifold').volume if a.is_volume else float('nan')
    print('  %s: valid %s/%s bad-edges %d bodies %d size %s vol %.1fcm3 cup-overlap %.3f faces %d'%(name,a.is_volume,b.is_volume,bad,b.body_count,b.extents.round(1),b.volume/1000,ov,len(b.faces)))
