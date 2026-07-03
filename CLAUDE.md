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
| `lib/features/scale/services/claude_vision_service.dart` | Claude Vision API (Haiku) でパッケージ写真から豆情報を抽出 |
| `lib/features/scale/screens/main_screen.dart` | Orchestrates BLE state, measurement, recipe selection, bean measurement |
| `lib/features/scale/widgets/weight_graph.dart` | Custom `CustomPainter` real-time graph (no charting library) |
| `lib/features/scale/models/coffee_session.dart` | Main domain model with all brew metadata + weight points |
| `lib/features/scale/models/brew_recipe.dart` | Recipe model with `id`, `scaledForBeanQuantity()` scaling logic |
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

### Bean Measurement Feature

MainScreen に「豆量計測」ボタンがあり、タレ後に豆をのせて「決定」すると `_currentBeanQuantityG` が更新されレシピスケーリングに反映される。

### MainScreen Layout Policy

- **グラフ最優先**: AppBarは使わず薄いカスタムヘッダー（`_buildTopBar`）。上部要素はコンパクトに保ち、残り全高をグラフに割り当てる。実機の狭い画面でグラフが潰れないようにするための方針なので、上部に要素を追加する際は高さに注意
- レシピ選択は横チップ列ではなく**ピル1つ＋ボトムシート**（`_pickRecipe`）
- 旧ステータス行（IDLE/BREWINGバッジ）は撤去済み（git履歴の `_buildStatusRow` 参照）
- システムバー色は `SystemChrome.setSystemUIOverlayStyle` で管理（main.dart / splash_screen.dart）
- ランチャーアイコンは `assets/icon/*.png` を `flutter_launcher_icons`（Androidのみ）で反映

### Live Brew Metrics (MainScreen)

- **流量 (FLOW)**: 直近約1秒の重量差分から g/s を算出しヒーローカード下段に表示
- **ペースガイド (PACE)**: `_recipeTargetAt()` がレシピステップを線形補間（各ステップ目標量へ「次ステップ開始まで」に到達する想定）。±2g以内は ON PACE
- **レシオ (RATIO)**: `_currentBeanQuantityG` と現在重量から 1:N を表示
- **自動スタート**: 「自動」トグルでワンショット武装。直近6サンプルの最小値から **+2.0g** 増加で計測開始（スケールノイズ±0.5g対策の閾値）。`_isMeasuringBeans` 中は判定停止、発動・切断で自動解除
- **ゴースト表示**: グラフヘッダーのレイヤーアイコンから過去セッションを選び、曲線を半透明で重ねる

### Brew Analytics

- `CoffeeSession.doseG` / `tdsPercent`（nullable、後方互換）から `brewRatio` / `extractionYieldPercent` を算出。抽出液量は「総注湯 − 豆量×2.0（保持率近似）」
- 保存画面・詳細画面に豆量/TDS入力欄あり。dose初期値は豆量計測値 or レシピ豆量
- CSV: 履歴画面=全セッションサマリ、詳細画面=重量点データ。UTF-8 BOM付きでExcel対応

### Package Scan Feature (Vision API)

- `ClaudeVisionService.analyzeCoffeePackage(File)` → `CoffeePackageInfo`
- Claude Haiku (`claude-haiku-4-5`) を使用
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
