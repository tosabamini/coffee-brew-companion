"""Caffeine (1,3,7-trimethylxanthine, C8H10N4O2) 2D geometry in the usual textbook orientation:
hexagon pointy-top: C6(top,=O) C5(upper right) C4(lower right) N3(bottom,-CH3) C2(lower left,=O) N1(upper left,-CH3);
regular pentagon on the right: C5 N7(-CH3, up-right) C8(-H, right) N9 C4. Double bonds: C6=O, C2=O, C4=C5, C8=N9."""
import numpy as np
def caf2d(L=6.0, origin=(0,0), rot=0.0, flip=False, hydrogens=False, sub=0.95):
    c=np.zeros(2)
    hexang={'C6':90,'C5':30,'C4':-30,'N3':-90,'C2':-150,'N1':150}
    P={k:c+L*np.array([np.cos(np.radians(a)),np.sin(np.radians(a))]) for k,a in hexang.items()}
    ap=L/(2*np.tan(np.radians(36))); R5=L/(2*np.sin(np.radians(36)))
    pc=np.array([L*np.cos(np.radians(30))+ap,0.0])
    for k,a in {'N7':72,'C8':0,'N9':-72}.items(): P[k]=pc+R5*np.array([np.cos(np.radians(a)),np.sin(np.radians(a))])
    out=lambda k,cen:(P[k]-cen)/np.linalg.norm(P[k]-cen)
    P['O6']=P['C6']+out('C6',c)*L*sub; P['O2']=P['C2']+out('C2',c)*L*sub
    P['Me1']=P['N1']+out('N1',c)*L*sub; P['Me3']=P['N3']+out('N3',c)*L*sub; P['Me7']=P['N7']+out('N7',pc)*L*sub
    elem={k:k[0] if k[0] in 'CNO' else 'C' for k in P}
    for k in ('Me1','Me3','Me7'): elem[k]='C'
    bonds=[('N1','C2',1),('C2','N3',1),('N3','C4',1),('C4','C5',2),('C5','C6',1),('C6','N1',1),
           ('C5','N7',1),('N7','C8',1),('C8','N9',2),('N9','C4',1),
           ('C6','O6',2),('C2','O2',2),('N1','Me1',1),('N3','Me3',1),('N7','Me7',1)]
    if hydrogens:
        P['H8']=P['C8']+out('C8',pc)*L*0.62; elem['H8']='H'; bonds.append(('C8','H8',1))
        for m,parent in (('Me1','N1'),('Me3','N3'),('Me7','N7')):
            d=(P[m]-P[parent])/np.linalg.norm(P[m]-P[parent])
            for j,a in enumerate((-62,0,62)):
                t=np.radians(a); dd=np.array([d[0]*np.cos(t)-d[1]*np.sin(t),d[0]*np.sin(t)+d[1]*np.cos(t)])
                hk=f'H{m}{j}'; P[hk]=P[m]+dd*L*0.55; elem[hk]='H'; bonds.append((m,hk,1))
    # centre the drawing, then flip/rotate/translate
    allp=np.array(list(P.values())); mid=(allp.min(0)+allp.max(0))/2
    t=np.radians(rot); Rm=np.array([[np.cos(t),-np.sin(t)],[np.sin(t),np.cos(t)]])
    for k in P:
        q=P[k]-mid
        if flip: q=q*[1,-1]
        P[k]=Rm@q+np.asarray(origin,float)
    return P,elem,bonds
def ring_centres(P):
    h=np.mean([P[k] for k in ('C6','C5','C4','N3','C2','N1')],0); p=np.mean([P[k] for k in ('C5','N7','C8','N9','C4')],0); return h,p
