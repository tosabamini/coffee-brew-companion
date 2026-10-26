# CoffeeHolder — 紙コップホルダー

このリポジトリ（coffee-brew-companion）の中にある、**独立した別アプリ**です。
抽出アプリ・スケール・挽き目サンプルなど、ほかのフォルダとはコードもデータも共有していません。

3Dプリント用の紙コップホルダーを作るための、次の2つのブラウザアプリとその生成プログラムです。

| アプリ | 内容 |
|---|---|
| 組み合わせ | 本体（柄164種と無地）と持ち手（130種）を選んで3Dで確認し、結合したSTLを保存する |
| 画像から作る | 画像の明るさを穴（透かし）や凹凸（浮き彫り）にして、ホルダーの側面に巻き付ける |

どちらもネットにつながっていなくても動きます。
寸法は紙コップ（`assets/cup.stl`）の外形に0.35 mmのすき間を足したもので、試作で合うことを確認済みです。

## 使い方

1. ビルドします（下の「ビルド」を参照）。
2. `dist/組み合わせ/index.html` か `dist/画像から作る/index.html` をブラウザ（Chrome / Edge）で開きます。
3. 「STLを保存」を押すと、zipに入ったSTLがダウンロードフォルダに保存されます。

## ビルド

```
pip install -r requirements.txt
python build.py              # 全部（部品約300個とサムネイル。数十分かかります）
python build.py --html       # HTMLだけ組み直す（web/ を直したとき）
python build.py --only b153 h126   # 指定した部品だけ作り直す（b=本体, h=持ち手）
python build.py --thumbs     # サムネイルだけ描き直す（generator/fastr.py を直したとき）
```

- 部品ごとのSTLは `build/stl/` にもできます。
- `build/` と `dist/` は生成物なので、Gitには入れていません（`.gitignore`）。

## フォルダ構成

```
CoffeeHolder/
├─ build.py                 ビルドの入口
├─ requirements.txt
├─ generator/               形を作るPython
│   ├─ common.py, geokit.py, lightkit.py   紙コップの寸法・筒の展開・立体化の共通部分
│   ├─ lib100.py            柄の壁の作り方（桟の太さの確保、浮いた部分の補強など）
│   ├─ patterns100.py       柄 B001〜B124
│   ├─ coffee_bodies.py     柄 B125〜B154（コーヒー）
│   ├─ caf_bodies.py        柄 B155〜B164（カフェインの構造式）
│   ├─ cafkit.py            カフェイン分子（1,3,7-トリメチルキサンチン）の座標
│   ├─ hkit.py              持ち手の部品（チューブ・スイープ・板）とコップとの干渉よけ
│   ├─ handles100.py        持ち手 H001〜H115
│   ├─ coffee_handles.py    持ち手 H116〜H125（コーヒー）
│   ├─ caf_handles.py       持ち手 H126〜H130（カフェイン）
│   ├─ body_params.json     柄ごとの調整値
│   └─ fastr.py             サムネイル用の簡易レンダラー
├─ web/                     アプリのHTMLの元とライブラリ
│   ├─ combo.template.html, image_maker.template.html
│   ├─ image_core.js        画像→ホルダー変換の計算部分
│   └─ lib/                 three.js, OrbitControls, fflate, manifold（WASM）
└─ assets/
    ├─ cup.stl              紙コップのモデル
    └─ image_maker_handles.json   画像から作るアプリの持ち手6種
```

全デザインの番号と名前は [DESIGNS.md](DESIGNS.md) にあります。

## 柄・持ち手を追加するには

- 柄：`generator/` の該当ファイルに、`(W, H, rng, scale)` を受け取って穴（と浮き出し線）のポリゴンを返す関数を `@reg(...)` で追加します。
- 持ち手：`hkit.py` の部品で形を作り、Manifoldを返す関数を追加します。
- 追加したら、`build.py` の `N_BODY` / `N_HAND` と、`body_entry` / `hand_entry` の番号の範囲を合わせてください。
