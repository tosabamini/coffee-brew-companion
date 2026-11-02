"""撮影受信サーバー：スマホの Coffee Lab アプリから写真を受け取り、名前を付けて保存し、その場で解析して結果を返す。

python server.py        （同じ Wi-Fi のスマホから自動で見つかる。見つからないときはアプリに表示中のアドレスを入力）

保存先（config.json の server で変更可）
  挽き目 : <リポジトリ>/grind_samples/<背景フォルダ>/<条件>_<番号>.jpg
  焙煎度 : <リポジトリ>/roast_samples/<フォルダ>/<条件>_<番号>.jpg
  確認用画像は各フォルダの _preview、取り消した写真は _trash に入る。
"""
import json
import os
import re
import shutil
import socket
import sys
import threading
import time
import traceback
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from common import HERE, IMAGE_EXTS, group_of, imwrite, list_images, load_config  # noqa: E402
import grind  # noqa: E402
import roast  # noqa: E402

SERVER_DEFAULT = {
    "port": 47130,
    "discovery_port": 47131,
    "grind_dir": "../../grind_samples",
    "roast_dir": "../../roast_samples",
}
KINDS = ("grind", "roast")
_cache = {}            # 画像パス → (更新時刻, 挽き目の粒リスト（輪郭なし）)
_lock = threading.Lock()


def server_cfg(cfg):
    s = dict(SERVER_DEFAULT)
    s.update(cfg.get("server") or {})
    return s


def root_of(kind, cfg):
    s = server_cfg(cfg)
    p = s["grind_dir"] if kind == "grind" else s["roast_dir"]
    p = p if os.path.isabs(p) else os.path.join(HERE, p)
    p = os.path.normpath(p)
    os.makedirs(p, exist_ok=True)
    return p


def clean_name(s, what):
    s = re.sub(r'[\\/:*?"<>|\s]+', "_", (s or "").strip()).strip("._")
    if not s:
        raise ValueError(f"{what}が空です")
    if s.startswith("_"):
        s = s.lstrip("_") or "x"
    return s[:60]


def folder_path(kind, folder, cfg):
    if kind not in KINDS:
        raise ValueError("kind は grind か roast")
    p = os.path.join(root_of(kind, cfg), clean_name(folder, "フォルダ名"))
    os.makedirs(p, exist_ok=True)
    return p


def groups_in(folder):
    out = {}
    for p in list_images(folder):
        g = group_of(p)
        out[g] = out.get(g, 0) + 1
    return out


def next_name(folder, group):
    n = 0
    pat = re.compile(r"^" + re.escape(group) + r"[_\-](\d+)$")
    for name in os.listdir(folder):
        stem, ext = os.path.splitext(name)
        m = pat.match(stem)
        if m and ext.lower() in IMAGE_EXTS:
            n = max(n, int(m.group(1)))
    for name in os.listdir(os.path.join(folder, "_trash")) if os.path.isdir(os.path.join(folder, "_trash")) else []:
        m = pat.match(os.path.splitext(name)[0])
        if m:
            n = max(n, int(m.group(1)))     # 取り消した番号は使い回さない
    return f"{group}_{n + 1:02d}.jpg"


def _strip(particles):
    return [{k: v for k, v in p.items() if k != "contour"} for p in particles]


def grind_particles(path, cfg, keep_result=False):
    blank = grind.find_blank(path)
    mt = (os.path.getmtime(path), os.path.getmtime(blank) if blank else 0)   # 空のトレイを撮り直したら解析し直す
    hit = _cache.get(path)
    if hit and hit[0] == mt and not keep_result:
        return hit[1], None
    r = grind.analyze_image(path, cfg)
    _cache[path] = (mt, _strip(r["particles"]))
    return _cache[path][1], r


def analyze_one(kind, folder, path, cfg):
    """1枚を解析し、スマホに返す結果と確認用画像を作る。"""
    prev_dir = os.path.join(folder, "_preview")
    os.makedirs(prev_dir, exist_ok=True)
    prev = os.path.join(prev_dir, os.path.basename(path))
    if kind == "grind" and grind.is_blank(path):
        return blank_result(folder, path, cfg)
    if kind == "grind":
        parts, r = grind_particles(path, cfg, keep_result=True)
        imwrite(prev, grind.overlay(r, max_side=1400), quality=85)
        det_dir = os.path.join(folder, "_detail")
        os.makedirs(det_dir, exist_ok=True)
        imwrite(os.path.join(det_dir, os.path.basename(path)), grind.detail_overlay(r, cfg), quality=90)
        s = grind.summarize(parts, cfg, n_boot=0) if parts else {"n": 0}
        g = group_of(path)
        group_parts = []
        n_img = 0
        for p in list_images(folder):
            if group_of(p) == g and not grind.is_blank(p):
                group_parts += grind_particles(p, cfg)[0]
                n_img += 1
        gs = grind.summarize(group_parts, cfg, n_boot=0) if group_parts else {"n": 0}
        res = {
            "n": s.get("n", 0),
            "n_below_limit": r["n_below_limit"],
            "vol_D50": s.get("vol_D50"), "num_D50": s.get("num_D50"),
            "fine_vol_pct": s.get("fine_vol_pct"), "boulder_vol_pct": s.get("boulder_vol_pct"),
            "clump_suspect_pct": s.get("clump_suspect_pct"),
            "n_chaff": r.get("n_chaff"), "chaff_area_pct": r.get("chaff_area_pct"),
            "n_dirt": r.get("n_dirt"), "blank": r.get("blank"), "blank_problem": r.get("blank_problem"),
            "group": g, "group_images": n_img, "group_n": gs.get("n", 0),
            "group_vol_D50": gs.get("vol_D50"), "group_vol_D10": gs.get("vol_D10"), "group_vol_D90": gs.get("vol_D90"),
        }
    else:
        r = roast.analyze_image(path, cfg)
        imwrite(prev, roast.preview(path, cfg, max_side=1400), quality=85)
        g = group_of(path)
        Ls = [roast.analyze_image(p, cfg)["L"] for p in list_images(folder) if group_of(p) == g]
        res = {"L": r["L"], "a": r["a"], "b": r["b"], "corrected": r["corrected"], "clipped_pct": r["clipped_pct"],
               "group": g, "group_images": len(Ls), "group_L": sum(Ls) / len(Ls)}
    res["warnings"] = photo_warnings(kind, res, r, cfg)
    return {k: (round(v, 2) if isinstance(v, float) else v) for k, v in res.items()}


def blank_result(folder, path, cfg):
    """空のトレイの写真：汚れ・傷の数を数えて返す。このあと同じフォルダで撮る写真から、これらを除く。"""
    from common import imread
    import cv2
    import numpy as np
    img = imread(path)
    dm, _ = grind._dirt_mask(img, grind._pick_channel(img))
    n = cv2.connectedComponents((dm > 0).astype(np.uint8))[0] - 1
    prev_dir = os.path.join(folder, "_preview")
    os.makedirs(prev_dir, exist_ok=True)
    ov = img.copy()
    cnts, _ = cv2.findContours((dm > 0).astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(ov, cnts, -1, (90, 90, 255), max(2, img.shape[1] // 1000))
    h, w = ov.shape[:2]
    sc = 1400 / max(h, w)
    imwrite(os.path.join(prev_dir, os.path.basename(path)), cv2.resize(ov, (int(w * sc), int(h * sc))), quality=85)
    cover = float((dm > 0).mean() * 100)
    warn = []
    if cover > 6:
        warn.append("暗い所が多すぎます（粉が残っていませんか）。トレイをきれいにして撮り直してください")
    return {"blank": True, "dirt_spots": int(n), "dirt_cover_pct": round(cover, 2), "warnings": warn}


def photo_warnings(kind, res, r, cfg):
    """撮り直したほうがよさそうな点。スマホの結果欄に出す。"""
    w = []
    if kind == "grind":
        n = res.get("n", 0)
        if (res.get("clump_suspect_pct") or 0) >= 15 or r["n_edge"] >= max(30, 0.3 * max(n, 1)):
            w.append("粒どうしが重なっています。粉を減らして、粒の間にすき間ができるように薄く散らしてください（重なった所は測れません）")
        if res.get("blank_problem"):
            w.append(res["blank_problem"])
        elif not res.get("blank"):
            w.append("空のトレイを先に撮っておくと、汚れや傷を粒と間違えずに済みます（「空のトレイを撮る」）")
        if n < 300:
            w.append(f"測れた粒が {n} 粒と少なめです。同じ条件で何枚か撮ると合計で安定します")
    else:
        if (res.get("clipped_pct") or 0) > 1:
            w.append("白飛びしています。明るさを下げてください")
        if not res.get("corrected"):
            w.append("色の補正なし（グレー基準を写して設定すると、照明の違いを打ち消せます）")
    if float(cfg["um_per_px"]) == 27.0 and not cfg.get("um_per_px_zoom1") and kind == "grind":
        w.append("大きさの較正がまだなので、µm の値は目安です（定規で較正.bat）")
    return w


def local_ips():
    """[(アドレス, 説明)]。Windows ではネットワークの名前も出す（VPN のアドレスと見分けるため）。"""
    out = []
    if os.name == "nt":
        try:
            import subprocess
            ps = ("Get-NetIPConfiguration | Where-Object { $_.NetAdapter.Status -eq 'Up' } | ForEach-Object { "
                  "$g = [bool]$_.IPv4DefaultGateway; foreach ($a in $_.IPv4Address) { "
                  "'{0}|{1}|{2}|{3}' -f $a.IPAddress, $_.InterfaceAlias, $_.NetAdapter.InterfaceDescription, $g } }")
            r = subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True, text=True,
                               timeout=15, encoding="utf-8", errors="replace")
            for line in r.stdout.splitlines():
                parts = line.strip().split("|")
                if len(parts) == 4 and not parts[0].startswith(("127.", "169.254.")):
                    vpn = any(k in (parts[1] + parts[2]).lower() for k in
                              ("vpn", "tap", "tun", "wireguard", "tailscale", "zerotier", "hamachi", "anyconnect", "fortinet", "pangp", "virtual", "vethernet", "hyper-v", "wsl"))
                    note = parts[1] + ("（VPN・仮想：スマホからは使えないことが多い）" if vpn else "") + ("" if parts[3] == "True" or vpn else "（ゲートウェイなし）")
                    out.append((parts[0], note, (not vpn) and parts[3] == "True"))
        except Exception:  # noqa: BLE001
            out = []
    if not out:
        ips = set()
        try:
            for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
                ips.add(info[4][0])
        except OSError:
            pass
        out = [(i, "", True) for i in sorted(ips) if not i.startswith(("127.", "169.254."))]
    out.sort(key=lambda x: not x[2])
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "CoffeeLab/1"

    def log_message(self, fmt, *args):
        pass

    def _json(self, obj, code=200):
        data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _q(self):
        u = urlparse(self.path)
        return u.path, {k: v[0] for k, v in parse_qs(u.query).items()}

    def do_GET(self):
        try:
            path, q = self._q()
            cfg = load_config()
            if path == "/ping":
                print(f"スマホから接続: {self.client_address[0]}", flush=True)
                return self._json({"app": "coffee_lab", "host": socket.gethostname(), "um_per_px": cfg["um_per_px"]})
            if path == "/folders":
                kind = q.get("kind", "grind")
                root = root_of(kind, cfg)
                folders = []
                for name in sorted(os.listdir(root)):
                    p = os.path.join(root, name)
                    if os.path.isdir(p) and not name.startswith("_"):
                        folders.append({"name": name, "groups": groups_in(p)})
                return self._json({"kind": kind, "root": root, "folders": folders})
            if path == "/preview":
                folder = folder_path(q["kind"], q["folder"], cfg)
                f = os.path.join(folder, "_preview", os.path.basename(q["file"]))
                if not os.path.exists(f):
                    return self._json({"error": "確認用画像がありません"}, 404)
                with open(f, "rb") as fh:
                    data = fh.read()
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return
            return self._json({"error": "not found"}, 404)
        except Exception as e:  # noqa: BLE001
            traceback.print_exc()
            return self._json({"error": str(e)}, 400)

    def do_POST(self):
        try:
            path, q = self._q()
            cfg = load_config()
            n = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(n) if n else b""
            if path == "/upload":
                kind = q.get("kind", "grind")
                if len(body) < 1000 or body[:2] != b"\xff\xd8":
                    raise ValueError("JPEG ではありません")
                group = clean_name(q.get("group", ""), "条件名")
                folder = folder_path(kind, q.get("folder", ""), cfg)
                with _lock:
                    name = next_name(folder, group)
                    dst = os.path.join(folder, name)
                    with open(dst, "wb") as f:
                        f.write(body)
                meta = q.get("meta")
                if meta:
                    with open(os.path.splitext(dst)[0] + ".json", "w", encoding="utf-8") as f:
                        json.dump({"received": time.strftime("%Y-%m-%d %H:%M:%S"), **json.loads(meta)}, f, ensure_ascii=False, indent=2)
                rel = os.path.relpath(dst, root_of(kind, cfg))
                print(f"受信: {kind}/{rel}（{len(body) / 1e6:.1f} MB）", flush=True)
                t0 = time.time()
                try:
                    result = analyze_one(kind, folder, dst, cfg)
                    err = None
                except Exception as e:  # noqa: BLE001
                    traceback.print_exc()
                    result, err = None, f"解析に失敗: {e}"
                if result:
                    if result.get("blank"):
                        print(f"   空のトレイを登録：汚れ・傷 {result['dirt_spots']} か所", flush=True)
                    elif kind == "grind":
                        print(f"   {result['n']}粒  D50(体積) {result['vol_D50']} µm   [{result['group']} {result['group_images']}枚の合計 D50 {result['group_vol_D50']} µm]  {time.time() - t0:.1f}秒", flush=True)
                    else:
                        print(f"   L* {result['L']}  a* {result['a']}  b* {result['b']}", flush=True)
                return self._json({"file": name, "folder": os.path.basename(folder), "kind": kind,
                                   "result": result, "error": err})
            if path == "/calibrate":
                import calib_grid
                import numpy as np
                import cv2
                if len(body) < 1000 or body[:2] != b"\xff\xd8":
                    raise ValueError("JPEG ではありません")
                grid_mm = float(q.get("grid_mm", "5"))
                img = cv2.imdecode(np.frombuffer(body, np.uint8), cv2.IMREAD_COLOR)
                res = calib_grid.measure(img, grid_mm)
                res["current"] = float(cfg["um_per_px"])
                res["grid_mm"] = grid_mm
                d = os.path.join(root_of("grind", cfg), "_calibration")
                os.makedirs(d, exist_ok=True)
                stem = time.strftime("grid_%Y%m%d_%H%M%S")
                with open(os.path.join(d, stem + ".jpg"), "wb") as f:
                    f.write(body)
                with open(os.path.join(d, stem + ".json"), "w", encoding="utf-8") as f:
                    json.dump(res, f, ensure_ascii=False, indent=2)
                print(f"大きさ合わせ: 1画素 = {res['um_per_px']:.2f} µm（横 {res['um_x']:.2f} / 縦 {res['um_y']:.2f}、今の設定 {res['current']}）", flush=True)
                return self._json({k: (round(v, 4) if isinstance(v, float) else v) for k, v in res.items()})
            if path == "/config":
                if "um_per_px" in q:
                    v = float(q["um_per_px"])
                    if not 1 <= v <= 500:
                        raise ValueError("値が範囲外です")
                    from common import save_config
                    cfg["um_per_px"] = round(v, 3)
                    save_config(cfg)
                    _cache.clear()
                    print(f"設定を保存: 1画素 = {cfg['um_per_px']} µm", flush=True)
                return self._json({"um_per_px": cfg["um_per_px"]})
            if path == "/undo":
                kind = q.get("kind", "grind")
                folder = folder_path(kind, q.get("folder", ""), cfg)
                name = os.path.basename(q["file"])
                trash = os.path.join(folder, "_trash")
                os.makedirs(trash, exist_ok=True)
                moved = []
                for f in (name, os.path.splitext(name)[0] + ".json"):
                    src = os.path.join(folder, f)
                    if os.path.exists(src):
                        shutil.move(src, os.path.join(trash, f))
                        moved.append(f)
                print(f"取り消し: {kind}/{os.path.basename(folder)}/{name}", flush=True)
                return self._json({"moved": moved})
            if path == "/report":
                kind = q.get("kind", "grind")
                import analyze  # 遅延読み込み（matplotlib が重いため）
                root = root_of(kind, cfg)
                target = folder_path(kind, q["folder"], cfg) if q.get("folder") else root
                out_dir = os.path.join(target, "_report")
                secs = analyze.run_grind(target, out_dir, cfg) if kind == "grind" else analyze.run_roast(target, out_dir, cfg)
                import report
                html = os.path.join(out_dir, f"{kind}_report.html")
                report.write_html(html, "挽き目の解析" if kind == "grind" else "焙煎度の解析", secs, cfg)
                webbrowser.open("file:///" + html.replace("\\", "/"))
                print(f"レポート: {html}", flush=True)
                return self._json({"report": html})
            return self._json({"error": "not found"}, 404)
        except Exception as e:  # noqa: BLE001
            traceback.print_exc()
            return self._json({"error": str(e)}, 400)


def discovery(port, http_port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", port))
    while True:
        try:
            data, addr = s.recvfrom(256)
            if data.startswith(b"COFFEELAB?"):
                print(f"スマホが探しています: {addr[0]}", flush=True)
                s.sendto(f"COFFEELAB {http_port} {socket.gethostname()}".encode(), addr)
        except OSError:
            time.sleep(0.5)


def main():
    cfg = load_config()
    s = server_cfg(cfg)
    threading.Thread(target=discovery, args=(s["discovery_port"], s["port"]), daemon=True).start()
    httpd = ThreadingHTTPServer(("0.0.0.0", s["port"]), Handler)
    print("=" * 60)
    print(" Coffee Lab 撮影受信サーバー")
    print("  スマホのアプリが自動で見つけます。見つからないときは次のアドレスを入力：")
    for ip, note, good in local_ips():
        print(f"   {'→' if good else '  '} {ip}:{s['port']}   {note}")
    print(f"  挽き目の保存先: {root_of('grind', cfg)}")
    print(f"  焙煎度の保存先: {root_of('roast', cfg)}")
    print("  スマホのテザリングに PC をつないでも使えます（初回のファイアウォールの確認で")
    print("  「パブリック ネットワーク」にもチェックを入れてください）。")
    print("  終了するときはこの画面を閉じてください。")
    print("=" * 60, flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
