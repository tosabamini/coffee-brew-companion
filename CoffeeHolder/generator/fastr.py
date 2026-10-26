import numpy as np, trimesh
from PIL import Image
def render(meshes,az=-55,el=18,S=420,scale=4.0,center=(12,0,40),n=1600000,ss=2):
    a,e=np.radians(az),np.radians(el)
    f=np.array([np.cos(e)*np.cos(a),np.cos(e)*np.sin(a),np.sin(e)])
    r=np.cross([0,0,1],f); r/=np.linalg.norm(r); u=np.cross(f,r)
    L=(f*0.6+r*-0.4+u*0.7); L/=np.linalg.norm(L)
    SS=S*ss
    zb=np.full(SS*SS,-1e9); col=np.ones((SS*SS,3)); nb=np.zeros((SS*SS,3))
    for m,c in meshes:
        pts,fi=trimesh.sample.sample_surface(m,n)
        nrm=m.face_normals[fi]
        V=pts-center; x=(V@r)*scale*ss+SS/2; y=SS/2-(V@u)*scale*ss; z=V@f
        ix=x.astype(int); iy=y.astype(int); ok=(ix>=0)&(ix<SS)&(iy>=0)&(iy<SS)
        idx=iy[ok]*SS+ix[ok]; z=z[ok]; nrm=nrm[ok]
        o=np.lexsort((z,idx)); idx=idx[o]; z=z[o]; nrm=nrm[o]
        last=np.r_[idx[1:]!=idx[:-1],True]
        idx=idx[last]; z=z[last]; nrm=nrm[last]
        upd=z>zb[idx]; idx=idx[upd]; z=z[upd]; nrm=nrm[upd]
        zb[idx]=z; nb[idx]=nrm
        sh=np.abs(nrm@L)*0.7+0.3; sh=np.where(nrm@f>0,sh,sh*0.6)
        col[idx]=np.array(c)[None]*sh[:,None]
    zb=zb.reshape(SS,SS); nb=nb.reshape(SS,SS,3); img=col.reshape(SS,SS,3)
    # speckle removal: a pixel that is empty or lies clearly behind most of its 8 neighbours
    # is a gap between sample points through which the far wall shows -> take the neighbours' value
    for _ in range(5):
        P=np.pad(zb,1,constant_values=-1e9); Pc=np.pad(img,((1,1),(1,1),(0,0))); Pn=np.pad(nb,((1,1),(1,1),(0,0)))
        cnt=np.zeros((SS,SS)); zs=np.zeros((SS,SS)); cs=np.zeros((SS,SS,3)); ns=np.zeros((SS,SS,3))
        for dy in (0,1,2):
            for dx in (0,1,2):
                if dy==1 and dx==1: continue
                zn=P[dy:dy+SS,dx:dx+SS]; w=(zn>zb+0.8)&(zn>-1e8)
                cnt+=w; zs+=np.where(w,zn,0); cs+=Pc[dy:dy+SS,dx:dx+SS]*w[...,None]; ns+=Pn[dy:dy+SS,dx:dx+SS]*w[...,None]
        fix=cnt>=5
        if not fix.any(): break
        zb=np.where(fix,zs/np.maximum(cnt,1),zb); img=np.where(fix[...,None],cs/np.maximum(cnt,1)[...,None],img)
        nb=np.where(fix[...,None],ns/np.maximum(cnt,1)[...,None],nb)
    edge=np.zeros((SS,SS),bool)
    for ax in (0,1):
        n2=np.roll(nb,2,axis=ax); z2=np.roll(zb,2,axis=ax)
        e_=(((nb*n2).sum(-1)<0.75)|(np.abs(zb-z2)>0.6))&(zb>-1e8)&(z2>-1e8)
        edge|=e_
    img=img.copy(); img[edge]*=0.4
    im=Image.fromarray((np.clip(img,0,1)*255).astype(np.uint8))
    return im.resize((S,S),Image.LANCZOS)
