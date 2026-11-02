"""挽き目・焙煎度 撮影ボックス v2（v1 ＋ Redmi をはめ込む床。Redmi の振動を箱とトレイに伝える）

部品
  body.stl  : 床つきの黒い箱。床の上に Redmi を画面を上にしてはめ込む（前後にはみ出す）。
              Redmi の背面リング（バンカーリング）が通るよう、床の中央は大きく開けてある。
              床の四隅の裏に、ゴム足を貼る目印のくぼみ。内側にトレイを載せる棚、
              手前（S20 の下端側）の壁にトレイを出し入れする口。
  lid.stl   : S20 を画面を上にして置く板（v0 と同じ）。
  tray.stl  : 引き出し式の試料トレイ。上面のくぼみにクリアファイル等のシートを両面テープで貼る。
              前板で口をふさぐので外の光が入らない。丸ごと抜いてカップの上でひっくり返せる。

座標系（mm）: 原点 = S20 メインカメラの真下（＝写る範囲の中心）, X = 幅方向, Y = 長さ方向
（S20 の上端が +Y 側）, Z = 机からの高さ。数値はすべてこのファイル冒頭で変えられる。

使い方: python grind_box_v2.py  → 同じフォルダに body.stl / lid.stl / tray.stl を書き出す
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
REDMI_W, REDMI_T, REDMI_L = 76.1, 8.12, 164.2
REDMI_BUMP = 2.0          # 背面カメラの出っ張り（目安）

WORK_DIST = 80.0          # レンズ〜試料面（S20 通常モードの最短ピント約70mm＋余裕）
WALL = 3.0
INNER_X, INNER_Y = 92.0, 116.0   # 内寸（写る範囲 約81×108mm を確保）
# 床（v2）
BASE_T = 8.0              # 床（左右と前後の縁）の高さ。Redmi の背面がこの高さに載る。背面リング（折りたたみ 8mm まで）が机に当たらない
REDMI_CLR = 0.4           # Redmi と押さえの間のすき間（片側。3Dプリントの誤差込み。がたつくなら小さく、入らないなら大きく）
GRIP_LEN = 22.0           # 左右の押さえの長さ（ボタンに当たらないよう、Redmi の両端だけ）
GRIP_H = 5.0              # 押さえの高さ（床の上から）
STOP_H = 5.0              # 奥の当て止めの高さ
RING_HOLE_W = 66.0        # 床の中央の溝の幅。Redmi は左右の縁 5mm だけで支える。溝は手前まで抜けていて（手前に棒がない）、
                          # 差し込むときにリングとカメラの出っ張りがこの溝の中を通る
RING_HOLE_BACK = 78.0     # 溝の奥の端（y）。Redmi の奥の端 82.1 より手前なので、奥の 4mm の縁と当て止めは残る
FOOT_D, FOOT_DEPTH = 10.0, 1.0   # ゴム足を貼る目印のくぼみ（床の裏の四隅）
SCREEN_GAP = 13.9         # Redmi の画面〜トレイの下面（画素をぼかすための距離。v1 と同じ）
SHELF_Z = BASE_T + REDMI_T + SCREEN_GAP   # トレイの下面の高さ
ACRYLIC_T = 3.0
SHELF_W = 8.0             # 棚の張り出し（光が通る幅 = INNER_X - 2*SHELF_W = 76mm）
SLOT_W, SLOT_H = 80.0, BASE_T + REDMI_T + 2.5   # Redmi を通す前後の切り欠き（床の上から。保護フィルムと印刷の垂れ下がりの分の余裕）
LID_T = 4.0
LEDGE_W = 3.0             # ふたを受ける段（本体上端の内側、下は45°）
CLEAR = 0.3               # ふたと本体のすき間（片側）
NOTCH_W = 20.0            # ふたを指で持ち上げる切り欠き（前後の壁の上端）
RAIL_W, RAIL_H = 2.5, 2.5
# トレイの押さえ（奥の壁のひさし。差し込んだトレイの奥が持ち上がらないように）
LIP_D = 4.0               # 奥の壁から手前への張り出し（トレイの奥の縁 4mm の上にかぶさる。光の窓にはかからない）
LIP_GAP = 0.6             # トレイ上面とひさしの下面のすき間（印刷の垂れ下がり込み）
LIP_T = 3.0               # ひさしの厚み
TRAY_CHAMFER = 1.0        # トレイの奥の上の角の面取り（ひさしの下へ滑り込むように）

# 窓（S20 背面のカメラ部＋ライトを覆う範囲。背面から見た 左端からの距離 d, 上端からの距離 t）
WIN_D = (2.0, 38.0)
WIN_T = (3.0, 63.0)

# 試料トレイ（v1）
TRAY_T = 3.0              # トレイの厚み（棚の上面 z=SHELF_Z から試料面まで。v0 のアクリル 3mm と同じ高さ）
SHEET_T = 0.25            # 上面に貼るシートの厚み（クリアファイル ≒0.2mm。乳白アクリル 2mm を使うなら 2.0）
TRAY_W = 86.0             # トレイの幅（左右の棚に 5mm ずつ載る）
TRAY_CLEAR = 0.5          # 口・壁とのすき間（片側。横方向）
POWDER_CLEAR = 6.0        # 口の上端と試料面の間。撒いた粉（大きい粒・塊 3〜4mm）が口の縁でこそげ落とされないように
BORDER_Y = 4.0            # トレイの前後の縁（その内側が光の通る窓）
FRONT_T = 3.0             # 前板の厚み
FRONT_LAP = 3.0           # 前板が口のまわりに重なる幅（光をふさぐ）
FRONT_UP = 3.0            # 前板が口の上にはみ出す高さ
GRIP_W, GRIP_D = 22.0, 9.0       # 取っ手（前板の外側の出っ張り）
# --------------------------------------------

OUT_X, OUT_Y = INNER_X + 2 * WALL, INNER_Y + 2 * WALL
SAMPLE_Z = SHELF_Z + TRAY_T
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
    # Redmi を通す前後の切り欠き（床の上から）
    b = b - box(-SLOT_W / 2, SLOT_W / 2, -hy - 1, hy + 1, BASE_T, SLOT_H)
    # ── 床（Redmi の受け皿） ──
    rl = REDMI_L / 2
    gx = REDMI_W / 2 + REDMI_CLR                     # 押さえの内側
    fy0, fy1 = -rl - 1.0, rl + REDMI_CLR + 3.0        # 手前は開けたまま（ここから差し込む）、奥に当て止め
    fy0, fy1 = min(fy0, -hy), max(fy1, hy)
    floor = box(-hx, hx, fy0, fy1, 0, BASE_T)
    # 背面リングが通る中央の穴
    floor = floor - box(-RING_HOLE_W / 2, RING_HOLE_W / 2, fy0 - 1, RING_HOLE_BACK, -1, BASE_T + 1)
    # ゴム足の目印（裏の四隅）
    for sx in (-1, 1):
        for sy in (fy0 + FOOT_D / 2 + 3, fy1 - FOOT_D / 2 - 3):
            c = m3d.Manifold.cylinder(FOOT_DEPTH + 0.01, FOOT_D / 2, FOOT_D / 2, 48).translate([sx * (hx - FOOT_D / 2 - 3), sy, -0.01])
            floor = floor - c
    b = b + floor
    b = b - box(-RING_HOLE_W / 2, RING_HOLE_W / 2, fy0 - 1, RING_HOLE_BACK, -1, BASE_T)
    # 左右の押さえ（Redmi の両端だけ。側面のボタンに当たらないように）
    for sx in (-1, 1):
        for y0 in (-rl, rl - GRIP_LEN):
            x0, x1 = sorted([sx * gx, sx * (gx + 3.0)])
            b = b + box(x0, x1, y0, y0 + GRIP_LEN, BASE_T - 0.01, BASE_T + GRIP_H)
    # 奥の当て止め（Redmi をここまで差し込む）
    b = b + box(-gx - 3.0, gx + 3.0, rl + REDMI_CLR, rl + REDMI_CLR + 3.0, BASE_T - 0.01, BASE_T + STOP_H)
    # トレイの押さえ（奥の壁のひさし。左右の壁ともつながる）
    lz = SAMPLE_Z + LIP_GAP
    b = b + box(-ix, ix, iy - LIP_D, iy + 0.01, lz, lz + LIP_T)
    # トレイの出し入れ口（手前 = -Y の壁。下端は棚の上面と同じ高さなので、下からは光が漏れない）
    ow = TRAY_W + 2 * TRAY_CLEAR
    b = b - box(-ow / 2, ow / 2, -hy - 1, -iy + 0.01, SHELF_Z, SHELF_Z + TRAY_T + POWDER_CLEAR)
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


def tray():
    """引き出し式の試料トレイ（組み立てた位置の座標で作る。底面は z=SHELF_Z）。"""
    hy, iy = OUT_Y / 2, INNER_Y / 2
    z0, z1 = SHELF_Z, SHELF_Z + TRAY_T
    y_front, y_back = -hy, iy - TRAY_CLEAR
    w = TRAY_W / 2
    t = box(-w, w, y_front, y_back, z0, z1)
    # 光の通る窓（左右は棚の先端に合わせる）
    wx = INNER_X / 2 - SHELF_W
    t = t - box(-wx, wx, -iy + BORDER_Y, y_back - BORDER_Y, z0 - 1, z1 + 1)
    # 上面のシート用のくぼみ（外周 1mm を残す。シートの上面がトレイ上面とそろう）
    t = t - box(-w + 1, w - 1, -iy + 1, y_back - 1, z1 - SHEET_T, z1 + 1)
    # 奥の上の角の面取り（ひさしの下へ滑り込むように）
    c = TRAY_CHAMFER
    tri = [[0, c + 0.01], [c + 0.01, c + 0.01], [c + 0.01, 0]]          # (y, z) の三角形（奥の上の角）
    if (tri[1][0] - tri[0][0]) * (tri[2][1] - tri[0][1]) - (tri[1][1] - tri[0][1]) * (tri[2][0] - tri[0][0]) < 0:
        tri = tri[::-1]
    cs = m3d.CrossSection([tri])
    ch = m3d.Manifold.extrude(cs, TRAY_W + 2).rotate([90, 0, 90]).translate([-w - 1, y_back - c, z1 - c])
    t = t - ch
    # 前板（壁の外側。口のまわりに重なって光をふさぐ）
    ow = TRAY_W + 2 * TRAY_CLEAR
    fx = ow / 2 + FRONT_LAP
    t = t + box(-fx, fx, -hy - FRONT_T, -hy, z0, z1 + POWDER_CLEAR + FRONT_UP)
    # 取っ手（机側から立ち上がる塊なので、サポートなしで印刷できる）
    t = t + box(-GRIP_W / 2, GRIP_W / 2, -hy - FRONT_T - GRIP_D, -hy - FRONT_T, z0, z1 + POWDER_CLEAR + FRONT_UP)
    # 取っ手の指がかりの溝
    t = t - box(-GRIP_W / 2 - 1, GRIP_W / 2 + 1, -hy - FRONT_T - GRIP_D + 3, -hy - FRONT_T - GRIP_D + 5.5, z1 + 0.5, z1 + 10)
    return t.translate([0, 0, -z0])     # 印刷用に底面を z=0 へ


def retrofit_lip():
    """印刷済みの本体（ひさしなし）に後から貼る、トレイの押さえ。L字の板。
    奥の壁の内側に接着する。組み立てた位置の座標で作って確認したあと、印刷用に寝かせる。"""
    iy = INNER_Y / 2
    lz = SAMPLE_Z + LIP_GAP
    hx = INNER_X / 2 - 6.0            # 左右の壁の角（内側の丸み・はみ出し）を避けて、幅 80mm
    lip = box(-hx, hx, iy - LIP_D, iy, lz, lz + LIP_T)
    plate = box(-hx, hx, iy - 2.0, iy, lz, lz + 12.0)   # 壁に貼る面（80 × 12mm）
    return lip + plate


def to_trimesh(mf):
    mesh = mf.to_mesh()
    v = np.asarray(mesh.vert_properties)[:, :3]
    f = np.asarray(mesh.tri_verts)
    return trimesh.Trimesh(vertices=v, faces=f, process=False)


if __name__ == "__main__":
    out = os.path.dirname(os.path.abspath(__file__))
    # retrofit_lip は壁に貼る面を下にして印刷（サポート不要）
    rl_print = retrofit_lip().rotate([-90, 0, 0])
    lo = rl_print.bounding_box()
    rl_print = rl_print.translate([0, 0, -lo[2]])
    for name, mf in (("body", body()), ("lid", lid()), ("tray", tray()), ("retrofit_lip", rl_print)):
        tm = to_trimesh(mf)
        tm.export(os.path.join(out, f"{name}.stl"))
        ext = tm.bounds[1] - tm.bounds[0]
        print(f"{name}.stl  {ext[0]:.1f} x {ext[1]:.1f} x {ext[2]:.1f} mm  watertight={tm.is_watertight}")
    print(f"試料面 z={SAMPLE_Z:.1f}mm, ふた上面 z={LID_TOP_Z:.1f}mm, 本体高さ {BODY_H:.1f}mm")
    print(f"シートの大きさ: {TRAY_W - 2:.0f} x {INNER_Y / 2 - TRAY_CLEAR - 1 + INNER_Y / 2 - 1:.0f} mm（厚さ {SHEET_T} mm 用のくぼみ）")
