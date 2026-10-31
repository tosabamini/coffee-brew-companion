// ===== 紙コップのサイズ合わせ（両アプリ共通。build.py が /*CUPFIT*/ に埋め込む） =====
//
// 部品（本体・持ち手）は試作で合うことを確認した紙コップ（assets/cup.stl：口径72・底径50.3・高さ80.5 mm）に
// 合わせて作ってある。ほかのサイズの紙コップには、頂点を次のように動かして合わせる。
//   高さ : ホルダーの帯（基準 z=14〜64）が新しい帯（Z0〜Z1）になるよう、z を線形に伸縮
//   本体 : 基準カップ表面からの距離（すき間・壁の厚さ）を保ったまま、新しいカップの円錐面へ移す
//   持ち手: 壁の近くは本体と同じ動き、外側（壁から6 mm以上）は平行移動だけ（太さと形を保つ）
// どれも連続で一対一の変形なので、閉じた立体（マニフォールド）のまま。
const CUPFIT = (function () {
  const BASE = { rim: 72, bottom: 50.34, height: 80.5 };
  const B = { R0: 25.17, K: 0.1065, CL: 0.35, T: 2.6, Z0: 14, Z1: 64 };
  const LIP = 4.6;          // 口径（ふちの巻き込みの外側）と胴の外径の差（基準カップの実測）
  const PRESETS = [
    { id: 'base7', name: '7オンス・試作で確認済み（口径72）', rim: 72, bottom: 50.3, height: 80.5 },
    { id: '5oz', name: '5オンス（口径65.5）', rim: 65.5, bottom: 46.2, height: 73 },
    { id: '7oz74', name: '7オンス（口径74）', rim: 74, bottom: 52, height: 77 },
    { id: '9oz', name: '9オンス（口径77）', rim: 77, bottom: 52, height: 90.5 },
    { id: '8oz90', name: '8オンス・ホット用（口径90・低め）', rim: 90, bottom: 59, height: 82 },
    { id: '12oz', name: '12オンス（口径90）', rim: 90, bottom: 60, height: 110 },
  ];
  const LIMITS = { rim: [50, 110], bottom: [35, 95], height: [50, 160], gap: [0.15, 1.0] };
  const KEY = 'cupholder-cupfit-v1';

  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const defaultHolderH = c => clamp(Math.round(50 * c.height / BASE.height), 30, 90);
  function normalize(c) {
    const o = Object.assign({ preset: 'base7', rim: 72, bottom: 50.3, height: 80.5, gap: 0.35, holderH: null }, c || {});
    for (const k of ['rim', 'bottom', 'height', 'gap']) o[k] = clamp(+o[k] || 0, ...LIMITS[k]);
    if (o.holderH != null) o.holderH = clamp(+o.holderH, 30, Math.max(30, o.height - 12));
    return o;
  }
  // 新しいカップと帯の形
  function geometry(c) {
    c = normalize(c);
    const R0 = c.bottom / 2, K = ((c.rim - LIP) / 2 - R0) / c.height;
    const hh = c.holderH ?? defaultHolderH(c);
    const Z1 = Math.min(c.height - 8, B.Z1 * c.height / BASE.height), Z0 = Math.max(4, Z1 - hh);
    return { R0, K, CL: c.gap, Z0, Z1, sz: (Z1 - Z0) / (B.Z1 - B.Z0) };
  }
  function isBase(c) {
    c = normalize(c);
    return Math.abs(c.rim - BASE.rim) < 0.05 && Math.abs(c.bottom - 50.3) < 0.1 && Math.abs(c.height - BASE.height) < 0.05
      && Math.abs(c.gap - B.CL) < 1e-6 && (c.holderH == null || c.holderH === 50);
  }
  const smooth = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t); };

  // pos: Float32Array（x,y,z…、カップの軸=Z、底=0）。kind: 'b'（本体）| 'h'（持ち手）
  function warp(pos, c, kind) {
    if (isBase(c)) return pos;
    const g = geometry(c), out = new Float32Array(pos.length);
    for (let i = 0; i < pos.length; i += 3) {
      const x = pos[i], y = pos[i + 1], z = pos[i + 2];
      const z2 = g.Z0 + (z - B.Z0) * g.sz;
      const rOld = B.R0 + B.K * z, rNew = g.R0 + g.K * z2;
      const dr = rNew - rOld + (g.CL - B.CL);
      const r = Math.hypot(x, y) || 1e-9;
      const f = (r + dr) / r;
      let nx = x * f, ny = y * f;
      if (kind === 'h') {
        const wall = rOld + B.CL + B.T;
        const w = smooth(wall + 0.3, wall + 6, r);
        nx = nx * (1 - w) + (x + dr) * w; ny = ny * (1 - w) + y * w;
      }
      out[i] = nx; out[i + 1] = ny; out[i + 2] = z2;
    }
    return out;
  }
  // 新しいカップの輪郭（three.js の LatheGeometry 用、[r,z] の列）
  function cupProfile(c) {
    c = normalize(c); const g = geometry(c); const pts = [];
    for (let z = 0; z <= c.height - 2.5; z += 2) pts.push([g.R0 + g.K * z - 0.15, z]);
    const rt = c.rim / 2;
    pts.push([rt, c.height - 1], [rt - 1, c.height], [rt - 2.5, c.height - 0.5]);
    return pts;
  }
  function warnings(c) {
    c = normalize(c); const g = geometry(c), w = [];
    if ((c.rim - LIP) / 2 <= c.bottom / 2) w.push('口径が底の直径より小さすぎます。値を確かめてください。');
    const k = (g.R0 + g.K * (g.Z0 + g.Z1) / 2) / (B.R0 + B.K * 39);
    if (k < 0.93) w.push('基準より細いコップなので、柄の桟も細くなります（強度に注意）。');
    if (g.sz > 1.35) w.push('持ち手が縦に大きく伸びます。ホルダーの高さを下げると自然な形になります。');
    if (g.sz < 0.75) w.push('持ち手が縦に縮みます。');
    if (!isBase(c)) w.push('試作で確認済みなのは口径72 mmのコップだけです。初めてのサイズは、まず無地＋小さめの持ち手で試し刷りしてください。');
    return w;
  }
  function label(c) { c = normalize(c); return `口径${c.rim}・底${c.bottom}・高さ${c.height} mm`; }
  function fileTag(c) { return isBase(c) ? '' : `_cup${Math.round(c.rim)}x${Math.round(c.height)}`; }
  function load() { try { return normalize(JSON.parse(localStorage.getItem(KEY) || 'null')); } catch (e) { return normalize(null); } }
  function save(c) { try { localStorage.setItem(KEY, JSON.stringify(c)); } catch (e) { } }

  // 設定カードを container に作る。onChange(cup) は値が変わるたび（入力の区切りごと）に呼ばれる。
  function mountUI(container, onChange) {
    let cup = load();
    container.classList.add('cupfit');
    container.innerHTML = `
      <div class="cf-head"><h2>紙コップのサイズ</h2><span class="cf-badge"></span></div>
      <select class="cf-preset" aria-label="紙コップの種類"></select>
      <div class="cf-grid">
        <label>口径<small>ふちの外側</small><span><input type="number" step="0.5" data-k="rim"> mm</span></label>
        <label>底の直径<small>外側</small><span><input type="number" step="0.5" data-k="bottom"> mm</span></label>
        <label>高さ<small>ふちまで</small><span><input type="number" step="0.5" data-k="height"> mm</span></label>
      </div>
      <label class="cf-sl">ホルダーの高さ <output class="cf-hh"></output><button type="button" class="cf-auto">自動</button>
        <input type="range" class="cf-hhr" min="30" max="90" step="1"></label>
      <label class="cf-sl">コップとのすき間 <output class="cf-gap"></output>
        <input type="range" class="cf-gapr" min="0.15" max="1" step="0.05"></label>
      <p class="cf-warn"></p>
      <p class="cf-tip">ノギスか定規で、口径（ふちの丸まった部分の外側）・底の直径・高さを測って入れてください。袋や箱に書かれた寸法でも構いません。</p>`;
    const $ = s => container.querySelector(s);
    const sel = $('.cf-preset');
    for (const p of PRESETS) { const o = document.createElement('option'); o.value = p.id; o.textContent = p.name; sel.appendChild(o); }
    { const o = document.createElement('option'); o.value = 'custom'; o.textContent = '自分で測った値を入れる'; sel.appendChild(o); }
    function render() {
      sel.value = cup.preset;
      container.querySelectorAll('input[data-k]').forEach(i => { if (document.activeElement !== i) i.value = cup[i.dataset.k]; });
      const g = geometry(cup), hh = Math.round(g.Z1 - g.Z0);
      $('.cf-hhr').max = Math.max(30, Math.floor(cup.height - 12)); $('.cf-hhr').value = hh;
      $('.cf-hh').textContent = hh + ' mm' + (cup.holderH == null ? '（自動）' : '');
      $('.cf-auto').hidden = cup.holderH == null;
      $('.cf-gapr').value = cup.gap; $('.cf-gap').textContent = cup.gap.toFixed(2) + ' mm';
      $('.cf-badge').textContent = isBase(cup) ? '試作で確認済み' : '未確認のサイズ';
      $('.cf-badge').classList.toggle('base', isBase(cup));
      $('.cf-warn').textContent = warnings(cup).join(' ');
    }
    function commit() { cup = normalize(cup); save(cup); render(); onChange(cup); }
    sel.onchange = () => {
      const p = PRESETS.find(x => x.id === sel.value);
      cup.preset = sel.value;
      if (p) Object.assign(cup, { rim: p.rim, bottom: p.bottom, height: p.height, holderH: null });
      commit();
    };
    container.querySelectorAll('input[data-k]').forEach(i => {
      i.onchange = () => { const v = parseFloat(i.value); if (!isFinite(v)) { render(); return; } cup[i.dataset.k] = v; cup.preset = 'custom'; commit(); };
    });
    let t = null;
    $('.cf-hhr').oninput = () => { cup.holderH = +$('.cf-hhr').value; $('.cf-hh').textContent = cup.holderH + ' mm'; clearTimeout(t); t = setTimeout(commit, 120); };
    $('.cf-gapr').oninput = () => { cup.gap = +$('.cf-gapr').value; $('.cf-gap').textContent = cup.gap.toFixed(2) + ' mm'; clearTimeout(t); t = setTimeout(commit, 120); };
    $('.cf-auto').onclick = () => { cup.holderH = null; commit(); };
    render();
    return { get: () => cup };
  }

  return { BASE, B, PRESETS, normalize, geometry, isBase, warp, cupProfile, warnings, label, fileTag, load, save, mountUI };
})();
if (typeof module !== 'undefined') module.exports = CUPFIT;
