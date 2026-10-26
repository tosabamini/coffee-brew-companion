import numpy as np, trimesh, shapely, shapely.affinity
from shapely.geometry import Polygon, box, Point, LineString
from shapely.ops import unary_union
import common as cm
from geokit import toM, fromM, fix, finish, handle_relief
import manifold3d as mf
ri,ro,Z0,Z1,T=cm.ri,cm.ro,cm.Z0,cm.Z1,cm.T
H=Z1-Z0; Ravg=cm.Ravg; C=cm.C
SH=1.6           # shell thickness (was 2.6 solid + relief)
def shell(z0=Z0,z1=Z1,t=SH):
    prof=[(ri(z0),z0),(ri(z0)+t,z0),(ri(z1)+t,z1),(ri(z1),z1),(ri(z0),z0)]
    return fix(trimesh.creation.revolve(np.array(prof)[::-1],sections=397))
def deep_shell(depth_fn,n=60):
    zs=np.linspace(Z0,Z1,n)
    prof=[(ri(Z0),Z0)]+[(ri(z)+depth_fn(z),z) for z in zs]+[(ri(Z1),Z1),(ri(Z0),Z0)]
    return fix(trimesh.creation.revolve(np.array(prof)[::-1],sections=397))
def band(z0,z1,t):
    prof=[(ri(z0),z0),(ri(z0)+t,z0),(ri(z1)+t,z1),(ri(z1),z1),(ri(z0),z0)]
    return fix(trimesh.creation.revolve(np.array(prof)[::-1],sections=389))
def holes3d(geom):   # through the shell
    return [cm._solid(p,lambda z:ri(z)-1.0-0.017*hi,lambda z:ri(z)+SH+6.0+0.017*hi,2.0) for p,hi in cm.seam_split(geom) if p.area>0.4]
def fins3d(geom,height_fn,base=1.1):
    g=unary_union(geom).buffer(-0.02,join_style='mitre').buffer(0.02,join_style='mitre')
    return [cm._solid(p,lambda z:ri(z)+base,lambda z:ri(z)+SH+height_fn(z),1.0) for p,hi in cm.seam_split(g) if p.area>0.2]
def thin_handle(dx=0.0):
    P=np.array([(ri(58.0)+0.6,58.0),(52.5+dx,58.0),(59.5+dx,51.0),(59.5+dx,31.0),(52.5+dx,24.0),(ri(24.0)+0.6,24.0)])
    P3=np.c_[P[:,0],np.zeros(len(P)),P[:,1]]
    sec=np.array([(3.1,2.0),(0.0,4.1),(-3.1,2.0),(-3.1,-2.0),(0.0,-4.1),(3.1,-2.0)])
    Y=np.array([0,1.0,0]); rings=[]
    for k in range(len(P3)):
        if k in (0,len(P3)-1): t=(P3[1]-P3[0]) if k==0 else (P3[-1]-P3[-2]); sc=1.0
        else:
            t1=P3[k]-P3[k-1]; t1/=np.linalg.norm(t1); t2=P3[k+1]-P3[k]; t2/=np.linalg.norm(t2)
            t=t1+t2; sc=1/np.cos(np.arccos(np.clip(t1@t2,-1,1))/2)
        t=t/np.linalg.norm(t); n=np.cross(t,Y)
        rings.append(np.array([P3[k]+n*a*sc+Y*b for a,b in sec]))
    V=np.vstack(rings); m=len(sec); F=[]
    for k in range(len(rings)-1):
        for j in range(m):
            a,b,c,d=k*m+j,k*m+(j+1)%m,(k+1)*m+(j+1)%m,(k+1)*m+j; F+=[[a,b,c],[a,c,d]]
    c0=len(V); c1=c0+1; V=np.vstack([V,rings[0].mean(0),rings[-1].mean(0)]); L=(len(rings)-1)*m
    for j in range(m): F+=[[c0,(j+1)%m,j],[c1,L+j,L+(j+1)%m]]
    return fix(trimesh.Trimesh(V,np.array(F),process=False))
# region where the pattern lives; a narrow solid strip stays behind the handle roots
def pattern_region(margin=4.0):
    reg=box(-C/2,Z0+3.2,C/2,Z1-3.2)
    for zc in (58.0,24.0):
        reg=reg.difference(box(-5.5,zc-4.5,5.5,zc+4.5).buffer(1.5))
    return reg
