from lightkit import *
from handles import plate, xin, preview
from shapely.strtree import STRtree
PIER=8.0; P2=(C-2*PIER)/9
wrap=lambda x:(x+C/2)%C-C/2
def clean(g,r=0.3): return g.buffer(-r).buffer(r,quad_segs=8)
def lancet(cx,zb,w,zs,n=28):
    pts=[(cx-w/2,zb),(cx+w/2,zb),(cx+w/2,zs)]
    for a in np.linspace(0,np.pi/3,n)[1:]: pts.append((cx-w/2+w*np.cos(a),zs+w*np.sin(a)))
    for a in np.linspace(2*np.pi/3,np.pi,n)[1:]: pts.append((cx+w/2+w*np.cos(a),zs+w*np.sin(a)))
    return Polygon(pts)
def bez(P,n=30):
    P=np.array(P,float); t=np.linspace(0,1,n)[:,None]
    return (1-t)**3*P[0]+3*(1-t)**2*t*P[1]+3*(1-t)*t**2*P[2]+t**3*P[3]
def ogee(cx,zb,w,zs,h):
    L=bez([(cx-w/2,zs),(cx-w/2,zs+0.55*h),(cx-0.02*w,zs+0.42*h),(cx,zs+h)])
    R=L[::-1].copy(); R[:,0]=2*cx-R[:,0]
    return Polygon([(cx-w/2,zb),(cx+w/2,zb)]+[tuple(p) for p in R[::-1][:-1]][::-1][::-1]+[tuple(p) for p in L[::-1]]).buffer(0)
def ogee_poly(cx,zb,w,zs,h):
    L=bez([(cx-w/2,zs),(cx-w/2,zs+0.55*h),(cx-0.02*w,zs+0.42*h),(cx,zs+h)])
    R=L[::-1][1:].copy(); R[:,0]=2*cx-R[:,0]
    pts=[(cx+w/2,zb),(cx+w/2,zs)]+[tuple(p) for p in R[::-1]][::-1][::-1]
    right=[(2*cx-x,z) for x,z in L]          # right side from springing to apex
    left=[tuple(p) for p in L[::-1]]          # apex down to left springing
    return Polygon([(cx-w/2,zb),(cx+w/2,zb)]+right+left[1:]).buffer(0)
def tudor(cx,zb,w,zs,h,n=40):
    u=np.linspace(-1,1,2*n+1)
    z=zs+h*(np.sqrt(np.clip(1-u**2,0,1))*0.55+(1-np.abs(u))*0.45)
    pts=[(cx-w/2,zb),(cx+w/2,zb)]+[(cx+w/2*uu,zz) for uu,zz in zip(u[::-1],z[::-1])]
    return Polygon(pts).buffer(0)
def quatrefoil(cx,cz,r):
    rl=r*0.42
    return unary_union([Point(cx+r*0.55*np.cos(a),cz+r*0.55*np.sin(a)).buffer(rl,quad_segs=12) for a in np.radians([90,0,180,270])]+[Point(cx,cz).buffer(r*0.5)])
def trefoil_head(cx,zb,w,zt):
    """light with a cusped (trefoil) head; flat bottom at zb, top at zt"""
    r=w/2
    body=box(cx-r,zb,cx+r,zt-r*1.1)
    lobes=[Point(cx,zt-r*0.62).buffer(r*0.62,quad_segs=10),Point(cx-r*0.42,zt-r*1.05).buffer(r*0.58,quad_segs=10),Point(cx+r*0.42,zt-r*1.05).buffer(r*0.58,quad_segs=10)]
    return unary_union([body]+lobes).intersection(box(cx-r,zb,cx+r,zt))
def mouchette(size,curl=0.55,head=0.34):
    """flame / dagger shape in local coords: head at origin, tail curling toward +x"""
    t=np.linspace(0,1,40)
    cxs=t*size; czs=curl*size*t**2
    wid=head*size*(1-t)**1.2+0.05
    dx=np.gradient(cxs); dz=np.gradient(czs); L=np.hypot(dx,dz); nx,nz=-dz/L,dx/L
    left=np.c_[cxs+nx*wid,czs+nz*wid]; right=np.c_[cxs-nx*wid,czs-nz*wid]
    tail=Polygon(np.vstack([left,right[::-1]])).buffer(0)
    return unary_union([tail,Point(0,0).buffer(head*size,quad_segs=12)])
def place(shape,x,z,ang=0.0,mirror=False):
    s=shapely.affinity.scale(shape,-1 if mirror else 1,1,origin=(0,0))
    s=shapely.affinity.rotate(s,ang,origin=(0,0))
    return shapely.affinity.translate(s,x,z)
def fit_in(shape,region,margin=0.65,min_scale=0.45):
    c=shape.centroid
    for sc in np.linspace(1.0,min_scale,12):
        s=shapely.affinity.scale(shape,sc,sc,origin=c)
        if region.buffer(-margin).contains(s): return s
    return None
def check_voids(VO,label):
    hp=cm.polys_of(VO); tr=STRtree(hp); dmin=9; where=None
    for i,q in enumerate(hp):
        for j in tr.query(q.buffer(2)):
            if j>i:
                d=q.distance(hp[j])
                if d<dmin: dmin,where=d,q.centroid.coords[0]
    print(label,'voids',len(hp),'islands',sum(len(q.interiors) for q in hp),'min bar %.2f at'%dmin,np.round(where,1) if where else '')
def handle_generic(arch_fn,top_fn,extra_holes_fn,name,XO=62.8,ZBh=17.0,ZTOP=61.0,OB=27.5,OT=54.5):
    XR=XO-6.0; XL=ri(33.0)+1.8+0.3
    zz=np.linspace(ZBh,ZTOP+0.6,30)
    base=Polygon([(xin(ZBh),ZBh),(XO,ZBh),(XO,ZTOP),(xin(ZTOP+0.6),ZTOP+0.6)]+[(xin(z),z) for z in zz[::-1][1:-1]])
    outline=unary_union([base,top_fn(XL,XR,XO,ZTOP)]).buffer(-0.45).buffer(0.45,quad_segs=6)
    zq=np.linspace(0,90,40)
    outside=Polygon([(xin(z),z) for z in zq]+[(200,90),(200,0)])
    outline=outline.intersection(outside)                       # never reach into the cup
    opening=unary_union([arch_fn(XL,XR,OB,OT),box(xin(OB)-4,OB,XL+0.01,OT-8)])
    body=outline.difference(opening)
    holes=unary_union(extra_holes_fn(body,XL,XR,XO,ZBh,ZTOP,OB,OT)).intersection(body.buffer(-1.2))
    preview(name,body.difference(holes),holes,opening)
    print(name,'handle opening: width %.1f height %.1f'%(XR-(ri(40)+1.5),OT-OB))
    return plate(body,outline,opening,holes,half=2.7,step=0.6)
def build_wall(VO,FR,name,handle_parts,dep=1.5,fin=1.1):
    strip=box(-7.6,Z0,7.6,Z1)
    VO=VO.difference(strip.buffer(0.8)); FR=FR.difference(strip)
    check_voids(VO,name)
    cm.flat_preview(name,FR,VO,None)
    parts=[deep_shell(lambda z:dep+0*z)]+fins3d(FR,lambda z:fin+0*z)+handle_parts
    finish(name,parts,holes3d(VO))
def trefoil(cx,cz,r):
    rl=r*0.46
    return unary_union([Point(cx+r*0.5*np.cos(a),cz+r*0.5*np.sin(a)).buffer(rl,quad_segs=12) for a in np.radians([90,210,330])]+[Point(cx,cz).buffer(r*0.45)])
def radiating_rose(cx,cz,R,n=6,petal_w=None,bar=1.2):
    """circle with a centre eye and n radiating lancet petals; returns voids that keep bars >= bar"""
    import itertools
    best=None
    for c0,r0,pw in itertools.product([0.6,0.8,1.0,1.3],[R*0.26,R*0.32,R*0.38,R*0.46],[1.1,1.4,1.8,2.2,2.6]):
        eye=Point(cx,cz).buffer(c0,quad_segs=12)
        L=R-bar-r0
        if L<1.5: continue
        st=max(L-pw*0.866,0.2)
        pet=lancet(0,0,pw,st)
        ps=[]
        for i in range(n):
            a=360.0*i/n+90
            p=shapely.affinity.translate(pet,0,r0); p=shapely.affinity.rotate(p,a-90,origin=(0,0))
            ps.append(shapely.affinity.translate(p,cx,cz))
        disk=Point(cx,cz).buffer(R-bar+0.01,quad_segs=48)
        if not all(disk.contains(p) for p in ps): continue
        if min(ps[i].distance(ps[(i+1)%n]) for i in range(n))<bar: continue
        if min(p.distance(eye) for p in ps)<bar: continue
        area=sum(p.area for p in ps)+eye.area
        if best is None or area>best[0]: best=(area,[eye]+ps)
    return best[1] if best else [Point(cx,cz).buffer(max(R-bar,0.5))]
