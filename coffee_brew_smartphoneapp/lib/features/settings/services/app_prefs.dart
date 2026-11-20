import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// アプリ全体の設定（app_prefs.json に保存）。
///
/// - [miniWindow]: スケールとつながっている間、アプリを離れたらグラフを小窓で表示する
class AppPrefs {
  AppPrefs._();

  static const _file = 'app_prefs.json';

  static final ValueNotifier<bool> miniWindow = ValueNotifier(true);

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
      miniWindow.value = m['miniWindow'] as bool? ?? true;
    } catch (_) {
      // 壊れていたら既定値のまま
    }
  }

  static Future<void> setMiniWindow(bool v) async {
    miniWindow.value = v;
    try {
      final f = await _path();
      await f.writeAsString(jsonEncode({'miniWindow': v}));
    } catch (_) {}
  }
}
