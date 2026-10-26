import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'session_storage.dart';

/// 全データ（記録・レシピ・豆の在庫・豆情報・フレーバーホイールなど）を
/// 1つのJSONファイルに書き出す／取り込む。
///
/// アプリの保存フォルダ直下にある .json / .txt をそのまま丸ごと入れるので、
/// 保存ファイルが増えても自動で対象になる。
class BackupService {
  BackupService._();

  static const String _appId = 'coffee_brew_companion';
  static const int _formatVersion = 1;

  static bool _isTarget(String name) =>
      name.endsWith('.json') || name.endsWith('.txt');

  /// バックアップファイルを作って共有シートを開く。入れたファイル数を返す
  static Future<int> exportAndShare() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = <String, String>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!_isTarget(name)) continue;
      files[name] = await entity.readAsString();
    }

    final now = DateTime.now();
    final stamp =
        '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}';
    final data = {
      'app': _appId,
      'version': _formatVersion,
      'createdAt': now.toIso8601String(),
      'files': files,
    };

    final tmp = await getTemporaryDirectory();
    final out = File('${tmp.path}/brew_companion_backup_$stamp.json');
    await out.writeAsString(jsonEncode(data));

    await Share.shareXFiles(
      [XFile(out.path, mimeType: 'application/json')],
      text: 'Brew Companion バックアップ',
    );
    return files.length;
  }

  /// バックアップファイルを読み込んで、保存データを上書きする。書き戻したファイル数を返す。
  /// 形式が違うファイルなら FormatException を投げる
  static Future<int> restoreFrom(File backup) async {
    final decoded = jsonDecode(await backup.readAsString());
    if (decoded is! Map || decoded['app'] != _appId || decoded['files'] is! Map) {
      throw const FormatException('Brew Companion のバックアップファイルではありません');
    }
    final files = Map<String, dynamic>.from(decoded['files'] as Map);
    final dir = await getApplicationDocumentsDirectory();
    int count = 0;
    for (final entry in files.entries) {
      final name = entry.key;
      // フォルダ外への書き込みを防ぐ
      if (name.contains('/') || name.contains('\\') || name.contains('..')) continue;
      if (!_isTarget(name) || entry.value is! String) continue;
      await File('${dir.path}/$name').writeAsString(entry.value as String);
      count++;
    }
    // ホーム画面のレシピ一覧を読み直させる
    SessionStorage.recipesRevision.value++;
    return count;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
