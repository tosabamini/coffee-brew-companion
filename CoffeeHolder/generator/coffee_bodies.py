import numpy as np, shapely, shapely.affinity as A
from shapely.geometry import Polygon, box, Point, LineString
from patterns100 import grid, reg_poly, star, bars_to_voids, raster, vor_cells, U, polys
CB={}
def reg(name,jp):
    def d(f): CB[name]=(f,jp); return f
    return d
def bean(cx,cy,a=4.4,b=2.9,rot=0.0):
    e=A.scale(Point(0,0).buffer(1,quad_segs=16),a,b)
    t=np.linspace(-1.15,1.15,30); crease=LineString(np.c_[t*a,0.55*b*np.sin(t*2.6)])
    g=e.difference(crease.buffer(0.68,cap_style='flat'))
    return [A.translate(A.rotate(p,rot,origin=(0,0)),cx,cy) for p in polys(g)]
def heart(cx,cy,R,rot=0):
    t=np.linspace(0,2*np.pi,72); x=16*np.sin(t)**3; y=13*np.cos(t)-5*np.cos(2*t)-2*np.cos(3*t)-np.cos(4*t)
    return A.rotate(Polygon(np.c_[cx+x*R/17,cy+y*R/17]).buffer(0),rot,origin=(cx,cy))
def tear(cx,cy,R,rot=0):
    g=U([Point(cx,cy).buffer(R,quad_segs=12),Polygon([(cx-R*0.86,cy+R*0.5),(cx+R*0.86,cy+R*0.5),(cx,cy+R*2.5)])])
    return A.rotate(g,rot,origin=(cx,cy))
@reg('bean_field','コーヒー豆の畑（ならんだ豆）')
def _(W,H,r,s): return grid(W,H,11,8.4,lambda x,y,i,j:bean(x,y,rot=(25 if (i+j)%2 else -25)),True)
@reg('bean_diagonal','斜めに流れる豆')
def _(W,H,r,s):
    out=[]
    for k,y0 in enumerate(np.arange(-40,H+40,9.0)):
        for x in np.arange(0,W+12,10.5): out+=bean(x+(k%2)*5,y0+x*0.38,rot=21)
    return out
@reg('bean_spiral','豆のフィボナッチ配置')
def _(W,H,r,s):
    out=[]; ga=np.pi*(3-5**0.5); n=150
    for i in range(n):
        x=(i*ga%(2*np.pi))/(2*np.pi)*W; y=(i+0.5)/n*H; out+=bean(x,y,3.4,2.3,np.degrees(i*ga)%180)
    keep=[]
    for g in out:
        if all(g.distance(o)>1.25 for o in keep[-60:]): keep.append(g)
    return keep
@reg('latte_heart','ラテアートのハート')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/22)):
        cx=(k+0.5)*W/int(W/22); cy=H/2+1
        h=heart(cx,cy,9.0)
        sw=LineString([(cx,cy-9),(cx-0.6,cy-3),(cx+0.8,cy+2),(cx,cy+6)]).buffer(0.7)
        out+=polys(h.difference(sw))
    return out
@reg('rosetta','ラテアートのロゼッタ（リーフ）')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/20)):
        cx=(k+0.5)*W/int(W/20)
        for j in range(6):
            R=8.5-j*1.05; y=4+j*5.2
            c=Point(cx,y).buffer(R,quad_segs=20).difference(Point(cx,y+2.7).buffer(R,quad_segs=20))
            out.append(c.difference(box(cx-0.7,0,cx+0.7,H)))
        out.append(heart(cx,H-5.5,3.2))
    return [p for g in out for p in polys(g)]
@reg('tulip','ラテアートのチューリップ')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/20)):
        cx=(k+0.5)*W/int(W/20)
        for j,(y,R) in enumerate([(9,8.0),(19,6.6),(28,5.3)]):
            h=heart(cx,y,R); nxt=heart(cx,y+5.0,R*0.95); out+=polys(h.difference(nxt.buffer(0.7)))
        out.append(heart(cx,36,3.6))
    return out
@reg('steam','立ちのぼる湯気')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/14)):
        x0=(k+0.5)*W/int(W/14)
        for d in (-3.4,0,3.4):
            y=np.linspace(2,H-2,80); x=x0+d+1.8*np.sin(y/5.0+d)+0.6*np.sin(y/2.1)
            out.append(LineString(np.c_[x,y]).buffer(0.75,cap_style='round'))
    return out
@reg('cup_icon','コーヒーカップの影絵')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/24)):
        cx=(k+0.5)*W/int(W/24)
        cup=Polygon([(cx-8,22),(cx+8,22),(cx+6.5,8),(cx-6.5,8)]).buffer(1.2).buffer(-1.0)
        hd=Point(cx+9.5,16).buffer(4.0).difference(Point(cx+9.5,16).buffer(2.2))
        sauc=box(cx-11,4.4,cx+11,6.0).buffer(0.6)
        st=[LineString([(cx+dx,25),(cx+dx+1.4,29),(cx+dx-1.2,33),(cx+dx+0.6,37)]).buffer(0.7) for dx in (-3.5,0,3.5)]
        out+=[U([cup,hd]),sauc]+st
    return out
@reg('plant','コーヒーの木（葉と実）')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/18)):
        x0=(k+0.5)*W/int(W/18)
        for j,y in enumerate((9,21,33)):
            d=1 if (j+k)%2 else -1
            leaf=A.rotate(A.scale(Point(0,0).buffer(1,quad_segs=16),6.4,2.6),d*28,origin=(0,0))
            leaf=leaf.difference(A.rotate(LineString([(-7,0),(7,0)]),d*28,origin=(0,0)).buffer(0.62))
            out+=[A.translate(p,x0+d*4.5,y) for p in polys(leaf)]
            for a in (0,1,2): out.append(Point(x0-d*3.6+a*1.7*(-d),y-1.6+a*1.9).buffer(1.25))
    return out
@reg('drip_cone','ドリッパーとしずく')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/20)):
        cx=(k+0.5)*W/int(W/20)
        cone=Polygon([(cx-8,H-3),(cx+8,H-3),(cx+2,H-17),(cx-2,H-17)])
        ribs=U([box(cx-9,y,cx+9,y+1.2) for y in (H-12.5,H-8)])
        out+=polys(cone.difference(ribs))
        for j,y in enumerate((16,9,3)): out.append(tear(cx,y,1.6+0.4*j,180))
    return out
@reg('drops','落ちるしずく')
def _(W,H,r,s):
    out=[]
    for k in range(3000):
        x,y=r.uniform(3,W-3),r.uniform(3,H-5); R=r.uniform(1.0,2.4); d=tear(x,y,R,180)
        if all(d.distance(o)>1.3 for o in out): out.append(d)
        if len(out)>230: break
    return out
@reg('crema','エスプレッソのクレマの泡')
def _(W,H,r,s):
    out=[]
    for k in range(9000):
        x,y=r.uniform(1,W-1),r.uniform(1,H-1); R=0.6+2.6*(y/H)**1.4*r.uniform(0.6,1.0)
        c=Point(x,y).buffer(R,quad_segs=8)
        if all(c.distance(o)>1.25 for o in out[-400:]) : out.append(c)
        if len(out)>700: break
    return [c for c in out if all(c.distance(o)>1.25 for o in out if o is not c)] if False else out
@reg('grind','挽いた粉（細挽き→粗挽き）')
def _(W,H,r,s):
    pts=[]
    while len(pts)<520:
        x,y=r.uniform(0,W),r.uniform(0,H)
        if r.random()<(1.15-y/H): pts.append((x,y))
    return vor_cells(np.array(pts),W,H,0.65)
@reg('moka','マキネッタ（モカポット）')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/20)):
        cx=(k+0.5)*W/int(W/20)
        low=Polygon([(cx-6.5,3),(cx+6.5,3),(cx+5,16),(cx-5,16)])
        up=Polygon([(cx-5,18),(cx+5,18),(cx+6.5,31),(cx-6.5,31)])
        lid=Polygon([(cx-5.5,33),(cx+5.5,33),(cx,37.5)])
        sp=Polygon([(cx-6.5,29),(cx-9.5,31.5),(cx-6.3,31)])
        hd=Polygon([(cx+7.5,30),(cx+10,29),(cx+10,20),(cx+8.5,19)])
        out+=[low,U([up,sp]),lid,hd]
    return out
@reg('burr','グラインダーの刃（コニカル刃の溝）')
def _(W,H,r,s):
    out=[]
    for x0 in np.arange(-H,W+H,4.6):
        y=np.linspace(0,H,30); x=x0+0.9*y
        out.append(LineString(np.c_[x,y]).buffer(0.85,cap_style='flat'))
    return out
@reg('ring_stain','カップの輪じみ')
def _(W,H,r,s):
    out=[]
    for k in range(26):
        cx,cy=r.uniform(0,W),r.uniform(4,H-4); R=r.uniform(7,13); a0=r.uniform(0,6.28); a=np.linspace(a0,a0+r.uniform(4,5.6),60)
        out.append(LineString(np.c_[cx+R*np.cos(a),cy+R*np.sin(a)]).buffer(r.uniform(0.7,1.1)))
    return out
@reg('v60','ドリッパーのらせんリブ')
def _(W,H,r,s):
    out=[]
    for x0 in np.arange(0,W,8.5):
        y=np.linspace(1.5,H-1.5,40); x=x0+6*(y/H)**1.6
        out.append(LineString(np.c_[x,y]).buffer(1.0))
    out+=[Point(x,H/2).buffer(0.0) for x in []]
    return out
@reg('chemex','ケメックス（砂時計形）')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/16)):
        cx=(k+0.5)*W/int(W/16)
        top=Polygon([(cx-6.5,H-2),(cx+6.5,H-2),(cx+1.2,H/2+2.2),(cx-1.2,H/2+2.2)])
        bot=Polygon([(cx-1.2,H/2-2.2),(cx+1.2,H/2-2.2),(cx+6.5,3),(cx-6.5,3)]).buffer(0.8).buffer(-0.8)
        tie=[Point(cx+2.6,H/2-0.2).buffer(0.9),LineString([(cx+3,H/2-0.6),(cx+4.6,H/2-5)]).buffer(0.55)]
        out+=[top,bot]+tie
    return out
@reg('french_press','フレンチプレスの細かい網')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/22)):
        x0=k*W/int(W/22)+3
        for i in range(6):
            for j in range(13): out.append(box(x0+1+i*2.8,3+j*2.8,x0+1+i*2.8+1.5,3+j*2.8+1.5))
        out.append(box(x0+19,6,x0+20.4,H-6))
    return out
@reg('filter_basket','エスプレッソのフィルターバスケット')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/24)):
        cx=(k+0.5)*W/int(W/24); cy=H/2
        for R in np.arange(0,9.0,2.9):
            n=max(1,int(2*np.pi*R/2.9))
            for a in np.linspace(0,2*np.pi,n,endpoint=False): out.append(Point(cx+R*np.cos(a),cy+R*np.sin(a)).buffer(0.78,quad_segs=8))
        out.append(Point(cx,cy).buffer(12.5).difference(Point(cx,cy).buffer(11.3)))
    return out
@reg('burlap','麻袋の織り目')
def _(W,H,r,s):
    out=[]
    for j,y in enumerate(np.arange(1,H-1,3.0)):
        for i,x in enumerate(np.arange(1+(j%2)*1.8,W-2,3.6)):
            w=r.uniform(1.4,2.0); h=r.uniform(1.0,1.5)
            out.append(box(x,y,x+w,y+h))
    return out
@reg('origin_mountains','産地の山なみ')
def _(W,H,r,s):
    out=[]
    for k,base in enumerate((5,15,25)):
        xs=np.arange(0,W+6,6.0); ys=base+np.where(np.arange(len(xs))%2==0,0,r.uniform(5,9,len(xs)))
        line=LineString(np.c_[xs,ys]); band=line.buffer(1.0,join_style='mitre')
        out+=[p for p in polys(band.intersection(box(0,0,W,H)))]
    sun=[Point(x,H-5).buffer(2.4) for x in np.arange(12,W,36)]
    return out+sun
@reg('awning','カフェの日よけ（スカラップ）')
def _(W,H,r,s):
    out=[]
    for x in np.arange(0,W,8.0):
        b=box(x+1,8,x+7,H-2); sc=Point(x+4,8).buffer(3.0)
        out.append(U([b,sc]).difference(box(x+3.4,8,x+4.6,H)) )
    return [p for g in out for p in polys(g)]
@reg('cup_top','真上から見たカップとソーサー')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/26)):
        cx=(k+0.5)*W/int(W/26); cy=H/2
        out.append(Point(cx,cy).buffer(15).difference(Point(cx,cy).buffer(13.8)))
        out.append(Point(cx,cy).buffer(10.5).difference(Point(cx,cy).buffer(9.3)))
        out.append(Point(cx,cy).buffer(8.1).difference(heart(cx,cy,4.4).buffer(0.7)))
        out.append(Point(cx+11.8,cy).buffer(1.8).difference(Point(cx+11.8,cy).buffer(0.0)))
    return [p for g in out for p in polys(g)]
@reg('pour','注がれるミルクとハート')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/20)):
        cx=(k+0.5)*W/int(W/20)
        y=np.linspace(H-1,17,40); x=cx-3+3*np.cos((y-17)/(H-18)*np.pi/2)
        out.append(LineString(np.c_[x,y]).buffer(0.95))
        out.append(heart(cx,9.5,6.2))
    return out
def text_mask(text,W,H,size,font):
    from PIL import Image, ImageDraw, ImageFont
    dx=0.2; img=Image.new('L',(int(W/dx),int(H/dx)),0); d=ImageDraw.Draw(img); F=ImageFont.truetype(font,int(size/dx))
    bb=d.textbbox((0,0),text,font=F); tw=bb[2]-bb[0]; th=bb[3]-bb[1]
    sc=min(1.0,0.94*img.width/tw,0.84*img.height/th)
    if sc<1.0:
        F=ImageFont.truetype(font,int(size/dx*sc)); bb=d.textbbox((0,0),text,font=F); tw=bb[2]-bb[0]; th=bb[3]-bb[1]
    x=(img.width-tw)/2-bb[0]; y=(img.height-th)/2-bb[1]; d.text((x,y),text,255,font=F)
    m=np.array(img)[::-1]>127
    return m,dx
@reg('text_coffee','COFFEE の文字')
def _(W,H,r,s):
    m,dx=text_mask('COFFEE  COFFEE',W,H,30,'/usr/share/fonts/opentype/noto/NotoSansCJK-Black.ttc'); return raster(m,dx)
@reg('text_kohi','珈琲 の文字')
def _(W,H,r,s):
    m,dx=text_mask('珈琲　珈琲',W,H,34,'/usr/share/fonts/opentype/noto/NotoSansCJK-Black.ttc'); return raster(m,dx)
@reg('aroma','香りの波')
def _(W,H,r,s):
    out=[]
    for j,y0 in enumerate(np.arange(4,H-2,4.6)):
        for x0 in np.arange(-10+(j%2)*12,W,24):
            x=np.linspace(x0,x0+20,40); y=y0+1.4*np.sin((x-x0)/20*2*np.pi)
            out.append(LineString(np.c_[x,y]).buffer(0.8))
    return out
@reg('caffeine','カフェインの分子構造')
def _(W,H,r,s):
    """caffeine = 1,3,7-trimethylxanthine. purine skeleton (6-ring fused with 5-ring),
    C=O on C2 and C6, CH3 on N1, N3, N7. N atoms = holes, O = large holes, CH3 = small holes,
    bonds = raised lines (double bonds drawn as two lines)."""
    holes=[]; fins=[]
    L=6.4
    hexa=np.array([(np.cos(a),np.sin(a)) for a in np.radians(np.arange(30,390,60))])*L
    def bond(a,b,double=False):
        a=np.asarray(a); b=np.asarray(b); d=b-a; n=np.array([-d[1],d[0]])/np.linalg.norm(d)
        if double:
            for o in (-0.95,0.95): fins.append(LineString([a+n*o+d*0.12,b+n*o-d*0.12]).buffer(0.45))
        else: fins.append(LineString([a,b]).buffer(0.75))
    for k in range(int(W/38)):
        c=np.array([(k+0.5)*W/int(W/38)-4,H/2+0.5]); P=hexa+c
        C4,N3,C2,N1,C6,C5=P[0],P[1],P[2],P[3],P[4],P[5]
        e=C5-C4; n=np.array([e[1],-e[0]]); n/=np.linalg.norm(n)
        if np.dot(n,(C4+C5)/2-c)<0: n=-n
        mid=(C4+C5)/2
        N9=C4+n*L*0.95-e*0.31; N7=C5+n*L*0.95+e*0.31; C8=mid+n*L*1.54
        out=lambda p:(p-c)/np.linalg.norm(p-c)
        O2=C2+out(C2)*L*0.95; O6=C6+out(C6)*L*0.95
        Me1=N1+out(N1)*L*0.95; Me3=N3+out(N3)*L*0.95; Me7=N7+out(N7-mid+c-c)*L*0.0+ (N7-mid)/np.linalg.norm(N7-mid)*L*0.95
        # flip upside down so it matches the usual textbook drawing (N7-CH3 at the top right, C6=O on top)
        F=lambda p:np.array([p[0],2*c[1]-p[1]])
        C4,N3,C2,N1,C6,C5,N9,N7,C8,O2,O6,Me1,Me3,Me7=[F(p) for p in (C4,N3,C2,N1,C6,C5,N9,N7,C8,O2,O6,Me1,Me3,Me7)]
        # ring bonds (one Kekule structure)
        bond(C4,N3); bond(N3,C2); bond(C2,N1); bond(N1,C6); bond(C6,C5); bond(C5,C4,True)
        bond(C4,N9); bond(N9,C8,True); bond(C8,N7); bond(N7,C5)
        bond(C2,O2,True); bond(C6,O6,True); bond(N1,Me1); bond(N3,Me3); bond(N7,Me7)
        for p in (N1,N3,N7,N9): holes.append(Point(p).buffer(1.7))
        for p in (O2,O6): holes.append(Point(p).buffer(2.3))
        for p in (Me1,Me3,Me7): holes.append(Point(p).buffer(1.25))
    return holes,fins
@reg('cezve','ジェズベ（トルココーヒーの小鍋）')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/24)):
        cx=(k+0.5)*W/int(W/24)-4
        pot=Polygon([(cx-6,4),(cx+6,4),(cx+4.2,17),(cx+6,21),(cx-6,21),(cx-4.2,17)]).buffer(0.6).buffer(-0.6)
        hd=LineString([(cx+5.5,19),(cx+16,30)]).buffer(1.1)
        st=[LineString([(cx+dx,24),(cx+dx+1.2,28),(cx+dx-1,32),(cx+dx+0.5,36)]).buffer(0.7) for dx in (-2.5,1.5)]
        out+=[pot,hd]+st
    return out
