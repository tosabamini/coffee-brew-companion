"""方眼（実寸 grid_mm ごとの黒い線）を写した写真から「1画素＝何µm」を求める。

ライトのスマホに方眼を出し、カメラで撮った写真を使う。
画像を細い帯に分け、帯ごとに明るさの断面から線の位置を拾い、線の間隔（画素）を直線の当てはめで求める。
少し傾いていても、帯ごとに求めて中央値をとるので影響は小さい。粉が少し乗っていてもかまわない。
"""
import cv2
import numpy as np


def _smooth(v, sigma):
    r = int(3 * sigma)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    pad = np.pad(v, r, mode="edge")
    return np.convolve(pad, k, mode="valid")


def _period_from_profile(p, min_p=25, max_p=700):
    """暗い線が並んだ1次元の断面から、線の間隔（画素）を求める。"""
    v = -(p - _smooth(p, 40))
    n = len(v)
    if n < 4 * min_p:
        return None
    # 自己相関の最初の山＝線の間隔（細い線は高調波が強く、FFT の最大では間隔の 1/2・1/3 を拾いやすいため）
    vc = v - v.mean()
    ac = np.correlate(vc, vc, mode="full")[n - 1:]
    ac = ac / max(ac[0], 1e-9)
    hi = min(max_p, n // 2)
    cand = [i for i in range(min_p, hi) if ac[i] >= ac[i - 1] and ac[i] >= ac[i + 1] and ac[i] > 0.3]
    if not cand:
        return None
    P0 = float(cand[0])
    # 線の位置（局所的な最大）
    half = max(2, int(0.4 * P0))
    thr = 0.3 * np.percentile(v, 99)
    peaks = []
    i = half
    while i < n - half:
        seg = v[i - half:i + half + 1]
        j = i - half + int(np.argmax(seg))
        if j == i and v[i] > thr:
            a, b, c = v[i - 1], v[i], v[i + 1]
            den = a - 2 * b + c
            off = 0.5 * (a - c) / den if den != 0 else 0.0
            peaks.append(i + float(np.clip(off, -0.5, 0.5)))
            i += half
        else:
            i += 1
    if len(peaks) < 4:
        return None
    x = np.array(peaks)
    k = np.round((x - x[0]) / P0)
    for _ in range(2):
        A = np.vstack([k, np.ones_like(k)]).T
        (P, a0), *_ = np.linalg.lstsq(A, x, rcond=None)
        res = x - (a0 + P * k)
        keep = np.abs(res) < max(1.0, 0.12 * P)
        if keep.all() or keep.sum() < 4:
            break
        x, k = x[keep], k[keep]
    rms = float(np.sqrt(np.mean(res[keep] ** 2))) if keep.any() else float("nan")
    return float(P), rms, int(len(x))


def lit_box(gray):
    """光っている（画面が写っている）範囲の外枠。"""
    h, w = gray.shape
    s = 600 / max(h, w)
    small = cv2.resize(gray, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
    small = cv2.morphologyEx(small, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))   # 線と粉を埋める
    m = small > 0.5 * np.percentile(small, 95)
    n, lab, st, _ = cv2.connectedComponentsWithStats(m.astype(np.uint8))
    if n < 2:
        return 0, 0, w, h
    i = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    x, y, bw, bh = st[i, :4]
    x0, y0, x1, y1 = x / s, y / s, (x + bw) / s, (y + bh) / s
    mx, my = 0.05 * (x1 - x0), 0.05 * (y1 - y0)
    return int(x0 + mx), int(y0 + my), int(x1 - mx), int(y1 - my)


def measure(img, grid_mm, bands=7):
    """BGR 画像と方眼の間隔（mm）から {um_per_px, um_x, um_y, residual_px, …} を返す。"""
    gray = img[:, :, 1].astype(np.float32)
    x0, y0, x1, y1 = lit_box(gray)
    roi = gray[y0:y1, x0:x1]
    H, W = roi.shape
    out = {}
    for axis in ("x", "y"):
        Ps, rms, ns = [], [], []
        L = H if axis == "x" else W
        bh = max(40, L // (bands * 3))
        for c in np.linspace(0.15, 0.85, bands):
            m = int(c * L)
            band = roi[m - bh // 2:m + bh // 2, :] if axis == "x" else roi[:, m - bh // 2:m + bh // 2]
            prof = np.median(band, axis=0 if axis == "x" else 1)
            r = _period_from_profile(prof)
            if r:
                Ps.append(r[0]); rms.append(r[1]); ns.append(r[2])
        if len(Ps) < 2:
            raise ValueError("方眼の線が見つかりません（ライトに方眼が出ているか、ピントが合っているか確認してください）")
        P = float(np.median(Ps))
        out[f"period_{axis}_px"] = P
        out[f"spread_{axis}_pct"] = float((np.max(Ps) - np.min(Ps)) / P * 100)
        out[f"um_{axis}"] = grid_mm * 1000.0 / P
        out[f"rms_{axis}"] = float(np.median(rms))
        out[f"lines_{axis}"] = int(np.median(ns))
    out["um_per_px"] = (out["um_x"] + out["um_y"]) / 2
    out["residual_px"] = max(out["rms_x"], out["rms_y"])
    out["lit_box"] = [x0, y0, x1, y1]
    return out
