"""共通処理：設定ファイル、画像の読み込み、ファイル名からのグループ分け。"""
import json
import os
import re

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(HERE, "config.json")

DEFAULT_CONFIG = {
    "um_per_px": 27.0,          # 1画素あたりの大きさ（µm）。calibrate で上書きされる
    "grind": {
        "threshold": 0.60,      # 背景の明るさに対してこの割合より暗い画素を「粒」とみなす（Gagné 方式は約0.59）
        "min_short_px": 8,      # 短い方の径がこの画素数未満の粒は「測定下限未満」として数だけ数える
        "max_ecd_um": 4000,     # これより大きい塊はゴミ・固まりとして除外
        "fine_um": 400,         # 「細かい粒」の境目（体積の割合を出す）
        "boulder_um": 1400,     # 「大きい粒」の境目
        "shell_um": 100,        # 表面から何µmまでが抽出されるとみなすか（Gagné のモデル）
        "split_touching": False # くっついた粒を watershed で分けるか
    },
    "roast": {
        "sample_roi": None,     # 粉の範囲 [x0, y0, x1, y1]（画像に対する 0〜1 の割合）。None なら自動
        "ref_roi": None,        # グレー（白）基準の範囲。None なら色の補正をしない
        "ref_target": 200       # 基準をこの明るさ（0〜255）にそろえる
    }
}

IMAGE_EXTS = (".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp")


def load_config():
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, encoding="utf-8") as f:
            user = json.load(f)
        for k, v in user.items():
            if isinstance(v, dict) and isinstance(cfg.get(k), dict):
                cfg[k].update(v)
            else:
                cfg[k] = v
    return cfg


def save_config(cfg):
    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)


def imread(path):
    """日本語パスでも読めるように np.fromfile 経由で読む（EXIF の回転も反映される）。"""
    data = np.fromfile(path, dtype=np.uint8)
    img = cv2.imdecode(data, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"画像を読み込めません: {path}")
    return img


def imwrite(path, img, quality=88):
    ext = os.path.splitext(path)[1] or ".jpg"
    ok, buf = cv2.imencode(ext, img, [cv2.IMWRITE_JPEG_QUALITY, quality])
    if not ok:
        raise ValueError(f"画像を書き出せません: {path}")
    buf.tofile(path)


def list_images(folder):
    files = []
    for name in sorted(os.listdir(folder)):
        if name.lower().endswith(IMAGE_EXTS) and not name.startswith("_"):
            files.append(os.path.join(folder, name))
    return files


def group_of(path):
    """dial12_01.jpg → dial12。区切りがなければファイル名そのもの。"""
    stem = os.path.splitext(os.path.basename(path))[0]
    m = re.match(r"^(.*?)[_\-\s](\d+)$", stem)
    return m.group(1) if m else stem
