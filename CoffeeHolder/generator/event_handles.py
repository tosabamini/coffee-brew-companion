"""イベント記念の持ち手（H131〜）。CML Horizons 2026 で手渡す相手の国にちなむ。

H131 北マケドニア：国旗の太陽（8本の光が外へ広がる）。円盤の中心が指穴、カップ側の光3本で本体につなぐ
H132 ケニア      ：国旗にも描かれるマサイの盾。D型の握りで、両面に盾の模様を彫る
H133 ジンバブエ  ：国章のジンバブエ・バード（グレート・ジンバブエの石彫りの鳥）が柱にとまる。
                   柱の両面にグレート・ジンバブエの石壁のシェブロン（山形）模様を彫る

どれも xz 平面の輪郭を厚み方向（y）に押し出した板。縁は 0.7 mm 段を付けて角を和らげる。
カップと重なる部分は build.py 側で hkit.clip が削る。
"""
import numpy as np, shapely.affinity as SA
from shapely.geometry import Polygon, Point, LineString, box
from shapely.ops import unary_union
import manifold3d as mf
from hkit import ri, catmull
import common as cm

EH = {}
def reg(name, jp):
    def d(f): EH[name] = (f, jp); return f
    return d

def U2(gs):
    gs = [g for g in gs if g is not None and not g.is_empty]
    return unary_union(gs) if gs else Polygon()

def _ext(g, y0, y1):
    """shapely の (x,z) 多角形を y0〜y1 に押し出す"""
    rings = []
    for p in cm.polys_of(g.buffer(0)):
        if p.area < 0.05: continue
        rings.append(np.asarray(p.exterior.coords)[:-1])
        rings += [np.asarray(i.coords)[:-1] for i in p.interiors]
    if not rings: return mf.Manifold()
    cs = mf.CrossSection(rings, mf.FillRule.EvenOdd)
    m = cs.extrude(y1 - y0).rotate((90, 0, 0))     # (x,y,z)->(x,-z,y): 押し出しは -y 向き
    return m.translate((0, y1, 0))

def soft_plate(outline, t=7.0, step=0.7, grooves=None, groove_depth=0.8):
    """縁に段を付けた板。grooves は両面に彫る溝（xz の多角形）"""
    core = _ext(outline, -t / 2 + step, t / 2 - step)
    face = outline.buffer(-step, join_style='round')
    parts = [core, _ext(face, t / 2 - step - 0.05, t / 2), _ext(face, -t / 2, -t / 2 + step + 0.05)]
    m = mf.Manifold.batch_boolean(parts, mf.OpType.Add)
    if grooves is not None and not grooves.is_empty:
        g = grooves.intersection(face.buffer(-0.4))
        cut = U2([g])
        m = m - _ext(cut, t / 2 - groove_depth, t / 2 + 1) - _ext(cut, -t / 2 - 1, -t / 2 + groove_depth)
    return m

def wall_edge(z): return ri(z) + 0.2      # 本体の壁（ri〜ri+1.5）に食い込ませる位置

def arm(z0, z1, x1):
    """カップの壁から x1 までの腕"""
    zz = np.linspace(z0, z1, 8)
    return Polygon([(wall_edge(z), z) for z in zz] + [(x1, z1), (x1, z0)])

def smooth_poly(pts, n=10):
    P = catmull(np.asarray(pts, float), n=n, closed=True)
    return Polygon(P[:, :2] if P.shape[1] == 2 else P[:, [0, 1]]).buffer(0)

# ------------------------------------------------------------------ H131 北マケドニア
@reg('mk_sun', '北マケドニアの太陽（8本の光）')
def mk_sun():
    cx, cz = 48.5, 39.5
    R_disc, R_hole, R_ray = 12.4, 9.4, 21.0
    disc = Point(cx, cz).buffer(R_disc, quad_segs=48)
    rays = []
    for k in range(8):
        a = np.radians(22.5 + 45 * k)            # 国旗と同じく斜め方向にも光が出る配置
        d = np.array([np.cos(a), np.sin(a)]); n = np.array([-d[1], d[0]])
        r1 = R_ray if np.cos(a) > -0.3 else 24.0  # カップ側の光は壁まで届かせる
        p0 = np.array([cx, cz]) + d * (R_disc - 1.0); p1 = np.array([cx, cz]) + d * r1
        w0, w1 = 2.0, 4.4                         # 外へ行くほど広がる
        ray = Polygon([p0 + n * w0, p1 + n * w1, p1 - n * w1, p0 - n * w0]).buffer(0.9, quad_segs=6).buffer(-0.6)
        rays.append(ray)
    # 真横（カップ側）にも太い光を1本：本体との主な接合
    rays.append(Polygon([(cx - R_disc + 1, cz - 3.2), (wall_edge(cz - 4.5), cz - 4.5), (wall_edge(cz + 4.5), cz + 4.5), (cx - R_disc + 1, cz + 3.2)]))
    outline = U2([disc] + rays).difference(Point(cx, cz).buffer(R_hole, quad_segs=48))
    outline = outline.intersection(box(0, 15.5, 200, 63.5))
    grooves = Point(cx, cz).buffer(R_disc - 1.2, quad_segs=48).difference(Point(cx, cz).buffer(R_disc - 1.9, quad_segs=48))
    return soft_plate(outline, 7.0, grooves=grooves, groove_depth=0.6)

# ------------------------------------------------------------------ H132 ケニア
def lens(cx, cz, hw, hh, n=80):
    t = np.linspace(-1, 1, n)
    right = np.c_[cx + hw * (1 - t ** 2) ** 0.85, cz + hh * t]
    left = np.c_[cx - hw * (1 - t ** 2) ** 0.85, cz - hh * t]
    return Polygon(np.vstack([right, left])).buffer(0)

@reg('ke_shield', 'ケニアのマサイの盾')
def ke_shield():
    cx, cz, hw, hh = 57.5, 39.5, 8.6, 23.0
    shield = lens(cx, cz, hw, hh)
    arms = [arm(50.0, 56.0, cx - 2), arm(22.5, 28.5, cx - 2)]
    outline = U2([shield] + arms).buffer(1.2, quad_segs=8).buffer(-1.2, quad_segs=8)
    # 盾の模様：内側の輪郭、中央の縦の筋、中央のレンズ形、上下の三角模様
    inner = lens(cx, cz, hw - 1.9, hh - 3.2); inner2 = lens(cx, cz, hw - 2.7, hh - 4.4)
    grooves = [inner.difference(inner2),
               lens(cx, cz, 2.6, 7.0).difference(lens(cx, cz, 1.7, 5.6)),
               box(cx - 0.35, cz + 7.6, cx + 0.35, cz + hh - 5.2), box(cx - 0.35, cz - hh + 5.2, cx + 0.35, cz - 7.6)]
    for s in (1, -1):
        for k in range(3):
            zc = cz + s * (10.5 + 3.4 * k)
            tri = Polygon([(cx - 3.2 + k * 0.5, zc), (cx - 1.0, zc + s * 1.4), (cx - 1.0, zc - s * 1.4)])
            grooves += [tri, SA.scale(tri, -1, 1, origin=(cx, cz))]
    return soft_plate(outline, 7.0, grooves=U2(grooves), groove_depth=0.7)

# ------------------------------------------------------------------ H133 ジンバブエ
@reg('zw_bird', 'ジンバブエ・バードと石壁のシェブロン')
def zw_bird():
    x0, x1 = 49.0, 58.0                         # 柱
    column = box(x0, 21.0, x1, 52.0)
    arms = [arm(47.0, 53.0, x0 + 1), arm(21.0, 27.0, x0 + 1)]
    # 柱の上にとまる鳥（外向き。長い首と小さな頭、くちばし、背に沿って下がる尾）
    bird = smooth_poly([(49.6, 51.5), (47.6, 54.0), (48.4, 58.0), (49.6, 61.6), (50.6, 64.6), (51.0, 67.4), (52.8, 69.2), (55.2, 69.0), (59.4, 67.9), (61.4, 66.7), (57.6, 66.2), (55.8, 64.8), (55.6, 62.6), (58.4, 59.6), (59.2, 55.6), (57.6, 51.5)], n=8)
    outline = U2([column, bird] + arms).buffer(1.0, quad_segs=8).buffer(-1.0, quad_segs=8)
    # 柱：グレート・ジンバブエの石壁のシェブロン（山形）を彫る
    grooves = []
    for z in np.arange(25.0, 49.0, 3.4):
        xs = np.linspace(x0 + 1.2, x1 - 1.2, 5)
        zs = z + np.array([0, 1.3, 0, 1.3, 0])
        grooves.append(LineString(np.c_[xs, zs]).buffer(0.45, cap_style='flat', join_style='mitre'))
    grooves.append(Point(54.0, 67.2).buffer(0.75))           # 目
    grooves.append(LineString([(49.4, 60.5), (52.2, 57.0), (56.6, 55.0)]).buffer(0.4))   # 翼の線
    grooves.append(LineString([(50.2, 63.0), (53.0, 59.6), (57.2, 57.4)]).buffer(0.4))
    return soft_plate(outline, 7.0, grooves=U2(grooves), groove_depth=0.7)
