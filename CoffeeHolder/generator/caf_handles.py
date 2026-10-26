import numpy as np, manifold3d as mf
from hkit import *
from handles100 import A, D_path
from cafkit import caf2d
CH2={}
def reg(name,jp):
    def d(f): CH2[name]=(f,jp); return f
    return d
RAD={'H':1.4,'C':1.9,'N':2.3,'O':2.7}
def mol3d(L,cx,cz,rot=0,hydrogens=False,rb=1.25,rd=0.85,scale_atoms=1.0):
    P,E,B=caf2d(L,(0,0),rot=rot,hydrogens=hydrogens)
    Q={k:V(cx+p[0],0,cz+p[1]) for k,p in P.items()}
    out=[]
    for a,b,o in B:
        pa,pb=Q[a],Q[b]
        if o==2:
            d=pb-pa; n=np.cross(d,[0,1,0]); n/=np.linalg.norm(n)
            out+=[capsule(pa+n*1.05,pb+n*1.05,rd),capsule(pa-n*1.05,pb-n*1.05,rd)]
        else: out.append(capsule(pa,pb,rb))
    out+=[sphere(Q[k],RAD[E[k]]*scale_atoms,24) for k in Q]
    return U(out),Q,E
@reg('caf_ballstick_handle','カフェインの球棒模型の持ち手')
def _():
    m,Q,E=mol3d(6.2,51,41,rot=0)
    a1=min(Q,key=lambda k:Q[k][0]+abs(Q[k][2]-52)*0.3); a2=min(Q,key=lambda k:Q[k][0]+abs(Q[k][2]-30)*0.3)
    return U([m,capsule(A(Q[a1][2]),Q[a1],2.4),capsule(A(Q[a2][2]),Q[a2],2.4)])
@reg('caf_ring_fingers','六員環と五員環の指リング')
def _():
    P,E,B=caf2d(10.5,(0,0),rot=90)
    Q={k:V(48+p[0]*0.0+p[1]*0.0+p[0],0,41+p[1]) for k,p in P.items()}
    ring=[('N1','C2'),('C2','N3'),('N3','C4'),('C4','C5'),('C5','C6'),('C6','N1'),('C5','N7'),('N7','C8'),('C8','N9'),('N9','C4')]
    out=[capsule(Q[a],Q[b],2.6) for a,b in ring]+[sphere(Q[k],3.1 if E[k]=='N' else 2.7,24) for k in ('N1','C2','N3','C4','C5','C6','N7','C8','N9')]
    for k in ('O6','O2','Me1','Me3','Me7'):
        par={'O6':'C6','O2':'C2','Me1':'N1','Me3':'N3','Me7':'N7'}[k]; q=Q[par]+(Q[k]-Q[par])*0.55
        out+=[capsule(Q[par],q,2.0),sphere(q,3.2 if k[0]=='O' else 2.5,24)]
    near=sorted(Q,key=lambda k:Q[k][0])[:2]
    m=U(out); dx=min(q[0] for q in Q.values())
    shift=X0(41)+4.5-dx
    m=m.translate((shift,0,0)); Qs={k:q+[shift,0,0] for k,q in Q.items()}
    att=[k for k in Qs if Qs[k][0]<Qs[min(Qs,key=lambda k:Qs[k][0])][0]+6]
    return U([m]+[capsule(A(Qs[k][2]),Qs[k],2.6) for k in att])
@reg('caf_spacefill_grip','空間充填モデルの握り')
def _():
    P,E,B=caf2d(4.6,(0,0),rot=90,hydrogens=True)
    vdw={'H':1.2,'C':1.7,'N':1.55,'O':1.52}
    out=[sphere((54+p[0]*0.55,p[0]*0.0+0.0,41+p[1]),vdw[E[k]]*1.75,24) for k,p in P.items()]
    out+=[sphere((54+p[0]*0.55,0,41+p[1]),vdw[E[k]]*1.2,16).translate((0,(1 if i%2 else -1)*1.6,0)) for i,(k,p) in enumerate(P.items())]
    zs=[41+p[1] for p in P.values()]
    return U(out+[capsule(A(max(zs)-3),(50,0,max(zs)-3),3.0),capsule(A(min(zs)+3),(50,0,min(zs)+3),3.0)])
@reg('caf_carbonyl_loop','C=O 二重結合のループ')
def _():
    P=resample(D_path(58),1.0); T,N,B=rmf(P)
    up=P+1.35*B; dn=P-1.35*B
    o=P[len(P)//2]+V(5.6,0,0)
    return U([tube(up,1.25),tube(dn,1.25),capsule(P[len(P)//2],o,1.2),sphere(o,4.2,32),
              sphere(P[len(P)//2],2.6,24)])
@reg('caf_methyl_knob','メチル基（CH₃）のつまみ')
def _():
    n_at=V(X0(44)+2.2,0,44); c=n_at+V(13,0,0)
    d=(c-n_at)/np.linalg.norm(c-n_at); out=[capsule(A(44),n_at,3.2),sphere(n_at,3.6,32),capsule(n_at,c,2.4),sphere(c,5.0,40)]
    ang=np.radians(180-109.47)
    for k in range(3):
        phi=2*np.pi*k/3+np.pi/2
        v=d*np.cos(ang)+np.sin(ang)*(np.cos(phi)*V(0,1,0)+np.sin(phi)*V(0,0,1))
        h=c+v*9.0; out+=[capsule(c,h,1.9),sphere(h,3.6,32)]
    return U(out)
