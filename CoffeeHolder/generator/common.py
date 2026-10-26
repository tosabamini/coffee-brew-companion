import trimesh, numpy as np, shapely, shapely.affinity
from shapely.geometry import Polygon, box, Point, LineString, MultiPolygon
from shapely.ops import unary_union
from trimesh import boolean
from paths import ASSETS
W=str(ASSETS)+'/'
R0,K,CL,T=25.17,0.1065,0.35,2.6
Z0,Z1=14.0,64.0
ri=lambda z:R0+K*z+CL
ro=lambda z:R0+K*z+CL+T
Ravg=(ri((Z0+Z1)/2)+ro((Z0+Z1)/2))/2
C=2*np.pi*Ravg                     # unwrapped circumference; s in [-C/2,C/2), s=0 at handle (+X)
FRONT=-C/4                         # face shown when handle is on the right
BACK=C/2
ARM_Z=(Z0+7,Z1-7)
def handle_keepout(margin=1.5, spine=True):
    k=[box(-5.5,z-4,5.5,z+4).buffer(margin) for z in ARM_Z]
    if spine: k.append(box(-5.5-margin,Z0,5.5+margin,Z1))
    return unary_union(k)
def polys_of(g):
    if g.is_empty: return []
    if g.geom_type=='Polygon': return [g]
    return [p for p in getattr(g,'geoms',[]) if p.geom_type=='Polygon']
def _solid(poly,rin,rout,maxe=1.0):
    poly=shapely.segmentize(poly.buffer(0.01,join_style='mitre'),maxe*0.9)
    v2,f2=trimesh.creation.triangulate_polygon(poly,engine='triangle',triangle_args='pqa%.3f'%(maxe*maxe*0.45))
    n=len(v2)
    e=np.sort(np.vstack([f2[:,[0,1]],f2[:,[1,2]],f2[:,[2,0]]]),axis=1)
    u,c=np.unique(e,axis=0,return_counts=True); bset=set(map(tuple,u[c==1]))
    # oriented boundary edges from triangles
    side=[]
    for t in f2:
        for i,j in ((t[0],t[1]),(t[1],t[2]),(t[2],t[0])):
            if (min(i,j),max(i,j)) in bset: side.append([i,j])
    side=np.array(side)
    F=np.vstack([f2[:,::-1], f2+n, np.c_[side[:,0],side[:,1],side[:,1]+n], np.c_[side[:,0],side[:,1]+n,side[:,0]+n]])
    s_,z=v2[:,0],v2[:,1]; th=s_/Ravg
    def ring(r): return np.c_[r*np.cos(th),r*np.sin(th),z]
    V=np.vstack([ring(rin(z)),ring(rout(z))])
    out=trimesh.Trimesh(V,F,process=False)
    if out.volume<0: out.invert()
    if not out.is_watertight: print('warn: non-watertight piece',poly.area)
    return out
def wrapg(geom):
    g=unary_union(geom)
    parts=[]
    for k in (-2,-1,0,1,2):
        piece=g.intersection(box(k*C-C/2,-1e4,(k+1)*C-C/2,1e4))
        if not piece.is_empty: parts.append(shapely.affinity.translate(piece,-k*C,0))
    return unary_union(parts)
def seam_split(geom):
    g=unary_union(geom)
    # preferred: put the unwrap seam at s=0 (handle) if nothing crosses it
    if g.is_empty: return []
    if not g.intersects(LineString([(0,-1e3),(0,1e3)])) and not g.intersects(LineString([(-C/2,-1e3),(-C/2,1e3)]).buffer(1e-6)) or True:
        if not g.intersects(LineString([(0,-1e3),(0,1e3)]).buffer(0.05)):
            g2=unary_union([shapely.affinity.translate(g.intersection(box(-C/2-1,-1e3,0,1e3)),C,0),g.intersection(box(0,-1e3,C/2+1,1e3))])
            return [(p,0) for p in polys_of(g2)]
    ext=unary_union([g, shapely.affinity.translate(g.intersection(box(-C/2,-1e3,-C/2+2,1e3)),C,0),
                        shapely.affinity.translate(g.intersection(box(C/2-2,-1e3,C/2,1e3)),-C,0)])
    out=[]
    for hi,bx in enumerate((box(-C/2-2,-1e3,0.6,1e3),box(-0.6,-1e3,C/2+2,1e3))):
        out+=[(p,hi) for p in polys_of(ext.intersection(bx))]
    return out
def relief_solids(geom,h=0.9,layer=0,maxe=1.0):
    g=unary_union(geom).buffer(-0.02,join_style='mitre').buffer(0.02,join_style='mitre')   # split point-contacts (pinches)
    if layer>0: g=g.buffer(-0.03*layer)
    g=g.intersection(box(-1e3,Z0+0.06,1e3,Z1-0.06))
    out=[]
    for p,hi in seam_split(g):
        if p.area<=0.2: continue
        e=0.013*hi
        out.append(_solid(p,lambda z,e=e:ro(z)-0.6+0.15*layer+e,lambda z,e=e:ro(z)+h+e,maxe))
    return out
def hole_solids(geom,maxe=2.0):
    out=[]
    for p,hi in seam_split(geom):
        if p.area<=0.5: continue
        e=0.017*hi
        out.append(_solid(p,lambda z,e=e:ri(z)-1.0-e,lambda z,e=e:ro(z)+3.0+e,maxe))
    return out
def build(name,relief=(),holes=None,base_file='holder_in_place.stl',extra=(),cutextra=()):
    base=trimesh.load(W+base_file)
    parts=[base]
    for L,(g,h) in enumerate(relief): parts+=relief_solids(g,h,layer=L)
    parts+=list(extra)
    import manifold3d as mf
    def toM(t): return mf.Manifold(mf.Mesh(vert_properties=np.asarray(t.vertices,np.float32),tri_verts=np.asarray(t.faces,np.uint32)))
    M=mf.Manifold.batch_boolean([toM(t) for t in parts],mf.OpType.Add)
    if holes is not None:
        hp=polys_of(unary_union(holes))
        isl=sum(len(p.interiors) for p in hp)
        from shapely.strtree import STRtree
        tr=STRtree(hp); dmin=99; where=None
        for i,p in enumerate(hp):
            for j in tr.query(p.buffer(3)):
                if j>i:
                    d=p.distance(hp[j])
                    if d<dmin: dmin,where=d,p.centroid.coords[0]
        print(' holes',len(hp),'enclosed-islands',isl,'(must be 0)  min rib between holes %.2fmm at'%dmin,np.round(where,1) if where else '')
        hs=hole_solids(holes)
        hs+=list(cutextra)
        if hs: M=M-mf.Manifold.batch_boolean([toM(t) for t in hs],mf.OpType.Add)
    mesh=M.to_mesh(); V=np.asarray(mesh.vert_properties)[:,:3].astype(np.float32); F=np.asarray(mesh.tri_verts)
    m=trimesh.Trimesh(V.astype(np.float64),F,process=False)
    print(name,'wt',m.is_watertight,'faces',len(m.faces),'vol cm3 %.1f'%(m.volume/1000))
    m.export(W+f'holder_{name}_in_place.stl')
    V2=V.copy(); V2[:,2]-=V2[:,2].min()
    trimesh.Trimesh(V2.astype(np.float64),F,process=False).export(W+f'cup_holder_{name}.stl')
    return m
def flat_preview(name,relief,holes,keep=None):
    import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
    fig,ax=plt.subplots(figsize=(16,4))
    ax.add_patch(plt.Rectangle((-C/2,Z0),C,Z1-Z0,fc='#2b4f8a'))
    for g,c in [(relief,'#7fb0ff'),(holes,'white'),(keep,(1,0,0,0.25))]:
        if g is None: continue
        for p in polys_of(unary_union(g)):
            ax.fill(*p.exterior.xy,color=c)
            for i in p.interiors: ax.fill(*i.xy,color='#2b4f8a')
    ax.set_xlim(-C/2,C/2);ax.set_ylim(Z0-1,Z1+1);ax.set_aspect('equal');ax.axvline(FRONT,color='y',lw=.5)
    plt.tight_layout();plt.savefig(W+f'flat_{name}.png',dpi=90);plt.close()
