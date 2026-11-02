"""大きさの較正：定規を写した写真から「1画素＝何µm」を求めて config.json に保存する。

使い方
  python analyze.py calibrate 定規の写真.jpg            … 画像が開くので、目盛りの2点をクリック → 間の長さ(mm)を入力
  python analyze.py calibrate 定規の写真.jpg --points 812 1200 812 3100 --mm 70   … 座標を直接指定
撮影ボックスの中で、アクリル板の上に定規を置いて撮ること（粉を置く高さで測るため）。
"""
import math

import cv2

from common import imread, load_config, save_config


def _click_two_points(img):
    h, w = img.shape[:2]
    s = min(1.0, 1000 / max(h, w))
    view = cv2.resize(img, (int(w * s), int(h * s))) if s < 1 else img.copy()
    pts = []

    def on_mouse(ev, x, y, flags, param):
        if ev == cv2.EVENT_LBUTTONDOWN and len(pts) < 2:
            pts.append((x / s, y / s))
            cv2.circle(view, (x, y), 6, (0, 0, 255), 2)
            cv2.imshow(win, view)

    win = "2点をクリック（Enterで決定 / Escで中止）"
    cv2.namedWindow(win, cv2.WINDOW_AUTOSIZE)
    cv2.setMouseCallback(win, on_mouse)
    cv2.imshow(win, view)
    while True:
        k = cv2.waitKey(30) & 0xFF
        if k in (13, 10) and len(pts) == 2:
            break
        if k == 27:
            pts = []
            break
    cv2.destroyAllWindows()
    return pts


def run(path, points=None, mm=None):
    img = imread(path)
    if points:
        p1, p2 = (points[0], points[1]), (points[2], points[3])
    else:
        pts = _click_two_points(img)
        if len(pts) != 2:
            print("中止しました。")
            return None
        p1, p2 = pts
    if mm is None:
        mm = float(input("クリックした2点の間の長さ（mm）: "))
    dist_px = math.dist(p1, p2)
    umpp = mm * 1000.0 / dist_px
    cfg = load_config()
    cfg["um_per_px"] = round(umpp, 3)
    save_config(cfg)
    print(f"{dist_px:.1f} 画素 = {mm} mm → 1画素 = {umpp:.2f} µm（config.json に保存しました）")
    return umpp
