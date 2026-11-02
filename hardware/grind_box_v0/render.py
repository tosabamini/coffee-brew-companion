import numpy as np, trimesh, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
import grind_box_v0 as g
plt.rcParams['font.family']=['Noto Sans CJK JP','IPAexGothic','DejaVu Sans']
body=trimesh.load('body.stl'); lid=trimesh.load('lid.stl')
lid_a=lid.copy(); lid_a.apply_translation([0,0,g.LEDGE_Z])
def boxmesh(x0,x1,y0,y1,z0,z1):
    b=trimesh.creation.box(extents=[x1-x0,y1-y0,z1-z0]); b.apply_translation([(x0+x1)/2,(y0+y1)/2,(z0+z1)/2]); return b
s20=boxmesh(13-69.1,13,23-151.7,23,g.LID_TOP_Z,g.LID_TOP_Z+7.9)
redmi=boxmesh(-38.05,38.05,-82.1,82.1,0,8.12)
acr=boxmesh(-45,45,-55,55,g.SHELF_Z,g.SAMPLE_Z)
def add(ax,m,color,alpha,edge=None):
    pc=Poly3DCollection(m.vertices[m.faces],facecolor=color,alpha=alpha,edgecolor=edge,linewidths=0.2)
    ax.add_collection3d(pc)
def setup(ax,elev,azim,title):
    ax.set_xlim(-110,70);ax.set_ylim(-150,40);ax.set_zlim(0,130)
    ax.set_box_aspect((180,190,130)); ax.view_init(elev,azim); ax.set_title(title,fontsize=11); ax.set_axis_off()
fig=plt.figure(figsize=(14,6.5))
ax=fig.add_subplot(1,3,1,projection='3d')
add(ax,body,'#2b2b2b',0.95); add(ax,lid_a,'#4a4a4a',0.95); add(ax,s20,'#3b6ea5',0.55); add(ax,redmi,'#c9a227',0.6)
setup(ax,22,-58,'組み立て（青＝S20、黄＝Redmi）')
ax=fig.add_subplot(1,3,2,projection='3d')
add(ax,body,'#2b2b2b',0.35); add(ax,acr,'#f2f2f2',0.9,'#999'); add(ax,redmi,'#c9a227',0.7)
setup(ax,28,-35,'本体と中身（白＝アクリル板）')
ax=fig.add_subplot(1,3,3)
# ふたの上面図

sec=lid.section(plane_origin=[0,0,g.LID_T-0.01],plane_normal=[0,0,1])

for e in sec.discrete: ax.plot(e[:,0],e[:,1],color='#333',lw=1)
rs=lid.section(plane_origin=[0,0,g.LID_T+1],plane_normal=[0,0,1])
for e in rs.discrete: ax.fill(e[:,0],e[:,1],color='#d24',alpha=0.8)
ax.add_patch(plt.Rectangle((13-69.1,23-151.7),69.1,151.7,fill=False,ec='#3b6ea5',lw=1.5,ls='--'))
ax.plot(0,0,'o',color='#3b6ea5'); ax.annotate('メインカメラ',(0,0),(8,-25),fontsize=9,arrowprops=dict(arrowstyle='->',lw=0.8))
ax.add_patch(plt.Rectangle((-g.OUT_X/2,-g.OUT_Y/2),g.OUT_X,g.OUT_Y,fill=False,ec='#888',lw=1,ls=':'))
ax.set_aspect('equal'); ax.set_title('ふたを上から（赤＝L字ガイド、青点線＝S20の置き位置）',fontsize=10)
ax.set_xlabel('mm'); ax.grid(alpha=0.2)
plt.tight_layout(); plt.savefig('preview.png',dpi=130)
