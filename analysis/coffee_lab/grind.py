"""挽き目（粒度分布）の解析。

下から光を当てた写真（粉が黒い影、背景が白）を前提にする。
  1. 青チャンネル（茶色の粉と白い背景の差がいちばん大きい）を使う。背景が赤・緑・青などのときはその色のチャンネル
  2. 背景の明るさのムラを推定して割り算し、明るさをそろえる
  3. 背景の threshold 倍より暗い画素を粒とみなす
  4. つながった画素のかたまりを1粒とし、面積・長径・短径を測る
  5. 画像の端や光の当たっていない所にかかる粒、小さすぎる粒、大きすぎる塊を除く
体積は Gagné（coffeegrindsize）にならい、厚みを短径と同じとみなした楕円体で近似する。
"""
import json
import math
import os

import cv2
import numpy as np

from common import imread


def _background(gray):
    """粒を消した背景の明るさを推定する（縮小 → 閉じ処理で暗い粒を埋める → ぼかし → 元の大きさ）。"""
    h, w = gray.shape
    scale = 8
    small = cv2.resize(gray, (max(1, w // scale), max(1, h // scale)), interpolation=cv2.INTER_AREA)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (21, 21))
    closed = cv2.morphologyEx(small, cv2.MORPH_CLOSE, k)
    closed = cv2.GaussianBlur(closed, (0, 0), 6)
    return cv2.resize(closed, (w, h), interpolation=cv2.INTER_LINEAR).astype(np.float32)


def _hmax_seeds(dist, h):
    """距離変換の「山」のうち、まわりより h 以上高いものだけを残す（h-maxima）。山 1 つ＝粒の中心 1 つ。"""
    marker = np.maximum(dist - h, 0).astype(np.float32)
    k = np.ones((3, 3), np.uint8)
    for _ in range(1000):
        nxt = np.minimum(cv2.dilate(marker, k), dist)
        if np.array_equal(nxt, marker):
            break
        marker = nxt
    return ((dist - marker) >= h - 1e-3).astype(np.uint8)


def _split_touching(mask, h_frac=0.2, h_min=2.0, solidity_max=0.93):
    """くっついた粒を分ける。へこみのある塊だけを対象に、距離変換の山（粒の中心）を種にして watershed で分け、
    境目に細い切れ目を入れる。山の高さの差が小さいもの（同じ粒のでこぼこ）は分けない。"""
    out = mask.copy()
    n, lab, st, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    k3 = np.ones((3, 3), np.uint8)
    for i in range(1, n):
        x, y, w, h, area = st[i]
        if area < 200:
            continue
        crop = (lab[y:y + h, x:x + w] == i).astype(np.uint8)
        pad = cv2.copyMakeBorder(crop, 2, 2, 2, 2, cv2.BORDER_CONSTANT, value=0)
        cnts, _ = cv2.findContours(pad, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        c = max(cnts, key=cv2.contourArea)
        if cv2.contourArea(c) / max(cv2.contourArea(cv2.convexHull(c)), 1.0) > solidity_max:
            continue                                   # へこみがない＝1粒
        dist = cv2.distanceTransform(pad, cv2.DIST_L2, 5)
        seeds = _hmax_seeds(dist, max(h_min, h_frac * float(dist.max())))
        k, markers = cv2.connectedComponents(seeds)
        if k <= 2:
            continue                                   # 中心が1つ＝1粒
        markers = markers.astype(np.int32)
        markers[pad == 0] = k                          # 背景
        sm = cv2.GaussianBlur(dist, (0, 0), 1.5)       # 平らな所で境目が直線（格子に沿った四角）にならないように
        img = (255 * (1 - sm / max(float(sm.max()), 1e-6))).astype(np.uint8)
        cv2.watershed(cv2.merge([img, img, img]), markers)
        obj = np.where((markers > 0) & (markers < k), markers, 0).astype(np.float32)
        nb_max = cv2.dilate(obj, k3)
        nb_min = cv2.erode(np.where(obj > 0, obj, 1e6).astype(np.float32), k3)
        cut = (markers == -1) & (pad > 0) & (nb_max > 0) & (nb_min < 1e6) & (nb_max != nb_min)
        cut = cv2.dilate(cut.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_CROSS, (3, 3))) > 0
        cut = cut[2:-2, 2:-2] & (crop > 0)
        dist = dist[2:-2, 2:-2]
        pieces = (crop > 0) & ~cut
        pn, plab, pst, _ = cv2.connectedComponentsWithStats(pieces.astype(np.uint8), connectivity=8)
        if pn <= 2:
            continue                                   # 結局 1 つ＝切らない
        # 切れ目がくびれになっていないもの（境目が両側の粒の太さに比べて長い）は、1粒の中の切れ目なので戻す
        width = [2.0 * float(dist[plab == j].max()) if pst[j, 4] else 0.0 for j in range(pn)]
        sn, slab = cv2.connectedComponents(cut.astype(np.uint8), connectivity=8)
        for j in range(1, sn):
            seg = slab == j
            ys, xs = np.nonzero(seg)
            (_, _), (rw, rh), _ = cv2.minAreaRect(np.column_stack([xs, ys]).astype(np.float32))
            length = max(rw, rh)
            near = set(np.unique(plab[cv2.dilate(seg.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0])) - {0}
            if len(near) < 2 or (len(near) == 2 and length > 1.0 * min(width[t] for t in near)):
                cut[seg] = False
        pieces = (crop > 0) & ~cut
        pn, plab, pst, _ = cv2.connectedComponentsWithStats(pieces.astype(np.uint8), connectivity=8)
        if pn <= 2:
            continue
        # 切った結果の小さすぎるかけら（山のでこぼこが作った切れ目）は、となりに戻す
        # 小さすぎるかけら（山のでこぼこが作った切れ目）と、外側の輪郭に接していないかけら（輪になった切れ目）は、となりに戻す
        small_lim = max(150, 0.08 * area)
        rim = (crop > 0) & (cv2.erode(crop, k3) == 0)          # もとの塊の外周
        for j in range(1, pn):
            pj = plab == j
            if pst[j, 4] < small_lim or not (pj & rim).any():
                near = cv2.dilate(pj.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
                cut[near] = False
        # 何も分けていない切れ目（行き止まり）を消す：両側に別々のかけらがある所だけ残す
        pieces = (crop > 0) & ~cut
        pn, plab = cv2.connectedComponents(pieces.astype(np.uint8), connectivity=8)
        if pn <= 2:
            continue
        pl = plab.astype(np.float32)
        hi = cv2.dilate(pl, np.ones((5, 5), np.uint8))
        lo = cv2.erode(np.where(pl > 0, pl, 1e6).astype(np.float32), np.ones((5, 5), np.uint8))
        cut &= (hi > 0) & (lo < 1e6) & (hi != lo)
        out[y:y + h, x:x + w][cut] = 0
    return out


def _pick_channel(img):
    """使う色のチャンネル。背景が白っぽければ青（茶色の粉と白の差がいちばん大きい）、
    背景が赤・緑・青などの色なら、その色のチャンネル（ほかのチャンネルは背景も暗く、粒と区別できない）。"""
    small = cv2.resize(img, (max(1, img.shape[1] // 16), max(1, img.shape[0] // 16)), interpolation=cv2.INTER_AREA)
    lit = np.percentile(small.reshape(-1, 3), 90, axis=0)       # 背景の明るさ（B, G, R）
    if lit.min() > 0.6 * lit.max():
        return 0
    return int(np.argmax(lit))


def um_per_px(path, cfg):
    """1画素の大きさ（µm）。um_per_px_zoom1（ズーム1倍・トレイの面での値）があれば、
    写真と同じ名前の .json に記録されたズームで割る（S20 のズームは画像の切り出しなので比例する）。"""
    base = cfg.get("um_per_px_zoom1")
    if base:
        try:
            with open(os.path.splitext(path)[0] + ".json", encoding="utf-8") as f:
                z = float(json.load(f).get("zoom") or 1.0)
            return float(base) / max(z, 1e-6)
        except (OSError, ValueError, TypeError):
            pass
    return float(cfg["um_per_px"])


BLANK_GROUP = "blank"      # 空のトレイの写真の条件名（blank_01.jpg など）


def is_blank(path):
    stem = os.path.splitext(os.path.basename(path))[0]
    return stem == BLANK_GROUP or stem.startswith(BLANK_GROUP + "_")


def find_blank(path):
    """同じフォルダの空のトレイの写真のうち、この写真より前に撮った最新のもの（なければ最新のもの）。"""
    if is_blank(path):
        return None
    folder = os.path.dirname(os.path.abspath(path))
    try:
        cands = [os.path.join(folder, n) for n in os.listdir(folder)
                 if is_blank(n) and n.lower().endswith((".jpg", ".jpeg", ".png"))]
    except OSError:
        return None
    if not cands:
        return None
    t = os.path.getmtime(path)
    before = [c for c in cands if os.path.getmtime(c) <= t + 1]
    return max(before or cands, key=os.path.getmtime)


def _dirt_mask(blank_img, ch):
    """空のトレイの写真に写っている汚れ・傷・ほこり（背景よりわずかでも暗い所）。"""
    gray = blank_img[:, :, ch].astype(np.float32)
    bg = _background(gray)
    norm = gray / np.maximum(bg, 1.0)
    lit = bg > 0.5 * np.percentile(bg, 90)                 # 光が当たっている範囲だけ（箱のふちの影は除く）
    m = ((norm < 0.85) & lit).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    return cv2.dilate(m, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))), norm


def _estimate_shift(norm_a, norm_b):
    """トレイを出し入れしたときのずれ（画素）。汚れの模様どうしの位相相関で求める。"""
    def hp(n):
        x = np.clip(1.0 - n, 0, 1).astype(np.float32)
        x = cv2.resize(x, (x.shape[1] // 2, x.shape[0] // 2), interpolation=cv2.INTER_AREA)
        return x - cv2.GaussianBlur(x, (0, 0), 8)
    a, b = hp(norm_a), hp(norm_b)
    win = cv2.createHanningWindow((a.shape[1], a.shape[0]), cv2.CV_32F)
    (dx, dy), resp = cv2.phaseCorrelate(a, b, win)
    if resp < 0.03 or abs(dx) > 60 or abs(dy) > 60:
        return None
    return dx * 2, dy * 2


def analyze_image(path, cfg):
    g = cfg["grind"]
    umpp = um_per_px(path, cfg)
    img = imread(path)
    ch = _pick_channel(img)
    gray = img[:, :, ch].astype(np.float32)
    bg = _background(gray)
    # 皮（シルバースキン）の見分け用：白い背景のときだけ、赤と青の透け方を求める
    chaff_on = bool(g.get("exclude_chaff", True)) and ch == 0
    if chaff_on:
        t_red = img[:, :, 2].astype(np.float32) / np.maximum(_background(img[:, :, 2].astype(np.float32)), 1.0)
        t_blue = gray / np.maximum(bg, 1.0)
    lit_level = np.percentile(bg, 90)
    valid = (bg > 0.5 * lit_level).astype(np.uint8)  # 光が当たっている範囲
    valid = cv2.erode(valid, cv2.getStructuringElement(cv2.MORPH_RECT, (15, 15)))
    norm = gray / np.maximum(bg, 1.0)
    # 空のトレイの写真があれば、そこに写っている汚れ・傷を除く（トレイの出し入れのずれも考える）
    dirt_masks = []
    blank_problem = None
    blank_path = find_blank(path) if g.get("use_blank", True) else None
    if blank_path:
        try:
            bimg = imread(blank_path)
            if bimg.shape != img.shape:
                blank_problem = "空のトレイの写真と大きさが違います（ズームを変えたら撮り直してください）"
                blank_path = None
            elif (_dirt_mask(bimg, ch)[0][valid > 0] > 0).mean() > 0.08:
                blank_problem = "空のトレイの写真に暗い所が多すぎます（粉が残っていませんか）。トレイをきれいにして撮り直してください"
                blank_path = None
            else:
                dm, bnorm = _dirt_mask(bimg, ch)
                dirt_masks.append(dm)                    # 画面のほこりなど、動かないもの
                sh = _estimate_shift(bnorm, norm)
                if sh is not None and (abs(sh[0]) > 1 or abs(sh[1]) > 1):
                    M = np.float32([[1, 0, sh[0]], [0, 1, sh[1]]])
                    dirt_masks.append(cv2.warpAffine(dm, M, (dm.shape[1], dm.shape[0])))   # トレイの傷（トレイと一緒に動く）
        except ValueError:
            blank_path = None
    mask = ((norm < g["threshold"]) & (valid > 0)).astype(np.uint8) * 255
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3)))
    if g.get("split_touching"):
        mask = _split_touching(mask)

    # 画像の端・光の当たっていない所にかかる粒を除くため、その帯をラベル付けに含めて判定する
    border = np.zeros_like(mask)
    border[(valid == 0)] = 1
    border[:2, :] = border[-2:, :] = 1
    border[:, :2] = border[:, -2:] = 1
    border = cv2.dilate(border, np.ones((3, 3), np.uint8))

    n, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    touches = np.zeros(n, bool)
    touches[np.unique(labels[(border > 0) & (labels > 0)])] = True

    particles, n_small, n_big, n_edge = [], 0, 0, 0
    n_chaff, chaff_px = 0, 0
    n_dirt = 0
    dirt_max_px = math.pi / 4 * (g.get("dirt_max_um", 1000) / umpp) ** 2   # これより大きいものは汚れとみなさない
    rejected = []          # 測らなかったもの（理由, 輪郭）…詳しい確認用画像に使う

    def _contour(i, x, y, w, h):
        crop = (labels[y:y + h, x:x + w] == i).astype(np.uint8)
        cnts, _ = cv2.findContours(crop, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        return max(cnts, key=cv2.contourArea), crop
    min_short = float(g["min_short_px"])
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if touches[i]:
            n_edge += 1
            if area >= 30:
                c, _ = _contour(i, x, y, w, h)
                rejected.append(("edge", (c + np.array([[x, y]])).astype(np.int32)))
            continue
        if dirt_masks and area <= dirt_max_px:
            obj = labels[y:y + h, x:x + w] == i
            if any((dm[y:y + h, x:x + w][obj] > 0).mean() >= 0.6 for dm in dirt_masks):
                n_dirt += 1
                if area >= 30:
                    c, _ = _contour(i, x, y, w, h)
                    rejected.append(("dirt", (c + np.array([[x, y]])).astype(np.int32)))
                continue
        if area < 6:
            n_small += 1
            continue
        c, crop = _contour(i, x, y, w, h)
        (_, _), (rw, rh), _ = cv2.minAreaRect(c)
        long_px, short_px = max(rw, rh, 1.0), max(min(rw, rh), 1.0)
        if short_px < min_short:
            n_small += 1
            rejected.append(("small", (c + np.array([[x, y]])).astype(np.int32)))
            continue
        ecd_um = math.sqrt(4 * area / math.pi) * umpp
        if ecd_um > g["max_ecd_um"]:
            n_big += 1
            rejected.append(("big", (c + np.array([[x, y]])).astype(np.int32)))
            continue
        if chaff_on:
            # 皮：コーヒーの粒はほぼ光を通さないが、皮は薄く茶色で、赤い光をよく通す
            cm = crop > 0
            tr = float(t_red[y:y + h, x:x + w][cm].mean())
            tb = float(t_blue[y:y + h, x:x + w][cm].mean())
            if tr > g.get("chaff_red", 0.3) and tr / max(tb, 0.02) > g.get("chaff_ratio", 1.25):
                n_chaff += 1
                chaff_px += int(area)
                rejected.append(("chaff", (c + np.array([[x, y]])).astype(np.int32)))
                continue
        hull = cv2.convexHull(c)
        hull_area = max(cv2.contourArea(hull), 1.0)
        a, b = long_px * umpp / 2, short_px * umpp / 2       # 半径（µm）
        vol = 4 / 3 * math.pi * a * b * b                     # 厚み＝短径とみなした楕円体
        s = g["shell_um"]
        ai, bi = a - s, b - s
        inner = 4 / 3 * math.pi * ai * bi * bi if (ai > 0 and bi > 0) else 0.0
        particles.append({
            "ecd_um": ecd_um,
            "long_um": long_px * umpp,
            "short_um": short_px * umpp,
            "volume_um3": vol,
            "extractable": 1 - inner / vol,
            "solidity": area / hull_area,
            "cx": x + w / 2, "cy": y + h / 2,
            "contour": (c + np.array([[x, y]])).astype(np.int32),
        })
    return {
        "path": path,
        "image": img,
        "mask_fraction": float((mask > 0).mean()),
        "particles": particles,
        "n_below_limit": n_small,
        "n_too_big": n_big,
        "n_edge": n_edge,
        "n_chaff": n_chaff,
        "n_dirt": n_dirt,
        "blank": os.path.basename(blank_path) if blank_path else None,
        "blank_problem": blank_problem,
        "chaff_area_pct": (100.0 * chaff_px / max(chaff_px + sum(math.pi * (p["ecd_um"] / umpp / 2) ** 2 for p in particles), 1.0)
                           if chaff_on else None),
        "rejected": rejected,
        "detect_limit_um": min_short * umpp,
    }


def weighted_percentile(values, weights, q):
    v = np.asarray(values, float)
    w = np.asarray(weights, float)
    if len(v) == 0:
        return float("nan")
    order = np.argsort(v)
    v, w = v[order], w[order]
    cw = np.cumsum(w)
    cw = cw / cw[-1]
    return float(np.interp(q / 100.0, cw, v))


def summarize(particles, cfg, n_boot=200, seed=0):
    g = cfg["grind"]
    if not particles:
        return {"n": 0}
    d = np.array([p["ecd_um"] for p in particles])
    v = np.array([p["volume_um3"] for p in particles])
    ex = np.array([p["extractable"] for p in particles])
    sol = np.array([p["solidity"] for p in particles])
    res = {"n": len(d)}
    for q in (10, 50, 90):
        res[f"num_D{q}"] = float(np.percentile(d, q))
        res[f"vol_D{q}"] = weighted_percentile(d, v, q)
    res["fine_vol_pct"] = float(v[d < g["fine_um"]].sum() / v.sum() * 100)
    res["boulder_vol_pct"] = float(v[d > g["boulder_um"]].sum() / v.sum() * 100)
    res["extractable_pct"] = float((v * ex).sum() / v.sum() * 100)
    res["clump_suspect_pct"] = float((sol < 0.8).mean() * 100)   # へこみの多い形＝くっついた粒の疑い
    # 体積加重D50のばらつき（ブートストラップ、95%の幅）
    rng = np.random.default_rng(seed)
    boots = []
    for _ in range(n_boot):
        idx = rng.integers(0, len(d), len(d))
        boots.append(weighted_percentile(d[idx], v[idx], 50))
    if boots:
        res["vol_D50_lo"], res["vol_D50_hi"] = (float(np.percentile(boots, 2.5)), float(np.percentile(boots, 97.5)))
    else:
        res["vol_D50_lo"] = res["vol_D50_hi"] = None
    return res


def overlay(result, max_side=1600):
    """拾った粒を大きさで色分けした確認用画像（縮小版）。"""
    img = result["image"].copy()
    colors = [(255, 120, 0), (0, 200, 0), (0, 200, 255), (0, 60, 255)]   # BGR: 青→緑→黄→赤
    edges = [400, 800, 1200]
    for p in result["particles"]:
        k = sum(p["ecd_um"] > e for e in edges)
        cv2.drawContours(img, [p["contour"]], -1, colors[k], 2)
    h, w = img.shape[:2]
    s = max_side / max(h, w)
    if s < 1:
        img = cv2.resize(img, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
    return img


def detail_overlay(result, cfg):
    """1粒ずつ番号を付けた原寸の確認用画像（番号は CSV の id と同じ）。
    緑＝測った粒、橙＝測ったがくっつき疑い、紫＝固まりとして除外、灰＝画像の端・光の外にかかるので除外、水色＝小さすぎて除外、
    黄＝皮として除外、赤＝空のトレイにもある汚れ・傷として除外。"""
    img = result["image"].copy()
    h, w = img.shape[:2]
    lw = max(2, w // 1500)
    fs = max(0.7, w / 2800)
    cols = {"ok": (60, 200, 60), "clump": (0, 140, 255), "big": (220, 0, 220), "edge": (150, 150, 150), "small": (230, 200, 0),
            "chaff": (40, 220, 255), "dirt": (90, 90, 255)}
    for reason, c in result.get("rejected", []):
        cv2.drawContours(img, [c], -1, cols[reason], 1 if reason == "small" else lw)
    for i, p in enumerate(result["particles"], 1):
        col = cols["clump"] if p["solidity"] < 0.8 else cols["ok"]
        cv2.drawContours(img, [p["contour"]], -1, col, lw)
        x, y, bw, bh = cv2.boundingRect(p["contour"])
        org = (x + bw + 3, y + bh // 2 + int(10 * fs))
        cv2.putText(img, str(i), org, cv2.FONT_HERSHEY_SIMPLEX, fs, (255, 255, 255), lw * 3, cv2.LINE_AA)
        cv2.putText(img, str(i), org, cv2.FONT_HERSHEY_SIMPLEX, fs, col, lw, cv2.LINE_AA)
    # 凡例（英字：OpenCV は日本語を描けないため）
    bar_h = int(60 * fs)
    bar = np.full((bar_h, w, 3), 30, np.uint8)
    x = 15
    for key, text in (("ok", "measured"), ("clump", "measured, maybe touching"), ("big", "excluded: too big"),
                      ("edge", "excluded: at edge"), ("small", "excluded: too small"),
                      ("chaff", "excluded: chaff"), ("dirt", "excluded: dirt/scratch")):
        cv2.rectangle(bar, (x, bar_h // 4), (x + int(30 * fs), bar_h * 3 // 4), cols[key], -1)
        x += int(38 * fs)
        cv2.putText(bar, text, (x, bar_h * 2 // 3), cv2.FONT_HERSHEY_SIMPLEX, fs * 0.8, (240, 240, 240), lw, cv2.LINE_AA)
        x += int(cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, fs * 0.8, lw)[0][0] + 40 * fs)
    return np.vstack([bar, img])
