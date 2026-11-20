import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ほかのアプリを使っている間のミニ表示（Android のピクチャーインピクチャー）。
/// Android 側は MainActivity.kt。スケールとつながっている間だけ、ホームに戻ったりアプリを切り替えたときに
/// 自動で小窓になり、グラフだけを表示する。
class PipService {
  PipService._();

  static const _ch = MethodChannel('brew/pip');

  /// いま小窓で表示されているか（表示を切り替えるために画面が見る）
  static final ValueNotifier<bool> inPip = ValueNotifier(false);

  static bool _initialized = false;
  static bool? _lastAuto;

  static void init() {
    if (_initialized) return;
    _initialized = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        inPip.value = call.arguments == true;
      }
      return null;
    });
  }

  /// この端末で小窓表示が使えるか
  static Future<bool> isSupported() async {
    try {
      return await _ch.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// アプリを離れたときに自動で小窓にするか（同じ値なら何もしない）
  static Future<void> setAutoEnter(bool enabled) async {
    if (_lastAuto == enabled) return;
    _lastAuto = enabled;
    try {
      await _ch.invokeMethod('setAutoEnter', {'enabled': enabled});
    } catch (_) {}
  }
}
