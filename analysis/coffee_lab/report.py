"""結果を1枚のHTMLにまとめる（グラフは画像として埋め込み、確認用画像は _report フォルダに置く）。"""
import base64
import html
import io
import os
from datetime import datetime

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from matplotlib import font_manager as _fm

_have = {f.name for f in _fm.fontManager.ttflist}
plt.rcParams["font.family"] = [f for f in ("Yu Gothic", "Meiryo", "MS Gothic", "Noto Sans CJK JP", "IPAexGothic") if f in _have] + ["DejaVu Sans"]
plt.rcParams["axes.unicode_minus"] = False

PALETTE = ["#2f6f9f", "#c0662b", "#3f8f4f", "#8a4fa0", "#b03a48", "#6b6b2f", "#2b8a8a"]

CSS = """
body{font-family:'Yu Gothic','Meiryo','Noto Sans CJK JP',sans-serif;margin:0;background:#f4f4f1;color:#222}
main{max-width:1100px;margin:0 auto;padding:28px 20px 60px}
h1{font-size:24px;margin:0 0 4px} h2{font-size:19px;margin:36px 0 10px;border-bottom:1px solid #ccc;padding-bottom:6px}
h3{font-size:15px;margin:20px 0 8px}
.meta{color:#666;font-size:13px}
table{border-collapse:collapse;background:#fff;font-size:13px;margin:8px 0}
th,td{border:1px solid #ddd;padding:6px 9px;text-align:right;white-space:nowrap}
th{background:#eee;text-align:center} td.l{text-align:left}
.note{background:#fff;border-left:4px solid #888;padding:8px 12px;font-size:13px;margin:10px 0;max-width:900px}
.grid{display:flex;flex-wrap:wrap;gap:12px}
.grid figure{margin:0;background:#fff;padding:6px;border:1px solid #ddd}
.grid img{width:260px;display:block} figcaption{font-size:12px;color:#555;margin-top:4px}
img.chart{max-width:100%;background:#fff;border:1px solid #ddd}
"""


def _png(fig):
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=110, bbox_inches="tight")
    plt.close(fig)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def _f(x, nd=0):
    return "—" if x is None or (isinstance(x, float) and np.isnan(x)) else f"{x:.{nd}f}"


def grind_section(title, groups, cfg, img_dir_rel):
    """groups: {group: {"summary":…, "particles":[…], "images":[(file, overlay_rel, result)]}}"""
    g = cfg["grind"]
    out = [f"<h2>挽き目：{html.escape(title)}</h2>"]
    lim = None
    rows = []
    for i, (name, d) in enumerate(groups.items()):
        s = d["summary"]
        lim = d["images"][0][2]["detect_limit_um"] if d["images"] else lim
        n_small = sum(r["n_below_limit"] for _, _, r in d["images"])
        if s.get("n", 0) == 0:
            rows.append(f"<tr><td class=l>{html.escape(name)}</td><td colspan=10>粒が見つかりませんでした</td></tr>")
            continue
        rows.append(
            f"<tr><td class=l>{html.escape(name)}</td><td>{len(d['images'])}</td><td>{s['n']}</td><td>{n_small}</td>"
            f"<td>{_f(s['vol_D10'])}</td><td><b>{_f(s['vol_D50'])}</b><br><small>{_f(s['vol_D50_lo'])}〜{_f(s['vol_D50_hi'])}</small></td>"
            f"<td>{_f(s['vol_D90'])}</td><td>{_f(s['num_D50'])}</td>"
            f"<td>{_f(s['fine_vol_pct'],1)}</td><td>{_f(s['boulder_vol_pct'],1)}</td><td>{_f(s['extractable_pct'],1)}</td>"
            f"<td>{_f(s['clump_suspect_pct'],1)}</td></tr>")
    out.append("<table><tr><th>グループ</th><th>枚数</th><th>粒の数</th><th>下限未満</th>"
               "<th>D10<br>(体積)</th><th>D50<br>(体積・95%幅)</th><th>D90<br>(体積)</th><th>D50<br>(個数)</th>"
               f"<th>細粒%<br>&lt;{g['fine_um']}µm</th><th>大粒%<br>&gt;{g['boulder_um']}µm</th>"
               "<th>抽出可能%</th><th>くっつき<br>疑い%</th></tr>" + "".join(rows) + "</table>")
    out.append(f"<div class=note>単位はµm。体積＝粒の体積で重みを付けた値（大きい粒ほど効く）、個数＝粒の数で数えた値。"
               f"短い方の径が約{_f(lim)}µm未満の粒は測れないので「下限未満」に数だけ入れています。"
               f"抽出可能%は、表面から{g['shell_um']}µmまでが抽出されるとした場合に、粉全体のうち抽出に関わる体積の割合です（Gagné のモデル）。"
               "くっつき疑い%は、形のへこみが大きく2粒以上がくっついている可能性のある粒の割合です。</div>")

    # 分布グラフ（体積加重の累積と、体積加重のヒストグラム）
    valid = {k: v for k, v in groups.items() if v["summary"].get("n", 0) > 0}
    if valid:
        fig, axes = plt.subplots(1, 2, figsize=(11, 4))
        bins = np.logspace(np.log10(150), np.log10(4000), 36)
        for i, (name, d) in enumerate(valid.items()):
            dd = np.array([p["ecd_um"] for p in d["particles"]])
            vv = np.array([p["volume_um3"] for p in d["particles"]])
            o = np.argsort(dd)
            axes[0].plot(dd[o], np.cumsum(vv[o]) / vv.sum() * 100, color=PALETTE[i % 7], label=name, lw=2)
            hist, edges = np.histogram(dd, bins=bins, weights=vv)
            axes[1].step(edges[:-1], hist / hist.sum() * 100, where="post", color=PALETTE[i % 7], label=name, lw=2)
        for ax in axes:
            ax.set_xscale("log"); ax.set_xlabel("粒の大きさ（等価円直径, µm）"); ax.grid(alpha=0.3, which="both")
            ax.set_xticks([200, 300, 500, 700, 1000, 1500, 2000, 3000]); ax.xaxis.set_major_formatter(matplotlib.ticker.ScalarFormatter())
            ax.xaxis.set_minor_formatter(matplotlib.ticker.NullFormatter())
        axes[0].set_ylabel("累積（体積%）"); axes[0].set_title("小さい方から積み上げた体積の割合")
        axes[1].set_ylabel("体積%"); axes[1].set_title("大きさごとの体積の割合")
        axes[0].legend()
        if lim:
            for ax in axes:
                ax.axvline(lim, color="#999", ls="--", lw=1)
        out.append(f'<img class=chart src="{_png(fig)}" alt="粒度分布">')

    out.append("<h3>確認用の画像（拾った粒を大きさで色分け：青&lt;400 / 緑&lt;800 / 黄&lt;1200 / 赤≥1200 µm）</h3>"
               "<div class=note>画像をクリックすると原寸の詳しい画像が開きます。1粒ずつ番号が付いていて、grind_particles.csv の id と対応しています。"
               "緑＝測った粒、橙＝測ったがくっつき疑い、紫＝固まりとして除外、灰＝画像の端・光の外にかかるので除外、水色＝小さすぎて除外。</div><div class=grid>")
    for name, d in groups.items():
        for fname, ov_rel, r in d["images"]:
            out.append(f'<figure><a href="detail_{ov_rel}"><img src="{ov_rel}" alt=""></a>'
                       f"<figcaption>{html.escape(fname)}：{len(r['particles'])}粒（下限未満 {r['n_below_limit']}、端 {r['n_edge']}、大きすぎ {r['n_too_big']}）</figcaption></figure>")
    out.append("</div>")
    return "".join(out)


def roast_section(title, groups):
    """groups: {group: [(file, preview_rel, result), …]}"""
    out = [f"<h2>焙煎度：{html.escape(title)}</h2>"]
    rows, names, Ls, Lerr = [], [], [], []
    for name, items in groups.items():
        L = np.array([r["L"] for _, _, r in items]); a = np.array([r["a"] for _, _, r in items]); b = np.array([r["b"] for _, _, r in items])
        corr = all(r["corrected"] for _, _, r in items)
        clip = max(r["clipped_pct"] for _, _, r in items)
        rows.append(f"<tr><td class=l>{html.escape(name)}</td><td>{len(items)}</td><td><b>{L.mean():.1f}</b></td><td>{L.std():.1f}</td>"
                    f"<td>{a.mean():.1f}</td><td>{b.mean():.1f}</td><td>{'あり' if corr else '<b>なし</b>'}</td><td>{clip:.1f}</td></tr>")
        names.append(name); Ls.append(L.mean()); Lerr.append(L.std())
    out.append("<table><tr><th>グループ</th><th>枚数</th><th>L*（明るさ）</th><th>L*のばらつき</th><th>a*（赤み）</th><th>b*（黄み）</th>"
               "<th>色の補正</th><th>白飛び%</th></tr>" + "".join(rows) + "</table>")
    out.append("<div class=note>L* が大きいほど明るい＝浅煎りです。Agtron 値そのものではなく、同じ箱・同じ設定で撮った写真どうしを比べるための指標です。"
               "「色の補正：なし」のときは、スマホの自動補正の影響を受けています（config.json の roast.ref_roi にグレー基準の範囲を設定すると補正されます）。"
               "白飛び%が大きいときは、明るすぎて正しく測れていません。</div>")
    if names:
        order = np.argsort(Ls)[::-1]
        fig, ax = plt.subplots(figsize=(max(5, len(names) * 1.2), 3.6))
        ax.bar([names[i] for i in order], [Ls[i] for i in order], yerr=[Lerr[i] for i in order], color="#7a5236", capsize=4)
        ax.set_ylabel("L*（大きいほど浅煎り）"); ax.grid(axis="y", alpha=0.3)
        out.append(f'<img class=chart src="{_png(fig)}" alt="L*">')
    out.append("<h3>確認用の画像（緑＝粉として測った範囲、橙＝グレー基準）</h3><div class=grid>")
    for name, items in groups.items():
        for fname, pv_rel, r in items:
            out.append(f'<figure><a href="{pv_rel}"><img src="{pv_rel}" alt=""></a><figcaption>{html.escape(fname)}：L* {r["L"]:.1f}</figcaption></figure>')
    out.append("</div>")
    return "".join(out)


def write_html(path, title, sections, cfg):
    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    body = "".join(sections)
    doc = (f"<!doctype html><html lang=ja><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>"
           f"<title>{html.escape(title)}</title><style>{CSS}</style></head><body><main>"
           f"<h1>{html.escape(title)}</h1><div class=meta>作成 {now}・1画素 = {cfg['um_per_px']} µm</div>{body}</main></body></html>")
    with open(path, "w", encoding="utf-8") as f:
        f.write(doc)
