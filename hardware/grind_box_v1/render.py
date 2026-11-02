import numpy as np, trimesh, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
import grind_box_v1 as g
plt.rcParams['font.family']=['Noto Sans CJK JP','IPAexGothic','DejaVu Sans']
body=trimesh.load('body.stl'); lid=trimesh.load('lid.stl'); tray=trimesh.load('tray.stl')
lid_a=lid.copy(); lid_a.apply_translation([0,0,g.LEDGE_Z])
def boxmesh(x0,x1,y0,y1,z0,z1):
    b=trimesh.creation.box(extents=[x1-x0,y1-y0,z1-z0]); b.apply_translation([(x0+x1)/2,(y0+y1)/2,(z0+z1)/2]); return b
s20=boxmesh(13-69.1,13,23-151.7,23,g.LID_TOP_Z,g.LID_TOP_Z+7.9)
redmi=boxmesh(-38.05,38.05,-82.1,82.1,0,8.12)
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
ax.fill([-82,82,82,-82],[0,0,8.1,8.1],color='#c9a227',alpha=0.7)
ax.fill([23-151.7,23,23,23-151.7],[g.LID_TOP_Z,g.LID_TOP_Z,g.LID_TOP_Z+7.9,g.LID_TOP_Z+7.9],color='#3b6ea5',alpha=0.6)
ax.annotate('トレイ（赤）',(-40,g.SAMPLE_Z),(-120,45),fontsize=9,arrowprops=dict(arrowstyle='->',lw=0.8))
ax.annotate('S20（青）',(-60,g.LID_TOP_Z+4),(-150,118),fontsize=9)
ax.annotate('Redmi（黄）',(-60,4),(-150,-12),fontsize=9)
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
sec=tray.section(plane_origin=[0,0,0.5],plane_normal=[0,0,1])
pl,T=sec.to_2D()
for poly in pl.polygons_full:
    verts=[np.asarray(poly.exterior.coords)]+[np.asarray(h.coords) for h in poly.interiors]
    codes=[]; allv=[]
    for v in verts:
        v3=np.c_[v,np.zeros(len(v)),np.ones(len(v))] @ T.T
        allv.append(v3[:,:2]); codes+= [Path.MOVETO]+[Path.LINETO]*(len(v)-2)+[Path.CLOSEPOLY]
    ax.add_patch(PathPatch(Path(np.vstack(allv),codes),fc='#d24',alpha=0.45,ec='#a12'))
ax.set_xlim(-55,55); ax.set_ylim(-80,65)
sh=g.TRAY_W-2; y0=-g.INNER_Y/2+1; y1=g.INNER_Y/2-g.TRAY_CLEAR-1
ax.add_patch(plt.Rectangle((-sh/2,y0),sh,y1-y0,fill=False,ec='#3b6ea5',lw=1.5,ls='--'))
ax.text(0,(y0+y1)/2,f'シート {sh:.0f}×{y1-y0:.0f} mm\n（青点線）',ha='center',va='center',fontsize=10,color='#3b6ea5')
ax.annotate('取っ手（手前）',(0,-g.OUT_Y/2-8),(30,-g.OUT_Y/2-20),fontsize=9,arrowprops=dict(arrowstyle='->',lw=0.8))
ax.set_aspect('equal'); ax.set_title('トレイを上から（白い部分が光の通る窓）',fontsize=10); ax.grid(alpha=0.2)
plt.tight_layout(); plt.savefig('preview.png',dpi=120)
