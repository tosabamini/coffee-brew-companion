from lightkit import *
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
from paths import ASSETS
W_=str(ASSETS)+'/'
xin=lambda z: ri(z)+0.8          # embedded into the shell / stile
def ext_y(poly,y0,y1):
    """robust prism along y: triangulate (triangle engine), walls from boundary edges of the triangulation"""
    out=[]
    poly=poly.buffer(-0.02,join_style='mitre').buffer(0.02,join_style='mitre')
    for p in cm.polys_of(poly):
        if p.area<0.05: continue
        v2,f2=trimesh.creation.triangulate_polygon(p,engine='triangle',triangle_args='p')
        n=len(v2)
        e=np.sort(np.vstack([f2[:,[0,1]],f2[:,[1,2]],f2[:,[2,0]]]),axis=1)
        u,c=np.unique(e,axis=0,return_counts=True); bset=set(map(tuple,u[c==1]))
        side=[]
        for t in f2:
            for i,j in ((t[0],t[1]),(t[1],t[2]),(t[2],t[0])):
                if (min(i,j),max(i,j)) in bset: side.append([i,j])
        side=np.array(side)
        F=np.vstack([f2[:,::-1],f2+n,np.c_[side[:,0],side[:,1],side[:,1]+n],np.c_[side[:,0],side[:,1]+n,side[:,0]+n]])
        V=np.vstack([np.c_[v2[:,0],np.full(n,y0),v2[:,1]],np.c_[v2[:,0],np.full(n,y1),v2[:,1]]])
        m=trimesh.Trimesh(V,F,process=False)
        if m.volume<0: m.invert()
        out.append(m)
    return out
def plate(body,outline,opening,holes,half=3.1,step=0.75):
    """stepped-edge plate: full profile in the middle, outer faces inset along the outer edge and the finger opening"""
    core=body.difference(holes)
    face=(outline.buffer(-step,join_style='mitre').difference(opening.buffer(step,join_style='mitre'))).intersection(body).difference(holes)
    face=face.union(body.intersection(Polygon([(xin(z),z) for z in np.linspace(10,70,30)]+[(ri(z)+4.5,z) for z in np.linspace(70,10,30)])).difference(holes))
    face=face.difference(holes.buffer(0.15)).buffer(-0.3,join_style='mitre').buffer(0.3,join_style='mitre').intersection(body.buffer(-0.12,join_style='mitre'))      # offset from core walls, drop slivers
    return ext_y(core,-(half-step),half-step)+ext_y(face,-half,-(half-step)+0.13)+ext_y(face,half-step-0.13,half)
def preview(name,body,holes,opening):
    fig,ax=plt.subplots(figsize=(5,7))
    for g,c in [(body,'#2b4f8a')]:
        for p in cm.polys_of(g):
            ax.fill(*p.exterior.xy,color=c)
            for i in p.interiors: ax.fill(*i.xy,color='w')
    zz=np.linspace(14,64,20); ax.plot([ri(z)+SH for z in zz],zz,'k-',lw=0.8)
    ax.set_aspect('equal'); ax.grid(alpha=.3); plt.savefig(W_+f'hprof_{name}.png',dpi=90); plt.close()
# ---------------- C : golden rectangle + golden spiral ----------------
def golden_handle():
    PHI=(1+5**0.5)/2
    WG=30.0
    x0,x1=ri(40)+SH+0.2,ri(40)+SH+0.2+WG
    z1=63.3; z0=z1-WG*PHI                        # 48.5 tall
    x0b=xin(z0)
    outline=Polygon([(xin(z0),z0),(x1,z0),(x1,z1),(xin(z1),z1)])
    # recursive squares (top, left, bottom-right, right...) with spiral arcs
    sq=[]; arcs=[]
    def arc(c,r,a0,a1,n=40): a=np.linspace(a0,a1,n); return np.c_[c[0]+r*np.cos(a),c[1]+r*np.sin(a)]
    s1=WG; sq.append(box(x0,z1-s1,x1,z1)); arcs.append(arc((x1,z1-s1),s1,np.pi,np.pi/2))       # quarter disk = finger opening
    zA=z1-s1; s2=zA-z0                       # 16.07
    sq.append(box(x0,z0,x0+s2,zA)); arcs.append(arc((x0+s2,zA),s2,np.pi,3*np.pi/2))
    s3=x1-(x0+s2)                            # 9.93
    sq.append(box(x1-s3,z0,x1,z0+s3)); arcs.append(arc((x1-s3,z0+s3),s3,3*np.pi/2,2*np.pi))
    s4=zA-(z0+s3)                            # 6.14
    sq.append(box(x1-s4,zA-s4,x1,zA)); arcs.append(arc((x1-s4,zA-s4),s4,0,np.pi/2))
    s5=s3-s4                                 # 3.79
    sq.append(box(x1-s3,zA-s5,x1-s3+s5,zA)); arcs.append(arc((x1-s3+s5,zA-s5),s5,np.pi/2,np.pi))
    s6=s4-s5
    sq.append(box(x1-s3,z0+s3,x1-s3+s6,z0+s3+s6)); arcs.append(arc((x1-s3+s6,z0+s3+s6),s6,np.pi,3*np.pi/2))
    # finger opening: inside the first quarter circle
    q=Polygon(np.vstack([[[x1,z1-s1]],arcs[0]]))
    grip_frame=outline.buffer(-3.2,join_style='mitre')
    opening=q.intersection(grip_frame).intersection(box(xin(z1)+2.6,0,1e3,1e3))
    opening=opening.buffer(-2.0,join_style='round').buffer(2.0,quad_segs=12)          # rounded corners for the fingers
    ribs=unary_union([LineString(a).buffer(1.3,cap_style='round') for a in arcs[1:4]]+
                     [LineString(list(s.exterior.coords)).buffer(0.6,cap_style='flat',join_style='mitre') for s in sq[1:5]])

    frame=outline.difference(outline.buffer(-2.4,join_style='mitre'))
    # sunflower (Vogel) holes in the spandrel outside the big arc
    spand=sq[0].difference(opening.buffer(1.6)).intersection(outline.buffer(-1.9,join_style='mitre')).difference(box(0,0,xin(z1)+2.0,1e3))
    print('spandrel area %.1f'%spand.area)
    mic=shapely.maximum_inscribed_circle(spand); cx,cz=list(mic.coords)[0]
    GA=np.pi*(3-5**0.5); sun=[]
    for n in range(0,220):
        r=1.22*np.sqrt(n+0.5); a=n*GA
        p=Point(cx+r*np.cos(a),cz+r*np.sin(a)); rad=0.5
        hole=p.buffer(rad,quad_segs=8)
        if spand.buffer(-0.2).contains(hole): sun.append(hole)
    lower_holes=outline.intersection(box(x0,z0,x1,zA)).buffer(-2.4,join_style='mitre').difference(ribs)
    holes=unary_union([*cm.polys_of(lower_holes)]+sun)
    holes=unary_union([h for h in cm.polys_of(holes) if h.area>0.6])
    body=outline.difference(opening)
    preview('golden',body.difference(holes),holes,opening)
    print('golden handle: opening bbox',np.round(opening.bounds,1),'sunflower holes',len(sun))
    return plate(body,outline,opening,holes)
if __name__=='__main__':
    parts=golden_handle(); print(len(parts))
# ---------------- A : Penrose lattice plate ----------------
def penrose_tiles(N=16,seed=11):
    rng=np.random.default_rng(seed)
    e=np.array([[np.cos(2*np.pi*k/5),np.sin(2*np.pi*k/5)] for k in range(5)])
    gam=rng.uniform(-0.4,0.4,5); gam-=gam.mean(); tiles=[]
    for r in range(5):
        for s in range(r+1,5):
            Ainv=np.linalg.inv(np.array([e[r],e[s]]))
            for kr in range(-N,N):
                for ks in range(-N,N):
                    p=Ainv@np.array([kr-gam[r],ks-gam[s]]); K=np.ceil(p@e.T+gam); K[r]=kr; K[s]=ks
                    b=K@e; tiles.append((np.array([b,b+e[r],b+e[r]+e[s],b+e[s]]),(s-r) in (1,4)))
    return tiles
def penrose_handle():
    zt,zb=63.4,17.4; xg=67.0
    # outline: pentagonal 'arrow' whose outer point carries the 108deg Penrose angle
    t108=np.tan(np.radians(54))
    zc=(zt+zb)/2; dx=(zt-zb)/2/t108*0.55
    outline=Polygon([(xin(zb),zb),(xg-dx,zb),(xg,zc-6.0),(xg,zc+6.0),(xg-dx,zt),(xin(zt),zt)])
    outline=outline.buffer(-1.0,join_style='round').buffer(1.0,quad_segs=6)
    opening=Polygon([(xin(zc)-4.0,zb+8.6),(xg-dx-2.5,zb+8.6),(xg-9.0,zc-4.0),(xg-9.0,zc+4.0),(xg-dx-2.5,zt-8.6),(xin(zc)-4.0,zt-8.6)])
    opening=opening.buffer(-1.8,join_style='round').buffer(1.8,quad_segs=10)
    body=outline.difference(opening)
    web=outline.buffer(-1.7,join_style='mitre').difference(opening.buffer(2.1,join_style='round')).difference(box(0,0,ri(40)+SH+2.0,1e3))
    EDGE=5.0; holes=[]
    for v,thick in penrose_tiles():
        P=Polygon(np.c_[v[:,0]*EDGE+50.0,v[:,1]*EDGE+zc])
        if not P.intersects(web): continue
        h=P.buffer(-0.55,join_style='mitre').intersection(web)
        h=h.buffer(-0.25).buffer(0.25)
        for q in cm.polys_of(h):
            if q.area>0.9: holes.append(q)
    holes=unary_union(holes)
    preview('penrose',body.difference(holes),holes,opening)
    print('penrose handle: opening bbox',np.round(opening.bounds,1),'holes',len(cm.polys_of(holes)))
    return plate(body,outline,opening,holes,half=3.0)
# ---------------- B : Shukhov handle (straight members only) ----------------
def bar(p0,p1,a=1.8,ext=0.6,up=None):
    p0=np.asarray(p0,float); p1=np.asarray(p1,float); d=p1-p0; L=np.linalg.norm(d); d/=L
    ref=np.array([0,0,1.0]) if abs(d[2])<0.9 else np.array([1.0,0,0])
    if up is not None: ref=np.asarray(up,float)
    u=np.cross(d,ref); u/=np.linalg.norm(u); w=np.cross(d,u); pts=[]
    for t in (-ext,L+ext):
        for su,sw in ((1,1),(1,-1),(-1,-1),(-1,1)): pts.append(p0+d*t+u*su*a/2+w*sw*a/2)
    return trimesh.convex.convex_hull(np.array(pts))
def poly_ring(c,r,z,n,a=1.8,phase=0.0):
    pts=[np.array([c[0]+r*np.cos(phase+2*np.pi*k/n),c[1]+r*np.sin(phase+2*np.pi*k/n),z]) for k in range(n)]
    return [bar(pts[k],pts[(k+1)%n],a,ext=0.5*a,up=[0,0,1]) for k in range(n)],pts
def shukhov_handle():
    xg=62.2; R=4.5; zt,zb=56.6,24.8; NG=10; TWG=np.radians(70)
    parts=[]
    rt,pt=poly_ring((xg,0),R,zt,NG); rb,pb=poly_ring((xg,0),R,zb,NG,phase=0.0)
    parts+=rt+rb
    for fam in (1,-1):                                    # grip = small hyperboloid
        for k in range(NG):
            a0=2*np.pi*k/NG; a1=a0+fam*TWG
            p0=(xg+R*np.cos(a0),R*np.sin(a0),zb); p1=(xg+R*np.cos(a1),R*np.sin(a1),zt)
            parts.append(bar(p0,p1,1.6 if fam>0 else 1.55))
    # arms = hyperbolic paraboloids spanned between the stile and the grip rings
    def hypar(P0,P1,Q0,Q1,n=6):
        out=[bar(P0,P1,1.7,up=[1,0,0]),bar(Q0,Q1,1.7,up=[1,0,0])]
        for t in np.linspace(0,1,n):
            out.append(bar(np.asarray(P0)*(1-t)+np.asarray(P1)*t,np.asarray(Q0)*(1-t)+np.asarray(Q1)*t,1.5))
        return out
    xs_t=ri(59.0)+1.8; xs_b=ri(22.0)+1.8
    parts+=hypar((xs_t,-3.6,62.2),(xs_t,3.6,56.4),(xg-R*0.95,-3.9,zt-0.4),(xg-R*0.95,3.9,zt+3.4))
    parts+=hypar((xs_b,-3.6,19.2),(xs_b,3.6,25.0),(xg-R*0.95,-3.9,zb+0.4),(xg-R*0.95,3.9,zb-3.4))
    # tie the far ends of the arms to the grip rings
    parts+=[bar((xg-R*0.95,3.9,zt+3.4),(xg,0,zt),1.6),bar((xg-R*0.95,3.9,zb-3.4),(xg,0,zb),1.6)]
    print('shukhov handle members',len(parts),' finger gap x: %.1f mm'%((xg-R-0.9)-(ri(40)+3.6+0.9)))
    return parts
