"""CoffeeHolder build script.

  python build.py            -> build everything into dist/ (takes a while: ~300 parts + thumbnails)
  python build.py --html     -> only re-assemble the two HTML apps from web/ (uses existing build/)
  python build.py --only b153 h126   -> rebuild just these parts, then the apps
  python build.py --jobs 4   -> number of parallel workers (default: CPU count)

Outputs
  build/stl/body_XXX.stl, build/stl/hand_XXX.stl   each part as STL (in place, cup axis = Z)
  dist/組み合わせ/   combiner app (index.html + parts/ + sprites)
  dist/画像から作る/  image -> holder app
"""
import sys, os, json, argparse, base64, zlib, struct, shutil
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'generator'))
from paths import ROOT, ASSETS, BUILD, DIST
import numpy as np

WEB = ROOT / 'web'
N_BODY = 165   # 0 = plain, 1-124 patterns, 125-154 coffee, 155-164 caffeine
N_HAND = 130   # 1-115 shapes, 116-125 coffee, 126-130 caffeine
PATTERN_CATS = [(1,8,'幾何・タイル'),(9,16,'フラクタル・再帰'),(17,23,'曲線・波'),(24,38,'シミュレーション・情報'),(39,52,'世界と日本の文様'),
                (53,60,'テキスタイル・美術様式'),(61,72,'世界の建築'),(73,74,'オプ・アート'),(75,89,'自然・生き物'),(90,100,'タイリング・数学'),(101,124,'モチーフ')]

# ---------------------------------------------------------------- catalogue
def body_entry(k):
    """(generator function or None, japanese name, category, rng seed)"""
    if k == 0: return None, '無地（穴なし）', '無地', 0
    if k <= 124:
        import patterns100 as P
        name = list(P.G)[k-1]; fn, jp, _, _ = P.G[name]
        cat = [c for a, z, c in PATTERN_CATS if a <= k <= z][0]
        return fn, jp, cat, 1000 + k
    if k <= 154:
        import coffee_bodies as CB
        fn, jp = list(CB.CB.values())[k-125]; return fn, jp, 'コーヒー', 5000 + (k-125)
    import caf_bodies as CF
    fn, jp = list(CF.CB2.values())[k-155]; return fn, jp, 'カフェイン', 7000 + (k-155)
def hand_entry(k):
    if k <= 115:
        import handles100 as H
        fn, jp, grp = list(H.H.values())[k-1]; return fn, jp, grp
    if k <= 125:
        import coffee_handles as CH
        fn, jp = list(CH.CH.values())[k-116]; return fn, jp, 'コーヒー'
    import caf_handles as CF
    fn, jp = list(CF.CH2.values())[k-126]; return fn, jp, 'カフェイン'

# ---------------------------------------------------------------- geometry
def build_body(k):
    import manifold3d as mf, lib100 as L
    from lightkit import deep_shell, holes3d, fins3d
    from geokit import toM, fromM
    params = json.load(open(ROOT/'generator'/'body_params.json'))
    fn, jp, cat, seed = body_entry(k)
    M = toM(deep_shell(lambda z: 1.5 + 0*z))
    if fn is not None:
        p = params[str(k)]
        VO, FR, _ = L.wall(fn, np.random.default_rng(seed), vfix=p['vfix'])
        if p['fins'] and not FR.is_empty:
            M = mf.Manifold.batch_boolean([M] + [toM(q) for q in fins3d(FR, lambda z: 1.1 + 0*z)], mf.OpType.Add)
        cuts = holes3d(VO)
        if cuts: M = M - mf.Manifold.batch_boolean([toM(q) for q in cuts], mf.OpType.Add)
    m = fromM(M)
    if m.body_count > 1: m = max(m.split(only_watertight=False), key=lambda q: abs(q.volume))
    m.export(BUILD/'stl'/f'body_{k:03d}.stl')
def build_hand(k):
    import hkit
    from geokit import fromM
    fn, jp, grp = hand_entry(k)
    fromM(hkit.clip(fn())).export(BUILD/'stl'/f'hand_{k:03d}.stl')

# ---------------------------------------------------------------- encoding + thumbnail
def encode(kind, k):
    """compact mesh (int32 deltas of 0.002 mm quantised vertices, zlib) wrapped in a JS file + 280px thumbnail"""
    import trimesh
    from fastr import render
    stl = BUILD/'stl'/f"{'body' if kind=='b' else 'hand'}_{k:03d}.stl"
    m = trimesh.load(stl)
    q = np.round(m.vertices/0.002).astype(np.int32); f = m.faces.astype(np.int64)
    dv = np.diff(np.vstack([[0,0,0], q]), axis=0).astype(np.int32); df = np.diff(np.r_[0, f.ravel()]).astype(np.int32)
    raw = zlib.compress(struct.pack('<II', len(q), len(f)) + dv.tobytes() + df.tobytes(), 9)
    b64 = base64.b64encode(raw).decode()
    (BUILD/'parts'/f'{kind}{k:03d}.js').write_text(f'(window.__parts=window.__parts||{{}})["{kind}{k:03d}"]="{b64}";')
    thumb(kind, k, m)
    return round(m.volume/1000, 2)

def thumb(kind, k, m=None):
    """280px thumbnail rendered from the part's STL"""
    import trimesh
    from fastr import render
    if m is None: m = trimesh.load(BUILD/'stl'/f"{'body' if kind=='b' else 'hand'}_{k:03d}.stl")
    if kind == 'b': im = render([(m,(0.86,0.56,0.34))], -55, 18, S=280, scale=3.6, center=(0,0,39), n=4000000)
    else:           im = render([(m,(0.86,0.56,0.34))], -50, 20, S=280, scale=4.6, center=(46,0,42), n=2000000)
    im.save(BUILD/'thumbs'/f'{kind}{k:03d}.webp', 'WEBP', quality=80)

def thumb_job(t):
    thumb(*t); print(f'  {t[0]}{t[1]:03d} thumb', flush=True)

def job(t):
    kind, k = t
    try:
        (build_body if kind == 'b' else build_hand)(k)
        v = encode(kind, k)
        print(f'  {kind}{k:03d} ok  {v} cm3', flush=True)
        return kind, k, v
    except Exception as e:
        print(f'  {kind}{k:03d} FAILED: {e!r}', flush=True); raise

# ---------------------------------------------------------------- assembly
def assemble():
    from PIL import Image
    vols = json.load(open(BUILD/'volumes.json')) if (BUILD/'volumes.json').exists() else {}
    bodies = [dict(i=k, jp=body_entry(k)[1], c=body_entry(k)[2], v=vols.get(f'b{k}', 0)) for k in range(N_BODY)]
    hands = [dict(i=k, jp=hand_entry(k)[1], c=hand_entry(k)[2], v=vols.get(f'h{k}', 0)) for k in range(1, N_HAND+1)]
    # display order: plain, coffee, caffeine, then the rest
    order_b = [0] + list(range(125, 155)) + list(range(155, 165)) + list(range(1, 125))
    order_h = list(range(116, 126)) + list(range(126, 131)) + list(range(1, 116))
    B = {d['i']: d for d in bodies}; Hd = {d['i']: d for d in hands}
    data = dict(b=[B[i] for i in order_b], h=[Hd[i] for i in order_h])
    out = DIST/'組み合わせ'; (out/'parts').mkdir(parents=True, exist_ok=True)
    for f in (BUILD/'parts').glob('*.js'): shutil.copy(f, out/'parts'/f.name)
    rows = {}
    for kind, n0, n1 in (('b', 0, N_BODY), ('h', 1, N_HAND+1)):
        S = 200; r = (n1-1)//16 + 1; rows[kind] = r
        sp = Image.new('RGB', (16*S, r*S), 'white')
        for k in range(n0, n1):
            p = BUILD/'thumbs'/f'{kind}{k:03d}.webp'
            if p.exists(): sp.paste(Image.open(p).resize((S, S), Image.LANCZOS), ((k % 16)*S, (k//16)*S))
        sp.save(out/f'sprite_{kind}.webp', 'WEBP', quality=78)
    t = (WEB/'combo.template.html').read_text(encoding='utf-8')
    t = t.replace('/*DATA*/', json.dumps(data, ensure_ascii=False, separators=(',', ':')))
    import re
    t = re.sub(r"const rows=tab==='b'\?\d+:\d+", f"const rows=tab==='b'?{rows['b']}:{rows['h']}", t)
    (out/'index.html').write_text(t, encoding='utf-8')
    img = DIST/'画像から作る'; img.mkdir(parents=True, exist_ok=True)
    t = (WEB/'image_maker.template.html').read_text(encoding='utf-8')
    t = t.replace('/*CORE*/', (WEB/'image_core.js').read_text(encoding='utf-8')).replace('/*HANDLES*/', (ASSETS/'image_maker_handles.json').read_text(encoding='utf-8'))
    (img/'index.html').write_text(t, encoding='utf-8')
    shutil.copytree(WEB/'lib', DIST/'lib', dirs_exist_ok=True)
    print(f'apps written to {DIST}')

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--html', action='store_true', help='only re-assemble the HTML apps')
    ap.add_argument('--only', nargs='*', help='parts to rebuild, e.g. b153 h126')
    ap.add_argument('--thumbs', action='store_true', help='only re-render thumbnails from build/stl (after editing fastr.py)')
    ap.add_argument('--jobs', type=int, default=os.cpu_count())
    a = ap.parse_args()
    for d in ('stl', 'parts', 'thumbs'): (BUILD/d).mkdir(parents=True, exist_ok=True)
    if a.thumbs:
        from multiprocessing import Pool
        with Pool(a.jobs) as p: p.map(thumb_job, [('h', k) for k in range(1, N_HAND+1)] + [('b', k) for k in range(N_BODY)], chunksize=1)
    elif not a.html:
        jobs = [(s[0], int(s[1:])) for s in a.only] if a.only else \
               [('h', k) for k in range(1, N_HAND+1)] + [('b', k) for k in range(N_BODY)]
        print(f'building {len(jobs)} parts with {a.jobs} workers ...')
        from multiprocessing import Pool
        with Pool(a.jobs) as p: res = p.map(job, jobs, chunksize=1)
        vp = BUILD/'volumes.json'; vols = json.load(open(vp)) if vp.exists() else {}
        for kind, k, v in res: vols[f'{kind}{k}'] = v
        json.dump(vols, open(vp, 'w'))
    assemble()

if __name__ == '__main__':
    main()
