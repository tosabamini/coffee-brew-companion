"""Coffee Lab：挽き目・焙煎度の写真解析ツール（PC用）

使い方（このフォルダで実行）
  python analyze.py grind <フォルダ>       … 挽き目。フォルダ直下の写真、または中のサブフォルダごと（背景の種類ごと）に解析
  python analyze.py roast <フォルダ>       … 焙煎度
  python analyze.py calibrate <定規の写真> … 1画素の大きさを求めて config.json に保存
オプション
  --split   くっついた粒を分ける処理を入れる（挽き目）
  --out DIR レポートの出力先（既定：<フォルダ>/_report）
ファイル名の「_番号」の前がグループになる（dial12_01.jpg, dial12_02.jpg → dial12）。
"""
import argparse
import csv
import os
import sys
import webbrowser
from collections import OrderedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from common import group_of, imwrite, list_images, load_config  # noqa: E402
import calibrate  # noqa: E402
import grind  # noqa: E402
import report  # noqa: E402
import roast  # noqa: E402


def _sections(folder):
    """フォルダ直下に写真があればそれ1つ、なければ写真を含むサブフォルダごとに分ける。"""
    direct = list_images(folder)
    if direct:
        return [(os.path.basename(os.path.normpath(folder)), folder, direct)]
    out = []
    for name in sorted(os.listdir(folder)):
        sub = os.path.join(folder, name)
        if os.path.isdir(sub) and not name.startswith("_"):
            imgs = list_images(sub)
            if imgs:
                out.append((name, sub, imgs))
    return out


def run_grind(folder, out_dir, cfg):
    sections_html = []
    os.makedirs(out_dir, exist_ok=True)
    csv_rows = []
    for title, sub, imgs in _sections(folder):
        groups = OrderedDict()
        for p in imgs:
            if grind.is_blank(p):
                continue                    # 空のトレイの写真（汚れ・傷を除くために使う）
            print(f"  解析中: {os.path.relpath(p, folder)}", flush=True)
            r = grind.analyze_image(p, cfg)
            ov_name = f"grind_{title + '_' if sub != folder else ''}{os.path.splitext(os.path.basename(p))[0]}.jpg"
            imwrite(os.path.join(out_dir, ov_name), grind.overlay(r))
            imwrite(os.path.join(out_dir, "detail_" + ov_name), grind.detail_overlay(r, cfg), quality=90)
            g = groups.setdefault(group_of(p), {"particles": [], "images": []})
            g["particles"] += r["particles"]
            r_light = {k: v for k, v in r.items() if k not in ("image", "rejected")}
            g["images"].append((os.path.basename(p), ov_name, r_light))
            for pid, q in enumerate(r["particles"], 1):
                csv_rows.append([title, group_of(p), os.path.basename(p), pid, f"{q['ecd_um']:.1f}", f"{q['long_um']:.1f}",
                                 f"{q['short_um']:.1f}", f"{q['volume_um3']:.0f}", f"{q['extractable']:.3f}", f"{q['solidity']:.3f}"])
        for d in groups.values():
            d["summary"] = grind.summarize(d["particles"], cfg)
        sections_html.append(report.grind_section(title, groups, cfg, out_dir))
        for name, d in groups.items():
            s = d["summary"]
            print(f"  [{title}] {name}: {s.get('n', 0)}粒  D50(体積) {s.get('vol_D50', float('nan')):.0f} µm")
    with open(os.path.join(out_dir, "grind_particles.csv"), "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow(["section", "group", "file", "id", "ecd_um", "long_um", "short_um", "volume_um3", "extractable", "solidity"])
        w.writerows(csv_rows)
    return sections_html


def run_roast(folder, out_dir, cfg):
    sections_html = []
    os.makedirs(out_dir, exist_ok=True)
    for title, sub, imgs in _sections(folder):
        groups = OrderedDict()
        for p in imgs:
            print(f"  解析中: {os.path.relpath(p, folder)}", flush=True)
            r = roast.analyze_image(p, cfg)
            pv_name = f"roast_{title + '_' if sub != folder else ''}{os.path.splitext(os.path.basename(p))[0]}.jpg"
            imwrite(os.path.join(out_dir, pv_name), roast.preview(p, cfg))
            groups.setdefault(group_of(p), []).append((os.path.basename(p), pv_name, r))
        sections_html.append(report.roast_section(title, groups))
    return sections_html


def main(argv=None):
    ap = argparse.ArgumentParser(description="挽き目・焙煎度の写真解析")
    ap.add_argument("mode", choices=["grind", "roast", "calibrate"])
    ap.add_argument("path")
    ap.add_argument("--out")
    ap.add_argument("--split", action="store_true")
    ap.add_argument("--points", type=float, nargs=4)
    ap.add_argument("--mm", type=float)
    ap.add_argument("--no-open", action="store_true", help="終わってもブラウザで開かない")
    a = ap.parse_args(argv)

    if a.mode == "calibrate":
        calibrate.run(a.path, a.points, a.mm)
        return

    cfg = load_config()
    if a.split:
        cfg["grind"]["split_touching"] = True
    folder = os.path.abspath(a.path)
    if not _sections(folder):
        print(f"写真が見つかりません: {folder}")
        sys.exit(1)
    out_dir = os.path.abspath(a.out or os.path.join(folder, "_report"))
    print(f"{'挽き目' if a.mode == 'grind' else '焙煎度'}の解析：{folder}（1画素 = {cfg['um_per_px']} µm）")
    secs = run_grind(folder, out_dir, cfg) if a.mode == "grind" else run_roast(folder, out_dir, cfg)
    name = "grind_report.html" if a.mode == "grind" else "roast_report.html"
    path = os.path.join(out_dir, name)
    report.write_html(path, "挽き目の解析" if a.mode == "grind" else "焙煎度の解析", secs, cfg)
    print(f"レポート: {path}")
    if not a.no_open:
        webbrowser.open("file:///" + path.replace("\\", "/"))


if __name__ == "__main__":
    main()
