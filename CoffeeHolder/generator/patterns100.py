import numpy as np, shapely, shapely.affinity
from shapely.geometry import Polygon, box, Point, LineString, MultiLineString
from shapely.ops import unary_union
from lib100 import U, polys, lancet, ogee_poly, tudor, quatrefoil, trefoil
from skimage import measure
from scipy.spatial import Voronoi, Delaunay
A=shapely.affinity
def grid(W,H,pu,pv,fn,stagger=False,margin=1):
    out=[]
    nu=int(W/pu)+3; nv=int(H/pv)+3
    for j in range(-margin,nv):
        for i in range(-margin,nu):
            x=i*pu+(pu/2 if (stagger and j%2) else 0); y=j*pv
            g=fn(x,y,i,j)
            if g is None: continue
            out+= g if isinstance(g,list) else [g]
    return out
def reg_poly(cx,cy,r,n,rot=0.0):
    a=np.radians(rot)+2*np.pi*np.arange(n)/n
    return Polygon(np.c_[cx+r*np.cos(a),cy+r*np.sin(a)])
def star(cx,cy,r1,r2,n,rot=90):
    a=np.radians(rot)+np.pi*np.arange(2*n)/n; r=np.where(np.arange(2*n)%2==0,r1,r2)
    return Polygon(np.c_[cx+r*np.cos(a),cy+r*np.sin(a)])
def bars_to_voids(W,H,bars,w):
    w=max(w,1.7)
    return [box(0,0,W,H).difference(U([b.buffer(w/2,cap_style='flat',join_style='mitre') if not isinstance(b,Polygon) else b for b in bars]))]
def raster(mask,dx):
    m=np.pad(mask.astype(float),1)
    cs=measure.find_contours(m,0.5)
    g=Polygon()
    for c in cs:
        if len(c)<4: continue
        p=Polygon(np.c_[(c[:,1]-1)*dx,(c[:,0]-1)*dx]).buffer(0)
        g=g.symmetric_difference(p)
    return [g]
def vor_cells(pts,W,H,shrink):
    vor=Voronoi(np.vstack([pts,[[-1e3,-1e3],[1e3,-1e3],[-1e3,1e3],[1e4,1e4]]]))
    out=[]
    for k in range(len(pts)):
        reg=vor.regions[vor.point_region[k]]
        if -1 in reg or not reg: continue
        c=Polygon(vor.vertices[reg]).buffer(-shrink)
        if not c.is_empty: out.append(c)
    return out
def noise2(W,H,dx,scale,rng,octaves=3):
    nx,ny=int(W/dx)+1,int(H/dx)+1
    f=np.zeros((ny,nx))
    for o in range(octaves):
        s=scale/(2**o); gx,gy=int(W/s)+3,int(H/s)+3
        g=rng.standard_normal((gy,gx))
        from scipy.ndimage import zoom
        z=zoom(g,(ny/gy+1e-9,nx/gx+1e-9),order=3)[:ny,:nx]
        f[:z.shape[0],:z.shape[1]]+=z/(2**o)
    return f
G={}
def reg(name,jp,arch,top):
    def deco(fn): G[name]=(fn,jp,arch,top); return fn
    return deco
# ---------------- geometry / tilings ----------------
@reg('honeycomb','蜂の巣（正六角形）','porthole','crest')
def _(W,H,r,s): return grid(W,H,6.4*s,5.54*s,lambda x,y,i,j:reg_poly(x,y,3.0*s,6,30),True)
@reg('kagome','カゴメ（三角と六角）','pointed','gable')
def _(W,H,r,s):
    a=7.0*s
    def f(x,y,i,j): return [reg_poly(x,y,a*0.5-0.7,6,0),reg_poly(x+a/2,y+a*0.29,a*0.22,3,90),reg_poly(x,y+a*0.58,a*0.22,3,-90)]
    return grid(W,H,a,a*0.866*2,f,True)
@reg('bauhaus_grid','バウハウスの正方格子','rect','none')
def _(W,H,r,s): return grid(W,H,6.0*s,6.0*s,lambda x,y,i,j:box(x+0.7,y+0.7,x+6*s-0.7,y+6*s-0.7))
@reg('argyle','アーガイル（菱形）','pointed','gable')
def _(W,H,r,s): return grid(W,H,7*s,10*s,lambda x,y,i,j:Polygon([(x,y-4.3*s),(x+2.9*s,y),(x,y+4.3*s),(x-2.9*s,y)]),True)
@reg('bubbles','泡（大小の円）','porthole','crest')
def _(W,H,r,s):
    pts=[];out=[]
    for k in range(4000):
        x,y=r.uniform(0,W),r.uniform(0,H); rr=r.uniform(1.0,3.6)*s
        c=Point(x,y).buffer(rr,quad_segs=10)
        if all(c.distance(o)>1.3 for o in out[-60:]) and all(c.distance(o)>1.3 for o in out): out.append(c)
        if len(out)>400: break
    return out
@reg('cracked_mud','乾いた泥のひび割れ','rect','none')
def _(W,H,r,s): return vor_cells(np.c_[r.uniform(0,W,int(W*H/30/s/s)),r.uniform(0,H,int(W*H/30/s/s))],W,H,0.7)
@reg('sunflower','ひまわり（黄金角配置）','porthole','sunburst')
def _(W,H,r,s):
    n=int(W*H/34/s/s); ga=np.pi*(3-5**0.5)
    pts=np.c_[((np.arange(n)*ga)%(2*np.pi))/(2*np.pi)*W,np.linspace(0,H,n)]
    return [c.buffer(-0.3).buffer(0.3) for c in vor_cells(pts,W,H,0.7)]
@reg('delaunay','ドロネー三角形分割','pointed','gable')
def _(W,H,r,s):
    pts=np.c_[r.uniform(-2,W+2,int(W*H/22/s/s)),r.uniform(-2,H+2,int(W*H/22/s/s))]
    tri=Delaunay(pts); return [Polygon(pts[t]).buffer(-0.65) for t in tri.simplices]
@reg('truchet_arcs','トルシェ・タイル（円弧）','round','dome')
def _(W,H,r,s):
    a=7.0*s; bars=[]
    for i in range(int(W/a)+1):
        for j in range(int(H/a)+1):
            x,y=i*a,j*a
            if r.random()<0.5: cs=[(x,y),(x+a,y+a)]; angs=[(0,90),(180,270)]
            else: cs=[(x+a,y),(x,y+a)]; angs=[(90,180),(270,360)]
            for (cx,cy),(a0,a1) in zip(cs,angs):
                t=np.radians(np.linspace(a0,a1,12)); bars.append(LineString(np.c_[cx+a/2*np.cos(t),cy+a/2*np.sin(t)]))
    return bars_to_voids(W,H,bars,1.5)
@reg('ten_print','10 PRINT 迷路（斜線トルシェ）','pointed','none')
def _(W,H,r,s):
    a=5.0*s; bars=[LineString([(i*a,j*a),((i+1)*a,(j+1)*a)]) if r.random()<0.5 else LineString([((i+1)*a,j*a),(i*a,(j+1)*a)]) for i in range(int(W/a)+1) for j in range(int(H/a)+1)]
    return bars_to_voids(W,H,bars,1.5)
@reg('hilbert','ヒルベルト曲線','rect','battlement')
def _(W,H,r,s):
    def hil(n):
        pts=[(0,0)]
        def d2xy(n,d):
            x=y=0;t=d;sq=1
            while sq<n:
                rx=1&(t//2); ry=1&(t^rx)
                if ry==0:
                    if rx==1: x,y=sq-1-x,sq-1-y
                    x,y=y,x
                x+=sq*rx; y+=sq*ry; t//=4; sq*=2
            return x,y
        return [d2xy(n,d) for d in range(n*n)]
    n=8; p=np.array(hil(n),float); cell=H/n
    bars=[]
    for k in range(int(W/H)+1):
        q=p*cell+[k*H+cell/2,cell/2]; bars.append(LineString(q))
    return bars_to_voids(W,H,bars,1.5)
@reg('sierpinski','シェルピンスキーの三角形','pointed','gable')
def _(W,H,r,s):
    out=[]
    def rec(x,y,L,d):
        if d==0 or L<4: return
        out.append(Polygon([(x+L/4,y+L*0.433),(x+3*L/4,y+L*0.433),(x+L/2,y)]).buffer(-0.6))
        rec(x,y,L/2,d-1); rec(x+L/2,y,L/2,d-1); rec(x+L/4,y+L*0.433,L/2,d-1)
    L=H/0.866
    for k in range(int(W/L*2)+2):
        rec(k*L/2-L/2 if k%2 else k*L/2,0,L,4) if k%2==0 else None
    return out
@reg('sierpinski_carpet','シェルピンスキーのカーペット','rect','ziggurat')
def _(W,H,r,s):
    out=[]
    def rec(x,y,L,d):
        if d==0: return
        t=L/3; out.append(box(x+t+0.3,y+t+0.3,x+2*t-0.3,y+2*t-0.3))
        for i in range(3):
            for j in range(3):
                if (i,j)!=(1,1): rec(x+i*t,y+j*t,t,d-1)
    for k in range(int(W/H)+1): rec(k*H,0,H,3)
    return out
@reg('koch','コッホ雪片','porthole','crest')
def _(W,H,r,s):
    def koch(p,q,d):
        if d==0: return [p]
        p=np.array(p);q=np.array(q);d1=(q-p)/3;a=p+d1;b=p+2*d1
        rot=np.array([[0.5,-0.866],[0.866,0.5]]); c=a+rot@d1
        return koch(p,a,d-1)+koch(a,c,d-1)+koch(c,b,d-1)+koch(b,q,d-1)
    def flake(cx,cy,R):
        v=[(cx+R*np.cos(t),cy+R*np.sin(t)) for t in np.radians([90,330,210])]
        pts=koch(v[0],v[1],3)+koch(v[1],v[2],3)+koch(v[2],v[0],3)
        return Polygon(pts).buffer(0)
    return grid(W,H,13*s,13*s,lambda x,y,i,j:flake(x,y,4.6*s),True)
@reg('apollonian','アポロニウスのギャスケット（円充填）','porthole','dome')
def _(W,H,r,s):
    out=[]
    for k in range(6000):
        x,y=r.uniform(0,W),r.uniform(0,H)
        d=min([Point(x,y).distance(o) for o in out]+[x,W-x,y,H-y,8.0*s])
        if d>2.0: out.append(Point(x,y).buffer(d-1.25,quad_segs=16))
    return out
@reg('fibonacci_squares','フィボナッチ正方形と黄金らせん','rect','none')
def _(W,H,r,s):
    bars=[]; u=H/21.0
    for k in range(int(W/(H*1.618))+1):
        ox=k*H*1.618; x0,y0,x1,y1=ox,0.0,ox+34*u,21*u
        fib=[21,13,8,5,3,2,1]
        for n,f in enumerate(fib):
            L=f*u; d=n%4
            if d==0: sq=(x0,y0,x0+L,y1); c=(x0+L,y0); a=(90,180); x0+=L
            elif d==1: sq=(x0,y1-L,x1,y1); c=(x0,y1-L); a=(0,90); y1-=L
            elif d==2: sq=(x1-L,y0,x1,y1); c=(x1-L,y1); a=(270,360); x1-=L
            else: sq=(x0,y0,x1,y0+L); c=(x1,y0+L); a=(180,270); y0+=L
            bars.append(box(*sq).exterior)
            t=np.radians(np.linspace(a[0],a[1],30)); bars.append(LineString(np.c_[c[0]+L*np.cos(t),c[1]+L*np.sin(t)]))
    return bars_to_voids(W,H,bars,1.7)
@reg('rose_curves','バラ曲線（正葉曲線）','round','dome')
def _(W,H,r,s):
    def rose(cx,cy,R,k):
        t=np.linspace(0,2*np.pi,400); rr=R*np.abs(np.cos(k*t))
        petals=[]
        for i in range(int(2*k)):
            tt=np.linspace(-np.pi/(2*k),np.pi/(2*k),40)+i*np.pi/k
            rr2=R*np.cos(k*(tt-i*np.pi/k))
            petals.append(Polygon(np.vstack([[cx,cy],np.c_[cx+rr2*np.cos(tt),cy+rr2*np.sin(tt)]])).buffer(-0.35))
        return petals
    return grid(W,H,14*s,14*s,lambda x,y,i,j:rose(x,y,6.2*s,[2,3,4][(i+j)%3]),True)
@reg('lissajous','リサージュ図形','porthole','none')
def _(W,H,r,s):
    bars=[]
    for k,(a,b) in enumerate([(3,2),(5,4),(3,4),(5,6),(1,2),(2,3),(4,5),(5,2),(3,5),(4,3)]):
        cx=(k+0.5)*W/10; t=np.linspace(0,2*np.pi,500)
        bars.append(LineString(np.c_[cx+W/22*np.sin(a*t+np.pi/4),H/2+H*0.42*np.sin(b*t)]))
    return bars_to_voids(W,H,bars+[LineString([(0,0),(W,0)]),LineString([(0,H),(W,H)])],1.4)
@reg('spirograph','スピログラフ','porthole','sunburst')
def _(W,H,r,s):
    bars=[]
    for k in range(int(W/18)):
        cx=(k+0.5)*W/int(W/18); R,rr,d=9.0,3.0+(k%3),4.2
        t=np.linspace(0,2*np.pi*rr,900)
        bars.append(LineString(np.c_[cx+(R-rr)*np.cos(t)+d*np.cos((R-rr)/rr*t),H/2+(R-rr)*np.sin(t)-d*np.sin((R-rr)/rr*t)]))
    return bars_to_voids(W,H,bars,1.3)
@reg('interference','波の干渉縞（モアレ）','round','wave')
def _(W,H,r,s):
    dx=0.25; X,Y=np.meshgrid(np.arange(0,W,dx),np.arange(0,H,dx))
    f=np.sin(np.hypot(X-W*0.3,Y-H*0.5)/1.6)+np.sin(np.hypot(X-W*0.7,Y-H*0.5)/1.6)
    return raster(f>0.6,dx)
@reg('ripples','水面の同心円','porthole','wave')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/22)):
        cx=(k+0.5)*W/int(W/22); cy=H/2+r.uniform(-6,6)
        for R in np.arange(2.2,30,3.0):
            out.append(Point(cx,cy).buffer(R+1.0,quad_segs=24).difference(Point(cx,cy).buffer(R-0.2,quad_segs=24)))
    g=U(out)
    return [p for p in polys(g)]
@reg('radar','レーダー（極座標格子）','porthole','dome')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/24)):
        cx=(k+0.5)*W/int(W/24); cy=H/2
        for R0 in (2.5,6.5,10.5,14.5,18.5):
            for t in range(12):
                a0=np.radians(t*30)+0.9/R0; a1=np.radians((t+1)*30)-0.9/R0
                tt=np.linspace(a0,a1,12)
                out.append(Polygon(np.vstack([np.c_[cx+R0*np.cos(tt),cy+R0*np.sin(tt)],np.c_[cx+(R0+2.8)*np.cos(tt[::-1]),cy+(R0+2.8)*np.sin(tt[::-1])]])))
    return out
@reg('chladni','クラドニ図形（振動板の節線）','rect','wave')
def _(W,H,r,s):
    dx=0.25; X,Y=np.meshgrid(np.arange(0,W,dx),np.arange(0,H,dx))
    n,m=3,5; L=H
    f=np.cos(n*np.pi*X/L)*np.cos(m*np.pi*Y/L)-np.cos(m*np.pi*X/L)*np.cos(n*np.pi*Y/L)
    return raster(np.abs(f)>0.35,dx)
def gray_scott(W,H,F,k,rng,dx=0.5,steps=6000):
    nx,ny=int(W/dx),int(H/dx)
    u=np.ones((ny,nx)); v=np.zeros((ny,nx))
    for _ in range(40):
        x,y=rng.integers(0,nx-6),rng.integers(0,ny-6); u[y:y+6,x:x+6]=0.5; v[y:y+6,x:x+6]=0.25+0.05*rng.random()
    def lap(a): return np.roll(a,1,0)+np.roll(a,-1,0)+np.roll(a,1,1)+np.roll(a,-1,1)-4*a
    for _ in range(steps):
        uvv=u*v*v; u+=0.16*lap(u)-uvv+F*(1-u); v+=0.08*lap(v)+uvv-(F+k)*v
    return v
@reg('turing_spots','チューリング・パターン（斑点）','porthole','crest')
def _(W,H,r,s): return raster(gray_scott(W,H,0.035,0.065,r)>0.22,0.5)
@reg('brain_coral','脳サンゴ（迷路状の反応拡散）','round','dome')
def _(W,H,r,s): return raster(gray_scott(W,H,0.029,0.057,r)>0.2,0.5)
@reg('topo_map','等高線地図','rect','wave')
def _(W,H,r,s):
    dx=0.25; f=noise2(W,H,dx,20.0,r)
    lv=np.linspace(f.min(),f.max(),12)[1:-1]
    m=np.zeros_like(f,bool)
    for L in lv: m|=np.abs(f-L)<(f.max()-f.min())*0.012
    return raster(~m,dx)
@reg('rule30','セルオートマトン「ルール30」','rect','battlement')
def _(W,H,r,s):
    a=2.8*s; nx,ny=int(W/a),int(H/a)
    row=(r.random(nx)<0.15).astype(int); out=[]
    for j in range(ny):
        for i in np.nonzero(row)[0]: out.append(box(i*a+0.65,H-(j+1)*a+0.65,(i+1)*a-0.65,H-j*a-0.65))
        l=np.roll(row,1); rr=np.roll(row,-1); row=(l^(row|rr))
    return out
@reg('game_of_life','ライフゲーム（グライダーの群れ）','rect','none')
def _(W,H,r,s):
    a=2.6; nx,ny=int(W/a),int(H/a)
    g=(r.random((ny,nx))<0.45).astype(int)
    for _ in range(3):
        n=sum(np.roll(np.roll(g,i,0),j,1) for i in (-1,0,1) for j in (-1,0,1))-g
        g=((n==3)|((g==1)&(n==2))).astype(int)
    return [box(i*a+0.65,j*a+0.65,(i+1)*a-0.65,(j+1)*a-0.65) for j in range(ny) for i in range(nx) if g[j,i]]
@reg('maze','迷路','rect','battlement')
def _(W,H,r,s):
    a=5.0; nx,ny=int(W/a),int(H/a)
    seen=np.zeros((ny,nx),bool); walls=set()
    for j in range(ny+1):
        for i in range(nx): walls.add(('h',i,j))
    for i in range(nx+1):
        for j in range(ny): walls.add(('v',i,j))
    st=[(0,0)]; seen[0,0]=1
    while st:
        x,y=st[-1]; nb=[(x+dx,y+dy) for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)) if 0<=x+dx<nx and 0<=y+dy<ny and not seen[y+dy,x+dx]]
        if not nb: st.pop(); continue
        nx_,ny_=nb[r.integers(len(nb))]
        if nx_!=x: walls.discard(('v',max(x,nx_),y))
        else: walls.discard(('h',x,max(y,ny_)))
        seen[ny_,nx_]=1; st.append((nx_,ny_))
    bars=[LineString([(i*a,j*a),((i+1)*a,j*a)]) if t=='h' else LineString([(i*a,j*a),(i*a,(j+1)*a)]) for t,i,j in walls]
    return bars_to_voids(W,H,bars,1.4)
@reg('binary','2進数（バイナリコード）','rect','none')
def _(W,H,r,s):
    out=[]; a=3.2; msg=''.join(format(ord(c),'08b') for c in 'PAPER CUP HOLDER '*6)
    k=0
    for j in range(int(H/a)):
        for i in range(int(W/a)):
            if msg[k%len(msg)]=='1': out.append(box(i*a+0.65,j*a+0.65,(i+1)*a-0.65,(j+1)*a-0.65))
            k+=1
    return out
@reg('morse','モールス信号','rect','none')
def _(W,H,r,s):
    code={'C':'-.-.','O':'---','F':'..-.','E':'.','T':'-','A':'.-','I':'..','M':'--','H':'....','N':'-.','K':'-.-',' ':' '}
    text='COFFEE TIME TEA TIME HOT COFFEE '*4
    out=[]; y=H-4.0
    while y>2:
        x=1.0
        for ch in text:
            for sym in code.get(ch,''):
                if sym==' ': x+=4; continue
                L=1.8 if sym=='.' else 5.4
                if x+L>W-1: break
                out.append(box(x,y-1.8,x+L,y).buffer(0.5).buffer(-0.5)); x+=L+1.3
            x+=2.6
            if x>W-6: break
        y-=4.2
    return out
@reg('barcode','バーコード','rect','none')
def _(W,H,r,s):
    out=[]; x=1.0
    while x<W-3:
        w=r.choice([0.9,1.4,2.2,3.0]); out.append(box(x,1.0,x+w,H-1.0)); x+=w+r.choice([1.25,1.6,2.4])
    return out
@reg('pixel_noise','ピクセル・グラデーション','rect','ziggurat')
def _(W,H,r,s):
    a=2.6; out=[]
    for j in range(int(H/a)):
        for i in range(int(W/a)):
            if r.random()< (j*a/H)*0.9: out.append(box(i*a+0.65,j*a+0.65,(i+1)*a-0.65,(j+1)*a-0.65))
    return out
@reg('waveform','音声波形（イコライザー）','rect','none')
def _(W,H,r,s):
    out=[]; x=1.0; ph=r.uniform(0,6)
    while x<W-2:
        amp=(0.5+0.5*np.sin(x/9+ph))*np.abs(np.sin(x/2.3))*0.9+0.08
        out.append(box(x,H/2-amp*H/2.2,x+1.3,H/2+amp*H/2.2)); x+=2.6
    return out
@reg('dna','DNAの二重らせん','round','none')
def _(W,H,r,s):
    bars=[]; t=np.linspace(0,W,800); per=26.0
    y1=H/2+H*0.36*np.sin(2*np.pi*t/per); y2=H/2-H*0.36*np.sin(2*np.pi*t/per)
    bars+= [LineString(np.c_[t,y1]),LineString(np.c_[t,y2])]
    for x in np.arange(0,W,2.6): 
        a=H/2+H*0.36*np.sin(2*np.pi*x/per); b=H/2-H*0.36*np.sin(2*np.pi*x/per)
        if abs(a-b)>2.5: bars.append(LineString([(x,a),(x,b)]))
    bars+= [LineString([(0,1),(W,1)]),LineString([(0,H-1),(W,H-1)])]
    return bars_to_voids(W,H,bars,1.25)
@reg('circuit','電子回路の配線','rect','battlement')
def _(W,H,r,s):
    bars=[];pads=[]
    for k in range(70):
        x,y=r.uniform(0,W),r.uniform(0,H); pts=[(x,y)]
        for st in range(r.integers(2,6)):
            d=r.choice([0,45,90,135,180,225,270,315]); L=r.uniform(3,10)
            x+=L*np.cos(np.radians(d)); y+=L*np.sin(np.radians(d)); pts.append((x,y))
        bars.append(LineString(pts)); pads.append(Point(pts[-1]).buffer(1.8)); pads.append(Point(pts[0]).buffer(1.8))
    V=box(0,0,W,H).difference(U([b.buffer(0.7) for b in bars]+pads))
    vias=[Point(p.centroid).buffer(0.9) for p in pads]
    return [V]+vias
@reg('gears','歯車','porthole','crest')
def _(W,H,r,s):
    def gear(cx,cy,R,n):
        t=np.linspace(0,2*np.pi,n*8,endpoint=False); rr=R+1.1*(np.sin(n*t)>0)
        g=Polygon(np.c_[cx+rr*np.cos(t),cy+rr*np.sin(t)])
        hub=Point(cx,cy).buffer(R*0.35)
        spokes=U([LineString([(cx,cy),(cx+R*np.cos(a),cy+R*np.sin(a))]).buffer(0.8) for a in np.linspace(0,2*np.pi,5,endpoint=False)])
        return g.difference(hub).difference(spokes).difference(Point(cx,cy).buffer(R).exterior.buffer(0.7)) if False else [p for p in polys(Point(cx,cy).buffer(R-1.0).difference(hub.buffer(0.6)).difference(spokes))]
    out=[]
    for k in range(int(W/15)):
        R=r.uniform(4.5,8.0); out+=gear((k+0.5)*W/int(W/15),r.uniform(R+1,H-R-1),R,int(R*2))
    return out
@reg('skyline','夜の摩天楼（窓明かり）','rect','ziggurat')
def _(W,H,r,s):
    out=[]; x=0.5
    while x<W-3:
        w=r.uniform(6,14); h=r.uniform(12,H-3)
        for yy in np.arange(2,h-2,3.0):
            for xx in np.arange(x+1.2,x+w-2.2,2.6):
                if r.random()<0.7: out.append(box(xx,yy,xx+1.4,yy+1.6))
        x+=w+1.4
    return out
# ---------------- world architecture & ornament ----------------
@reg('islamic_8star','イスラームの八芒星','horseshoe','onion')
def _(W,H,r,s):
    a=10*s
    def f(x,y,i,j): return [star(x,y,4.4*s,2.6*s,8,22.5),reg_poly(x+a/2,y+a/2,1.7*s,4,45)]
    return grid(W,H,a,a,f)
@reg('islamic_6star','イスラームの六芒星格子','horseshoe','onion')
def _(W,H,r,s):
    a=9*s
    return grid(W,H,a,a*0.866,lambda x,y,i,j:[star(x,y,3.6*s,2.1*s,6,90)],True)
@reg('moroccan','モロッコのトレリス（四つ葉格子）','horseshoe','onion')
def _(W,H,r,s): return grid(W,H,9*s,9*s,lambda x,y,i,j:quatrefoil(x,y,3.5*s),True)
@reg('jali','ムガルのジャリ（石の透かし格子）','multifoil','dome')
def _(W,H,r,s):
    a=9.6*s
    def f(x,y,i,j): return [star(x,y,3.4*s,1.8*s,6,90).buffer(0.3),Point(x+a/2,y+a*0.29).buffer(0.9)]
    return grid(W,H,a,a*0.866,f,True)
@reg('asanoha','麻の葉','pointed','gable')
def _(W,H,r,s):
    a=15.0*s; h=a*0.866; out=[]
    def f(x,y,i,j):
        P=[(x,y),(x+a,y),(x+a/2,y+h)]; c=np.mean(P,0); res=[]
        for k in range(3):
            p,q=np.array(P[k]),np.array(P[(k+1)%3]); m=(p+q)/2
            res+=[Polygon([p,m,c]).buffer(-0.62),Polygon([m,q,c]).buffer(-0.62)]
        P2=[(x+a/2,y+h),(x+a,y),(x+1.5*a,y+h)]; c2=np.mean(P2,0)
        for k in range(3):
            p,q=np.array(P2[k]),np.array(P2[(k+1)%3]); m=(p+q)/2
            res+=[Polygon([p,m,c2]).buffer(-0.62),Polygon([m,q,c2]).buffer(-0.62)]
        return res
    return grid(W,H,a,h,f,True)
@reg('seigaiha','青海波','round','wave')
def _(W,H,r,s):
    a=18.0*s; bars=[]
    for j in range(int(H/(a/4))+3):
        for i in range(-1,int(W/a)+2):
            cx=i*a+(a/2 if j%2 else 0); cy=j*a/4
            for rr in (a/2,a/2*0.66,a/2*0.33):
                t=np.linspace(0,np.pi,30); bars.append(LineString(np.c_[cx+rr*np.cos(t),cy+rr*np.sin(t)]))
    # wave scales: draw from top to bottom so later rows overlap
    return bars_to_voids(W,H,bars,1.25)
@reg('shippo','七宝つなぎ','porthole','crest')
def _(W,H,r,s):
    a=7.0*s; out=[]
    def f(x,y,i,j):
        c=[Point(x,y).buffer(a/2,quad_segs=16),Point(x+a,y).buffer(a/2,quad_segs=16),Point(x+a/2,y+a/2).buffer(a/2,quad_segs=16),Point(x+a/2,y-a/2).buffer(a/2,quad_segs=16)]
        lens=c[0].intersection(c[2]).buffer(-0.62)
        lens2=c[0].intersection(c[3]).buffer(-0.62)
        star_=box(x,y-a/2,x+a,y+a/2).difference(U(c)).buffer(-0.62)
        return [lens,lens2]+polys(star_)
    return grid(W,H,a,a,f)
@reg('kikko','亀甲','pointed','gable')
def _(W,H,r,s):
    a=4.2*s
    def f(x,y,i,j): return [reg_poly(x,y,a-0.75,6,0),reg_poly(x,y,a*0.42,6,0).buffer(0)]
    out=grid(W,H,a*1.5,a*1.732,f,True)
    return [o for k,o in enumerate(out) if k%2==0]
@reg('yagasuri','矢絣','pointed','none')
def _(W,H,r,s):
    a=6.0*s
    def f(x,y,i,j):
        d=1 if i%2 else -1
        return Polygon([(x+0.95,y),(x+a-0.95,y+d*2.2),(x+a-0.95,y+a*1.3+d*2.2),(x+0.95,y+a*1.3)])
    return grid(W,H,a,a*1.3+1.9,f)
@reg('ichimatsu','市松','rect','battlement')
def _(W,H,r,s):
    a=4.0*s; return grid(W,H,a,a,lambda x,y,i,j:box(x+0.6,y+0.6,x+a-0.6,y+a-0.6) if (i+j)%2==0 else box(x+1.4,y+1.4,x+a-1.4,y+a-1.4))
@reg('uroko','鱗文（三角の鱗）','pointed','gable')
def _(W,H,r,s):
    a=6.0*s
    return grid(W,H,a,a*0.866,lambda x,y,i,j:Polygon([(x,y),(x+a,y),(x+a/2,y+a*0.866)]).buffer(-0.62) if (i+j)%2==0 else None,True)
@reg('sayagata','紗綾形（卍つなぎ）','rect','battlement')
def _(W,H,r,s):
    a=2.0; n=6; bars=[]
    for j in range(-2,int(H/(a*n))+3):
        for i in range(-2,int(W/(a*n))+3):
            x,y=i*a*n+(j%2)*a*n/2,j*a*n
            for rot in (0,90,180,270):
                L=LineString([(0,0),(3*a,0),(3*a,2*a),(2*a,2*a)])
                bars.append(A.translate(A.rotate(L,rot,origin=(0,0)),x+3*a,y+3*a))
    return bars_to_voids(W,H,bars,1.25)
@reg('kumiko','組子（三つ組手）','pointed','gable')
def _(W,H,r,s):
    a=12.0*s; h=a*0.866; out=[]
    def f(x,y,i,j):
        res=[]
        for P in ([(x,y),(x+a,y),(x+a/2,y+h)],[(x+a/2,y+h),(x+a,y),(x+1.5*a,y+h)]):
            c=np.mean(P,0)
            for k in range(3):
                p=np.array(P[k]); q=np.array(P[(k+1)%3])
                res.append(Polygon([p,q,c]).buffer(-0.62))
        return res
    return grid(W,H,a,h,f,True)
@reg('greek_key','ギリシャの雷文（メアンダー）','rect','battlement')
def _(W,H,r,s):
    a=1.9; bars=[]
    unit=[(0,0),(0,4),(4,4),(4,1),(2,1),(2,2),(3,2),(3,3),(1,3),(1,0),(5,0)]
    for row in range(int(H/(5*a))+1):
        for k in range(int(W/(5*a))+2):
            bars.append(LineString([(x*a+k*5*a,y*a+row*5*a+0.6) for x,y in unit]))
    return bars_to_voids(W,H,bars,1.25)
@reg('basketweave','バスケット織り','rect','none')
def _(W,H,r,s):
    a=6.0*s
    def f(x,y,i,j):
        if (i+j)%2==0: return [box(x+0.6,y+0.6+k*a/3,x+a-0.6,y+(k+1)*a/3-0.6) for k in range(3)]
        return [box(x+0.6+k*a/3,y+0.6,x+(k+1)*a/3-0.6,y+a-0.6) for k in range(3)]
    return grid(W,H,a,a,f)
@reg('herringbone','ヘリンボーン','rect','none')
def _(W,H,r,s):
    out=[]; L,w=7.0,2.2
    for j in range(-2,int(H/2.6)+4):
        for i in range(-2,int(W/6)+3):
            x,y=i*6.0,j*2.6
            b=box(0,0,L,w).buffer(-0.62)
            out.append(A.translate(A.rotate(b,45 if i%2 else -45,origin=(0,0)),x,y))
    return out
@reg('chevron','シェブロン（山形）','pointed','gable')
def _(W,H,r,s):
    bars=[]
    for y in np.arange(-6,H+6,3.6):
        xs=np.arange(-3,W+3,5.0); bars.append(LineString([(x,y+(2.4 if k%2 else 0)) for k,x in enumerate(xs)]))
    return bars_to_voids(W,H,bars,1.4)
@reg('houndstooth','千鳥格子','rect','none')
def _(W,H,r,s):
    a=4.0*s
    def f(x,y,i,j):
        p=Polygon([(0,0),(2,0),(2,1),(3,2),(4,2),(4,3),(3,3),(2,4),(2,3),(1,2),(0,2),(0,1),(1,1)])
        return A.translate(A.scale(p,a/4,a/4,origin=(0,0)),x,y).buffer(-0.45)
    return grid(W,H,a,a,f)
@reg('tartan','タータンチェック','rect','none')
def _(W,H,r,s):
    out=[]
    for x in np.arange(0,W,9.0):
        for y in np.arange(0,H,9.0):
            out+=[box(x+0.6,y+0.6,x+4.2,y+4.2),box(x+5.4,y+0.6,x+8.4,y+4.2),box(x+0.6,y+5.4,x+4.2,y+8.4),box(x+5.4,y+5.4,x+6.6,y+6.6),box(x+7.8,y+7.8,x+8.4,y+8.4).buffer(0.3)]
    return out
@reg('art_deco_sunburst','アール・デコの放射（サンバースト）','stepped','sunburst')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/20)):
        cx=(k+0.5)*W/int(W/20)
        for t in np.linspace(12,168,9):
            a=np.radians(t); out.append(Polygon([(cx+3*np.cos(a-0.06),2+3*np.sin(a-0.06)),(cx+40*np.cos(a-0.11),2+40*np.sin(a-0.11)),(cx+40*np.cos(a+0.11),2+40*np.sin(a+0.11)),(cx+3*np.cos(a+0.06),2+3*np.sin(a+0.06))]))
        out.append(Point(cx,2).buffer(1.6))
    return out
@reg('art_deco_ziggurat','アール・デコの階段状（ジッグラト）','stepped','ziggurat')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/14)):
        cx=(k+0.5)*W/int(W/14)
        for n in range(5):
            out.append(box(cx-6+n*1.2,2+n*7.6,cx+6-n*1.2,2+n*7.6+5.6))
    return out
@reg('art_nouveau','アール・ヌーヴォーのむち紐曲線','ogee','wave')
def _(W,H,r,s):
    bars=[]
    for k in range(int(W/12)+1):
        x0=k*12; t=np.linspace(0,1,80)
        bars.append(LineString(np.c_[x0+6*np.sin(t*np.pi*2.2)+3*t,H*t]))
        bars.append(LineString(np.c_[x0+6-6*np.sin(t*np.pi*2.2+1)+3*t,H*t]))
    bars+= [LineString([(0,0.6),(W,0.6)]),LineString([(0,H-0.6),(W,H-0.6)])]
    return bars_to_voids(W,H,bars,1.4)
@reg('romanesque','ロマネスクの半円アーケード','round','battlement')
def _(W,H,r,s):
    out=[]; p=9.6
    for k in range(int(W/p)):
        cx=(k+0.5)*W/int(W/p); w=p-2.4
        out.append(U([box(cx-w/2,2,cx+w/2,H-6-w/2),Point(cx,H-6-w/2).buffer(w/2,quad_segs=16)]))
        out.append(Point(cx+p/2,H-3.2).buffer(1.2))
    return out
@reg('moorish','ムーアの馬蹄形アーチ','horseshoe','onion')
def _(W,H,r,s):
    out=[]; p=11.0
    for k in range(int(W/p)):
        cx=(k+0.5)*W/int(W/p); R=(p-2.4)/2*1.1; zc=H-6-R
        out.append(U([box(cx-R*0.8,2,cx+R*0.8,zc),Point(cx,zc).buffer(R,quad_segs=20).intersection(box(0,zc-R*0.5,1e3,1e3))]))
        out.append(star(cx+p/2,H-2.6,1.6,0.8,8,0))
    return out
@reg('mughal_multifoil','ムガルの多弁アーチ','multifoil','onion')
def _(W,H,r,s):
    out=[]; p=12.0
    for k in range(int(W/p)):
        cx=(k+0.5)*W/int(W/p); w=p-2.6; zc=H-8-w/2
        a=U([box(cx-w/2,2,cx+w/2,zc),Point(cx,zc).buffer(w/2,quad_segs=20)])
        cusps=[Point(cx+(w/2+0.3)*np.cos(t),zc+(w/2+0.3)*np.sin(t)).buffer(1.2) for t in np.radians([25,60,90,120,155])]
        out.append(a.difference(U(cusps)))
    return out
@reg('byzantine','ビザンチンの円窓と十字','round','dome')
def _(W,H,r,s):
    out=[]; p=12.0
    for k in range(int(W/p)):
        cx=(k+0.5)*W/int(W/p)
        out.append(U([box(cx-3.4,2,cx+3.4,H*0.55),Point(cx,H*0.55).buffer(3.4)]))
        c=Point(cx,H*0.84).buffer(3.6); cross=U([box(cx-0.7,H*0.84-3.6,cx+0.7,H*0.84+3.6),box(cx-3.6,H*0.84-0.7,cx+3.6,H*0.84+0.7)]).buffer(0.0)
        out+=polys(c.difference(cross))
    return out
@reg('egyptian_lotus','エジプトの蓮の柱','pointed','ziggurat')
def _(W,H,r,s):
    out=[]; p=10.0
    for k in range(int(W/p)):
        cx=(k+0.5)*W/int(W/p)+p/2
        out.append(box(cx-3.2,2,cx+3.2,H-12))
        out.append(Polygon([(cx-3.2,H-11),(cx+3.2,H-11),(cx+4.2,H-3),(cx,H-6),(cx-4.2,H-3)]))
    return out
@reg('aztec_fret','アステカの階段渦文','stepped','ziggurat')
def _(W,H,r,s):
    a=1.8; bars=[]
    for k in range(int(W/(12*a))+1):
        x0=k*12*a
        pts=[(0,0),(2,0),(2,2),(4,2),(4,4),(6,4),(6,6),(8,6),(8,2),(7,2),(7,5),(5,5)]
        for row in range(int(H/(10*a))+1):
            bars.append(LineString([(x0+x*a,row*10*a+y*a+1) for x,y in pts]))
    return bars_to_voids(W,H,bars,1.3)
@reg('onion_domes','ロシアの玉ねぎ屋根','ogee','onion')
def _(W,H,r,s):
    out=[]; p=13.0
    for k in range(int(W/p)):
        cx=(k+0.5)*W/int(W/p); hgt=r.uniform(0.6,1.0)
        out.append(box(cx-3.2,2,cx+3.2,H*0.45*hgt+6))
        out.append(ogee_poly(cx,H*0.45*hgt+7.4,9.0,H*0.45*hgt+11,9.0))
    return out
@reg('ice_ray','中国の氷裂紋','rect','none')
def _(W,H,r,s):
    cells=[box(0,0,W,H)]
    for _ in range(9):
        new=[]
        for c in cells:
            if c.area<40: new.append(c); continue
            x0,y0,x1,y1=c.bounds; cx,cy=r.uniform(x0,x1),r.uniform(y0,y1); a=r.uniform(0,np.pi)
            L=LineString([(cx-60*np.cos(a),cy-60*np.sin(a)),(cx+60*np.cos(a),cy+60*np.sin(a))]).buffer(0.01)
            new+=polys(c.difference(L))
        cells=new
    return [c.buffer(-0.65) for c in cells]
@reg('wanzi','中国の万字格子','rect','battlement')
def _(W,H,r,s):
    a=3.0; bars=[]
    for j in range(int(H/(4*a))+2):
        for i in range(int(W/(4*a))+2):
            x,y=i*4*a,j*4*a
            bars+=[LineString([(x,y+a),(x+2*a,y+a),(x+2*a,y+3*a)]),LineString([(x+2*a,y+a),(x+2*a,y-a)]),LineString([(x+a,y+2*a),(x+3*a,y+2*a)])]
    return bars_to_voids(W,H,bars,1.25)
@reg('brutalist','ブルータリズム（大小の矩形）','rect','battlement')
def _(W,H,r,s):
    out=[]; x=1
    while x<W-4:
        w=r.uniform(3,10); y=1
        while y<H-3:
            h=r.uniform(3,12); out.append(box(x,y,x+w,min(y+h,H-1))); y+=h+r.uniform(1.4,3)
        x+=w+r.uniform(1.4,3)
    return out
@reg('mondrian','モンドリアンの分割','rect','none')
def _(W,H,r,s):
    cells=[box(0,0,W,H)]
    for _ in range(6):
        new=[]
        for c in cells:
            x0,y0,x1,y1=c.bounds
            if (x1-x0)>(y1-y0) and x1-x0>10: x=r.uniform(x0+3,x1-3); new+=[box(x0,y0,x,y1),box(x,y0,x1,y1)]
            elif y1-y0>10: y=r.uniform(y0+3,y1-3); new+=[box(x0,y0,x1,y),box(x0,y,x1,y1)]
            else: new.append(c)
        cells=new
    return [c.buffer(-0.7*(1+r.integers(0,2))) for c in cells]
@reg('bauhaus_shapes','バウハウスの○△□','porthole','none')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/12)):
        cx=(k+0.5)*W/int(W/12)
        for j,cy in enumerate((H*0.2,H*0.5,H*0.8)):
            t=(k+j)%3
            out.append(Point(cx,cy).buffer(4) if t==0 else box(cx-3.6,cy-3.6,cx+3.6,cy+3.6) if t==1 else reg_poly(cx,cy-0.8,4.6,3,90))
    return out
@reg('vasarely','ヴァザルリのオプ・アート（膨らむ格子）','rect','none')
def _(W,H,r,s):
    out=[]; a=4.0
    for i in range(int(W/a)):
        for j in range(int(H/a)):
            x,y=(i+0.5)*a,(j+0.5)*a
            d=np.hypot((x-W/2)/(W/2),(y-H/2)/(H/2)); k=1.0-0.55*d
            h=max(a*k/2-0.6,0.5)
            out.append(box(x-h,y-h,x+h,y+h))
    return out
@reg('riley_waves','ブリジット・ライリーの波縞','round','wave')
def _(W,H,r,s):
    out=[]
    for y0 in np.arange(0,H+3,2.8):
        xs=np.linspace(0,W,300); amp=1.2+1.0*np.sin(xs/W*np.pi*3)
        top=y0+amp*np.sin(xs/4.0)+1.4*0.5; bot=y0+amp*np.sin(xs/4.0)-0.0
        out.append(Polygon(np.vstack([np.c_[xs,bot],np.c_[xs[::-1],top[::-1]+0.5]])).buffer(0))
    return out
# ---------------- nature ----------------
@reg('snowflakes','雪の結晶','porthole','crest')
def _(W,H,r,s):
    def flake(cx,cy,R):
        arms=[]
        for k in range(6):
            a=np.radians(60*k+90); e=(cx+R*np.cos(a),cy+R*np.sin(a))
            arms.append(LineString([(cx,cy),e]).buffer(0.9))
            for t in (0.5,0.75):
                m=(cx+R*t*np.cos(a),cy+R*t*np.sin(a))
                for d in (-1,1):
                    b=a+d*np.radians(50); arms.append(LineString([m,(m[0]+R*0.3*np.cos(b),m[1]+R*0.3*np.sin(b))]).buffer(0.7))
        return U(arms)
    return grid(W,H,14,14,lambda x,y,i,j:flake(x,y,5.6),True)
@reg('constellation','星座（星と線）','porthole','none')
def _(W,H,r,s):
    pts=np.c_[r.uniform(3,W-3,60),r.uniform(3,H-3,60)]
    out=[star(x,y,r.uniform(1.6,2.8),0.8,5,90) for x,y in pts]
    tri=Delaunay(pts)
    for a,b,c in tri.simplices[:40]:
        out.append(LineString([pts[a],pts[b]]).buffer(0.5))
    return out
@reg('moon_phases','月の満ち欠け','porthole','dome')
def _(W,H,r,s):
    out=[]; n=int(W/12)
    for k in range(n):
        cx=(k+0.5)*W/n; ph=k/n*2-1
        for cy in (H*0.3,H*0.72):
            m=Point(cx,cy).buffer(4.8,quad_segs=24); sh=Point(cx+ph*9.6,cy).buffer(4.8,quad_segs=24)
            out+=polys(m.difference(sh.buffer(0.0)))
    return out
@reg('raindrops','雨粒','ogee','none')
def _(W,H,r,s):
    out=[]
    for k in range(3000):
        x,y=r.uniform(2,W-2),r.uniform(2,H-4); R=r.uniform(1.0,2.2)
        d=U([Point(x,y).buffer(R,quad_segs=10),Polygon([(x-R*0.85,y+R*0.5),(x+R*0.85,y+R*0.5),(x,y+R*2.6)])])
        if all(d.distance(o)>1.3 for o in out): out.append(d)
        if len(out)>260: break
    return out
@reg('leaves','木の葉と葉脈','ogee','wave')
def _(W,H,r,s):
    out=[]
    def leaf(cx,cy,L,ang):
        t=np.linspace(0,np.pi,30); w=L*0.32
        P=Polygon(np.vstack([np.c_[L*(t/np.pi),w*np.sin(t)],np.c_[L*(t[::-1]/np.pi),-w*np.sin(t[::-1])]]))
        veins=U([LineString([(0,0),(L,0)]).buffer(0.6)]+[LineString([(L*q,0),(L*q+L*0.18,d*w*0.7)]).buffer(0.5) for q in (0.3,0.5,0.7) for d in (-1,1)])
        g=P.difference(veins)
        return [A.translate(A.rotate(p,ang,origin=(0,0)),cx,cy) for p in polys(g)]
    return grid(W,H,12,9,lambda x,y,i,j:leaf(x-5,y,11,35 if (i+j)%2 else -35),True)
@reg('tree_branches','樹の枝（Lシステム）','pointed','none')
def _(W,H,r,s):
    bars=[]
    def br(x,y,a,L,d):
        if d==0 or L<1.5: return
        x2,y2=x+L*np.cos(a),y+L*np.sin(a); bars.append(LineString([(x,y),(x2,y2)]))
        br(x2,y2,a+r.uniform(0.3,0.6),L*0.72,d-1); br(x2,y2,a-r.uniform(0.3,0.6),L*0.72,d-1)
    for k in range(int(W/22)): br((k+0.5)*W/int(W/22),0,np.pi/2,H*0.36,6)
    bars+= [LineString([(0,0.5),(W,0.5)]),LineString([(0,H-0.5),(W,H-0.5)])]
    return bars_to_voids(W,H,bars,1.4)
@reg('spider_web','蜘蛛の巣','porthole','crest')
def _(W,H,r,s):
    bars=[]
    for k in range(int(W/30)):
        cx=(k+0.5)*W/int(W/30); cy=H/2
        for t in np.linspace(0,2*np.pi,12,endpoint=False): bars.append(LineString([(cx,cy),(cx+40*np.cos(t),cy+40*np.sin(t))]))
        for R in np.arange(3,22,3.0):
            tt=np.linspace(0,2*np.pi,13); bars.append(LineString(np.c_[cx+R*np.cos(tt),cy+R*np.sin(tt)]))
    return bars_to_voids(W,H,bars,1.25)
@reg('dragonfly_wing','トンボの翅脈','pointed','none')
def _(W,H,r,s):
    pts=np.c_[r.uniform(0,W,240),np.abs(r.normal(0,1,240))*H/2.2 % H]
    pts[:,1]=r.uniform(0,H,240)**1.0
    cells=vor_cells(np.c_[pts[:,0],pts[:,1]],W,H,0.62)
    return [A.scale(c,1.0,1.0) for c in cells]
@reg('fish_scales','魚の鱗','round','wave')
def _(W,H,r,s):
    a=6.0
    def f(x,y,i,j):
        return Point(x,y).buffer(a/2,quad_segs=16).difference(Point(x,y-a*0.42).buffer(a/2+0.6,quad_segs=16)).buffer(-0.3)
    return grid(W,H,a,a*0.55,f,True)
@reg('feathers','羽根','ogee','none')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/11)):
        cx=(k+0.5)*W/int(W/11)
        vane=Polygon(np.c_[cx+4.2*np.sin(np.linspace(0,np.pi,30)),np.linspace(2,H-2,30)]).union(Polygon(np.c_[cx-4.2*np.sin(np.linspace(0,np.pi,30)),np.linspace(2,H-2,30)]))
        barbs=U([LineString([(cx,y),(cx+6,y+3.2)]).buffer(0.6) for y in np.arange(4,H,2.6)]+[LineString([(cx,y),(cx-6,y+3.2)]).buffer(0.6) for y in np.arange(4,H,2.6)]+[LineString([(cx,0),(cx,H)]).buffer(0.7)])
        out+=polys(vane.difference(barbs))
    return out
@reg('bamboo','竹林','rect','none')
def _(W,H,r,s):
    out=[]; x=1
    while x<W-4:
        w=r.uniform(2.4,4.4); y=0.8
        while y<H-2:
            L=r.uniform(6,12); out.append(box(x,y,x+w,min(y+L,H-0.8)).buffer(-0.3).buffer(0.3)); y+=L+1.4
        x+=w+1.5
    return out
@reg('snake_skin','蛇皮（歪んだ六角）','pointed','none')
def _(W,H,r,s):
    pts=[]; a=4.6
    for j in range(int(H/(a*0.866))+2):
        for i in range(int(W/a)+2):
            pts.append(((i+0.5*(j%2))*a+r.normal(0,0.6),j*a*0.866+r.normal(0,0.6)))
    return vor_cells(np.array(pts),W,H,0.62)
@reg('giraffe','キリン柄','round','none')
def _(W,H,r,s):
    pts=np.c_[r.uniform(0,W,int(W*H/70)),r.uniform(0,H,int(W*H/70))]
    return [c.buffer(-0.8).buffer(0.8,quad_segs=8) for c in vor_cells(pts,W,H,0.9)]
@reg('zebra','シマウマ柄','ogee','wave')
def _(W,H,r,s):
    dx=0.25; X,Y=np.meshgrid(np.arange(0,W,dx),np.arange(0,H,dx))
    n=noise2(W,H,dx,30.0,r,2)
    f=np.sin(X/2.4+n*2.2)
    return raster(f>0.15,dx)
@reg('leopard','ヒョウ柄（ロゼット）','round','crest')
def _(W,H,r,s):
    out=[]
    for k in range(2000):
        x,y=r.uniform(2,W-2),r.uniform(2,H-2); R=r.uniform(2.0,3.4)
        ring=Point(x,y).buffer(R,quad_segs=16).difference(Point(x,y).buffer(R-1.0,quad_segs=16))
        gaps=U([LineString([(x,y),(x+5*np.cos(t),y+5*np.sin(t))]).buffer(0.7) for t in r.uniform(0,6.28,3)])
        segs=[p for p in polys(ring.difference(gaps)) if p.area>0.6]
        seg=U(segs)
        if all(seg.distance(o)>1.3 for o in out): out.append(seg)
        if len(out)>150: break
    return out
# ---------------- more tilings / math ----------------
@reg('bricks','レンガ積み（フランス積み）','round','battlement')
def _(W,H,r,s):
    out=[]; h=3.6
    for j,y in enumerate(np.arange(0,H,h+1.4)):
        x=-(j%2)*4.0
        while x<W:
            L=7.0 if (int(x/5)+j)%3 else 3.0
            out.append(box(x,y,x+L,y+h)); x+=L+1.4
    return out
@reg('octagon_488','4.8.8タイル（八角形と正方形）','porthole','none')
def _(W,H,r,s):
    a=7.0
    return grid(W,H,a,a,lambda x,y,i,j:[reg_poly(x,y,a/2/np.cos(np.pi/8)-0.75,8,22.5),reg_poly(x+a/2,y+a/2,(a/2*np.tan(np.pi/8))*1.414-0.85,4,45)])
@reg('dodecagon','3.12.12タイル（十二角形と三角形）','porthole','crest')
def _(W,H,r,s):
    a=9.0; out=[]
    def f(x,y,i,j): return [reg_poly(x,y,a/2/np.cos(np.pi/12)-0.75,12,15),reg_poly(x+a/2,y+a*0.29,a*0.13,3,90),reg_poly(x,y+a*0.58,a*0.13,3,-90)]
    return grid(W,H,a,a*0.866*2,f,True)
@reg('ammann_beenker','アマン＝ベーンカー（八回対称の準結晶）','pointed','gable')
def _(W,H,r,s):
    e=np.array([[np.cos(np.pi*k/4),np.sin(np.pi*k/4)] for k in range(4)]); gam=r.uniform(-0.3,0.3,4)
    tiles=[]; N=22; L=4.4
    for a_ in range(4):
        for b_ in range(a_+1,4):
            Ainv=np.linalg.inv(np.array([e[a_],e[b_]]))
            for ka in range(-N,N):
                for kb in range(-N,N):
                    p=Ainv@np.array([ka-gam[a_],kb-gam[b_]]); K=np.ceil(p@e.T+gam); K[a_]=ka; K[b_]=kb
                    bse=K@e; P=Polygon(np.array([bse,bse+e[a_],bse+e[a_]+e[b_],bse+e[b_]])*L+[W/2,H/2])
                    if P.intersects(box(0,0,W,H)): tiles.append(P.buffer(-0.62))
    return tiles
@reg('penrose','ペンローズ・タイル','pointed','gable')
def _(W,H,r,s):
    e=np.array([[np.cos(2*np.pi*k/5),np.sin(2*np.pi*k/5)] for k in range(5)]); gam=r.uniform(-0.4,0.4,5); gam-=gam.mean()
    tiles=[]; N=26; L=5.2
    for a_ in range(5):
        for b_ in range(a_+1,5):
            Ainv=np.linalg.inv(np.array([e[a_],e[b_]]))
            for ka in range(-N,N):
                for kb in range(-N,N):
                    p=Ainv@np.array([ka-gam[a_],kb-gam[b_]]); K=np.ceil(p@e.T+gam); K[a_]=ka; K[b_]=kb
                    bse=K@e; P=Polygon(np.array([bse,bse+e[a_],bse+e[a_]+e[b_],bse+e[b_]])*L+[W/2,H/2])
                    if P.intersects(box(0,0,W,H)): tiles.append(P.buffer(-0.62))
    return tiles
@reg('hex_truchet','六角トルシェ（円弧の流れ）','round','wave')
def _(W,H,r,s):
    a=4.0; bars=[]
    def f(x,y,i,j):
        rot=r.integers(0,2)*60
        V=[(x+a*np.cos(np.radians(60*k+30+rot)),y+a*np.sin(np.radians(60*k+30+rot))) for k in range(6)]
        for k in (0,2,4):
            c=V[k]; a0=np.degrees(np.arctan2(y-c[1],x-c[0]))
            t=np.radians(np.linspace(a0-60,a0+60,12)); bars.append(LineString(np.c_[c[0]+a/2*np.cos(t),c[1]+a/2*np.sin(t)]))
        return None
    grid(W,H,a*1.732,a*1.5,f,True)
    return bars_to_voids(W,H,bars,1.3)
@reg('poisson_disks','ランダム円充填','porthole','none')
def _(W,H,r,s):
    out=[]
    for k in range(5000):
        x,y=r.uniform(0,W),r.uniform(0,H); rr=r.choice([1.0,1.6,2.4,3.4])
        c=Point(x,y).buffer(rr,quad_segs=10)
        if all(c.distance(o)>1.3 for o in out): out.append(c)
        if len(out)>350: break
    return out
@reg('halftone','網点（ハーフトーン）','porthole','none')
def _(W,H,r,s):
    a=3.4; out=[]
    for i in range(int(W/a)):
        for j in range(int(H/a)):
            x,y=(i+0.5)*a,(j+0.5)*a; t=0.5+0.5*np.sin(x/14)*np.cos(y/9)
            rr=0.3+t*(a/2-1.1)
            if rr>0.5: out.append(Point(x,y).buffer(rr,quad_segs=8))
    return out
@reg('archimedes_spiral','アルキメデスのらせん','porthole','none')
def _(W,H,r,s):
    bars=[]
    for k in range(int(W/24)):
        cx=(k+0.5)*W/int(W/24); t=np.linspace(0,8*np.pi,600); rr=0.75*t
        bars.append(LineString(np.c_[cx+rr*np.cos(t),H/2+rr*np.sin(t)]))
    bars+=[LineString([(x,0),(x,H)]) for x in np.arange(0,W,W/int(W/24))]
    return bars_to_voids(W,H,bars,1.3)
@reg('fingerprint','指紋','round','none')
def _(W,H,r,s):
    dx=0.25; X,Y=np.meshgrid(np.arange(0,W,dx),np.arange(0,H,dx))
    f=np.zeros_like(X)
    for k in range(int(W/30)):
        cx=(k+0.5)*W/int(W/30); f+=np.exp(-((X-cx)**2+(Y-H/2)**2)/400)
    n=noise2(W,H,dx,25.0,r,2)
    g=np.sin(np.hypot((X-(W/2))*0.0+X%30-15,Y-H/2)*1.6+n*1.5)
    return raster(g>0.2,dx)
@reg('voronoi_gradient','ボロノイの粗密グラデーション','rect','none')
def _(W,H,r,s):
    pts=[]
    while len(pts)<420:
        x,y=r.uniform(0,W),r.uniform(0,H)
        if r.random()<(0.25+0.75*x/W): pts.append((x,y))
    return vor_cells(np.array(pts),W,H,0.62)
@reg('stained_glass','ステンドグラスの鉛線','lancet','gable')
def _(W,H,r,s):
    pts=np.c_[r.uniform(0,W,180),r.uniform(0,H,180)]
    return [c.buffer(-0.3).buffer(0.3,join_style='mitre') for c in vor_cells(pts,W,H,0.75)]
@reg('lancet_arcade','ゴシックの尖頭アーケード','lancet','pinnacle')
def _(W,H,r,s):
    out=[]; p=8.0
    for k in range(int(W/p)):
        cx=(k+0.5)*W/int(W/p); w=p-1.8
        out.append(lancet(cx,2,w,H-4-w*0.866))
    return out
@reg('zigzag_lightning','稲妻','pointed','none')
def _(W,H,r,s):
    bars=[]
    for x0 in np.arange(0,W,7.5):
        pts=[(x0,0)]; y=0
        while y<H: y+=r.uniform(3,6); pts.append((x0+r.uniform(-3,3),y))
        bars.append(LineString(pts))
    return [box(0,0,W,H).difference(U([b.buffer(0.9) for b in bars]))] if False else [p for b in bars for p in polys(b.buffer(1.1))]
@reg('dots_and_dashes','点と線のリズム','rect','none')
def _(W,H,r,s):
    out=[]
    for j,y in enumerate(np.arange(2,H-1,3.6)):
        x=1.0
        while x<W-2:
            if r.random()<0.6: out.append(Point(x+0.8,y).buffer(0.8,quad_segs=8)); x+=2.9
            else: L=r.uniform(3,9); out.append(box(x,y-0.8,x+L,y+0.8).buffer(0.0)); x+=L+1.4
    return out
@reg('origami_crane','折り鶴（三角形の折り線）','pointed','gable')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/26)):
        cx=(k+0.5)*W/int(W/26); cy=H/2
        P=[(cx+1.6*dx,cy+1.6*dy) for dx,dy in [(0,12),(3,2),(12,6),(4,-1),(0,-12),(-4,-1),(-12,6),(-3,2)]]
        for i in range(len(P)):
            out.append(Polygon([(cx,cy),P[i],P[(i+1)%len(P)]]).buffer(-0.65))
    return out
@reg('hexagram_lattice','籠目（かごめ編み）','pointed','gable')
def _(W,H,r,s):
    a=7.5; bars=[]
    for y in np.arange(-H,2*H,a*0.866): bars.append(LineString([(-5,y),(W+5,y)]))
    for x in np.arange(-H*2,W+H*2,a):
        bars.append(LineString([(x,-1),(x+H*1.2/1.732,H*1.2)])); bars.append(LineString([(x,-1),(x-H*1.2/1.732,H*1.2)]))
    return bars_to_voids(W,H,bars,1.3)
@reg('diagonal_lattice','斜め格子（菱目）','pointed','none')
def _(W,H,r,s):
    bars=[]
    for x in np.arange(-H,W+H,5.0): bars+= [LineString([(x,0),(x+H,H)]),LineString([(x,0),(x-H,H)])]
    return bars_to_voids(W,H,bars,1.3)
@reg('crosses','十字の連続','rect','none')
def _(W,H,r,s): return grid(W,H,7,7,lambda x,y,i,j:U([box(x-2.8,y-0.9,x+2.8,y+0.9),box(x-0.9,y-2.8,x+0.9,y+2.8)]),True)
@reg('stars_field','星の群れ','porthole','crest')
def _(W,H,r,s):
    out=[]
    for k in range(3000):
        x,y=r.uniform(2,W-2),r.uniform(2,H-2); R=r.uniform(1.4,3.4); st=star(x,y,R,R*0.45,5,90+r.uniform(-15,15))
        if all(st.distance(o)>1.3 for o in out): out.append(st)
        if len(out)>200: break
    return out
@reg('hearts','ハート','round','crest')
def _(W,H,r,s):
    def heart(cx,cy,R):
        t=np.linspace(0,2*np.pi,60); x=16*np.sin(t)**3; y=13*np.cos(t)-5*np.cos(2*t)-2*np.cos(3*t)-np.cos(4*t)
        return Polygon(np.c_[cx+x*R/17,cy+y*R/17])
    return grid(W,H,9,9,lambda x,y,i,j:heart(x,y,3.6),True)
@reg('keyholes','鍵穴','round','none')
def _(W,H,r,s): return grid(W,H,8,10,lambda x,y,i,j:U([Point(x,y+1.6).buffer(2.0),Polygon([(x-1.1,y+1),(x+1.1,y+1),(x+1.8,y-3.6),(x-1.8,y-3.6)])]),True)
@reg('music_staff','五線譜と音符','rect','none')
def _(W,H,r,s):
    fins=[]; notes=[]
    for y0 in (H*0.12,H*0.58):
        for k in range(5): fins.append(box(0.5,y0+k*2.8,W-0.5,y0+k*2.8+0.9))
        for x in np.arange(5,W-5,7.0):
            yy=y0+r.integers(0,5)*2.8+1.4
            head=A.rotate(A.scale(Point(x,yy).buffer(1.0,quad_segs=10),1.5,1.0),25)
            stem=box(x+1.0,yy,x+1.9,yy+8.5)
            notes.append(U([head,stem]))
    return notes,fins
@reg('city_grid','碁盤の目の街路図','rect','battlement')
def _(W,H,r,s):
    out=[]; x=0.6
    while x<W-2:
        w=r.choice([4.0,6.0,8.0]); y=0.6
        while y<H-2:
            h=r.choice([4.0,6.0,9.0]); out.append(box(x,y,x+w,min(y+h,H-0.6))); y+=h+r.choice([1.25,2.4])
        x+=w+r.choice([1.25,2.4])
    return out
@reg('waves_ocean','北斎の大波','ogee','wave')
def _(W,H,r,s):
    bars=[]
    for k in range(int(W/16)):
        x0=k*16; t=np.linspace(0,1,60)
        bars.append(LineString(np.c_[x0+16*t,H*0.25+H*0.45*np.sin(np.pi*t)**2]))
        c=(x0+12,H*0.62); tt=np.linspace(0,1.6*np.pi,60); rr=4.0*(1-tt/(2*np.pi))
        bars.append(LineString(np.c_[c[0]+rr*np.cos(tt),c[1]+rr*np.sin(tt)]))
        for d in (2,4,6): bars.append(LineString(np.c_[x0+16*t,H*0.25+H*0.45*np.sin(np.pi*t)**2-d]))
    bars+=[LineString([(0,0.6),(W,0.6)]),LineString([(0,H-0.6),(W,H-0.6)])]
    return bars_to_voids(W,H,bars,1.3)
@reg('clouds','瑞雲（雲の文様）','round','crest')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/14)):
        cx=(k+0.5)*W/int(W/14); cy=r.uniform(10,H-10)
        cl=U([Point(cx+dx,cy+dy).buffer(rr,quad_segs=10) for dx,dy,rr in [(-4,0,2.6),(-1,1.6,3.2),(2.6,0.6,2.8),(5,-0.4,2.0)]])
        out.append(cl.intersection(box(cx-9,cy-1.8,cx+9,cy+8)))
        out.append(LineString([(cx-8,cy-3),(cx+8,cy-3)]).buffer(0.8))
    return out
@reg('fireworks','花火','porthole','sunburst')
def _(W,H,r,s):
    out=[]
    for k in range(int(W/22)):
        cx=(k+0.5)*W/int(W/22); cy=r.uniform(14,H-14)
        for t in np.linspace(0,2*np.pi,14,endpoint=False):
            out.append(LineString([(cx+3*np.cos(t),cy+3*np.sin(t)),(cx+10*np.cos(t),cy+10*np.sin(t))]).buffer(0.7))
            out.append(Point(cx+12*np.cos(t),cy+12*np.sin(t)).buffer(0.9))
    return out
@reg('sakura','桜の花','round','crest')
def _(W,H,r,s):
    def flower(cx,cy,R):
        ps=[]
        for k in range(5):
            a=np.radians(72*k+90); c=(cx+R*0.55*np.cos(a),cy+R*0.55*np.sin(a))
            p=A.rotate(A.scale(Point(0,0).buffer(1,quad_segs=10),R*0.48,R*0.3),np.degrees(a),origin=(0,0))
            notch=Polygon([(R*0.35,0),(R*0.6,0.35*R*0.3),(R*0.6,-0.35*R*0.3)]); notch=A.rotate(notch,np.degrees(a),origin=(0,0))
            ps.append(A.translate(p.difference(notch),cx,cy))
        return ps
    return grid(W,H,13,11,lambda x,y,i,j:flower(x,y,5.2),True)
@reg('cogs_and_chains','鎖','round','none')
def _(W,H,r,s):
    bars=[]
    for row,y in enumerate(np.arange(5,H-3,9.0)):
        for k,x in enumerate(np.arange(-4+(row%2)*4.5,W+4,9.0)):
            bars.append(box(x,y-2.2,x+8.0,y+2.2).buffer(-1.2).buffer(1.2,quad_segs=8).exterior)
            bars.append(LineString([(x+6.0,y),(x+11.0,y)]))
    return bars_to_voids(W,H,bars,1.7)
@reg('arrows','矢印の流れ','pointed','none')
def _(W,H,r,s): return grid(W,H,8,7,lambda x,y,i,j:Polygon([(x-3,y-1),(x+0.5,y-1),(x+0.5,y-2.4),(x+3.4,y),(x+0.5,y+2.4),(x+0.5,y+1),(x-3,y+1)]),True)
@reg('plus_minus','プラスとマイナス','rect','none')
def _(W,H,r,s): return grid(W,H,6,6,lambda x,y,i,j:U([box(x-2.2,y-0.8,x+2.2,y+0.8)]+([box(x-0.8,y-2.2,x+0.8,y+2.2)] if (i+j)%2 else [])))
@reg('tetris','落ち物ブロック','rect','battlement')
def _(W,H,r,s):
    shapes=[[(0,0),(1,0),(2,0),(3,0)],[(0,0),(1,0),(0,1),(1,1)],[(0,0),(1,0),(2,0),(1,1)],[(0,0),(1,0),(1,1),(2,1)],[(0,0),(0,1),(0,2),(1,0)]]
    a=2.6; out=[]
    for k in range(400):
        sh=shapes[r.integers(len(shapes))]; x,y=r.integers(0,int(W/a)),r.integers(0,int(H/a))
        g=U([box((x+i)*a+0.65,(y+j)*a+0.65,(x+i+1)*a-0.65,(y+j+1)*a-0.65).buffer(0.66,join_style='mitre') for i,j in sh]).buffer(-0.01)
        g=g.buffer(-0.0)
        if g.within(box(0,0,W,H)) and all(g.distance(o)>1.3 for o in out): out.append(g.buffer(-0.66+0.01,join_style='mitre'))
    return out
@reg('cells_biology','生物の細胞','round','none')
def _(W,H,r,s):
    pts=np.c_[r.uniform(0,W,160),r.uniform(0,H,160)]
    out=[]
    for c in vor_cells(pts,W,H,0.75):
        c=c.buffer(-0.8).buffer(0.8,quad_segs=8)
        nuc=Point(c.centroid).buffer(1.0)
        out+=polys(c.difference(nuc.buffer(0.65)))
    return out
@reg('neurons','神経細胞のネットワーク','round','none')
def _(W,H,r,s):
    pts=np.c_[r.uniform(2,W-2,45),r.uniform(2,H-2,45)]
    tri=Delaunay(pts); bars=[]
    for t in tri.simplices:
        for a,b in ((t[0],t[1]),(t[1],t[2])):
            p,q=pts[a],pts[b]; m=(p+q)/2+r.normal(0,1.5,2)
            bars.append(LineString([p,m,q]))
    V=box(0,0,W,H).difference(U([b.buffer(0.7) for b in bars]+[Point(p).buffer(2.0) for p in pts]))
    return [V]
@reg('molecules','分子構造（ベンゼン環）','porthole','none')
def _(W,H,r,s):
    a=4.0
    def f(x,y,i,j): return [reg_poly(x,y,a-0.7,6,30).difference(reg_poly(x,y,a*0.55,6,30).exterior.buffer(0.65))]
    return grid(W,H,a*1.732*1.3,a*1.5*1.3,f,True)
