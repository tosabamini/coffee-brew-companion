"""検証用の合成画像を作る。大きさの分かった「粉」を、ムラのある白い背景（下からの光を想定）に撒く。

python tests/make_synthetic.py <出力フォルダ>
  grind: dial10 / dial15 / dial20（中央値 約600 / 850 / 1100 µm）を各2枚、真値CSVつき
  roast: light / medium / dark の3段階を、照明の色を変えて各2枚（左上にグレー基準）
"""
import csv
import math
import os
import sys

import cv2
import numpy as np

UMPP = 27.0
H, W = 4000, 3000


def blob(rng, r_px):
    """不規則な形の粒（半径 r_px 前後の多角形）。"""
    k = rng.integers(7, 12)
    ang = np.sort(rng.uniform(0, 2 * np.pi, k))
    aspect = rng.uniform(1.0, 1.6)
    rad = r_px * rng.uniform(0.75, 1.15, k)
    rot = rng.uniform(0, np.pi)
    x = rad * np.cos(ang) * aspect
    y = rad * np.sin(ang) / math.sqrt(aspect)
    xr = x * np.cos(rot) - y * np.sin(rot)
    yr = x * np.sin(rot) + y * np.cos(rot)
    return np.stack([xr, yr], 1)


def make_grind(out, name, median_um, rng, n=700):
    yy, xx = np.mgrid[0:H, 0:W]
    bg = 235 - 45 * (((xx - W / 2) / W) ** 2 + ((yy - H / 2) / H) ** 2) * 2   # 周辺が暗い
    img = np.dstack([bg, bg, bg]).astype(np.float32)
    occ = np.zeros((H, W), np.uint8)
    truth = []
    sigma = 0.35
    tries = 0
    while len(truth) < n and tries < n * 30:
        tries += 1
        d_um = median_um * math.exp(rng.normal(0, sigma))
        r_px = d_um / UMPP / 2
        pts = blob(rng, r_px)
        cx, cy = rng.uniform(80, W - 80), rng.uniform(80, H - 80)
        poly = (pts + [cx, cy]).astype(np.int32)
        m = np.zeros((H, W), np.uint8)
        x0, y0 = poly.min(0) - 6
        x1, y1 = poly.max(0) + 6
        if x0 < 0 or y0 < 0 or x1 >= W or y1 >= H:
            continue
        cv2.fillPoly(m, [poly], 1)
        if (occ[y0:y1, x0:x1] & cv2.dilate(m, np.ones((9, 9), np.uint8))[y0:y1, x0:x1]).any():
            continue
        occ |= m
        area = int(m.sum())
        truth.append(math.sqrt(4 * area / math.pi) * UMPP)
        for c, v in zip(range(3), (38, 52, 70)):     # 暗い茶色（BGR）
            img[:, :, c][m > 0] = v
    img = cv2.GaussianBlur(img, (0, 0), 0.8)
    img += rng.normal(0, 3, img.shape)
    img = np.clip(img, 0, 255).astype(np.uint8)
    cv2.imwrite(os.path.join(out, f"{name}.jpg"), img, [cv2.IMWRITE_JPEG_QUALITY, 92])
    with open(os.path.join(out, f"{name}_truth.csv"), "w", newline="") as f:
        csv.writer(f).writerows([[t] for t in truth])
    return truth


def make_roast(out, name, base_bgr, light_bgr, rng):
    """粉の色 base_bgr を、色付きの照明 light_bgr（0〜1 の倍率）で撮った画像。左上にグレー基準。"""
    img = np.zeros((H, W, 3), np.float32)
    img[:] = (70, 70, 70)                              # 暗い箱の中
    cv2.circle(img, (W // 2, H // 2), 1100, base_bgr, -1)   # 皿に平らにした粉
    img[200:700, 200:700] = (128, 128, 128)            # グレー基準（本来は中性のグレー）
    img *= np.array(light_bgr, np.float32)
    tex = rng.normal(0, 6, (H, W, 1))
    img += tex
    img = np.clip(img, 0, 255).astype(np.uint8)
    cv2.imwrite(os.path.join(out, f"{name}.jpg"), img, [cv2.IMWRITE_JPEG_QUALITY, 92])


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "synthetic"
    rng = np.random.default_rng(42)
    g = os.path.join(out, "grind")
    r = os.path.join(out, "roast")
    os.makedirs(g, exist_ok=True)
    os.makedirs(r, exist_ok=True)
    for dial, med in (("dial10", 600), ("dial15", 850), ("dial20", 1100)):
        for k in (1, 2):
            t = make_grind(g, f"{dial}_{k:02d}", med, rng)
            print(dial, k, "particles", len(t))
    roasts = {"light": (60, 95, 140), "medium": (40, 62, 95), "dark": (25, 35, 52)}
    lights = [(1.0, 1.0, 1.0), (0.80, 0.95, 1.15)]     # 白い光 / 黄色っぽい光
    for name, col in roasts.items():
        for k, lt in enumerate(lights, 1):
            make_roast(r, f"{name}_{k:02d}", col, lt, rng)
    print("done")
