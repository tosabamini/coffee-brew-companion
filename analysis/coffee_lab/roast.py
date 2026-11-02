"""焙煎度（粉の色）の解析。

上から照らした写真の、粉の範囲の色を L*a*b* で出す。
グレー（白）基準の範囲 ref_roi を設定すると、基準が中性の同じ明るさになるよう
色ごとの倍率をかけてから測る（スマホの自動ホワイトバランス・明るさの違いを打ち消すため）。
L* が大きいほど明るい＝浅煎り。Agtron 値そのものではなく、同じ箱・同じ設定どうしで比べる指標。
"""
import cv2
import numpy as np

from common import imread


def _roi(img, frac):
    h, w = img.shape[:2]
    x0, y0, x1, y1 = frac
    return img[int(y0 * h):int(y1 * h), int(x0 * w):int(x1 * w)]


DEFAULT_SAMPLE = (0.35, 0.38, 0.65, 0.62)   # 画像の中央（皿を箱の中央に置く前提）


def analyze_image(path, cfg):
    r = cfg["roast"]
    img = imread(path).astype(np.float32)
    corrected = False
    gains = np.ones(3, np.float32)
    if r.get("ref_roi"):
        ref = _roi(img, r["ref_roi"]).reshape(-1, 3)
        ref_mean = np.median(ref, axis=0)
        gains = r["ref_target"] / np.maximum(ref_mean, 1.0)
        corrected = True
    sample = _roi(img, r.get("sample_roi") or DEFAULT_SAMPLE).reshape(-1, 3) * gains
    sample = np.clip(sample, 0, 255)
    lab = cv2.cvtColor((sample / 255.0).reshape(-1, 1, 3).astype(np.float32), cv2.COLOR_BGR2LAB).reshape(-1, 3)
    L, a, b = np.median(lab, axis=0)
    return {
        "path": path,
        "L": float(L), "a": float(a), "b": float(b),
        "L_std": float(lab[:, 0].std()),
        "corrected": corrected,
        "gains": [float(x) for x in gains],
        "clipped_pct": float((sample >= 254).any(axis=1).mean() * 100),
    }


def preview(path, cfg, max_side=900):
    """どこを粉・基準として測ったかを枠で示した確認用画像。"""
    img = imread(path)
    h, w = img.shape[:2]
    r = cfg["roast"]
    for frac, color in ((r.get("sample_roi") or DEFAULT_SAMPLE, (0, 200, 0)), (r.get("ref_roi"), (0, 120, 255))):
        if not frac:
            continue
        x0, y0, x1, y1 = frac
        cv2.rectangle(img, (int(x0 * w), int(y0 * h)), (int(x1 * w), int(y1 * h)), color, max(3, w // 300))
    s = max_side / max(h, w)
    if s < 1:
        img = cv2.resize(img, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
    return img
