import numpy as np, shapely.affinity as A
from shapely.geometry import Polygon, box, Point, LineString
from patterns100 import U, polys, raster
from cafkit import caf2d, ring_centres
from coffee_bodies import bean
FONT='/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
def text_poly(txt,cx,cy,h,font=FONT):
    from PIL import Image, ImageDraw, ImageFont
    px=12; F=ImageFont.truetype(font,int(h*px*1.35)); im=Image.new('L',(int(h*px*1.6*max(1,len(txt))+20),int(h*px*2.2)),0); d=ImageDraw.Draw(im)
    d.text((10,0),txt,255,font=F); m=np.array(im)[::-1]>127
    ys,xs=np.nonzero(m)
    g=raster(m,1.0/px)[0]
    b=g.bounds; s=h/(b[3]-b[1]) if b[3]>b[1] else 1
    g=A.scale(g,s,s,origin=(0,0)); b=g.bounds
    return A.translate(g,cx-(b[0]+b[2])/2,cy-(b[1]+b[3])/2)
def bonds_geom(P,B,w=0.75,dw=0.45,gap=0.95,shorten=0.0,skip=()):
    out=[]
    for a,b,o in B:
        if a in skip or b in skip: continue
        pa,pb=np.asarray(P[a]),np.asarray(P[b]); d=pb-pa; L=np.linalg.norm(d); u=d/L; n=np.array([-u[1],u[0]])
        pa2,pb2=pa+u*shorten,pb-u*shorten
        if o==2: out+=[LineString([pa2+n*s_+u*L*0.1,pb2+n*s_-u*L*0.1]).buffer(dw) for s_ in (-gap,gap)]
        else: out.append(LineString([pa2,pb2]).buffer(w))
    return out
RAD={'H':0.85,'C':1.35,'N':1.75,'O':2.2}
CB2={}
def reg(name,jp):
    def d(f): CB2[name]=(f,jp); return f
    return d
@reg('caf_textbook','カフェインの構造式（元素記号つき）')
def _(W,H,r,s):
    holes=[]; fins=[]
    for k in range(3):
        P,E,B=caf2d(8.0,((k+0.5)*W/3,H/2))
        lab=[a for a in P if E[a] in 'NO' ]
        fins+=bonds_geom(P,B,0.7,0.42,1.0)
        for a in lab:
            holes.append(text_poly(E[a],*P[a],4.6))
    clear=U([Point(P_).buffer(3.4) for P_ in []])
    return holes,[f.difference(U([h.buffer(1.0) for h in holes])) for f in fins]
@reg('caf_ballstick','球と棒の分子模型（水素まで全部）')
def _(W,H,r,s):
    holes=[]; fins=[]
    for k in range(3):
        P,E,B=caf2d(6.6,((k+0.5)*W/3,H/2),hydrogens=True)
        fins+=bonds_geom(P,B,0.6,0.38,0.9)
        for a in P: holes.append(Point(P[a]).buffer(RAD[E[a]]*1.15))
    return holes,fins
@reg('caf_spacefill','空間充填モデル（原子の大きさで重なる球）')
def _(W,H,r,s):
    holes=[]; fins=[]
    vdw={'H':1.2,'C':1.7,'N':1.55,'O':1.52}
    for k in range(3):
        P,E,B=caf2d(5.2,((k+0.5)*W/3,H/2),hydrogens=True)
        sc=2.2
        discs=[Point(P[a]).buffer(vdw[E[a]]*sc) for a in P]
        fins.append(U(discs).difference(U([Point(P[a]).buffer(vdw[E[a]]*sc-0.9) for a in P])))
        for a in P:
            if E[a] in 'NO': holes.append(Point(P[a]).buffer(1.5 if E[a]=='N' else 2.0))
    return holes,fins
@reg('caf_wallpaper','カフェインの壁紙（小さな分子をびっしり）')
def _(W,H,r,s):
    holes=[]; fins=[]
    for j,y in enumerate((H*0.27,H*0.73)):
        for i,x in enumerate(np.arange(10+(j%2)*12,W-6,24)):
            P,E,B=caf2d(3.9,(x,y),rot=180 if (i+j)%2 else 0)
            fins+=bonds_geom(P,B,0.55,0.34,0.7)
            for a in P:
                if E[a] in 'NO': holes.append(Point(P[a]).buffer(1.05 if E[a]=='N' else 1.4))
    return holes,fins
@reg('caf_formula','分子式 C₈H₁₀N₄O₂ と構造式')
def _(W,H,r,s):
    holes=[]; fins=[]
    def formula(x,y):
        gs=[]
        for t,big in (('C',1),('8',0),('H',1),('10',0),('N',1),('4',0),('O',1),('2',0)):
            g=text_poly(t,0,0,7.6 if big else 4.0); b=g.bounds
            gs.append(A.translate(g,x-b[0],(y-3.8 if big else y-5.4)-b[1])); x+=b[2]-b[0]+(1.0 if big else 1.4)
        return gs,x
    gs,xe=formula(0,0); fw=xe
    P0,_,_=caf2d(5.2,(0,0)); mw=max(p[0] for p in P0.values())-min(p[0] for p in P0.values())
    unit=mw+6+fw; n=int(W//(unit+6)); gap=(W-n*unit)/n
    for k in range(n):
        x0=k*(unit+gap)+gap/2
        P,E,B=caf2d(5.2,(x0+mw/2,H/2)); fins+=bonds_geom(P,B,0.62,0.38,0.85)
        for a in P:
            if E[a] in 'NO': holes.append(Point(P[a]).buffer(1.4 if E[a]=='N' else 1.8))
        gs,_=formula(x0+mw+6,H/2); holes+=gs
    return holes,fins
@reg('caf_numbered','原子番号つき（1〜9の位置番号）')
def _(W,H,r,s):
    holes=[]; fins=[]
    for k in range(3):
        P,E,B=caf2d(8.6,((k+0.5)*W/3,H/2))
        fins+=bonds_geom(P,B,0.7,0.42,1.0)
        hc,pc=ring_centres(P)
        num={'N1':'1','C2':'2','N3':'3','C4':'4','C5':'5','C6':'6','N7':'7','C8':'8','N9':'9'}
        for a,t in num.items():
            cen=pc if a in ('N7','C8','N9') else hc
            d=(cen-P[a]); d/=np.linalg.norm(d)
            q=P[a]+d*(3.4 if a in ('C4','C5') else 3.2)
            fins.append(text_poly(t,*q,3.4).buffer(0.2))
        for a in P:
            if E[a] in 'NO': holes.append(Point(P[a]).buffer(1.5 if E[a]=='N' else 2.0))
    return holes,fins
@reg('caf_silhouette','骨格のシルエット（大中小）')
def _(W,H,r,s):
    holes=[]
    x=6
    for k,L in enumerate([8.2,5.6,3.8,5.6,8.2,5.6,3.8]):
        P,E,B=caf2d(L,(0,0)); allx=[p[0] for p in P.values()]; wdt=max(allx)-min(allx)
        if x+wdt>W-4: break
        P,E,B=caf2d(L,(x+wdt/2,H/2),rot=0)
        hexa=Polygon([P[a] for a in ('C6','C5','C4','N3','C2','N1')]); pent=Polygon([P[a] for a in ('C5','N7','C8','N9','C4')])
        ring=U([hexa,pent]); body=U([ring.buffer(L*0.22)]+[LineString([P[a],P[b]]).buffer(L*0.12) for a,b,o in B if a not in('C4','C5') or b not in('C4','C5')])
        holes.append(body.difference(hexa.buffer(-L*0.18)).difference(pent.buffer(-L*0.18)))
        x+=wdt+4.0
    return holes
@reg('caf_scatter','カップに溶けて散らばる分子')
def _(W,H,r,s):
    holes=[]; fins=[]; placed=[]
    for t in range(400):
        L=r.uniform(3.0,5.4); x,y=r.uniform(8,W-8),r.uniform(L*2,H-L*2)
        P,E,B=caf2d(L,(x,y),rot=r.uniform(0,360),flip=bool(r.integers(2)))
        hull=U([Point(p).buffer(1.6) for p in P.values()]).convex_hull
        if hull.bounds[0]<2 or hull.bounds[2]>W-2 or hull.bounds[1]<1 or hull.bounds[3]>H-1 or any(hull.distance(o)<1.6 for o in placed): continue
        placed.append(hull); fins+=bonds_geom(P,B,0.55,0.34,0.72)
        for a in P:
            if E[a] in 'NO': holes.append(Point(P[a]).buffer(0.95 if E[a]=='N' else 1.3))
        if len(placed)>=14: break
    return holes,fins
@reg('caf_stencil','ステンシル（結合を透かした切り絵）')
def _(W,H,r,s):
    holes=[]
    for k in range(3):
        P,E,B=caf2d(8.0,((k+0.5)*W/3,H/2))
        holes+=bonds_geom(P,B,0.85,0.55,1.05,shorten=2.2)
    return holes
@reg('caf_beans','カフェインとコーヒー豆')
def _(W,H,r,s):
    holes=[]; fins=[]
    for k in range(4):
        cx=(k+0.5)*W/4
        P,E,B=caf2d(4.6,(cx,H/2),rot=0); fins+=bonds_geom(P,B,0.6,0.38,0.8)
        for a in P:
            if E[a] in 'NO': holes.append(Point(P[a]).buffer(1.2 if E[a]=='N' else 1.6))
    for k in (1,2,3):
        x=k*W/4; holes+=bean(x,H*0.3,4.2,2.8,30)+bean(x-1,H*0.72,4.2,2.8,-35)
    return holes,fins
