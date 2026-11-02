"""イベント記念の柄（B165〜）。

B165 CML Horizons 2026（ジョージア・トビリシ, 2026年11月13〜15日）
  個人が参加者との交流で手渡すための記念品（非商用）。公式ロゴは使わず、オリジナルの図案にしている。
  - 全周の下側：コーカサスの山なみ（透かし）＝ "Horizons"（地平線）
  - 正面（持ち手を右にしたとき見える面）：山の稜線から昇るボルジガリ（ジョージアの太陽の紋、7本の腕）
  - 反対側：浮き出し文字 "CML HORIZONS 2026" / 合言葉 "LEARN · SHARE · GROW" / "TBILISI · თბილისი"
  - 文字の間：芽（GROW）と、白血病の啓発色リボンの輪郭
  座標は lib100.wall に渡される展開図（幅 W≈178.6 mm, 高さ H≈42.1 mm, x=0 が持ち手の右側）。
"""
import numpy as np, shapely.affinity as A
from shapely.geometry import Polygon, box, Point, LineString
from shapely.ops import unary_union
from matplotlib.textpath import TextPath
from matplotlib.font_manager import FontProperties
import common as cm

EB = {}
def reg(name, jp):
    def d(f): EB[name] = (f, jp); return f
    return d

def U(gs):
    gs = [g for g in gs if g is not None and not g.is_empty]
    return unary_union(gs) if gs else Polygon()

FONT_LATIN = '/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf'
FONT_KA = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'   # ジョージア文字（ムヘドルリ）を含む

def text_poly(text, size, font, cx, cy, track=0.0):
    """文字をベクトルの多角形にする。size=大文字の高さの目安(mm)。(cx,cy) に中央揃え"""
    fp = FontProperties(fname=font)
    g = Polygon(); x = 0.0
    for ch in text:
        if ch == ' ':
            x += size * 0.32 + track; continue
        tp = TextPath((x, 0), ch, size=size * 1.38, prop=fp)
        rings = [Polygon(r) for r in tp.to_polygons() if len(r) >= 3]
        cg = Polygon()
        for r in rings: cg = cg.symmetric_difference(r.buffer(0))
        g = g.union(cg)
        adv = TextPath((0, 0), ch, size=size * 1.38, prop=fp).get_extents().x1
        x += max(adv, size * 0.3) + track
    b = g.bounds
    return A.translate(g, cx - (b[0] + b[2]) / 2, cy - (b[1] + b[3]) / 2)

def fit_width(g, w):
    b = g.bounds; s = min(1.0, w / (b[2] - b[0]))
    return A.scale(g, s, s, origin=((b[0] + b[2]) / 2, (b[1] + b[3]) / 2))

def ridge(W, rng):
    """コーカサスの稜線 y(x)。全周でつながるよう周期的に作る"""
    xs = np.linspace(0, W, 400)
    y = 9.0 + 2.2 * np.sin(xs / W * 2 * np.pi * 3 + 0.6) + 1.4 * np.sin(xs / W * 2 * np.pi * 7 + 1.9)
    # 鋭い峰（カズベギ山のような高い峰をいくつか）
    for p, h, w in ((22, 4.0, 9), (58, 2.8, 7), (96, 3.4, 8), (138, 5.0, 10), (170, 3.0, 7)):
        y += h * np.clip(1 - np.abs(xs - p) / w, 0, 1) ** 1.3
    return xs, y

def borjgali(cx, cy, R, arms=7, rot=0.0):
    """ボルジガリ：中心の円と、そのまわりで同じ向きに渦を巻く7本の腕（それぞれ独立した穴）"""
    out = [Point(cx, cy).buffer(R * 0.17, quad_segs=16)]
    for k in range(arms):
        a0 = rot + 2 * np.pi * k / arms
        t = np.linspace(0, 1, 48)
        r = R * (0.36 + 0.64 * t)
        a = a0 + 0.55 * t + 0.45 * t ** 2.5        # 先端ほど強く巻く（巻きすぎると隣の腕との桟が細くなる）
        w = R * (0.03 + 0.075 * np.sin(np.pi * np.clip(t * 0.92, 0, 1)) ** 0.7)   # 半幅
        P = np.c_[cx + r * np.cos(a), cy + r * np.sin(a)]
        d = np.gradient(P, axis=0); d /= np.linalg.norm(d, axis=1)[:, None]
        n = np.c_[-d[:, 1], d[:, 0]]
        arm = Polygon(np.vstack([P + n * w[:, None], (P - n * w[:, None])[::-1]])).buffer(0)
        out.append(arm.buffer(0.15, quad_segs=6))
    return out

def ribbon(cx, cy, s=1.0):
    """啓発リボン：上で輪になり、中央で交差して2本の端が下へ（線を浮き出しに）"""
    from scipy.interpolate import splprep, splev
    P = np.array([(-3.4, -6.6), (-1.4, -2.6), (0, 0), (1.9, 3.0), (2.0, 5.6), (0, 7.2),
                  (-2.0, 5.6), (-1.9, 3.0), (0, 0), (1.4, -2.6), (3.4, -6.6)]) * s
    tck, _ = splprep([P[:, 0], P[:, 1]], s=0, k=3)
    x, y = splev(np.linspace(0, 1, 160), tck)
    return LineString(np.c_[cx + x, cy + y]).buffer(0.62, cap_style='flat')

def sprout(cx, cy, s=1.0):
    """芽（GROW）：茎と2枚の葉（穴）"""
    leaf = lambda ang: A.rotate(A.scale(Point(0, 0).buffer(1, quad_segs=16), 3.0 * s, 1.35 * s), ang, origin=(0, 0))
    l1 = A.translate(leaf(35), cx + 2.6 * s, cy + 5.6 * s)
    l2 = A.translate(leaf(-35), cx - 2.6 * s, cy + 5.6 * s)
    stem = LineString([(cx, cy), (cx, cy + 4.2 * s)]).buffer(0.75 * s, cap_style='flat')
    return [l1, l2, stem]

def row(parts, cx, cy, gap):
    """横に並べて中央揃え（parts は中央(0,0)基準の多角形）"""
    ws = [g.bounds[2] - g.bounds[0] for g in parts]
    x = cx - (sum(ws) + gap * (len(parts) - 1)) / 2; out = []
    for g, w in zip(parts, ws):
        b = g.bounds
        out.append(A.translate(g, x - b[0], cy - (b[1] + b[3]) / 2)); x += w + gap
    return out

@reg('cml_horizons_2026', 'CML Horizons 2026（トビリシ）')
def cml_horizons_2026(W, H, rng, s):
    holes, fins = [], []
    xs, y = ridge(W, rng)
    yr = lambda x: float(np.interp(x, xs, y))

    # 1) 山なみ（透かし）：稜線の 1.6 mm 下から下端まで。持ち手のそばは少し空ける
    base = -2.0
    # 稜線の下 1.6〜6.6 mm の帯だけを抜く（下は壁を残して強度を確保。光が稜線の形に抜ける）
    lower = np.maximum(y - 6.6 - 0.8 * np.sin(xs / 9.0), 1.0)
    mtn = Polygon(list(zip(xs, y - 1.6)) + list(zip(xs[::-1], lower[::-1]))).buffer(0).intersection(box(3.0, base, W - 3.0, H))
    # 一続きの長い穴にならないよう、細い柱で区切る（強度と見た目のリズム）
    cuts = [box(x - 0.8, base - 1, x + 0.8, H) for x in (20, 46, 76, 100, 118, 160)]
    holes += cm.polys_of(mtn.difference(U(cuts)))
    fins.append(LineString(list(zip(xs, y))).buffer(0.55))      # 稜線は浮き出しの線

    # 2) 正面（持ち手を右にしたとき見える面, x≈138）：稜線から昇るボルジガリ
    cxs, R = 138.0, 11.5
    cys = yr(cxs) + R * 0.66
    below = lambda dy: Polygon(list(zip(xs, y + dy)) + [(W, base), (0, base)])
    sun = U(borjgali(cxs, cys, R, rot=0.3)).difference(below(1.4))
    holes += cm.polys_of(sun)
    fins.append(Point(cxs, cys).buffer(R + 1.9, quad_segs=48).difference(Point(cxs, cys).buffer(R + 1.0, quad_segs=48)).difference(below(0.9)))
    for a in np.radians(np.arange(20, 170, 20)):                 # 光
        p0 = (cxs + (R + 3.2) * np.cos(a), cys + (R + 3.2) * np.sin(a))
        p1 = (cxs + (R + 5.4) * np.cos(a), cys + (R + 5.4) * np.sin(a))
        if p1[1] < H - 0.6: fins.append(LineString([p0, p1]).buffer(0.5))

    # 3) 反対側（x≈40.6, 持ち手を左にしたとき見える面）：文字（浮き出し）
    cxt = 40.6; wmax = 66.0
    fins.append(fit_width(text_poly('CML HORIZONS', 6.2, FONT_LATIN, cxt, 34.8, track=0.3), wmax))
    fins.append(box(cxt - wmax / 2, 30.4, cxt + wmax / 2, 31.0))
    fins.append(fit_width(text_poly('LEARN · SHARE · GROW', 3.2, FONT_LATIN, cxt, 26.6, track=0.4), wmax * 0.94))
    l3 = row([text_poly('TBILISI 2026', 3.3, FONT_LATIN, 0, 0, track=0.35), Point(0, 0).buffer(0.7),
              text_poly('თბილისი', 3.6, FONT_KA, 0, 0, track=0.15)], cxt, 20.6, 2.2)
    fins += l3

    # 4) 文字と太陽の間・太陽の向こう：芽（穴）とリボン（浮き出し）
    holes += sprout(88.0, yr(88.0) + 1.0, 1.1)
    fins.append(ribbon(107.0, 26.0, 1.15))
    holes += sprout(165.0, yr(165.0) + 1.0, 1.0)
    return holes, fins
