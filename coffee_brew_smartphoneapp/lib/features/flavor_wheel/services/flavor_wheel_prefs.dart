import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// フレーバーホイールの表示設定（flavor_wheel_prefs.json に保存）。
///
/// - [useLegacy]: true なら旧デザイン（FlavorWheelScreen）を表示する。
///   新デザインで不具合があったときにすぐ戻せるようにするためのスイッチ。
/// - [japaneseLabels]: 新デザインでフレーバー名を日本語で表示するか。
class FlavorWheelPrefs {
  FlavorWheelPrefs._();

  static const _file = 'flavor_wheel_prefs.json';

  static final ValueNotifier<bool> useLegacy = ValueNotifier(false);
  static final ValueNotifier<bool> japaneseLabels = ValueNotifier(true);

  static bool _loaded = false;

  static Future<File> _path() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_file');
  }

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _path();
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      useLegacy.value = m['useLegacy'] as bool? ?? false;
      japaneseLabels.value = m['japaneseLabels'] as bool? ?? true;
    } catch (_) {
      // 壊れていたら既定値のまま
    }
  }

  static Future<void> _save() async {
    try {
      final f = await _path();
      await f.writeAsString(jsonEncode({
        'useLegacy': useLegacy.value,
        'japaneseLabels': japaneseLabels.value,
      }));
    } catch (_) {}
  }

  static Future<void> setUseLegacy(bool v) async {
    useLegacy.value = v;
    await _save();
  }

  static Future<void> setJapaneseLabels(bool v) async {
    japaneseLabels.value = v;
    await _save();
  }
}
