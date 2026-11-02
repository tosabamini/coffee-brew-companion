import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// 画面の明るさ・常時点灯（Android 側 MainActivity.kt）と、小さな設定ファイル。
class Screen {
  static const _ch = MethodChannel('coffee_lab/screen');

  /// 0〜1。負の値で端末の設定に戻す。
  static Future<void> setBrightness(double v) async {
    try {
      await _ch.invokeMethod('setBrightness', {'value': v});
    } catch (_) {}
  }

  static Future<void> keepOn(bool on) async {
    try {
      await _ch.invokeMethod('keepOn', {'on': on});
    } catch (_) {}
  }

  /// 振動させる。ms ミリ秒を pulses 回（間に gapMs 休む）。strength は 0〜1。振動できなければ false。
  static Future<bool> vibrate({int ms = 300, double strength = 1.0, int pulses = 1, int gapMs = 150}) async {
    final timings = <int>[0];
    for (var i = 0; i < pulses.clamp(1, 50); i++) {
      if (i > 0) timings.add(gapMs);
      timings.add(ms);
    }
    try {
      return await _ch.invokeMethod<bool>('vibrate', {
            'timings': timings,
            'amplitude': (strength.clamp(0.0, 1.0) * 255).round().clamp(1, 255),
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> vibrateCancel() async {
    try {
      await _ch.invokeMethod('vibrateCancel');
    } catch (_) {}
  }

  /// {xdpi, ydpi, density, widthPixels, heightPixels, model}
  static Future<Map<String, dynamic>> displayInfo() async {
    try {
      final m = await _ch.invokeMethod<Map>('displayInfo');
      return m == null ? {} : Map<String, dynamic>.from(m);
    } catch (_) {
      return {};
    }
  }

  static Future<String?> filesDir() async {
    try {
      return await _ch.invokeMethod<String>('filesDir');
    } catch (_) {
      return null;
    }
  }
}

/// アプリの設定（JSON 1ファイル）。
class Prefs {
  static Map<String, dynamic> _data = {};
  static File? _file;

  static Future<void> load() async {
    final dir = await Screen.filesDir();
    if (dir == null) return;
    _file = File('$dir/coffee_lab_settings.json');
    try {
      if (await _file!.exists()) {
        _data = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {
      _data = {};
    }
  }

  static T? get<T>(String key) {
    final v = _data[key];
    return v is T ? v : null;
  }

  static Future<void> set(String key, Object? value) async {
    _data[key] = value;
    try {
      await _file?.writeAsString(jsonEncode(_data));
    } catch (_) {}
  }
}
