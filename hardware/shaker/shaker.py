"""粉の振り出し容器（トレイに粉を薄く均一に撒くため）

部品
  shaker_body.stl : 容器（底あり・上が開いている）。開いた側を上にしてそのまま印刷。
  shaker_cap.stl  : 穴あきのふた。容器にかぶせてはめる。穴の面を下にして印刷。

ねらい
  - 穴（直径 HOLE_D）を一番大きい粒（約 3.4mm）より大きくして、粒をふるい分けない（分布が偏らない）
  - 入れた粉は最後まで全部振り出す（途中でやめると、出やすい粒だけが撒かれて偏る）

使い方: python shaker.py → 同じフォルダに STL を書き出す（必要: pip install manifold3d trimesh）
"""
import os

import manifold3d as m3d
import numpy as np
import trimesh

# ---------------- パラメータ（mm） ----------------
BODY_D = 40.0       # 容器の外径
BODY_H = 45.0       # 容器の高さ
WALL = 2.0          # 壁の厚み
FLOOR = 2.0         # 底の厚み
CAP_CLEAR = 0.15    # ふたと容器のすき間（片側）。逆さにして振っても外れないよう、きつめ。入らなければ 0.25、ゆるければ 0.1
CAP_SKIRT = 9.0     # ふたが容器にかぶさる深さ
CAP_TOP = 2.0       # ふたの天板の厚み
HOLE_D = 5.0        # 穴の直径（一番大きい粒より大きく）
HOLE_RING_R = 10.0  # 外側の穴を並べる円の半径
HOLE_RING_N = 6     # 外側の穴の数（＋中央に1つ）
SEG = 96
# ----------------------------------------------


def cyl(h, r, z0=0.0):
    return m3d.Manifold.cylinder(h, r, r, SEG).translate([0, 0, z0])


def body():
    outer = cyl(BODY_H, BODY_D / 2)
    inner = cyl(BODY_H, BODY_D / 2 - WALL, FLOOR)
    return outer - inner


def cap():
    """組み立てた向き（天板が上）で作る。"""
    ri = BODY_D / 2 + CAP_CLEAR
    ro = ri + WALL
    c = cyl(CAP_SKIRT + CAP_TOP, ro) - cyl(CAP_SKIRT, ri)
    holes = [(0.0, 0.0)] + [(HOLE_RING_R * np.cos(a), HOLE_RING_R * np.sin(a))
                            for a in np.linspace(0, 2 * np.pi, HOLE_RING_N, endpoint=False)]
    for x, y in holes:
        c = c - m3d.Manifold.cylinder(CAP_TOP + 2, HOLE_D / 2, HOLE_D / 2, 48).translate([x, y, CAP_SKIRT - 1])
    return c


def to_tm(mf):
    m = mf.to_mesh()
    return trimesh.Trimesh(vertices=np.asarray(m.vert_properties)[:, :3], faces=np.asarray(m.tri_verts), process=False)


if __name__ == "__main__":
    out = os.path.dirname(os.path.abspath(__file__))
    b, c = body(), cap()
    # 組み立てたとき（ふたを容器の上端にかぶせる）に重ならないか
    placed = c.translate([0, 0, BODY_H - CAP_SKIRT])
    print("組み立てたときの重なり:", round((b ^ placed).volume(), 4), "mm³")
    # ふたは天板を下にして印刷
    c_print = c.rotate([180, 0, 0])
    c_print = c_print.translate([0, 0, -c_print.bounding_box()[2]])
    for name, mf in (("shaker_body", b), ("shaker_cap", c_print)):
        tm = to_tm(mf)
        tm.export(os.path.join(out, name + ".stl"))
        e = tm.bounds[1] - tm.bounds[0]
        print(f"{name}.stl  {e[0]:.1f} x {e[1]:.1f} x {e[2]:.1f} mm  watertight={tm.is_watertight}")
    vol_ml = np.pi * (BODY_D / 2 - WALL) ** 2 * (BODY_H - FLOOR) / 1000
    print(f"容量 約 {vol_ml:.0f} mL / 穴 直径 {HOLE_D} mm × {HOLE_RING_N + 1} 個")
