# Coffee Brew Companion ☕️

A high-precision Flutter application designed to bridge the gap between coffee brewing as an art and as a science. 

This app connects via **Bluetooth Low Energy (BLE)** to a custom-built ESP32 coffee scale, providing real-time extraction curves, recipe guidance, and comprehensive brewing logs.

---

## 📖 Table of Contents
- [Core Features](#-core-features)
- [Project Structure & Key Files](#-project-structure--key-files)
- [Deep Dive into Scale Feature](#-deep-dive-into-scale-feature)
- [Hardware Integration](#-hardware-integration)
- [Tech Stack](#-tech-stack)
- [Roadmap & Vision](#-roadmap--vision)

---

## 🚀 Core Features

### 1. Real-time Brewing Visualization
- **Live Graphing**: Weight data from the scale is plotted instantly against a time axis.
- **Recipe Overlay**: Visualizes "target zones" on the graph based on selected recipes, helping you time your pours perfectly.
- **Auto-Scaling**: Adjust the amount of coffee beans, and the app recalculates all water volume targets in the recipe automatically.

### 2. Smart Connectivity
- **BLE Service**: Robust background service to manage connection to ESP32 (HX711-based) scales.
- **Tare & Reset**: Control the scale hardware directly from the app's interface.

### 3. Brew Logging & Metadata
- **Session History**: Every brew is saved with its weight curve and time data.
- **Deep Metadata**: Track coffee origin, roast level, grind size, elevation, and sensory notes.

---

## 🏗 Project Structure & Key Files

This project uses a **Feature-based Architecture**. If you want to improve or fix something, here is where to look:

### `lib/features/scale/` (The Core Engine)
This is where 90% of the current logic resides.

#### 📱 Screens (`/screens/`)
- **`main_screen.dart`**: The primary dashboard. Contains the live graph and real-time weight display. **Edit here to change the UI layout of the brewing screen.**
- **`history_screen.dart`**: Lists all past brewing sessions.
- **`session_detail_screen.dart`**: Shows the post-brew analysis and the saved graph.
- **`save_session_screen.dart`**: The form where users input bean metadata and tasting notes after a brew.
- **`recipe_settings_screen.dart`**: Configuration for recipe targets and auto-scaling logic.

#### ⚙️ Services (`/services/`)
- **`ble_scale_service.dart`**: Manages scanning, connecting, and parsing BLE packets from the ESP32. **Go here if you have connection issues or want to support new scale protocols.**
- **`session_storage.dart`**: Handles local persistence (JSON/SharedPrefs) for your brew history.

#### 📦 Models (`/models/`)
- **`coffee_session.dart`**: The main data structure representing a completed brew.
- **`weight_point.dart`**: Simple (timestamp, weight) pair for graph plotting.
- **`brew_recipe.dart`**: Defines the target pours, timings, and ratios.

---

## 🛠 Deep Dive into Scale Feature

### How the Data Flows
1. **ESP32** sends a raw weight string via BLE (e.g., `"12.5"`).
2. **`ble_scale_service.dart`** listens to the characteristic, parses the string to a double, and notifies the app.
3. **`main_screen.dart`** receives the stream of weights, adds them to a list of `WeightPoint`, and triggers a UI rebuild for the graph.
4. **`session_storage.dart`** serializes the entire session to a local file once "Save" is pressed.

---

## ⚙️ Hardware Integration

This app is designed to work with the following DIY hardware setup:
- **MCU**: ESP32 (WROOM-32)
- **Scale Module**: HX711 Load Cell Amplifier
- **BLE Profile**: Custom GATT service with a Notify characteristic for weight data.

*Note: The app expects a UTF-8 string of the current weight sent periodically from the scale.*

---

## 💻 Tech Stack
- **Framework**: [Flutter](https://flutter.dev)
- **State Management**: Provider / StreamBuilder
- **Charts**: `fl_chart` for high-performance real-time plotting.
- **BLE**: `flutter_blue_plus` for reliable Bluetooth communication.

---

## 🗺 Roadmap & Vision

1. **Flavor Mapping**: Integrating an interactive **Flavor Wheel** to record sensory data beyond just text.
2. **Grind Analysis**: Using the camera and Computer Vision to estimate the average particle size (microns) of your coffee grounds.
3. **Cloud Sync**: Optional backup of brew history to Firebase or Supabase.
4. **Advanced Recipes**: Support for "Pulse Pour" vs "Steady Flow" visualizations.

---

## 🤝 Contribution Guide
1. **Adding a UI Element?** Check `lib/features/scale/widgets/` first for existing components.
2. **Changing Data Structure?** Update the models in `lib/features/scale/models/` and ensure the `toJson` logic in `session_storage.dart` is updated.
3. **Fixing BLE?** Most issues are in `ble_scale_service.dart`.
