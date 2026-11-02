"""挽き目・焙煎度 撮影ボックス v0（Galaxy S20 通常カメラ ＋ Redmi Note 11 Pro 5G バックライト）

部品
  body.stl : 底なしの黒い筒。Redmi を机に置いて上からかぶせる。内側にアクリル板の棚。
  lid.stl  : S20 を画面を上にして置く板。カメラ・ライトの窓、L字ガイド、はみ出し側の支え。

座標系（mm）: 原点 = S20 メインカメラの真下（＝写る範囲の中心）, X = 幅方向, Y = 長さ方向
（S20 の上端が +Y 側）, Z = 机からの高さ。数値はすべてこのファイル冒頭で変えられる。

使い方: python grind_box_v0.py  → 同じフォルダに body.stl / lid.stl を書き出す
必要: pip install manifold3d trimesh
"""
import os
import numpy as np
import manifold3d as m3d
import trimesh

# ---------------- パラメータ ----------------
# S20（ケースなし）
S20_W, S20_L = 69.1, 151.7
CAM_FROM_TOP, CAM_FROM_LEFT_BACK = 23.0, 13.0   # 背面から見て 上端から / 左端から

# Redmi Note 11 Pro 5G（画面を上にして机に置く）
REDMI_W, REDMI_T = 76.1, 8.12
REDMI_BUMP = 2.0          # 背面カメラの出っ張り（目安）

WORK_DIST = 80.0          # レンズ〜試料面（S20 通常モードの最短ピント約70mm＋余裕）
WALL = 3.0
INNER_X, INNER_Y = 92.0, 116.0   # 内寸（写る範囲 約81×108mm を確保）
SHELF_Z = 22.0            # アクリル板の下面の高さ（Redmi 画面から約12mm 離して画素をぼかす）
ACRYLIC_T = 3.0
SHELF_W = 8.0             # 棚の張り出し（光が通る幅 = INNER_X - 2*SHELF_W = 76mm）
SLOT_W, SLOT_H = 80.0, 13.0      # Redmi を通す前後の切り欠き
LID_T = 4.0
LEDGE_W = 3.0             # ふたを受ける段（本体上端の内側、下は45°）
CLEAR = 0.3               # ふたと本体のすき間（片側）
NOTCH_W = 20.0            # ふたを指で持ち上げる切り欠き（前後の壁の上端）
RAIL_W, RAIL_H = 2.5, 2.5

# 窓（S20 背面のカメラ部＋ライトを覆う範囲。背面から見た 左端からの距離 d, 上端からの距離 t）
WIN_D = (2.0, 38.0)
WIN_T = (3.0, 63.0)
# --------------------------------------------

OUT_X, OUT_Y = INNER_X + 2 * WALL, INNER_Y + 2 * WALL
SAMPLE_Z = SHELF_Z + ACRYLIC_T
LID_TOP_Z = SAMPLE_Z + WORK_DIST
BODY_H = LID_TOP_Z        # ふたは本体の上端に落とし込み、上面がそろう
LEDGE_Z = LID_TOP_Z - LID_T


def box(x0, x1, y0, y1, z0, z1):
    return m3d.Manifold.cube([x1 - x0, y1 - y0, z1 - z0]).translate([x0, y0, z0])


def wedge_x(x_wall, x_tip, y0, y1, z_top, depth):
    """壁から内側へ張り出す棚の下の45°面（サポート不要にするため）。"""
    pts = [[x_wall, z_top], [x_tip, z_top], [x_wall, z_top - depth]]
    # 反時計回りにそろえる（向きが逆だと空の断面になる）
    (ax, ay), (bx, by), (cx, cy) = pts
    if (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) < 0:
        pts = pts[::-1]
    cs = m3d.CrossSection([pts])
    solid = m3d.Manifold.extrude(cs, y1 - y0)          # (x, z) の三角形を w 方向へ押し出し
    # X軸まわりに+90°回転: (x, v, w) → (x, -w, v)。鏡映を使わないので面の向きが崩れない
    solid = solid.rotate([90, 0, 0])
    return solid.translate([0, y1, 0])


def body():
    hx, hy = OUT_X / 2, OUT_Y / 2
    ix, iy = INNER_X / 2, INNER_Y / 2
    b = box(-hx, hx, -hy, hy, 0, BODY_H) - box(-ix, ix, -iy, iy, -1, BODY_H + 1)
    # アクリル板の棚（左右）＋下の45°面
    for sgn in (-1, 1):
        x_wall, x_tip = sgn * ix, sgn * (ix - SHELF_W)
        lo, hi = sorted([x_wall, x_tip])
        b = b + box(lo, hi, -iy, iy, SHELF_Z - 2.0, SHELF_Z)
        b = b + wedge_x(x_wall, x_tip, -iy, iy, SHELF_Z - 2.0, SHELF_W)
    # ふたを受ける段（内側3mm、下は45°でサポート不要）
    frame = box(-ix, ix, -iy, iy, LEDGE_Z - LEDGE_W, LEDGE_Z)
    taper = m3d.Manifold.extrude(
        m3d.CrossSection.square([INNER_X, INNER_Y], center=True), LEDGE_W,
        scale_top=((INNER_X - 2 * LEDGE_W) / INNER_X, (INNER_Y - 2 * LEDGE_W) / INNER_Y),
    ).translate([0, 0, LEDGE_Z - LEDGE_W])
    b = b + (frame - taper)
    # ふたを指で持ち上げる切り欠き（前後の壁の上端、ふたの厚みの分だけ。下の段が光を遮る）
    for sgn in (-1, 1):
        b = b - box(-NOTCH_W / 2, NOTCH_W / 2, sgn * hy - 4, sgn * hy + 4, LEDGE_Z, BODY_H + 1)
    # Redmi を通す前後の切り欠き
    b = b - box(-SLOT_W / 2, SLOT_W / 2, -hy - 1, hy + 1, -1, SLOT_H)
    # Redmi の中心合わせ用の刻み（前後の外面、中央に縦溝）
    for sgn in (-1, 1):
        y = sgn * hy
        b = b - box(-0.6, 0.6, y - 0.6, y + 0.6, SLOT_H + 2, SLOT_H + 12)
    return b


def lid():
    hx, hy = OUT_X / 2, OUT_Y / 2
    # S20 の外形（上から見た位置）: カメラは右端から13mm, 上端から23mm
    s20_x1 = CAM_FROM_LEFT_BACK          # 右端
    s20_x0 = s20_x1 - S20_W              # 左端
    s20_y1 = CAM_FROM_TOP                # 上端
    s20_y0 = s20_y1 - S20_L              # 下端
    # ふたは本体の内側に落とし込む平らな板（下面が平らなのでそのまま印刷できる）。
    # S20 の重心（y≈-53）は本体の上面（y≥-61）に収まるので、S20 ははみ出して置いてよい。
    ix, iy = INNER_X / 2 - CLEAR, INNER_Y / 2 - CLEAR
    p = box(-ix, ix, -iy, iy, 0, LID_T)
    # 窓（背面 d,t → 上から見た x = 13 - d, y = 23 - t）
    wx0, wx1 = sorted([CAM_FROM_LEFT_BACK - WIN_D[1], CAM_FROM_LEFT_BACK - WIN_D[0]])
    wy0, wy1 = sorted([CAM_FROM_TOP - WIN_T[1], CAM_FROM_TOP - WIN_T[0]])
    p = p - box(wx0, wx1, wy0, wy1, -1, LID_T + 1)
    # L字ガイド（S20 の右端と上端を当てる）
    g = 0.3
    p = p + box(s20_x1 + g, s20_x1 + g + RAIL_W, -45, s20_y1 + g + RAIL_W, LID_T, LID_T + RAIL_H)
    p = p + box(-40, s20_x1 + g + RAIL_W, s20_y1 + g, s20_y1 + g + RAIL_W, LID_T, LID_T + RAIL_H)
    # 印刷向き: 平らな下面をベッドに、L字ガイドが上
    return p


def to_trimesh(mf):
    mesh = mf.to_mesh()
    v = np.asarray(mesh.vert_properties)[:, :3]
    f = np.asarray(mesh.tri_verts)
    return trimesh.Trimesh(vertices=v, faces=f, process=True)


if __name__ == "__main__":
    out = os.path.dirname(os.path.abspath(__file__))
    for name, mf in (("body", body()), ("lid", lid())):
        tm = to_trimesh(mf)
        tm.export(os.path.join(out, f"{name}.stl"))
        ext = tm.bounds[1] - tm.bounds[0]
        print(f"{name}.stl  {ext[0]:.1f} x {ext[1]:.1f} x {ext[2]:.1f} mm  watertight={tm.is_watertight}")
    print(f"試料面 z={SAMPLE_Z:.1f}mm, ふた上面 z={LID_TOP_Z:.1f}mm, 本体高さ {BODY_H:.1f}mm")
