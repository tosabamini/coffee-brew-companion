import numpy as np, trimesh, shapely, shapely.affinity, json, time, traceback
from shapely.geometry import Polygon, box, Point, LineString, MultiLineString
from shapely.ops import unary_union
import common as cm
from lightkit import deep_shell, holes3d, fins3d
from geokit import toM, fromM, fix
from handles import plate, xin
import manifold3d as mf
from gothkit import lancet, ogee_poly, tudor, quatrefoil, trefoil
ri,ro,Z0,Z1=cm.ri,cm.ro,cm.Z0,cm.Z1
C=cm.C
from paths import BUILD
OUT=str(BUILD/'c100')+'/'
S0=8.0; WD=C-16.0
ZA,ZB=18.4,60.5; HD=ZB-ZA
BAR=1.2
def polys(g): return cm.polys_of(g)
def U(gs):
    gs=[g for g in gs if g is not None and not g.is_empty]
    return unary_union(gs) if gs else Polygon()
def repair(V,D,anchor,bar=BAR,min_hole=1.0,bridge=True):
    S0_=D.difference(V)
    """enforce bars>=bar and no floating islands. D: full solid domain, anchor: geometry that must stay connected."""
    S=D.difference(V)
    S=S.buffer(-bar/2,join_style='round').buffer(bar/2,quad_segs=6).intersection(D)
    S=S.union(S0_.intersection(anchor.buffer(0.8)))
    keep=[p for p in polys(S) if p.intersects(anchor)]
    isl=[p for p in polys(S) if not p.intersects(anchor) and p.area>2.0]
    if bridge and isl:
        from shapely.ops import nearest_points
        main=U(keep); added=[]
        isl.sort(key=lambda p:p.distance(main))
        for p in isl:
            a,b=nearest_points(p,main)
            br=LineString([a,b]).buffer(bar*0.8,cap_style='round').intersection(D)
            main=U([main,p,br]); added.append(br); keep.append(p)
        keep+=added
    S=U(keep)
    V2=D.difference(S)
    holes=[p for p in polys(V2) if p.area>=min_hole]
    holes=[Polygon(p.exterior) for p in holes]            # interiors would be floating islands -> drop them
    V2=U(holes)
    return V2, D.difference(V2)
def add_ribs(V,D,anchor,pitch=18.0,w=1.8):
    ribs=[box(x-w/2,D.bounds[1],x+w/2,D.bounds[3]) for x in np.arange(D.bounds[0]+pitch/2,D.bounds[2],pitch)]
    ribs.append(box(D.bounds[0],(D.bounds[1]+D.bounds[3])/2-w/2,D.bounds[2],(D.bounds[1]+D.bounds[3])/2+w/2))
    return V.difference(U(ribs))
# ---------------- wall ----------------
def wall(gen,rng,sc=1.0,vfix=0):
    """returns VO (wrapped voids on the unwrapped cup), FR (fins), stats"""
    out=gen(WD,HD,rng,sc)
    if isinstance(out,tuple): voids,fins=out
    else: voids,fins=out,[]
    R=box(0,0,WD,HD)
    V=U([v.buffer(0) for v in voids]).intersection(R.buffer(-1.3,join_style='mitre'))
    D=box(0,ZA-Z0-HD*0-ZA,WD,HD)  # placeholder (replaced below)
    D=box(0,-(ZA-Z0),WD,HD+(Z1-ZB))
    anchor=U([box(0,-(ZA-Z0),WD,0.0),box(0,HD,WD,HD+(Z1-ZB)),box(0,-(ZA-Z0),0.5,HD+(Z1-ZB)),box(WD-0.5,-(ZA-Z0),WD,HD+(Z1-ZB))])
    V,S=repair(V,D,anchor)
    openf=V.area/R.area
    if any((p.bounds[2]-p.bounds[0])>0.45*WD for p in polys(V)):   # hole runs around the cup -> wall would only hang at the handle
        ribs=[box(x-0.9,-10,x+0.9,HD+10) for x in np.arange(WD/10,WD,WD/5)]
        V,S=repair(V.difference(U(ribs)),D,anchor); openf=V.area/R.area
    if openf>0.72:
        V,S=repair(add_ribs(V,D,anchor),D,anchor); openf=V.area/R.area
    if vfix: V=V.buffer(-0.04*vfix,join_style='mitre').buffer(0.04*vfix,join_style='mitre').simplify(0.02*vfix)
    if not fins: fins=[V.buffer(1.0,quad_segs=2).difference(V)]   # raised rim around every opening
    F=U([f.buffer(0) for f in fins]).intersection(S.buffer(-0.15))
    F=U([p for p in polys(F) if p.area>0.3])
    F=F.simplify(0.06).buffer(0)
    tr=lambda g: shapely.affinity.translate(g,S0,ZA)
    return cm.wrapg(tr(V)),cm.wrapg(tr(F)),openf
# ---------------- handle ----------------
XO=62.8; XR=XO-6.0; ZBh=17.0; ZTOP=61.0; OB=27.5; OT=54.5
def XL(): return ri(33.0)+2.1
def arch_shape(kind):
    xl,xr=XL(),XR; w=xr-xl; cx=(xl+xr)/2; h=OT-OB
    if kind=='lancet': return lancet(cx,OB,w,OT-w*0.866)
    if kind=='round': return U([box(xl,OB,xr,OT-w/2),Point(cx,OT-w/2).buffer(w/2,quad_segs=24)])
    if kind=='rect': return box(xl,OB,xr,OT).buffer(-3.0).buffer(3.0,quad_segs=8)
    if kind=='horseshoe':
        r=w/2; zc=OT-r
        return U([box(xl+2.0,OB,xr-2.0,zc),Point(cx,zc).buffer(r,quad_segs=24).intersection(box(0,zc-r*0.45,200,200))])
    if kind=='ogee': return ogee_poly(cx,OB,w,OT-11,11)
    if kind=='tudor': return tudor(cx,OB,w,OT-0.3*w,0.3*w)
    if kind=='multifoil':
        a=arch_shape('round'); r=w/2; zc=OT-r
        cusps=[Point(cx+(r+0.4)*np.cos(t),zc+(r+0.4)*np.sin(t)).buffer(1.6) for t in np.radians([30,60,90,120,150])]
        return a.difference(U(cusps))
    if kind=='porthole':
        r=min(w,h)/2; return Point(cx,(OB+OT)/2).buffer(r,quad_segs=32)
    if kind=='stepped':
        return U([box(xl,OB,xr,OT-8),box(xl+3,OB,xr-3,OT-4),box(xl+6,OB,xr-6,OT)])
    if kind=='pointed':
        return Polygon([(xl,OB),(xr,OB),(xr,OT-9),(cx,OT),(xl,OT-9)])
    return box(xl,OB,xr,OT)
def top_shape(kind):
    xl,xr=XL(),XR; cx=(xl+xr)/2; T=ZTOP
    if kind=='none': return Polygon()
    if kind=='gable': return Polygon([(cx-10,T-0.5),(cx+10,T-0.5),(cx,T+9)])
    if kind=='battlement': return U([box(x,T-0.5,x+2.8,T+3.0) for x in np.arange(xl+0.5,XO-2.0,4.8)])
    if kind=='dome': return Point(cx,T-0.5).buffer(8.5,quad_segs=24).intersection(box(0,T-0.5,200,200))
    if kind=='onion': return U([ogee_poly(cx,T-1.0,15.0,T+1.0,9.0),box(cx-0.6,T+8,cx+0.6,T+11)])
    if kind=='ziggurat': return U([box(cx-11,T-0.5,cx+11,T+2.5),box(cx-7,T+2,cx+7,T+5),box(cx-3.5,T+4.5,cx+3.5,T+7.5)])
    if kind=='sunburst':
        return U([Polygon([(cx,T-0.5),(cx+12*np.cos(a)-1.0*np.sin(a),T+12*np.sin(a)*0.75),(cx+12*np.cos(a)+1.0*np.sin(a),T+12*np.sin(a)*0.75)]).buffer(0.7) for a in np.radians(np.linspace(20,160,7))])
    if kind=='pinnacle': return Polygon([(XO-5,T-0.2),(XO,T-0.2),(XO-2.5,T+8)])
    if kind=='wave':
        xs=np.linspace(xl,XO,60); return Polygon([(xl,T-0.5)]+[(x,T+1.6+1.6*np.sin((x-xl)/3.0)) for x in xs]+[(XO,T-0.5)])
    if kind=='crest':
        return U([Point(x,T+1.2).buffer(2.0,quad_segs=10) for x in np.arange(xl+2.0,XO-1.0,4.5)])
    return Polygon()
def handle(arch_kind,top_kind,gen,rng,sc=0.55,name='h'):
    zz=np.linspace(ZBh,ZTOP+0.6,30)
    base=Polygon([(xin(ZBh),ZBh),(XO,ZBh),(XO,ZTOP),(xin(ZTOP+0.6),ZTOP+0.6)]+[(xin(z),z) for z in zz[::-1][1:-1]])
    outline=U([base,top_shape(top_kind)]).buffer(-0.45).buffer(0.45,quad_segs=6)
    zq=np.linspace(0,90,40); outside=Polygon([(xin(z),z) for z in zq]+[(200,90),(200,0)])
    outline=outline.intersection(outside)
    opening=U([arch_shape(arch_kind),box(xin(OB)-4,OB,XL()+0.01,max(OB+1,OT-12))])
    body=outline.difference(opening)
    body=max(polys(body),key=lambda p:p.area)
    web=body.buffer(-1.5,join_style='mitre').difference(box(0,0,ri(40)+4.6,200))
    holes=Polygon()
    if gen is not None and not web.is_empty:
        b=web.bounds; Wd,Hd=b[2]-b[0],b[3]-b[1]
        try:
            out=gen(Wd,Hd,rng,sc)
            vs=out[0] if isinstance(out,tuple) else out
            hv=shapely.affinity.translate(U([v.buffer(0) for v in vs]),b[0],b[1]).intersection(web)
            anchor=body.intersection(box(0,0,ri(40)+4.0,200)).buffer(0.01)
            V,S=repair(hv,body,anchor)
            if V.area/web.area<0.62: holes=V
        except Exception as e:
            holes=Polygon()
    return plate(body,outline,opening,holes,half=2.7,step=0.6)
# ---------------- assemble ----------------
def build(idx,name,gen,arch_kind,top_kind,fins_h=1.1,seed=0,hsc=0.55,hgen=True,vfix=0):
    rng=np.random.default_rng(1000+idx)
    t0=time.time()
    VO,FR,openf=wall(gen,rng,vfix=vfix)
    HP=handle(arch_kind,top_kind,gen if hgen else None,np.random.default_rng(2000+idx),hsc)
    parts=[deep_shell(lambda z:1.5+0*z)]
    if fins_h>0 and not FR.is_empty: parts+=fins3d(FR,lambda z:fins_h+0*z)
    parts+=HP
    cuts=holes3d(VO)
    M=mf.Manifold.batch_boolean([toM(p) for p in parts],mf.OpType.Add)
    if cuts: M=M-mf.Manifold.batch_boolean([toM(p) for p in cuts],mf.OpType.Add)
    m=fromM(M)
    if m.body_count>1:
        ps=m.split(only_watertight=False); m=max(ps,key=lambda p:abs(p.volume))
    tag=f'{idx:03d}_{name}'
    m.export(OUT+f'stl/{tag}_inplace.stl')
    V=np.asarray(m.vertices).copy(); V[:,2]-=V[:,2].min()
    trimesh.Trimesh(V,m.faces,process=False).export(OUT+f'stl/{tag}.stl')
    # verify
    from collections import Counter
    from trimesh import boolean
    a=trimesh.load(OUT+f'stl/{tag}_inplace.stl')
    e=Counter(map(tuple,a.edges_sorted)); bad=sum(1 for v in e.values() if v!=2)
    cup=trimesh.load(cm.W+'cup.stl')
    ov=boolean.intersection([a,cup],engine='manifold').volume if a.is_volume else float('nan')
    info=dict(idx=idx,name=name,valid=bool(a.is_volume),bad=int(bad),bodies=int(a.body_count),vol=round(a.volume/1000,2),
              overlap=round(float(ov),3),open=round(openf,2),faces=len(a.faces),secs=round(time.time()-t0,1),arch=arch_kind,top=top_kind)
    return info
