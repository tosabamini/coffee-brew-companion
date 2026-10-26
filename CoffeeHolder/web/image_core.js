// ===== cup-holder geometry core (pure functions, no DOM) =====
const CUP = { R0: 25.17, K: 0.1065, CL: 0.35, Z0: 14.0, Z1: 64.0, ZA: 18.4, ZB: 60.5, STRIP: 8.0 };
const ri = z => CUP.R0 + CUP.K * z + CUP.CL;
const RAVG = ri((CUP.Z0 + CUP.Z1) / 2) + 1.3;
const CIRC = 2 * Math.PI * RAVG;

// grid: N columns around (wraps), M rows up. cell (j,i)
function makeGrid(cell) {
  const N = Math.round(CIRC / cell), M = Math.round((CUP.Z1 - CUP.Z0) / cell);
  return { N, M, ds: CIRC / N, dz: (CUP.Z1 - CUP.Z0) / M };
}
// s of column centre, measured from handle (s=0) going CCW, in [0,CIRC)
const colS = (g, j) => (j + 0.5) * g.ds;
const rowZ = (g, i) => CUP.Z0 + (i + 0.5) * g.dz;

// window region: which cells may carry the image. returns Uint8Array mask + bbox in (s,z)
function windowMask(g, p) {
  const W = new Uint8Array(g.N * g.M);
  let s0, s1;
  if (p.layout === 'wrap') { s0 = CUP.STRIP; s1 = CIRC - CUP.STRIP; }
  else {
    const c = ((p.center % 360) + 360) % 360 / 360 * CIRC;
    const half = Math.min(p.panelWidth, CIRC - 2 * CUP.STRIP) / 2;
    s0 = c - half; s1 = c + half;
  }
  const zlo = p.fullHeight ? CUP.Z0 + 1.2 : CUP.ZA, zhi = p.fullHeight ? CUP.Z1 - 1.2 : CUP.ZB;
  for (let i = 0; i < g.M; i++) {
    const z = rowZ(g, i); if (z < zlo || z > zhi) continue;
    for (let j = 0; j < g.N; j++) {
      let s = colS(g, j);
      // panel may cross s=0 seam: test in unwrapped frame around its centre
      let ss = s; if (p.layout !== 'wrap') { const c = (s0 + s1) / 2; while (ss - c > CIRC / 2) ss -= CIRC; while (c - ss > CIRC / 2) ss += CIRC; }
      if (ss < s0 || ss > s1) continue;
      if (s < CUP.STRIP || s > CIRC - CUP.STRIP) continue; // keep handle strip solid
      W[i * g.N + j] = 1;
    }
  }
  return { W, s0, s1, zlo, zhi };
}

// sample image luminance onto window cells. img = {w,h,data(Float32 lum 0..1, 1=white), alpha}
function sampleImage(g, win, img, p) {
  const L = new Float32Array(g.N * g.M).fill(1);
  const spanS = win.s1 - win.s0, spanZ = win.zhi - win.zlo;
  const aspect = img.w / img.h;
  let tileW;
  if (p.fit === 'stretch') tileW = spanS;
  else { tileW = spanZ * aspect * p.scale; }
  const tileH = p.fit === 'stretch' ? spanZ : spanZ * p.scale;
  const cS = (win.s0 + win.s1) / 2, cZ = (win.zlo + win.zhi) / 2;
  for (let i = 0; i < g.M; i++) for (let j = 0; j < g.N; j++) {
    const k = i * g.N + j; if (!win.W[k]) continue;
    let s = colS(g, j); const c = cS; while (s - c > CIRC / 2) s -= CIRC; while (c - s > CIRC / 2) s += CIRC;
    let u = (s - cS) / tileW + 0.5, v = 1 - ((rowZ(g, i) - cZ) / tileH + 0.5);
    if (p.fit === 'repeat') { u -= Math.floor(u); v -= Math.floor(v); }
    if (u < 0 || u >= 1 || v < 0 || v >= 1) { L[k] = p.invert ? 0 : 1; continue; }
    if (p.mirror) u = 1 - u;
    const x = Math.min(img.w - 1, Math.floor(u * img.w)), y = Math.min(img.h - 1, Math.floor(v * img.h));
    let l = img.data[y * img.w + x];
    l = (l - 0.5) * p.contrast + 0.5 + p.brightness;
    l = Math.min(1, Math.max(0, l));
    L[k] = p.invert ? 1 - l : l;
  }
  return L;
}

// ---- morphology on the cylinder grid (columns wrap) ----
function dilate(g, A, r) { // 8-neighbour, r iterations (r cells)
  let a = A, b;
  for (let t = 0; t < r; t++) {
    b = new Uint8Array(a);
    for (let i = 0; i < g.M; i++) for (let j = 0; j < g.N; j++) {
      if (a[i * g.N + j]) continue;
      let hit = 0;
      for (let di = -1; di <= 1 && !hit; di++) { const ii = i + di; if (ii < 0 || ii >= g.M) continue;
        for (let dj = -1; dj <= 1; dj++) { if (a[ii * g.N + (j + dj + g.N) % g.N]) { hit = 1; break; } } }
      if (hit) b[i * g.N + j] = 1;
    }
    a = b;
  }
  return a;
}
const notm = A => A.map(v => v ? 0 : 1);
function bfsDist(g, src, maxd) { // 8-neigh chessboard distance from src cells, capped
  const D = new Int16Array(g.N * g.M).fill(maxd + 1); let q = [];
  for (let k = 0; k < D.length; k++) if (src[k]) { D[k] = 0; q.push(k); }
  for (let d = 0; d < maxd && q.length; d++) {
    const nq = [];
    for (const k of q) { const i = (k / g.N) | 0, j = k % g.N;
      for (let di = -1; di <= 1; di++) { const ii = i + di; if (ii < 0 || ii >= g.M) continue;
        for (let dj = -1; dj <= 1; dj++) { const kk = ii * g.N + (j + dj + g.N) % g.N; if (D[kk] > d + 1) { D[kk] = d + 1; nq.push(kk); } } } }
    q = nq;
  }
  return D;
}
function components(g, A) { // 4-connected labels of cells where A=1
  const lab = new Int32Array(g.N * g.M).fill(-1); const sizes = []; let n = 0;
  for (let s = 0; s < lab.length; s++) {
    if (!A[s] || lab[s] >= 0) continue;
    const st = [s]; lab[s] = n; let c = 0;
    while (st.length) { const k = st.pop(); c++; const i = (k / g.N) | 0, j = k % g.N;
      const nb = [i > 0 ? k - g.N : -1, i < g.M - 1 ? k + g.N : -1, i * g.N + (j + 1) % g.N, i * g.N + (j - 1 + g.N) % g.N];
      for (const kk of nb) if (kk >= 0 && A[kk] && lab[kk] < 0) { lab[kk] = n; st.push(kk); } }
    sizes.push(c); n++;
  }
  return { lab, sizes };
}
function fixCheckerboard(g, H) { // remove diagonal-only contacts (non-manifold) by filling a hole cell
  let changed = 1, guard = 0;
  while (changed && guard++ < 20) {
    changed = 0;
    for (let i = 0; i < g.M - 1; i++) for (let j = 0; j < g.N; j++) {
      const a = i * g.N + j, b = i * g.N + (j + 1) % g.N, c = (i + 1) * g.N + j, d = (i + 1) * g.N + (j + 1) % g.N;
      if (H[a] === H[d] && H[b] === H[c] && H[a] !== H[b]) {
        if (H[a]) H[a] = 0; else H[b] = 0; changed = 1;
      }
    }
  }
}

// main: luminance -> holes + thickness per cell
function process(g, win, L, p) {
  const n = g.N * g.M, cell = (g.ds + g.dz) / 2;
  let H = new Uint8Array(n);
  const wantHoles = p.mode === 'cut' || p.mode === 'both';
  if (wantHoles) for (let k = 0; k < n; k++) if (win.W[k] && L[k] < p.threshold) H[k] = 1;
  const stats = { removedIslands: 0, filledTiny: 0 };
  if (wantHoles) {
    // 1) minimum bar: opening of the solid -> holes that pinch a bar thinner than p.bar are merged
    const r = Math.max(1, Math.round(p.bar / 2 / cell));
    let S = notm(H); S = notm(dilate(g, notm(S), r)); S = dilate(g, S, r); // open(solid)
    for (let k = 0; k < n; k++) { if (!win.W[k]) S[k] = 1; H[k] = S[k] ? 0 : 1; }
    // 2) tiny holes (< minHole mm^2) are filled back
    const minCells = p.minHole / (g.ds * g.dz);
    const hc = components(g, H);
    for (let k = 0; k < n; k++) if (H[k] && hc.sizes[hc.lab[k]] < minCells) { H[k] = 0; stats.filledTiny++; }
    fixCheckerboard(g, H);
    // 3) floating islands: solid pieces not connected to the frame fall out -> remove them
    const S2 = notm(H); const sc = components(g, S2);
    const keep = new Uint8Array(sc.sizes.length);
    for (let k = 0; k < n; k++) if (S2[k] && !win.W[k]) keep[sc.lab[k]] = 1;
    if (p.bridge) {
      // connect every island to the frame along the shortest path through the holes
      const par = new Int32Array(n).fill(-2); let q = [];
      for (let k = 0; k < n; k++) if (S2[k] && keep[sc.lab[k]]) { par[k] = -1; q.push(k); }
      while (q.length) { const nq = [];
        for (const k of q) { const i = (k / g.N) | 0, j = k % g.N;
          const nb = [i > 0 ? k - g.N : -1, i < g.M - 1 ? k + g.N : -1, i * g.N + (j + 1) % g.N, i * g.N + (j - 1 + g.N) % g.N];
          for (const kk of nb) if (kk >= 0 && H[kk] && par[kk] === -2) { par[kk] = k; nq.push(kk); } }
        q = nq; }
      const best = new Map();
      for (let k = 0; k < n; k++) { if (!S2[k] || keep[sc.lab[k]]) continue; const i = (k / g.N) | 0, j = k % g.N;
        const nb = [i > 0 ? k - g.N : -1, i < g.M - 1 ? k + g.N : -1, i * g.N + (j + 1) % g.N, i * g.N + (j - 1 + g.N) % g.N];
        for (const kk of nb) if (kk >= 0 && H[kk] && par[kk] !== -2) {
          let d = 0, t = kk; while (par[t] >= 0 && d < 9999) { t = par[t]; d++; }
          const b = best.get(sc.lab[k]); if (!b || d < b.d) best.set(sc.lab[k], { d, start: kk }); } }
      const P = new Uint8Array(n); let nb_ = 0;
      for (const { start } of best.values()) { let t = start; while (t >= 0 && H[t]) { P[t] = 1; t = par[t]; } nb_++; }
      const rb = Math.max(0, Math.round((p.bar / cell - 1) / 2));
      const PB = dilate(g, P, rb);
      for (let k = 0; k < n; k++) if (PB[k] && win.W[k]) H[k] = 0;
      stats.bridges = nb_;
      fixCheckerboard(g, H);
      const S3 = notm(H), c3 = components(g, S3); keep.fill(0);
      const keep3 = new Uint8Array(c3.sizes.length);
      for (let k = 0; k < n; k++) if (S3[k] && !win.W[k]) keep3[c3.lab[k]] = 1;
      for (let k = 0; k < n; k++) if (S3[k] && !keep3[c3.lab[k]]) { H[k] = 1; stats.removedIslands++; }
      fixCheckerboard(g, H);
      for (let k = 0; k < n; k++) S2[k] = 0; // islands already handled
    }
    for (let k = 0; k < n; k++) if (S2[k] && !keep[sc.lab[k]]) { H[k] = 1; stats.removedIslands++; }
    fixCheckerboard(g, H);
  }
  // thickness
  const T = new Float32Array(n);
  let D = null; const rimCells = Math.round(p.rimWidth / cell);
  if (wantHoles && p.rimHeight > 0 && rimCells > 0) D = bfsDist(g, H, rimCells);
  let open = 0, winCells = 0;
  for (let k = 0; k < n; k++) {
    if (win.W[k]) { winCells++; if (H[k]) open++; }
    if (H[k]) continue;
    let t = p.base;
    if (win.W[k]) {
      if (p.mode === 'relief' || p.mode === 'both') t += (1 - L[k]) * p.depth;
      if (D && D[k] <= rimCells) t = Math.max(t, p.base + p.rimHeight);
    } else t = Math.max(p.base, p.frame);
    T[k] = t;
  }
  // optional smoothing of relief (one 3x3 pass on solid cells)
  if (p.smooth) {
    const T2 = new Float32Array(T);
    for (let i = 1; i < g.M - 1; i++) for (let j = 0; j < g.N; j++) { const k = i * g.N + j; if (H[k] || !win.W[k]) continue;
      let s = 0, c = 0; for (let di = -1; di <= 1; di++) for (let dj = -1; dj <= 1; dj++) { const kk = (i + di) * g.N + (j + dj + g.N) % g.N; if (!H[kk]) { s += T[kk]; c++; } }
      T2[k] = Math.max(p.base, s / c); }
    T.set(T2);
  }
  stats.open = winCells ? open / winCells : 0;
  return { H, T, stats };
}

// grid -> closed triangle mesh (Float32 positions, Uint32 indices). Manifold by construction.
function buildMesh(g, H, T) {
  const N = g.N, M = g.M, NV = N * (M + 1);
  // corner thickness = mean of adjacent solid cells
  const ct = new Float32Array(NV), cc = new Uint8Array(NV);
  for (let i = 0; i < M; i++) for (let j = 0; j < N; j++) { const k = i * N + j; if (H[k]) continue; const t = T[k];
    for (const [ci, cj] of [[i, j], [i, j + 1], [i + 1, j], [i + 1, j + 1]]) { const v = ci * N + cj % N; ct[v] += t; cc[v]++; } }
  const idIn = new Int32Array(NV).fill(-1), idOut = new Int32Array(NV).fill(-1);
  const pos = []; let nv = 0;
  const vert = (ci, cj, outer) => { const v = ci * N + (cj % N); const ids = outer ? idOut : idIn;
    if (ids[v] < 0) { const z = CUP.Z0 + ci * g.dz, th = 2 * Math.PI * (cj % N) / N; const r = ri(z) + (outer ? ct[v] / cc[v] : 0);
      pos.push(r * Math.cos(th), r * Math.sin(th), z); ids[v] = nv++; } return ids[v]; };
  const tri = [];
  const solid = (i, j) => i >= 0 && i < M && !H[i * N + ((j + N) % N)];
  for (let i = 0; i < M; i++) for (let j = 0; j < N; j++) {
    if (H[i * N + j]) continue;
    const ao = vert(i, j, 1), bo = vert(i, j + 1, 1), co = vert(i + 1, j + 1, 1), dO = vert(i + 1, j, 1);
    const ai = vert(i, j, 0), bi = vert(i, j + 1, 0), ci = vert(i + 1, j + 1, 0), di = vert(i + 1, j, 0);
    tri.push(ao, bo, co, ao, co, dO);           // outer, normal +r
    tri.push(ai, ci, bi, ai, di, ci);           // inner, normal -r
    if (!solid(i - 1, j)) tri.push(ai, bi, bo, ai, bo, ao);        // bottom wall -z
    if (!solid(i + 1, j)) tri.push(di, dO, co, di, co, ci);        // top wall +z
    if (!solid(i, j - 1)) tri.push(ai, ao, dO, ai, dO, di);        // -theta wall
    if (!solid(i, j + 1)) tri.push(bi, ci, co, bi, co, bo);        // +theta wall
  }
  return { pos: new Float32Array(pos), idx: new Uint32Array(tri) };
}

function meshVolume(pos, idx) {
  let v = 0;
  for (let t = 0; t < idx.length; t += 3) {
    const a = idx[t] * 3, b = idx[t + 1] * 3, c = idx[t + 2] * 3;
    v += pos[a] * (pos[b + 1] * pos[c + 2] - pos[b + 2] * pos[c + 1]) - pos[a + 1] * (pos[b] * pos[c + 2] - pos[b + 2] * pos[c]) + pos[a + 2] * (pos[b] * pos[c + 1] - pos[b + 1] * pos[c]);
  }
  return v / 6;
}
function toSTL(pos, idx, zshift) {
  const nt = idx.length / 3, buf = new ArrayBuffer(84 + nt * 50), dv = new DataView(buf);
  const hdr = 'paper cup holder - image relief'; for (let i = 0; i < hdr.length; i++) dv.setUint8(i, hdr.charCodeAt(i));
  dv.setUint32(80, nt, true); let o = 84;
  for (let t = 0; t < nt; t++) {
    const a = idx[3 * t] * 3, b = idx[3 * t + 1] * 3, c = idx[3 * t + 2] * 3;
    const ux = pos[b] - pos[a], uy = pos[b + 1] - pos[a + 1], uz = pos[b + 2] - pos[a + 2];
    const vx = pos[c] - pos[a], vy = pos[c + 1] - pos[a + 1], vz = pos[c + 2] - pos[a + 2];
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx; const l = Math.hypot(nx, ny, nz) || 1;
    dv.setFloat32(o, nx / l, true); dv.setFloat32(o + 4, ny / l, true); dv.setFloat32(o + 8, nz / l, true); o += 12;
    for (const q of [a, b, c]) { dv.setFloat32(o, pos[q], true); dv.setFloat32(o + 4, pos[q + 1], true); dv.setFloat32(o + 8, pos[q + 2] - zshift, true); o += 12; }
    dv.setUint16(o, 0, true); o += 2;
  }
  return buf;
}
if (typeof module !== 'undefined') module.exports = { CUP, ri, CIRC, makeGrid, windowMask, sampleImage, process, buildMesh, meshVolume, toSTL };
