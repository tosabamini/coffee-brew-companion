import numpy as np, trimesh, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
import grind_box_v2 as g
plt.rcParams['font.family']=['Noto Sans CJK JP','IPAexGothic','DejaVu Sans']
body=trimesh.load('body.stl'); lid=trimesh.load('lid.stl'); tray=trimesh.load('tray.stl')
lid_a=lid.copy(); lid_a.apply_translation([0,0,g.LEDGE_Z])
def boxmesh(x0,x1,y0,y1,z0,z1):
    b=trimesh.creation.box(extents=[x1-x0,y1-y0,z1-z0]); b.apply_translation([(x0+x1)/2,(y0+y1)/2,(z0+z1)/2]); return b
s20=boxmesh(13-69.1,13,23-151.7,23,g.LID_TOP_Z,g.LID_TOP_Z+7.9)
redmi=boxmesh(-38.05,38.05,-82.1,82.1,g.BASE_T,g.BASE_T+8.12)
def add(ax,m,color,alpha,edge=None):
    ax.add_collection3d(Poly3DCollection(m.vertices[m.faces],facecolor=color,alpha=alpha,edgecolor=edge,linewidths=0.2))
def setup(ax,elev,azim,title,lim=((-110,70),(-190,40),(0,130))):
    ax.set_xlim(*lim[0]);ax.set_ylim(*lim[1]);ax.set_zlim(*lim[2])
    ax.set_box_aspect(tuple(b-a for a,b in lim)); ax.view_init(elev,azim); ax.set_title(title,fontsize=11); ax.set_axis_off()
fig=plt.figure(figsize=(15,6.5))
ax=fig.add_subplot(1,3,1)
def sect(m,color,dz=0,dy=0,alpha=0.85):
    mm=m.copy(); mm.apply_translation([0,dy,dz])
    s=mm.section(plane_origin=[20,0,0],plane_normal=[1,0,0])
    if s is None: return
    for e in s.discrete: ax.fill(e[:,1],e[:,2],color=color,alpha=alpha,lw=0)
sect(body,'#333'); sect(lid,'#555',dz=g.LEDGE_Z); sect(tray,'#d24',dz=g.SHELF_Z)
ax.fill([-82.1,82.1,82.1,-82.1],[g.BASE_T,g.BASE_T,g.BASE_T+8.12,g.BASE_T+8.12],color='#c9a227',alpha=0.7)
ax.fill([23-151.7,23,23,23-151.7],[g.LID_TOP_Z,g.LID_TOP_Z,g.LID_TOP_Z+7.9,g.LID_TOP_Z+7.9],color='#3b6ea5',alpha=0.6)
ax.annotate('トレイ（赤）',(-40,g.SAMPLE_Z),(-120,45),fontsize=9,arrowprops=dict(arrowstyle='->',lw=0.8))
ax.annotate('S20（青）',(-60,g.LID_TOP_Z+4),(-150,118),fontsize=9)
ax.annotate('Redmi（黄）。床にはめ込む',(-70,7),(-155,-14),fontsize=9)
ax.annotate('トレイの押さえ（ひさし）',(56,g.SAMPLE_Z+2),(-30,80),fontsize=9,arrowprops=dict(arrowstyle='->',lw=0.8))
ax.text(-75,60,'手前',fontsize=11); ax.text(50,60,'奥',fontsize=11)
ax.set_aspect('equal'); ax.set_xlim(-160,70); ax.set_ylim(-20,125); ax.grid(alpha=0.2)
ax.set_title('横から見た断面（左が手前）',fontsize=10)
ax=fig.add_subplot(1,3,2,projection='3d')
t_out=tray.copy(); t_out.apply_translation([0,-70,g.SHELF_Z])
add(ax,body,'#2b2b2b',0.30); add(ax,redmi,'#c9a227',0.6); add(ax,t_out,'#d24',0.95)
setup(ax,30,-35,'トレイを手前に引き出したところ')
ax=fig.add_subplot(1,3,3)
from matplotlib.patches import PathPatch
from matplotlib.path import Path
sec=body.section(plane_origin=[0,0,1.5],plane_normal=[0,0,1])
pl,T=sec.to_2D()
for poly in pl.polygons_full:
    verts=[np.asarray(poly.exterior.coords)]+[np.asarray(h.coords) for h in poly.interiors]
    codes=[]; allv=[]
    for v in verts:
        v3=np.c_[v,np.zeros(len(v)),np.ones(len(v))] @ T.T
        allv.append(v3[:,:2]); codes+= [Path.MOVETO]+[Path.LINETO]*(len(v)-2)+[Path.CLOSEPOLY]
    ax.add_patch(PathPatch(Path(np.vstack(allv),codes),fc='#555',alpha=0.55,ec='#222'))
sec2=body.section(plane_origin=[0,0,g.BASE_T+2],plane_normal=[0,0,1])
for e in sec2.discrete: ax.fill(e[:,0],e[:,1],color='#d24',alpha=0.8)
ax.add_patch(plt.Rectangle((-38.05,-82.1),76.1,164.2,fill=False,ec='#c9a227',lw=1.5,ls='--'))
ax.text(0,0,'中央の溝\n（手前まで抜けている。\nリングと出っ張りが通る）',ha='center',va='center',fontsize=9)
ax.add_patch(plt.Rectangle((-33,-83.1),66,5.1,fill=True,fc='none',ec='#1a7',lw=1.5,ls=':'))
ax.annotate('旧版の手前の棒（印刷済みなら\nここを切り取る）',(0,-80),(-30,-62),fontsize=8,color='#1a7',arrowprops=dict(arrowstyle='->',lw=0.8,color='#1a7'))
ax.text(0,-92,'手前（ここから Redmi を差し込む）',ha='center',fontsize=9)
ax.text(0,90,'奥（当て止め）',ha='center',fontsize=9)
ax.set_xlim(-60,60); ax.set_ylim(-100,100); ax.set_aspect('equal'); ax.grid(alpha=0.2)
ax.set_title('床を上から（赤＝押さえと当て止め、黄点線＝Redmi）',fontsize=10)
plt.tight_layout(); plt.savefig('preview.png',dpi=120)
