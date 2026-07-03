# Coffee Brew Companion ☕️

A high-precision Flutter application designed to bridge the gap between coffee brewing as an art and as a science.

This app connects via **Bluetooth Low Energy (BLE)** to a custom-built ESP32 coffee scale, providing real-time extraction curves, recipe guidance, and comprehensive brewing logs.

---

## 🚀 Core Features

### 1. Real-time Brewing Visualization
- **Live Graphing**: Weight data from the scale is plotted instantly against a time axis.
- **Recipe Overlay**: Visualizes target zones on the graph based on the selected recipe.
- **Auto-Scaling**: Adjust bean quantity and all water volume targets recalculate automatically.

### 2. Smart Connectivity
- **BLE Service**: Robust connection management to ESP32 (HX711-based) scale.
- **Tare & Reset**: Control the scale directly from the app.
- **Real-time Timer**: Elapsed time updates independently via `Timer.periodic`, even if BLE pauses.

### 3. Multiple Recipe Management
- **Save multiple recipes** with names in Recipe Settings.
- **Horizontal scroll chip selector** on the main screen for quick switching.
- **Per-recipe bean quantity scaling** — set a base recipe and scale it for any bean amount.

### 4. Bean Quantity Measurement
- Tap **「豆量計測」** to tare and measure beans directly on the scale.
- Confirm with **「決定」** to auto-apply the measured weight to the recipe scaler.

### 5. Package Scan (AI Auto-fill)
- Tap **「パッケージ写真から自動入力」** in the Save Session screen.
- Take or select a photo of the coffee package.
- **Claude Haiku Vision API** extracts bean name, origin, variety, process, roast level, flavor notes, and elevation automatically.
- All fields remain editable after auto-fill.

### 6. Brew Logging & Metadata
- **Session History**: Every brew saved with its weight curve and timestamps.
- **Deep Metadata**: Origin, roast, grind, variety, process, elevation, flavor notes.
- **Saved Bean Presets**: Reuse previously entered bean info.

---

## 🏗 Project Structure

```
coffee-brew-companion/
├── coffee_brew_smartphoneapp/     # Flutter app
│   └── lib/
│       ├── config/
│       │   ├── api_config.dart.example   # APIキーテンプレート
│       │   └── api_config.dart           # APIキー（.gitignore対象）
│       └── features/scale/
│           ├── models/
│           │   ├── brew_recipe.dart      # Recipe model (with id field)
│           │   ├── coffee_session.dart
│           │   ├── weight_point.dart
│           │   └── pour_step.dart
│           ├── screens/
│           │   ├── main_screen.dart
│           │   ├── save_session_screen.dart
│           │   ├── session_detail_screen.dart
│           │   ├── recipe_settings_screen.dart
│           │   └── history_screen.dart
│           ├── services/
│           │   ├── ble_scale_service.dart
│           │   ├── session_storage.dart
│           │   └── claude_vision_service.dart
│           └── widgets/
│               └── weight_graph.dart
└── coffee_scale_ble/
    └── coffee_scale_ble.ino               # ESP32 firmware
```

---

## ⚙️ Setup

### Flutter App

```bash
cd coffee_brew_smartphoneapp
flutter pub get
flutter run
```

### API Key (Package Scan feature)

1. Copy `lib/config/api_config.dart.example` → `lib/config/api_config.dart`
2. Get an API key from [console.anthropic.com](https://console.anthropic.com)
3. Paste the key into `api_config.dart`

`api_config.dart` is excluded from Git via `.gitignore`.

---

## 🔧 Hardware (ESP32)

| Item | Detail |
|------|--------|
| MCU | ESP32 (WROOM-32) |
| Load cell ADC | HX711 |
| DT pin | GPIO 4 |
| SCK pin | GPIO 5 |
| Calibration | 5-sample trimmed mean × 10 iterations at boot |
| BLE notify interval | ~210ms |
| Scaling factor | 236.2 (hardware-specific) |

### BLE Profile

| Item | Value |
|------|-------|
| Service UUID | `12345678-1234-1234-1234-1234567890ab` |
| Characteristic UUID | `abcdefab-1234-1234-1234-abcdefabcdef` |
| Data format | UTF-8 string e.g. `"12.5"` |

---

## 📦 Dependencies

| Package | Purpose |
|---------|---------|
| `flutter_blue_plus` | BLE communication |
| `path_provider` | Local file storage |
| `permission_handler` | Android runtime permissions |
| `image_picker` | Camera / gallery for package scan |
| `http` | Claude Vision API calls |
