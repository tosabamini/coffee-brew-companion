import numpy as np, manifold3d as mf
from hkit import *
from handles100 import A, D_path, ring, ring_pts, arms, rotpts, ZT, ZB
CH={}
def reg(name,jp):
    def d(f): CH[name]=(f,jp); return f
    return d
def bean3d(c,a=7.5,b=5.2,t=4.2,rot=0.0,axis='y'):
    e=ellipsoid((0,0,0),b,t,a,40)                       # long axis vertical (z), flat in y
    groove=capsule((0,-t-1,-a*0.85),(0,-t-1,a*0.85),1.0) if False else None
    s=np.linspace(-0.9,0.9,14); pts=[(0.9*np.sin(u*2.8),-t*0.9,u*a) for u in s]
    g=tube(pts,0.9,n=10)
    pts2=[(p[0],-p[1],p[2]) for p in pts]; g2=tube(pts2,0.9,n=10)
    m=e-g-g2
    return m.rotate((0,rot,0)).translate(tuple(map(float,c)))
@reg('bean_grip','コーヒー豆の握り')
def _(): return U([capsule(A(56),(48,0,52),3.0),capsule(A(26),(48,0,30),3.0),bean3d((54,0,41),15,7.4,5.2)])
@reg('demitasse','デミタスカップの小さな耳')
def _():
    P=xz(catmull([(X0(58),58),(40,61),(47,57),(47,50),(41,46),(X0(47),47)]))
    return U([tube(P,np.linspace(3.4,2.2,len(P))),sphere((39.5,0,61.3),2.3)])
@reg('moka_handle','モカポットの角ばった取っ手')
def _():
    sec=np.array([(-3.2,-4.5),(3.2,-4.5),(3.6,0),(3.2,4.5),(-3.2,4.5),(-3.6,0)])
    P=xz([(X0(58),58),(45,59),(57,55),(59,44),(57,30),(50,22),(X0(24),24)])
    P=catmull(P,n=6)
    return U([sweep(P,sec[:,::-1]),capsule(A(58),(46,0,59.5),2.6)])
@reg('steam_swirl','湯気のうず巻き')
def _():
    t=np.linspace(0,1,120); x=X0(56)+t*24+3*np.sin(t*np.pi*3); z=56-t*30+4*np.sin(t*np.pi*2)
    P=np.c_[x,0*t,z]
    tt=np.linspace(0,2.4*np.pi,80); r=6.5*np.exp(-0.2*tt); c=P[-1]+[-1.0,0,4.0]
    S=np.c_[c[0]+r*np.cos(-tt+np.pi*0.0),0*tt,c[2]+r*np.sin(-tt)-0]
    return U([tube(P,3.0),tube(S,np.linspace(3.0,2.0,len(S))),capsule(A(24),(42,0,24),2.6),capsule((42,0,24),P[-1],2.6)])
@reg('portafilter','ポルタフィルターの柄')
def _():
    t=np.linspace(0,1,40); x=X0(42)+t*40; z=42-6*t**2; r=4.0+2.2*np.sin(np.pi*t)**0.8; r[-1]=3.0
    P=np.c_[x,0*t,z]
    return U([tube(P,r),sphere(P[-1],4.6),mf.Manifold.cylinder(2.0,6.4,6.4,40,True).rotate((0,90,0)).translate((X0(42)+6,0,42))])
@reg('gooseneck','ドリップポットの細口（グースネック）')
def _():
    P=xz(catmull([(X0(58),58),(40,62),(52,60),(58,52),(52,40),(58,28),(64,24),(66,28)]))
    return U([tube(P,np.linspace(3.2,2.0,len(P))),capsule(A(26),(56,0,30),2.6)])
@reg('cherry_cluster','コーヒーチェリーの房')
def _():
    stem=xz(catmull([(X0(58),58),(44,60),(54,52),(56,38),(50,26),(X0(26),26)]))
    out=[tube(stem,2.4)]
    P=resample(stem,1.0)
    for k,i in enumerate(range(14,len(P)-12,7)):
        p=P[i]; out.append(sphere(p+[3.2,(k%2*2-1)*3.0,0],3.2,28))
    return U(out)
@reg('bean_chain','豆をつないだループ')
def _():
    P=resample(D_path(60),1.0); idx=np.linspace(6,len(P)-7,7).astype(int)
    out=[tube(P,1.8)]
    for i in idx:
        T=P[min(i+1,len(P)-1)]-P[max(i-1,0)]; ang=np.degrees(np.arctan2(T[0],T[2]))
        out.append(bean3d(P[i],4.6,3.4,2.8,rot=ang))
    return U(out)
@reg('latte_heart_loop','ハート形のループ')
def _():
    t=np.linspace(0,2*np.pi,160,endpoint=False); x=16*np.sin(t)**3; y=13*np.cos(t)-5*np.cos(2*t)-2*np.cos(3*t)-np.cos(4*t)
    P=np.c_[49+y*0.95,0*t,41+x*1.0]   # heart lying with point outward (+x)
    P=np.vstack([P,P[:1]])
    return U([tube(P,2.6),capsule(A(48),(36,0,48),3.0),capsule(A(34),(36,0,34),3.0)])
@reg('grinder_crank','手挽きミルのクランク')
def _():
    return U([capsule(A(44),(46,0,44),3.6),capsule((46,0,44),(46,0,62),3.0),capsule((46,0,62),(56,0,62),2.6),
              mf.Manifold.cylinder(14,4.6,4.0,40,True).translate((58,0,55)),sphere((58,0,62),4.2)])
