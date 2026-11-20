# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working Guidelines

- 回答は日本語で行う
- コード変更の前に、原因と修正方針を必ず説明する
- 変更は最小限にとどめ、関係ないファイルは触らない
- FlutterのUI変更では、対象Widgetと状態管理の流れを先に確認してから作業する

## Project Overview

Coffee Brew Companion is a dual-component system:
- **Flutter mobile app** (`coffee_brew_smartphoneapp/`) — connects to a BLE scale, visualizes real-time brew data, and logs sessions
- **ESP32 firmware** (`coffee_scale_ble/coffee_scale_ble.ino`) — reads HX711 load cell and advertises weight via BLE GATT notify

## Commands

All commands run from `coffee_brew_smartphoneapp/`:

```bash
flutter pub get          # Install dependencies
flutter run              # Run on connected device/emulator
flutter test             # Run tests
flutter analyze          # Lint (uses flutter_lints)
flutter build apk        # Android release build
```

## Architecture

### Data Flow

```
ESP32 (HX711 → BLE GATT notify every ~210ms)
  → BleScaleService (weightStream, connectionStream, statusStream)
  → MainScreen (StreamBuilder bindings, live WeightPoint list)
  → WeightGraph (CustomPainter canvas render)
  → SaveSessionScreen → CoffeeSession → SessionStorage (local JSON)
```

### Key Files

| File | Role |
|------|------|
| `lib/features/scale/services/ble_scale_service.dart` | BLE scanning, connection, weight parsing into streams |
| `lib/features/scale/services/session_storage.dart` | JSON persistence: sessions, multiple recipes, current recipe ID |
| `lib/features/shared/services/claude_api.dart` | Claude API の共通窓口（`ClaudeApi.model` = `claude-sonnet-5-5`。写真読み取り・フレーバー分類・AIチャットで共通） |
| `lib/features/scale/services/claude_vision_service.dart` | パッケージ写真から豆情報を抽出（ClaudeApi 経由） |
| `lib/features/shared/widgets/ai_chat_screen.dart` | AIチャット画面（共通）。返事の ```[tag] {JSON}``` を反映ボタンにする |
| `lib/features/scale/screens/main_screen.dart` | Orchestrates BLE state, measurement, recipe selection, bean measurement |
| `lib/features/scale/widgets/weight_graph.dart` | Custom `CustomPainter` real-time graph (no charting library) |
| `lib/features/scale/models/coffee_session.dart` | Main domain model with all brew metadata + weight points |
| `lib/features/scale/models/brew_recipe.dart` | Recipe model with `id`, `scaledForBeanQuantity()` scaling logic |
| `lib/features/scale/data/preset_recipes.dart` | 有名店・バリスタのプリセットレシピ（編集不可、JSONには保存しない） |
| `lib/config/api_config.dart` | APIキー設定（.gitignore対象 — コミットしない） |
| `lib/theme/app_theme.dart` | デザインシステム（BrewColorsパレット + AppTheme + ページ遷移） |
| `lib/theme/brew_widgets.dart` | 共有ウィジェット（PulsingDot / SectionLabel / FadeSlideIn） |
| `lib/splash_screen.dart` | 起動アニメーション（抽出カーブ描画 + 重量カウンター、約1.4秒） |
| `lib/features/scale/services/csv_export_service.dart` | セッションCSV出力（share_plus経由で共有） |
| `lib/features/scale/screens/stats_screen.dart` | 統計ダッシュボード（履歴画面から遷移） |
| `lib/features/scale/screens/bean_inventory_screen.dart` | 豆在庫・エイジング管理 |
| `lib/features/scale/models/bean_stock.dart` | 豆在庫モデル（bean_stocks.json に保存） |

### State Management

No Provider/Riverpod/GetX — state is managed via:
- `StreamController` in `BleScaleService` for BLE data
- `setState` in stateful screens for UI state
- `StreamBuilder` widgets for live BLE stream consumption
- `Timer.periodic` in `MainScreen` for independent elapsed time display

### BLE Profile

- Service UUID: `12345678-1234-1234-1234-1234567890ab`
- Characteristic UUID: `abcdefab-1234-1234-1234-abcdefabcdef`
- Data format: UTF-8 string `"weight:XX.XX"` notified every ~210ms
- Uses `onValueReceived` (not `lastValueStream`) to avoid stale value replay on reconnect

### Multiple Recipe System

- `SessionStorage.loadRecipes()` / `saveRecipes()` — `brew_recipes.json` に複数保存
- `SessionStorage.loadCurrentRecipeId()` / `saveCurrentRecipeId()` — 選択中レシピIDを永続化
- `BrewRecipe.id` — タイムスタンプベースの一意ID（例: `"1747300000000"`）
- MainScreen: 横スクロール `ChoiceChip` でレシピを切り替え
- **プリセット**: `PresetRecipes.all`（id は `preset_` で始まる、`BrewRecipe.isPreset`）。選択ボトムシートで「マイレシピ」「有名店・バリスタ」の2セクション表示。選択中IDはマイレシピ→プリセットの順で解決
- `BrewRecipe.source`（nullable、後方互換）: 出典。プリセットからコピーしたマイレシピに引き継ぐ
- RecipeSettingsScreen: 「既存のレシピをコピーして作る」/ 保存済み一覧のコピーボタンで、プリセット・マイレシピを新規レシピとして複製して編集できる（0からの作成も可）

### Bean Measurement Feature

MainScreen に「豆量計測」ボタンがあり、タレ後に豆をのせて「決定」すると `_currentBeanQuantityG` が更新されレシピスケーリングに反映される。

### App Navigation

- `lib/app_shell.dart`（`AppShell`）: 下部 `NavigationBar`（高さ62）で「ホーム / 豆 / フレーバー / 設定」を切り替え。`IndexedStack` なのでタブ切替でBLE接続・計測は途切れない。Splash → AppShell
- 豆タブ = `BeanInventoryScreen`（AppBarの「豆情報を登録」から `SaveSessionScreen(points: [])` へ）
- 設定タブ = `lib/features/settings/screens/settings_screen.dart`（今はレシピ管理への入口のみ）
- タブのルート画面では `Navigator.pop(context)` を呼ばないこと（AppShellごと閉じる）。保存後にpopする画面（SaveSessionScreen, RecipeSettingsScreen）はpushで開く
- フレーバータブ = `FlavorWheelTab`（`flavor_wheel/screens/flavor_wheel_tab.dart`）。`FlavorWheelPrefs.useLegacy` で新デザイン `FlavorWheelV2Screen`（サンバースト、タップで拡大、`widgets/flavor_sunburst.dart`）と旧デザイン `FlavorWheelScreen`（変更せず保存）を切り替える。設定タブのスイッチから戻せる。表示設定は `flavor_wheel_prefs.json`、日本語名は `data/flavor_labels_ja.dart`
- `SessionStorage.recipesRevision`（ValueNotifier）: レシピ保存・選択IDの保存で増え、MainScreenが購読して再読込する

### MainScreen Layout Policy

- **グラフ最優先**: AppBarは使わず薄いカスタムヘッダー（`_buildTopBar`）。上部要素はコンパクトに保ち、残り全高をグラフに割り当てる。実機の狭い画面でグラフが潰れないようにするための方針なので、上部に要素を追加する際は高さに注意
- レシピ選択は横チップ列ではなく**ピル1つ＋ボトムシート**（`_pickRecipe`）
- 旧ステータス行（IDLE/BREWINGバッジ）は撤去済み（git履歴の `_buildStatusRow` 参照）
- システムバー色は `SystemChrome.setSystemUIOverlayStyle` で管理（main.dart / splash_screen.dart）
- ランチャーアイコンは `assets/icon/*.png` を `flutter_launcher_icons`（Androidのみ）で反映

### Live Brew (MainScreen)

- 抽出中の FLOW / PACE / RATIO、「0:45 までに 120g」、「○g 先行」の表示は 2026-11 にユーザーの希望で撤去（グラフを見れば分かるため）。ヒーローカードは重さと時間だけ
- **自動スタート**: 「自動」トグルでワンショット武装。直近6サンプルの最小値から **+2.0g** 増加で計測開始（スケールノイズ±0.5g対策の閾値）。`_isMeasuringBeans` 中は判定停止、発動・切断で自動解除
- **ゴースト表示**: グラフヘッダーのレイヤーアイコンから過去セッションを選び、曲線を半透明で重ねる。重さは「今回の豆量 ÷ ゴーストの豆量（doseG → なければレシピの豆量）」倍に換算（時間はそのまま）。凡例は「ゴースト 16→18g」
- **小窓表示（PiP）**: スケール接続中はアプリを離れると Android のピクチャーインピクチャーで重さ・時間・グラフだけを表示。`PipService`（`brew/pip` チャンネル、MainActivity.kt）・`LiveBrew`（MainScreen が更新）・`MiniBrewView`（main.dart の `MaterialApp.builder` で IndexedStack 切替。元の画面は残す）。設定タブ `AppPrefs.miniWindow`（app_prefs.json）で無効化できる

### Rating / Repeat / Pour Cues / Backup

- `CoffeeSession.rating`（1〜3: いまいち/好き/とても好き, nullable）と `isFavorite`（後方互換）。入力UIは `widgets/rating_row.dart`。**詳細画面だけ**（即保存）。保存画面は抽出直後でまだ飲んでいないので評価を置かない。履歴は★でお気に入り絞り込み
- `CoffeeSession.notes` は**豆のメモ**（`SessionStorage.loadBeanPresets` の豆の見分けキーに含まれる）。1杯ごとのメモは `brewNotes`（キーに含めない）。ドリッパーは `dripper`（`data/drippers.dart` の一覧＋自由入力、`widgets/dripper_field.dart`）。「この条件でもう一度」ではドリッパーを引き継ぐ
- 「この条件でもう一度」: 詳細画面 → `Navigator.pop(session)` → 履歴も pop で中継 → MainScreen `_applyTemplate`（レシピ・豆量・ゴーストをセット）。次の `SaveSessionScreen(template:)` で豆情報を初期入力（1回限り）
- 注湯合図: `MainScreen._checkPourCues()`（重量ストリーム受信ごとに判定）。各ステップ開始3秒前と開始時に `HapticFeedback` + `SystemSound.click`。端末のタッチ振動/操作音設定に依存
- バックアップ: `services/backup_service.dart`。保存フォルダ直下の .json/.txt を丸ごと1ファイルに（share_plus で共有）、復元は `file_picker` で選んで上書き。設定タブから

### Brew Analytics

- `CoffeeSession.doseG` / `tdsPercent`（nullable、後方互換）から `brewRatio` / `extractionYieldPercent` を算出。抽出液量は「総注湯 − 豆量×2.0（保持率近似）」
- 保存画面・詳細画面に豆量/TDS入力欄あり。dose初期値は豆量計測値 or レシピ豆量
- CSV: 履歴画面=全セッションサマリ、詳細画面=重量点データ。UTF-8 BOM付きでExcel対応

### AI (Claude API, Sonnet 5.5)

- モデルは `ClaudeApi.model`（`claude-sonnet-5-5`）で一括管理。`api_config.dart` の `visionModel` は使っていない
- フレーバー: `flavor_wheel/services/flavor_ai.dart` の `FlavorAi.suggest` が新しいフレーバーの大分類・中分類を提案（ホイールの追加シート・未分類の「分類する」で自動、保存画面の自由入力ダイアログはボタン）。ユーザー追加の項目は長押しで「移動 / 削除」。ホイール右上から AI チャット（```flavor_add で追加提案）と「よく使うフレーバー」（`my_flavors_screen.dart`、記録に出たフレーバーだけを大分類ごとに頻度で文字サイズを変えて表示）
- 詳細画面: 「AIに相談」で記録（豆・レシピ・5秒ごとの重さ・メモ・評価）を渡してチャット。```recipe の提案は `BrewAi.saveRecipeFromJson` でマイレシピに保存

### Package Scan Feature (Vision API)

- `ClaudeVisionService.analyzeCoffeePackage(File)` → `CoffeePackageInfo`
- Claude Sonnet 5.5（`ClaudeApi.model`）を使用
- SaveSessionScreen の「パッケージ写真から自動入力」ボタンから起動
- APIキーは `lib/config/api_config.dart` に設定（`.gitignore` 対象）
- テンプレート: `lib/config/api_config.dart.example`

### Feature Structure

`lib/features/scale/` is the only active feature. The directories `bean_notes/`, `grind_analysis/`, `recipe/`, and `shared/` are scaffolded placeholders for future expansion. `flavor_wheel/` is partially implemented.

### Hardware (ESP32)

- HX711 pins: DT=4, SCK=5
- Calibration: トリム平均（5サンプル・最小最大除外）を10回平均してゼロ点を決定
- `wait_ready()` で変換完了を待ってからサンプリング（重複読み防止）
- Scaling factor: `236.2`（ハードウェア固有定数）
- BLE advertising uses preferred connection intervals tuned for iOS/Android stability
