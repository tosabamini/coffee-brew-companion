import numpy as np, manifold3d as m3d
import grind_box_v2 as G
B=G.body(); T=G.tray().translate([0,0,G.SHELF_Z])
def vol(a,b): return (a^b).volume()
box=G.box
# --- 面取りの位置確認（トレイの奥の上の角だけが削れているか）
yb=G.INNER_Y/2-G.TRAY_CLEAR; z1=G.SAMPLE_Z
probe=lambda x,y,z: vol(T, box(x-.05,x+.05,y-.05,y+.05,z-.05,z+.05))>0
print("面取り: 角の点", probe(0,yb-0.2,z1-0.2), "（Falseなら削れている） / 少し内側", probe(0,yb-0.2,z1-1.5), "（Trueのはず）")
# --- Redmi＋リング＋出っ張り を手前から差し込む
W,L,TH=G.REDMI_W,G.REDMI_L,G.REDMI_T; z0=G.BASE_T; hw=W/2
def redmi(y_end, bump_corner, ring_dy, m=6.0, bw=28, bl=44, bh=2.5, rs=45, rt=8.0):
    # y_end = Redmi の奥の端の y。最終位置は L/2
    y0=y_end-L; yc=y_end-L/2
    p=box(-hw,hw,y0,y_end,z0+0.01,z0+TH)
    sx,sy=bump_corner
    bx0 = hw-m-bw if sx>0 else -hw+m
    by0 = y_end-m-bl if sy>0 else y0+m
    p=p+box(bx0,bx0+bw,by0,by0+bl,z0-bh,z0+0.02)
    p=p+box(-rs/2,rs/2,yc+ring_dy-rs/2,yc+ring_dy+rs/2,z0-rt,z0+0.02)
    return p
worst=0; n=0
for corner in [(1,1),(1,-1),(-1,1),(-1,-1)]:
    for rdy in (-50,-25,0,25,50):
        for y_end in np.arange(-130, L/2+0.001, 1.0):   # 箱の手前の外から最終位置まで
            v=vol(B,redmi(y_end,corner,rdy)); n+=1
            if v>worst: worst=v; wc=(corner,rdy,y_end)
print(f"Redmi 差し込み: {n} 通り, 最大の重なり {worst:.4f} mm³", wc if worst>1e-6 else "")
# 机に当たらないか（最終位置でリング下端）
print("リング下端 z =", z0-8.0, "（0以上なら机に当たらない）")
# --- トレイの出し入れ
worst=0
for dy in np.arange(-140,0.001,0.5):
    worst=max(worst, vol(B,T.translate([0,dy,0])))
print(f"トレイ 出し入れ: 最大の重なり {worst:.4f} mm³")
# --- 粉を載せたトレイ: 粉の高さ 4mm がひさしに当たらない範囲
lip_y0=G.INNER_Y/2-G.LIP_D
print("ひさしの先端 y =", lip_y0, "/ 光の窓の奥の端 y =", yb-G.BORDER_Y, "/ 写る範囲の奥 ≈ 54")
# --- 押さえの効き：トレイの奥を持ち上げたときに当たる高さ
for lift in (0.3,0.6,0.7,1.0):
    print(f" トレイの奥を {lift}mm 持ち上げ → ひさしと重なる: {vol(B, T.translate([0,0,lift]))>1e-6}")
