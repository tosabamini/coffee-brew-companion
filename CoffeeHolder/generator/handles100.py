import numpy as np, manifold3d as mf
from hkit import *
ZT,ZB,ZM=56.0,24.0,40.0
def A(z,y=0.0): return V(X0(z),y,z)
def D_path(xo=60,zt=ZT,zb=ZB,bulge=1.0,y=0.0):
    return xz(catmull([(X0(zt),zt),(X0(zt)+14,zt+1.5),(xo-2,zt-4),(xo,(zt+zb)/2),(xo-2,zb+4),(X0(zb)+14,zb-1.5),(X0(zb),zb)]),y)
def ring_pts(c,R,n=64,plane='xz',a0=0):
    a=np.radians(a0)+np.linspace(0,2*np.pi,n,endpoint=False)
    if plane=='xz': return np.c_[c[0]+R*np.cos(a),np.full(n,c[1]),c[2]+R*np.sin(a)]
    if plane=='xy': return np.c_[c[0]+R*np.cos(a),c[1]+R*np.sin(a),np.full(n,c[2])]
    return np.c_[np.full(n,c[0]),c[1]+R*np.cos(a),c[2]+R*np.sin(a)]
def ring(c,R,r,plane='xz',n=64): P=ring_pts(c,R,n,plane); return tube(np.vstack([P,P[:1]]),r)
def rotpts(P,deg,axis,origin):
    P=np.asarray(P,float)-origin; t=np.radians(deg); c,s=np.cos(t),np.sin(t)
    if axis=='y': R=np.array([[c,0,s],[0,1,0],[-s,0,c]])
    elif axis=='z': R=np.array([[c,-s,0],[s,c,0],[0,0,1]])
    else: R=np.array([[1,0,0],[0,c,-s],[0,s,c]])
    return P@R.T+origin
H={}
def reg(name,jp,group):
    def d(f): H[name]=(f,jp,group); return f
    return d
G1,G2,G3,G4,G5,G6,G7,G8='ループ','バー・レバー','トラス・骨組み','握りの造形','断面のスイープ','複数の線','数学曲線','人間工学・特殊'
# ================= loops =================
@reg('d_loop','D字ループ（基本形）',G1)
def _(): return tube(D_path(),3.2,step=1.2)
@reg('finger_ring','指1本のリング',G1)
def _(): return U([ring((48,0,44),11,2.8),capsule(A(44),(36.5,0,44),4.2)])
@reg('tall_oval','縦長の楕円ループ',G1)
def _():
    P=xz(catmull([(X0(62),62),(44,64),(53,56),(55,40),(53,24),(44,17),(X0(18),18)]))
    return tube(P,3.0,step=1.2)
@reg('teardrop','しずく形ループ（下がふくらむ）',G1)
def _():
    P=xz(catmull([(X0(58),58),(40,58),(50,50),(60,34),(56,22),(46,20),(X0(26),28)]))
    return tube(P,3.2,step=1.2)
@reg('round_square','角の丸い四角ループ',G1)
def _():
    P=xz(catmull([(X0(56),56),(50,56.5),(56,55),(58,50),(58,30),(56,25),(50,23.5),(X0(24),24)],n=16))
    return tube(P,3.0,step=1.0)
@reg('triangle_loop','三角形ループ（頂点が外）',G1)
def _():
    P=xz(catmull([(X0(58),58),(44,52),(58,41),(60,40),(58,39),(44,28),(X0(22),22)],n=14))
    return tube(P,3.2,step=1.0)
@reg('trapezoid','台形ループ（下が広い）',G1)
def _():
    P=xz(catmull([(X0(56),56),(46,55),(52,52),(60,26),(57,21.5),(44,21),(X0(22),22)],n=14))
    return tube(P,3.0,step=1.0)
@reg('ear','耳形（上が太く下へ細る）',G1)
def _():
    P=xz(catmull([(X0(58),58),(44,62),(56,56),(58,42),(50,30),(40,26),(X0(30),30)]))
    return tube(P,np.linspace(4.6,2.2,len(P)),step=None)
@reg('open_hook','開いたフック（下が離れたC形）',G1)
def _():
    P=xz(catmull([(X0(58),58),(44,62),(57,54),(59,40),(53,28),(43,25),(37,28)]))
    return tube(P,np.linspace(4.4,3.0,len(P)))
@reg('two_rings','指2本の縦2連リング',G1)
def _(): return U([ring((47,0,51),9.0,2.6),ring((47,0,31),9.0,2.6),capsule(A(51),(38,0,51),3.8),capsule(A(31),(38,0,31),3.8)])
@reg('three_rings','指3本の3連リング',G1)
def _():
    out=[]
    for z in (55,40,25): out+= [ring((46,0,z),7.2,2.3),capsule(A(z),(38.8,0,z),3.2)]
    out.append(tube([(53.6,0,55),(54.5,0,40),(53.6,0,25)],2.6))
    return U(out)
@reg('figure8','8の字ループ',G1)
def _():
    t=np.linspace(0,2*np.pi,160); x=48+9*np.sin(2*t)/1.0*0.9; z=40+17*np.sin(t)
    P=np.c_[x,np.zeros_like(t),z]
    return U([tube(np.vstack([P,P[:1]]),2.6),capsule(A(40),(46,0,40),3.6)])
@reg('pretzel','プレッツェル形',G1)
def _():
    t=np.linspace(0,2*np.pi,200); r=13*(1+0.0*t)
    x=45+11*np.cos(t)+5*np.cos(2*t); z=40+15*np.sin(t)*np.cos(0.5*0)+0*t
    y=2.6*np.sin(3*t)
    P=np.c_[x,y,z]
    return U([tube(np.vstack([P,P[:1]]),2.2),capsule(A(52),(40,0,53),3.4),capsule(A(28),(40,0,27),3.4)])
@reg('coil_wrap','芯に巻き付くコイルのループ',G1)
def _():
    P=resample(D_path(),0.6); T,N,B=rmf(P); s=np.linspace(0,1,len(P))
    th=s*2*np.pi*14; C=P+3.6*(np.cos(th)[:,None]*N+np.sin(th)[:,None]*B)
    return U([tube(P,2.0,step=1.2),tube(C[::2],1.25)])
@reg('ribbon_twist','180°ねじれた帯のループ',G1)
def _(): return sweep(D_path(),sec_rect(11,2.6,0.8),twist=180)
@reg('ribbon_twist360','360°ねじれた帯のループ',G1)
def _(): return sweep(D_path(62),sec_rect(10,2.6,0.8),twist=360)
@reg('crossed_loops','交差する2本のループ',G1)
def _():
    P=D_path(58); o=V(X0(40),0,40)
    return U([tube(rotpts(P,22,'x',o),2.5,step=1.2),tube(rotpts(P,-22,'x',o),2.5,step=1.2)])
@reg('thumb_pad','親指パッド付きループ',G1)
def _(): return U([tube(D_path(),3.0,step=1.2),ellipsoid((45,0,58.5),10,8,2.4)])
@reg('scalloped','内側に指の溝があるループ',G1)
def _():
    m=tube(D_path(61),4.6,step=1.2)
    return m-U([sphere((55.5,0,z),3.3,24) for z in (48,40,32)])
@reg('tapered','下ほど太いループ',G1)
def _(): P=resample(D_path(),1.0); return tube(P,np.linspace(2.2,5.2,len(P)))
@reg('tilted_up','上向きに傾いたループ',G1)
def _():
    P=resample(D_path(),1.0); w=np.sin(np.linspace(0,np.pi,len(P)))**0.5
    R=rotpts(P,-24,'y',V(X0(40),0,40)); Q=P*(1-w[:,None])+R*w[:,None]
    return tube(Q,3.0)
@reg('swept_side','横へ流れるループ',G1)
def _():
    P=D_path(); P[:,1]=0.45*np.clip(P[:,0]-X0(40),0,None)**1.2/2.5
    return tube(P,3.0,step=1.2)
@reg('flat_ring','水平に寝かせたリング',G1)
def _(): return U([ring((47,0,46),10.5,3.0,'xy'),capsule(A(46),(37,0,46),4.4),capsule(A(30),(40,0,36),3.0),capsule((40,0,36),(42,0,45),3.0)])
# ================= bars & levers =================
@reg('t_bar','T字バー（つまむ）',G2)
def _(): return U([capsule(A(44),(50,0,44),4.6),capsule((52,-17,44),(52,17,44),4.4)])
@reg('pan_stick','フライパン型の棒',G2)
def _(): P=np.c_[np.linspace(X0(44),72,30),np.zeros(30),np.full(30,44)]; return tube(P,np.linspace(6,4.4,30))
@reg('pan_angled','上向き30°の棒',G2)
def _():
    t=np.linspace(0,1,30); x=X0(40)+t*36; z=40+t*36*np.tan(np.radians(30))
    return tube(np.c_[x,0*t,z],np.linspace(6,4.2,30))
@reg('knob','玉つまみ',G2)
def _(): return U([capsule(A(44),(46,0,44),3.6),sphere((51,0,44),8.5,40)])
@reg('thumb_tab','親指穴のあるタブ',G2)
def _():
    lens=[(X0(56)-0.5,56),(46,58),(58,50),(60,40),(58,30),(46,22),(X0(24)-0.5,24)]
    P=catmull(lens,n=12); return plate_xz([np.vstack([[X0(24)-1,24]],),P],1)[0] if False else plate_xz([P,circle2((48,40),8.5)],4.2)
@reg('pistol_grip','ピストルグリップ',G2)
def _(): return U([capsule(A(57),(50,0,57),3.4),capsule(A(27),(50,0,27),3.4),capsule((51,0,59),(55,0,22),5.0)])
@reg('drop_bar','ドロップハンドル',G2)
def _():
    t=np.linspace(-1,1,40); y=16*t; x=50+4*np.abs(t)**2; z=44-10*np.abs(t)**3
    return U([capsule(A(44),(50,0,44),4.4),tube(np.c_[x,y,z],3.6)])
@reg('pull_vertical','縦の引き手（取っ手金具）',G2)
def _(): return U([capsule(A(56),(46,0,56),3.0),capsule(A(26),(46,0,26),3.0),sweep(np.c_[np.full(30,47),np.zeros(30),np.linspace(20,62,30)],sec_rect(6,8,1.2))])
@reg('pull_horizontal','横の引き手',G2)
def _(): return U([capsule(A(44,-5),(45,-5,44),2.8),capsule(A(44,5),(45,5,44),2.8),sweep(np.c_[np.full(30,46.5),np.linspace(-19,19,30),np.full(30,44)],sec_rect(5,9,1.2))])
@reg('stirrup','あぶみ形（平らな底）',G2)
def _():
    P=xz(catmull([(X0(58),58),(44,58),(52,50),(56,30),(58,22)],n=16))
    P2=P.copy(); P2[:,2]=P2[:,2]
    return U([tube(P,2.6),tube(xz([(X0(22),22),(46,21.5),(58,22)]),2.6),box((40,-7,19.5),(60,7,22.5))])
@reg('yoke','Y字ヨーク',G2)
def _(): return U([capsule(A(56),(48,0,42),3.4),capsule(A(28),(48,0,42),3.4),capsule((48,0,42),(62,0,42),4.4),sphere((63,0,42),6,32)])
@reg('tripod','3本脚と玉',G2)
def _():
    c=V(55,0,44); return U([capsule(A(58,-5),c,2.4),capsule(A(58,5),c,2.4),capsule(A(26,0),c,2.8),sphere(c,7,32)])
@reg('lever','レバー（下向き）',G2)
def _():
    P=xz(catmull([(X0(52),52),(44,51),(52,46),(58,34),(60,20),(60,12)]))
    return U([tube(P,np.linspace(4.6,3.2,len(P))),sphere((60,0,12),4.4)])
@reg('bollard','2本の柱と横木',G2)
def _(): return U([capsule(A(54),(54,0,54),3.0),capsule(A(30),(54,0,30),3.0),capsule((54,0,62),(54,0,22),3.4),capsule((54,-8,58),(54,8,58),2.6),capsule((54,-8,26),(54,8,26),2.6)])
# ================= trusses & frames =================
def zigzag_between(P,Q,k):
    idx=np.linspace(0,len(P)-1,k).astype(int); out=[]
    for a,b in zip(idx[:-1],idx[1:]): out+= [capsule(P[a],Q[b],1.4),capsule(Q[b],P[b],1.4)]
    return out
@reg('truss_loop','トラス構造のループ',G3)
def _():
    P=resample(D_path(61),1.0); Q=resample(D_path(51,ZT-5,ZB+5),1.0)
    Q=Q[np.linspace(0,len(Q)-1,len(P)).astype(int)]
    return U([tube(P,2.2),tube(Q,1.8)]+zigzag_between(P,Q,12))
@reg('warren_double','ワーレントラス（2面）',G3)
def _():
    P=resample(D_path(60,y=-4),1.0); Q=resample(D_path(60,y=4),1.0)
    return U([tube(P,1.9),tube(Q,1.9)]+zigzag_between(P,Q,14))
@reg('ladder','はしご形（2本の枠と横木）',G3)
def _():
    P=resample(D_path(60,y=-4.2),1.0); Q=resample(D_path(60,y=4.2),1.0); idx=np.linspace(4,len(P)-5,9).astype(int)
    return U([tube(P,2.0),tube(Q,2.0)]+[capsule(P[i],Q[i],1.6) for i in idx])
@reg('tetra_frame','正四面体の骨組み',G3)
def _():
    a=V(50,-9,52); b=V(50,9,52); c=V(62,0,40); d=V(50,-9,28); e=V(50,9,28)
    E=[(a,b),(a,c),(b,c),(c,d),(c,e),(d,e),(a,d),(b,e),(a,e)]
    att=[A(56,-5),A(56,5),A(24,-5),A(24,5)]
    return U([capsule(p,q,1.8) for p,q in E]+[capsule(att[0],a,2.2),capsule(att[1],b,2.2),capsule(att[2],d,2.2),capsule(att[3],e,2.2)]+[sphere(p,2.6) for p in (a,b,c,d,e)])
@reg('string_art','ストリングアート（直線の交差）',G3)
def _():
    out=[tube(D_path(60),2.4,step=1.2)]
    P=resample(D_path(60),1.0); n=len(P)
    for k in range(0,7): out.append(capsule(A(56-k*1.6,-4+k*1.3),P[int(n*0.35+k*2)],1.0))
    for k in range(0,7): out.append(capsule(A(24+k*1.6,-4+k*1.3),P[int(n*0.65-k*2)],1.0))
    return U(out)
@reg('hyperboloid_grip','双曲面に並ぶ棒のグリップ',G3)
def _():
    out=[capsule(A(58),(53,0,60),3.0),capsule(A(22),(53,0,20),3.0)]
    for k in range(10):
        a=2*np.pi*k/10; b=a+np.radians(110)
        out.append(capsule((53+5.5*np.cos(a),5.5*np.sin(a),60),(53+5.5*np.cos(b),5.5*np.sin(b),20),1.1))
    out+=[ring((53,0,60),5.5,1.4,'xy'),ring((53,0,20),5.5,1.4,'xy')]
    return U(out)
@reg('hypar_rods','双曲放物面の棒すだれ',G3)
def _():
    out=[tube(D_path(60),2.4,step=1.2)]
    for k in range(9):
        t=k/8; p=V(X0(56)+3+t*14, -6+12*t, 56-1); q=V(56, 6-12*t, 24+t*30)
        out.append(capsule(p,q,0.95))
    return U(out)
@reg('box_frame','立方体のワイヤーフレーム',G3)
def _():
    c=V(52,0,40); s=11; pts=[c+V(i,j,k)*s for i in (-1,1) for j in (-1,1) for k in (-1,1)]
    E=[(a,b) for a in range(8) for b in range(a+1,8) if np.sum(np.abs(pts[a]-pts[b])>1e-6)==1]
    return U([capsule(pts[a],pts[b],1.7) for a,b in E]+[sphere(p,2.4) for p in pts]+[capsule(A(51),pts[1]*0+c+V(-11,0,11),2.6),capsule(A(29),c+V(-11,0,-11),2.6)])
@reg('octa_frame','正八面体のワイヤーフレーム',G3)
def _():
    c=V(50,0,40); s=14; P=[c+V(s,0,0),c+V(-s,0,0),c+V(0,s,0),c+V(0,-s,0),c+V(0,0,s),c+V(0,0,-s)]
    E=[(a,b) for a in range(6) for b in range(a+1,6) if a//2!=b//2]
    return U([capsule(P[a],P[b],1.7) for a,b in E]+[sphere(p,2.4) for p in P]+[capsule(A(54),P[4],2.6),capsule(A(26),P[5],2.6),capsule(A(40),P[1],2.8)])
@reg('icosa_frame','正二十面体のワイヤーフレーム',G3)
def _():
    ph=(1+5**0.5)/2; raw=[(0,a,b*ph) for a in (-1,1) for b in (-1,1)]+[(a,b*ph,0) for a in (-1,1) for b in (-1,1)]+[(b*ph,0,a) for a in (-1,1) for b in (-1,1)]
    P=[V(50,0,40)+np.array(p)*7.2 for p in raw]
    E=[(a,b) for a in range(12) for b in range(a+1,12) if abs(np.linalg.norm(P[a]-P[b])-14.4)<0.5]
    near=sorted(range(12),key=lambda i:P[i][0])[:3]
    return U([capsule(P[a],P[b],1.5) for a,b in E]+[sphere(p,2.0) for p in P]+[capsule(A(P[i][2]),P[i],2.4) for i in near])
@reg('wheel','ハンドル車輪（輪とスポーク）',G3)
def _():
    c=V(50,0,40); out=[ring(c,14,2.4),sphere(c,3.4),capsule(A(40),c-V(14,0,0),3.6)]
    for k in range(5):
        a=np.radians(72*k+36); out.append(capsule(c,c+14*V(np.cos(a),0,np.sin(a)),1.6))
    return U(out)
# ================= sculpted grips =================
def lattice_in_capsule(g):
    lat=mf.Manifold.level_set(lambda x,y,z:g(x,y,z),[44,-10,14,62,10,68],0.42,0.0).simplify(0.04)
    cap=capsule((53,0,24),(53,0,58),6.6,40)
    skin=cap-capsule((53,0,24),(53,0,58),5.6,40)
    rails=U([capsule((53+6.1*np.cos(a),6.1*np.sin(a),24),(53+6.1*np.cos(a),6.1*np.sin(a),58),1.0) for a in np.linspace(0,2*np.pi,6,endpoint=False)])
    core=(lat^cap)
    parts=sorted(core.decompose(),key=lambda p:-p.volume())
    ringz=U([mf.Manifold.cylinder(1.6,6.6,6.6,48,True).translate((53,0,z)) for z in (24,35,47,58)])
    return U(parts[:1]+[p for p in parts[1:] if p.volume()>3]+[rails,ringz])
def arms(xg=50,r=3.2): return [capsule(A(57),(xg,0,57),r),capsule(A(25),(xg,0,25),r)]
@reg('finger_grooves','指の溝つきグリップ',G4)
def _():
    g=capsule((53,0,60),(53,0,22),5.6)-U([sphere((47.5,0,z),3.2,24) for z in (50,41,32)])
    return U(arms()+[g])
@reg('palm_swell','手のひらに沿うふくらみ',G4)
def _(): return U(arms()+[hull_pts([(53,0,60),(56,0,41),(54,0,22)],4.2,24),ellipsoid((56,0,42),6.6,6.2,11)])
@reg('donut','ドーナツ（太い輪）',G4)
def _():
    cs=mf.CrossSection([circle2((11,0),5.2,40)]); d=mf.Manifold.revolve(cs,72).rotate((90,0,0)).translate((50,0,42))
    return U([d,capsule(A(42),(40,0,42),5.0)])
@reg('egg_ring','穴あき卵形',G4)
def _():
    e=ellipsoid((50,0,42),13,6.5,17,48)-mf.Manifold.cylinder(30,8.5,8.5,48,True).rotate((90,0,0)).translate((50,0,42))
    return U([e,capsule(A(48),(40,0,48),3.6),capsule(A(36),(40,0,36),3.6)])
@reg('lens_plate','レンズ形の厚板と指穴',G4)
def _():
    P=catmull([(X0(60),60),(50,58),(62,42),(50,24),(X0(22),22)],n=14)
    m=plate_xz([P,circle2((47,42),9)],7.0)
    return m-U([mf.Manifold.cylinder(20,3,3,24,True).rotate((90,0,0)).translate((x,0,z)) for x,z in []])
@reg('hourglass','くびれたグリップ',G4)
def _():
    z=np.linspace(21,61,30); r=5.8-2.4*np.exp(-((z-41)/9)**2)
    return U(arms(50,3.0)+[tube(np.c_[np.full(30,54),0*z,z],r)])
@reg('barrel','たる形グリップ',G4)
def _():
    z=np.linspace(21,61,30); r=3.6+2.8*np.sin(np.pi*(z-21)/40)
    return U(arms(50,3.0)+[tube(np.c_[np.full(30,54),0*z,z],r)])
@reg('bulb_end','先が丸くふくらむ持ち手',G4)
def _():
    P=xz(catmull([(X0(56),56),(44,56),(54,50),(58,40)])); return U([tube(P,3.6),tube(xz([(X0(24),24),(44,26),(56,36)]),3.0),sphere((58.5,0,39),7.4,40)])
@reg('wing_airfoil','翼断面のブレード',G4)
def _():
    t=np.linspace(0,1,24); xu=t; yu=0.12*5*(0.2969*np.sqrt(t)-0.126*t-0.3516*t**2+0.2843*t**3-0.1015*t**4)
    sec=np.vstack([np.c_[xu,yu],np.c_[xu[::-1],-yu[::-1]]][0:2])
    sec=np.r_[np.c_[xu,yu][:-1],np.c_[xu[::-1],-yu[::-1]][:-1]]; sec=(sec-[0.4,0])*[14,14]
    P=D_path(60); return sweep(P,sec[:,::-1]*[1,1],twist=0)
@reg('gyroid_grip','ジャイロイド格子のグリップ',G4)
def _():
    k=2*np.pi/7.0
    def f(x,y,z):
        g=np.sin(k*x)*np.cos(k*y)+np.sin(k*y)*np.cos(k*z)+np.sin(k*z)*np.cos(k*x)
        # capsule-shaped grip region
        zz=min(max(z,24.0),58.0); d=np.sqrt((x-53)**2+y*y+(z-zz)**2)-6.5
        return min(0.55-abs(g), -d)
    m=lattice_in_capsule(lambda x,y,z:0.55-abs(np.sin(k*x)*np.cos(k*y)+np.sin(k*y)*np.cos(k*z)+np.sin(k*z)*np.cos(k*x)))
    return U(arms(48,3.0)+[m])
@reg('schwarz_grip','シュワルツP格子のグリップ',G4)
def _():
    k=2*np.pi/7.5
    def f(x,y,z):
        g=np.cos(k*x)+np.cos(k*y)+np.cos(k*z)
        zz=min(max(z,24.0),58.0); d=np.sqrt((x-53)**2+y*y+(z-zz)**2)-6.8
        return min(0.7-abs(g),-d)
    m=lattice_in_capsule(lambda x,y,z:0.7-abs(np.cos(k*x)+np.cos(k*y)+np.cos(k*z)))
    return U(arms(48,3.0)+[m])
@reg('voxel_loop','ボクセル（積み木）ループ',G4)
def _():
    P=resample(D_path(),2.4); cells=set(tuple(np.round(p/3.0).astype(int)) for p in P)
    return U([box(np.array(c)*3.0-1.9,np.array(c)*3.0+1.9) for c in cells])
@reg('lowpoly_loop','ローポリ（多面体）ループ',G4)
def _():
    P=xz([(X0(56),56),(46,58),(58,50),(60,36),(52,24),(X0(24),24)])
    out=[]
    for a,b in zip(P[:-1],P[1:]): out.append(mf.Manifold.batch_hull([sphere(a,3.8,5),sphere(b,3.8,5)]))
    return U(out)
# ================= swept sections =================
@reg('star_section','星形断面のループ',G5)
def _(): return sweep(D_path(),sec_star(4.4,2.5,6),twist=0)
@reg('star_twist','星形断面をねじったループ',G5)
def _(): return sweep(D_path(),sec_star(4.4,2.5,5),twist=240)
@reg('diamond_section','ひし形断面のループ',G5)
def _(): return sweep(D_path(),sec_poly(4.4,4,0)*[1.0,0.75])
@reg('ibeam_section','I形鋼断面のループ',G5)
def _():
    s=np.array([(-4,-3),(4,-3),(4,-1.9),(1.0,-1.9),(1.0,1.9),(4,1.9),(4,3),(-4,3),(-4,1.9),(-1.0,1.9),(-1.0,-1.9),(-4,-1.9)])
    # I-section is not star-shaped from centre for fan caps? it is (centre sees all vertices)
    return sweep(D_path(),s[:,::-1]*[1.2,1.0])
@reg('t_section','T字断面のループ',G5)
def _():
    s=np.array([(-4.5,1.2),(-4.5,3.2),(4.5,3.2),(4.5,1.2),(1.2,1.2),(1.2,-3.2),(-1.2,-3.2),(-1.2,1.2)])
    return sweep(D_path(),s[:,::-1])
@reg('perforated_pipe','穴あきパイプのループ',G5)
def _():
    P=resample(D_path(),1.0); outer=tube(P,4.2); inner=tube(P[3:-3],2.8)
    T,N,B=rmf(P); holes=[]
    for i in range(6,len(P)-6,5):
        holes.append(capsule(P[i]-6*B[i],P[i]+6*B[i],1.5))
    return outer-inner-U(holes)
@reg('wide_band','幅広の平帯ループ',G5)
def _(): return sweep(D_path(),sec_rect(13,2.4,0.9))
@reg('triangle_twist','三角断面を120°ねじる',G5)
def _(): return sweep(D_path(),sec_poly(4.8,3,90),twist=120)
@reg('morph_section','丸→四角→丸に変わる断面',G5)
def _():
    P=resample(D_path(),0.8); n=len(P)
    sq=sec_rect(7.4,7.4,0.8,6); ci=sec_circle(3.9,len(sq))
    ang_s=np.arctan2(sq[:,1],sq[:,0]); ci=np.c_[3.9*np.cos(ang_s),3.9*np.sin(ang_s)]
    T,N,B=rmf(P); verts=[]; F=[]; m=len(sq)
    for i in range(n):
        w=np.sin(np.pi*i/(n-1))**2; S=(1-w)*ci+w*sq
        for u,v in S: verts.append(P[i]+u*N[i]+v*B[i])
    for i in range(n-1):
        for k in range(m):
            a,b,c_,d=i*m+k,i*m+(k+1)%m,(i+1)*m+(k+1)%m,(i+1)*m+k; F+=[[a,b,c_],[a,c_,d]]
    c0=len(verts); verts=np.vstack([verts,P[0],P[-1]])
    for k in range(m): F+=[[c0,(k+1)%m,k],[c0+1,(n-1)*m+k,(n-1)*m+(k+1)%m]]
    import trimesh; tm=trimesh.Trimesh(verts,F,process=False)
    if tm.volume<0: tm.invert()
    return toM(tm)
@reg('square_twist90','四角い棒を90°ねじったグリップ',G5)
def _(): return U(arms()+[sweep(np.c_[np.full(30,53),np.zeros(30),np.linspace(20,62,30)],sec_rect(8,8,1.0),twist=90)])
@reg('hex_section','六角断面のループ',G5)
def _(): return sweep(D_path(),sec_poly(4.0,6,0))
@reg('crescent_section','三日月断面（指に沿う）ループ',G5)
def _():
    a=np.linspace(-1.1,1.1,12); outer=np.c_[5.6*np.cos(a)-2.2,5.6*np.sin(a)]; inner=np.c_[3.4*np.cos(a[::-1])-0.9,3.4*np.sin(a[::-1])*0.9]
    s=np.r_[outer,inner]; s=s-s.mean(0)
    return sweep(D_path(),s[:,::-1]*[1,1])
# ================= multiple strands =================
@reg('nested_loops','入れ子の2重ループ',G6)
def _(): return U([tube(D_path(62),2.4,step=1.2),tube(D_path(52,ZT-6,ZB+6),2.0,step=1.2),capsule((62,0,40),(52,0,40),1.8)])
@reg('fan3','扇状に開く3本ループ',G6)
def _():
    P=D_path(58); o=V(X0(40),0,40); return U([tube(rotpts(P,a,'z',o),2.0,step=1.2) for a in (-24,0,24)])
@reg('fin_grip','放熱フィンのようなグリップ',G6)
def _():
    out=arms(50,3.0)+[capsule((54,0,60),(54,0,22),2.6)]
    for z in np.arange(25,59,4.2): out.append(mf.Manifold.cylinder(1.4,6.4,6.4,40,True).translate((54,0,z)))
    return U(out)
@reg('braid3','三つ編み（3本のらせん）',G6)
def _():
    P=resample(D_path(),0.6); T,N,B=rmf(P); s=np.linspace(0,1,len(P)); out=[]
    for k in range(3):
        th=s*2*np.pi*5+2*np.pi*k/3; C=P+2.3*(np.cos(th)[:,None]*N+np.sin(th)[:,None]*B); out.append(tube(C[::2],1.55))
    return U(out)
@reg('double_helix','二重らせんと横木',G6)
def _():
    P=resample(D_path(),0.6); T,N,B=rmf(P); s=np.linspace(0,1,len(P)); Cs=[]
    for k in range(2):
        th=s*2*np.pi*3.5+np.pi*k; Cs.append(P+4.0*(np.cos(th)[:,None]*N+np.sin(th)[:,None]*B))
    out=[tube(C[::2],1.5) for C in Cs]+[capsule(Cs[0][i],Cs[1][i],1.0) for i in range(8,len(P)-8,7)]
    return U(out)
@reg('rope','2本撚りのロープ',G6)
def _():
    P=resample(D_path(),0.5); T,N,B=rmf(P); s=np.linspace(0,1,len(P)); out=[]
    for k in range(2):
        th=s*2*np.pi*11+np.pi*k; C=P+1.5*(np.cos(th)[:,None]*N+np.sin(th)[:,None]*B); out.append(tube(C[::2],2.1))
    return U(out)
@reg('chain_links','つながった鎖のリンク',G6)
def _():
    out=[]; zs=[56,47,38,29]
    for i,z in enumerate(zs):
        P=ring_pts((0,0,0),1,48); P=np.c_[7.5*P[:,0],np.zeros(48),4.6*P[:,2]]
        P=np.vstack([P,P[:1]])
        if i%2: P=np.c_[P[:,0],P[:,2]*0+0,P[:,2]]*[1,1,1]; P=np.c_[P[:,0],4.6*np.sin(np.linspace(0,2*np.pi,49)),np.zeros(49)]
        P=P@np.array([[0,0,1],[0,1,0],[-1,0,0]])  # long axis vertical
        out.append(tube(P+[52,0,z],1.6))
    out+=[capsule(A(58),(52,0,60),2.6),capsule(A(24),(52,0,22.5),2.6)]
    return U(out)
@reg('bow','リボン結びのような左右ループ',G6)
def _():
    P=D_path(54,50,30); o=V(X0(40),0,40)
    return U([tube(rotpts(P,a,'z',o),2.4,step=1.2) for a in (-48,48)]+[sphere((X0(40)+4,0,40),4.0)])
@reg('trefoil_knot','三つ葉結び目（トレフォイル）',G6)
def _():
    t=np.linspace(0,2*np.pi,240,endpoint=False); x=np.sin(t)+2*np.sin(2*t); z=np.cos(t)-2*np.cos(2*t); y=-np.sin(3*t)
    P=np.c_[x,y*1.3,z]*4.6+[49,0,41]; P=np.vstack([P,P[:1]])
    return U([tube(P,2.1),capsule(A(52),(41,0,52),3.2),capsule(A(30),(41,0,30),3.2)])
@reg('torus_knot','トーラス結び目(2,5)',G6)
def _():
    t=np.linspace(0,2*np.pi,320,endpoint=False); p,q=2,5; r=np.cos(q*t)+2.4
    P=np.c_[r*np.cos(p*t),-np.sin(q*t),r*np.sin(p*t)]*4.6+[49,0,41]; P=np.vstack([P,P[:1]])
    return U([tube(P,1.5),capsule(A(41),(36,0,41),3.6)])
# ================= mathematical curves =================
def closed_curve(fx,fz,cx=48,cz=40,att=True,r=2.6,n=240,y=None):
    t=np.linspace(0,2*np.pi,n,endpoint=False); P=np.c_[cx+fx(t),np.zeros(n) if y is None else y(t),cz+fz(t)]; P=np.vstack([P,P[:1]])
    near=P[np.argmin(P[:,0])]
    return U([tube(P,r),capsule(A(near[2]),near,3.6)])
@reg('cardioid','カージオイド（心臓形）',G7)
def _(): return closed_curve(lambda t:-7*(2*np.cos(t)-np.cos(2*t))*-1+-7,lambda t:7*(2*np.sin(t)-np.sin(2*t)),cx=46)
@reg('lemniscate','レムニスケート（∞）縦置き',G7)
def _():
    t=np.linspace(0,2*np.pi,240,endpoint=False); s=np.sin(t); c=np.cos(t); d=1+s*s
    P=np.c_[48+11*s*c/d,np.zeros_like(t),40+19*c/d]; P=np.vstack([P,P[:1]])
    return U([tube(P,2.6),capsule(A(40),(48,0,40),3.6),capsule(A(58),(48,0,59),2.8),capsule(A(22),(48,0,21),2.8)])
@reg('squircle','スーパー楕円（スクワークル）ループ',G7)
def _():
    t=np.linspace(-np.pi/2,np.pi/2,120); n=4.0
    x=np.sign(np.cos(t))*np.abs(np.cos(t))**(2/n); z=np.sign(np.sin(t))*np.abs(np.sin(t))**(2/n)
    P=np.c_[X0(40)+28*x*0+ (X0(40)+0)*0+28*x, np.zeros_like(t), 40+17*z]
    P=np.vstack([A(57),P[::-1],A(23)]) if False else np.vstack([A(57)+[0,0,0],np.c_[X0(40)+2+26*x,0*t,40+17*z][::-1],A(23)])
    return tube(P,3.0,step=1.0)
@reg('concave_diamond','へこんだひし形（アステロイド風）',G7)
def _(): return closed_curve(lambda t:12*np.sign(np.cos(t))*np.abs(np.cos(t))**1.6,lambda t:17*np.sign(np.sin(t))*np.abs(np.sin(t))**1.6,cx=50,r=2.4)
@reg('deltoid','デルトイド（三尖形）',G7)
def _(): return closed_curve(lambda t:5.2*(2*np.cos(t)+np.cos(2*t)),lambda t:5.2*(2*np.sin(t)-np.sin(2*t)),cx=49,r=2.4)
@reg('superformula','スーパーフォーミュラ（花形）',G7)
def _():
    def sf(t,m=5,n1=0.6,n2=1.0,n3=1.0):
        r=(np.abs(np.cos(m*t/4))**n2+np.abs(np.sin(m*t/4))**n3)**(-1/n1); return r/np.max(r)
    t0=np.linspace(0,2*np.pi,600); rmax=1
    return closed_curve(lambda t:14*sf(t)*np.cos(t),lambda t:14*sf(t)*np.sin(t),cx=50,r=2.0)
@reg('lissajous3d','3Dリサージュ曲線の輪',G7)
def _(): return closed_curve(lambda t:10*np.sin(2*t),lambda t:16*np.sin(3*t+np.pi/2)*0+16*np.cos(t),cx=50,r=2.2,y=lambda t:5*np.sin(3*t))
@reg('epicycloid','エピサイクロイド（3尖）',G7)
def _(): return closed_curve(lambda t:3.2*(4*np.cos(t)-np.cos(4*t)),lambda t:3.2*(4*np.sin(t)-np.sin(4*t)),cx=50,r=2.1)
@reg('hypotrochoid','ハイポトロコイド',G7)
def _(): return closed_curve(lambda t:2.4*((5-3)*np.cos(t)+5*np.cos((5-3)/3*t)),lambda t:2.4*((5-3)*np.sin(t)-5*np.sin((5-3)/3*t)),cx=50,r=1.8,n=600) if False else closed_curve(lambda t:6*np.cos(t)+5*np.cos(4*t)*0.0+4.2*np.cos(3*t),lambda t:9*np.sin(t)+4.2*np.sin(3*t)*-1+6*np.sin(t),cx=50,r=2.0)
@reg('catenary','カテナリー（懸垂線）アーチ',G7)
def _():
    u=np.linspace(-1,1,40); x=X0(40)+30-30*(np.cosh(1.3*u)-1)/(np.cosh(1.3)-1); z=40+18*u
    return tube(np.c_[x,0*u,z],3.0)
@reg('parabola','放物線ループ',G7)
def _():
    u=np.linspace(-1,1,40); x=X0(40)+28*(1-u*u); z=40+17*u; return tube(np.c_[x,0*u,z],3.0)
@reg('scroll','渦巻きで終わるスクロール',G7)
def _():
    P=xz(catmull([(X0(58),58),(44,62),(56,56),(58,42),(54,32)]))
    t=np.linspace(0,3.4*np.pi,120); r=9*np.exp(-0.17*t); c=V(45.5,0,32)
    S=np.c_[c[0]+r*np.cos(t),0*t,c[2]+r*np.sin(-t)]
    return U([tube(P,3.0),tube(S,np.linspace(3.0,2.0,len(S))),capsule(A(28),(40,0,28),2.6)])
@reg('swan_neck','白鳥の首（S字）',G7)
def _():
    P=xz(catmull([(X0(60),60),(44,64),(52,58),(46,46),(52,34),(60,26),(54,20),(X0(22),22)])); return tube(P,3.0)
@reg('wavy_grip','波打つグリップ',G7)
def _():
    z=np.linspace(20,62,80); x=53+2.4*np.sin((z-20)/42*4*np.pi)
    return U(arms(50,3.0)+[tube(np.c_[x,0*z,z],3.6)])
@reg('zigzag_grip','ジグザググリップ',G7)
def _():
    pts=[(54,0,62)]+[(48 if k%2 else 58,0,62-k*6) for k in range(1,7)]+[(54,0,20)]
    return U(arms(50,3.0)+[tube(catmull(pts,n=8),2.8)])
@reg('spring_grip','コイルばねのグリップ',G7)
def _():
    t=np.linspace(0,2*np.pi*6,600); P=np.c_[53+5.4*np.cos(t),5.4*np.sin(t),21+t/(2*np.pi*6)*40]
    return U([capsule(A(58),(58.4,0,61),3.0),capsule(A(24),(58.4,0,21),3.0),tube(P[::3],1.7)])
@reg('log_spiral','対数らせんの持ち手',G7)
def _():
    t=np.linspace(0,2.6*np.pi,160); r=3+2.6*np.exp(0.21*t); a=-t+np.pi
    P=np.c_[46+r*np.cos(a),0*t,40+r*np.sin(a)]
    return U([tube(P,np.linspace(2.0,3.4,len(P))),capsule(A(56),P[-1],3.4),capsule(A(30),(40,0,34),2.6)])
# ================= ergonomic / special =================
@reg('thumb_ledge','親指の棚と指掛け（輪なし）',G8)
def _(): return U([plate_xy([catmull([(X0(56)-1,-7),(44,-11),(54,-6),(56,0),(54,6),(44,11),(X0(56)-1,7)],n=10,closed=True)],3.4,56),capsule(A(30),(44,0,30),3.6),sphere((45,0,30),5.0)])
@reg('saddle','鞍形の親指置き付きループ',G8)
def _():
    u=np.linspace(-1,1,14); out=[tube(D_path(),2.8,step=1.2)]
    pts=[(46+9*a,9*b,58+2.2*(a*a-b*b)) for a in u for b in u]
    return U(out+[hull_pts(pts,1.3,8)])
@reg('pinch_wings','左右からつまむ翼',G8)
def _():
    out=[]
    for s in (-1,1):
        P=catmull([(X0(56)-1,56),(46,58),(52,50),(52,30),(46,22),(X0(24)-1,24)],n=10)
        w=plate_xz([P],2.6); w=rot_z(w,s*28,(X0(40),0,40)).translate((0,s*4.0,0))
        out.append(w)
    return U(out)
@reg('cradle','カップを抱える添え板',G8)
def _():
    a=np.radians(np.linspace(-38,38,40)); R=ri(40)+16
    pts=[(R*np.cos(t),R*np.sin(t)) for t in a]+[((R+3)*np.cos(t),(R+3)*np.sin(t)) for t in a[::-1]]
    band=mf.CrossSection([np.array(pts)[::-1]]).extrude(30).translate((0,0,25))
    if band.volume()<1: band=mf.CrossSection([np.array(pts)]).extrude(30).translate((0,0,25))
    return U([band,capsule(A(50),(R+0.5,0,50),3.4),capsule(A(31),(R+0.5,0,31),3.4)])
@reg('pinky_rest','小指掛け付きループ',G8)
def _(): return U([tube(D_path(),3.0,step=1.2),tube(xz(catmull([(X0(18),18),(40,14),(48,12),(52,14)])),2.6),sphere((52.5,0,14.5),3.4)])
@reg('pull_ring','引き輪（外を向く輪）',G8)
def _(): return U([ring((50,0,42),9.5,2.6,'yz'),capsule(A(42),(50,0,42-9.5+0.01) if False else (49,0,42),3.4)]) - mf.Manifold() if False else U([ring((52,0,42),9.5,2.6,'yz'),capsule(A(51.5),(52,0,51.5),2.8),capsule(A(32.5),(52,0,32.5),2.8)])
@reg('two_slot_plate','2本指スロットの厚板',G8)
def _():
    P=catmull([(X0(60),60),(52,60),(60,52),(60,28),(52,20),(X0(20),20)],n=12)
    sl=[np.array([(41,46),(54,46),(55.5,48),(54,50.5),(41,50.5)])*1.0,np.array([(41,30),(54,30),(55.5,32),(54,34.5),(41,34.5)])]
    sl=[catmull(s,n=4,closed=True) for s in [[(41,45),(54,45),(56,49),(54,52),(41,52)],[(41,28),(54,28),(56,32),(54,35),(41,35)]]]
    return plate_xz([P]+sl,6.0)
@reg('offset_grip','握りが横にずれたグリップ（片手向き）',G8)
def _():
    return U([capsule(A(57),(48,6,57),3.0),capsule(A(25),(48,6,25),3.0),capsule((52,9,60),(54,10,22),4.8)])
@reg('cantilever_blade','片持ちの薄いブレード',G8)
def _():
    P=catmull([(X0(60),60),(48,62),(62,56),(64,50),(56,46),(46,44),(X0(42),42)],n=12)
    return plate_xz([P],3.6)
@reg('arch_bridge','アーチ橋（吊り材つき）',G8)
def _():
    P=xz(catmull([(X0(58),58),(48,59),(58,52),(60,40),(58,28),(48,21),(X0(22),22)]))
    out=[tube(P,2.6),capsule(A(40),(48,0,40),2.0)]
    for z in (50,30): out.append(capsule(A(z),(57.5 if True else 0,0,z),1.4))
    return U(out)
@reg('split_loop','二股に分かれて合流するループ',G8)
def _():
    P1=xz(catmull([(X0(56),56),(46,57),(56,50),(59,40)]),0); P2=xz(catmull([(59,40),(56,30),(46,23),(X0(24),24)]),0)
    Pa=xz(catmull([(46,57),(50,50),(52,40),(50,30),(46,23)]),-0)
    up=resample(np.vstack([P1,P2[1:]]),1.0)
    q=up.copy(); q[:,1]+=4.5*np.sin(np.linspace(0,np.pi,len(q))); q2=up.copy(); q2[:,1]-=4.5*np.sin(np.linspace(0,np.pi,len(q2)))
    return U([tube(q,2.2),tube(q2,2.2)])
@reg('ring_on_post','柱の先の輪（指を引っかける）',G8)
def _(): return U([capsule(A(36),(48,0,36),4.2),ring((48,0,46.5),8.5,2.4,'xy')]) if False else U([capsule(A(44),(41.6,0,44),3.6),ring((50,0,44),8.6,2.5,'xy'),capsule(A(30),(41.6,0,41),2.6)])
@reg('tea_cup_ear','ティーカップの耳（小さく上寄り）',G8)
def _():
    P=xz(catmull([(X0(60),60),(42,62),(48,58),(47,50),(40,46),(X0(46),46)])); return tube(P,np.linspace(3.6,2.4,len(P)))
@reg('mug_thick','マグの太い取っ手',G8)
def _(): return sweep(D_path(60),sec_rect(9,6.5,2.6,6))
@reg('lattice_plate','格子の厚板（握り込み）',G8)
def _():
    P=catmull([(X0(58),58),(50,59),(60,52),(61,40),(60,28),(50,21),(X0(22),22)],n=12)
    holes=[np.array([(x,z),(x+4.6,z),(x+4.6,z+4.6),(x,z+4.6)]) for x in np.arange(37,56,6.2) for z in np.arange(26,54,6.2) if (x-37)+abs(z-40)<26]
    return plate_xz([P]+holes,5.0)
