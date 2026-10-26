# handle-shape toolkit: tubes, sweeps, plates -> manifold3d
import numpy as np, manifold3d as mf, trimesh
import common as cm
from geokit import toM, fromM
ri=cm.ri; Z0,Z1=cm.Z0,cm.Z1
from paths import BUILD
OUT=str(BUILD/'h100')+'/'
def X0(z): return ri(z)+0.75          # mid-wall of the 1.5 mm shell
def V(*a): return np.array(a,float)
# ---------- curves ----------
def catmull(P,n=24,closed=False):
    P=np.asarray(P,float)
    if closed: P=np.vstack([P[-1],P,P[0],P[1]])
    else: P=np.vstack([2*P[0]-P[1],P,2*P[-1]-P[-2]])
    out=[]
    for i in range(1,len(P)-2):
        p0,p1,p2,p3=P[i-1],P[i],P[i+1],P[i+2]
        for t in np.linspace(0,1,n,endpoint=False):
            t2,t3=t*t,t*t*t
            out.append(0.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t2+(-p0+3*p1-3*p2+p3)*t3))
    if not closed: out.append(P[-2])
    return np.array(out)
def xz(pts,y=0.0):
    pts=np.asarray(pts,float); return np.c_[pts[:,0],np.full(len(pts),y) if np.isscalar(y) else y,pts[:,1]]
def resample(P,step=1.0):
    P=np.asarray(P,float); d=np.r_[0,np.cumsum(np.linalg.norm(np.diff(P,axis=0),axis=1))]
    n=max(2,int(d[-1]/step)+1); t=np.linspace(0,d[-1],n)
    return np.c_[[np.interp(t,d,P[:,k]) for k in range(3)]].T
# ---------- primitives ----------
def sphere(c,r,n=20): return mf.Manifold.sphere(r,n).translate(tuple(map(float,c)))
def U(ms): 
    ms=[m for m in ms if m is not None and not m.is_empty()]
    return mf.Manifold.batch_boolean(ms,mf.OpType.Add) if ms else mf.Manifold()
def tube(P,r,n=18,step=None):
    P=np.asarray(P,float)
    if step: P=resample(P,step)
    R=np.broadcast_to(np.asarray(r,float),(len(P),))
    sp=[sphere(p,rr,n) for p,rr in zip(P,R)]
    return U([mf.Manifold.batch_hull([sp[i],sp[i+1]]) for i in range(len(sp)-1)])
def capsule(a,b,r,n=18): return mf.Manifold.batch_hull([sphere(a,r,n),sphere(b,r,n)])
def hull_pts(pts,r,n=14): return mf.Manifold.batch_hull([sphere(p,r,n) for p in pts])
def box(lo,hi): lo=np.asarray(lo,float); hi=np.asarray(hi,float); return mf.Manifold.cube(tuple(hi-lo)).translate(tuple(lo))
def ellipsoid(c,a,b,cc,n=32): return mf.Manifold.sphere(1.0,n).scale((a,b,cc)).translate(tuple(map(float,c)))
def plate_xz(polys,t,y0=0.0):
    """extrude 2D polygons given in (x,z) by thickness t along y, centred on y0"""
    cs=mf.CrossSection([np.asarray(p,float) for p in polys],mf.FillRule.EvenOdd)
    m=cs.extrude(t).rotate((90,0,0))         # (x,y,z)->(x,-z,y): extrusion goes to -y
    return m.translate((0,t/2+y0,0))
def plate_xy(polys,t,z0):
    cs=mf.CrossSection([np.asarray(p,float) for p in polys],mf.FillRule.EvenOdd)
    return cs.extrude(t).translate((0,0,z0-t/2))
def circle2(c,r,n=48): a=np.linspace(0,2*np.pi,n,endpoint=False); return np.c_[c[0]+r*np.cos(a),c[1]+r*np.sin(a)]
def rot_z(m,deg,origin=(0,0,0)): o=np.asarray(origin,float); return m.translate(tuple(-o)).rotate((0,0,deg)).translate(tuple(o))
def rot_y(m,deg,origin=(0,0,0)): o=np.asarray(origin,float); return m.translate(tuple(-o)).rotate((0,deg,0)).translate(tuple(o))
def rot_x(m,deg,origin=(0,0,0)): o=np.asarray(origin,float); return m.translate(tuple(-o)).rotate((deg,0,0)).translate(tuple(o))
# ---------- sweep with arbitrary (star-shaped) section ----------
def rmf(P,closed=False):
    T=np.gradient(P,axis=0)
    if closed: T=np.roll(P,-1,0)-np.roll(P,1,0)
    T/=np.linalg.norm(T,axis=1)[:,None]
    a=np.array([0,1.0,0]) if abs(T[0][1])<0.9 else np.array([1.0,0,0])
    N=[np.cross(T[0],a)]; N[0]/=np.linalg.norm(N[0])
    for i in range(1,len(P)):
        v1=P[i]-P[i-1]; c1=v1@v1
        if c1<1e-12: N.append(N[-1]); continue
        rL=N[-1]-(2/c1)*(v1@N[-1])*v1; tL=T[i-1]-(2/c1)*(v1@T[i-1])*v1
        v2=T[i]-tL; c2=v2@v2
        n=rL-(2/c2)*(v2@rL)*v2 if c2>1e-12 else rL
        n-=T[i]*(n@T[i]); N.append(n/np.linalg.norm(n))
    N=np.array(N); B=np.cross(T,N)
    return T,N,B
def sweep(P,section,twist=0.0,scale=None,closed=False,step=0.8):
    P=resample(np.asarray(P,float),step)
    if closed and np.linalg.norm(P[0]-P[-1])<1e-6: P=P[:-1]
    T,N,B=rmf(P,closed)
    n=len(P); S=np.asarray(section,float); m=len(S)
    if closed:   # distribute frame mismatch
        ang=np.arctan2(np.cross(N[-1],N[0])@T[0],N[-1]@N[0])
    else: ang=0.0
    sc=np.ones(n) if scale is None else np.asarray([scale(i/(n-1)) for i in range(n)])
    verts=[]
    for i in range(n):
        th=np.radians(twist)*i/(n-1 if not closed else n)+ang*i/n
        c,s=np.cos(th),np.sin(th); n2=c*N[i]+s*B[i]; b2=-s*N[i]+c*B[i]
        sec=S if not callable(section) else S
        for u,v in sec*sc[i]: verts.append(P[i]+u*n2+v*b2)
    F=[]
    rng=range(n) if closed else range(n-1)
    for i in rng:
        j=(i+1)%n
        for k in range(m):
            a,b,c_,d=i*m+k,i*m+(k+1)%m,j*m+(k+1)%m,j*m+k
            F+= [[a,b,c_],[a,c_,d]]
    verts=np.array(verts)
    if not closed:
        c0=len(verts); verts=np.vstack([verts,P[0],P[-1]])
        for k in range(m):
            F.append([c0,(k+1)%m,k]); F.append([c0+1,(n-1)*m+k,(n-1)*m+(k+1)%m])
    tm=trimesh.Trimesh(verts,np.array(F),process=False)
    if tm.volume<0: tm.invert()
    return toM(tm)
def sec_circle(r,n=20): a=np.linspace(0,2*np.pi,n,endpoint=False); return np.c_[r*np.cos(a),r*np.sin(a)]
def sec_rect(w,h,rr=0.6,n=4):
    pts=[]
    for cx,cy,a0 in [(w/2-rr,h/2-rr,0),(-w/2+rr,h/2-rr,90),(-w/2+rr,-h/2+rr,180),(w/2-rr,-h/2+rr,270)]:
        for a in np.radians(np.linspace(a0,a0+90,n)): pts.append((cx+rr*np.cos(a),cy+rr*np.sin(a)))
    return np.array(pts)
def sec_poly(r,k,rot=0): a=np.radians(rot)+np.linspace(0,2*np.pi,k,endpoint=False); return np.c_[r*np.cos(a),r*np.sin(a)]
def sec_star(r1,r2,k): a=np.linspace(0,2*np.pi,2*k,endpoint=False); r=np.where(np.arange(2*k)%2==0,r1,r2); return np.c_[r*np.cos(a),r*np.sin(a)]
# ---------- clearance & assembly ----------
def clearance():
    zs=np.linspace(-10,76,40)
    prof=[(0.0,-10.0)]+[(ri(z)+0.5,z) for z in zs]+[(37.6,76.0),(37.6,84.0),(0.0,84.0)]
    cs=mf.CrossSection([np.array(prof)])
    return mf.Manifold.revolve(cs,256)
_CL=None
def clip(h):
    global _CL
    if _CL is None: _CL=clearance()
    return h-_CL
