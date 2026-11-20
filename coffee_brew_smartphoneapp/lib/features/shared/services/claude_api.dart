import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../config/api_config.dart';

/// Claude API への問い合わせ（パッケージ写真の読み取り・フレーバーの分類・AIチャットで共通）。
/// APIキーは lib/config/api_config.dart（Git に入らないファイル）から読む。
class ClaudeApi {
  ClaudeApi._();

  static const String _url = 'https://api.anthropic.com/v1/messages';

  /// 使うモデル（すべて Sonnet 5.5）
  static const String model = 'claude-sonnet-5-5';

  static bool get hasKey =>
      ApiConfig.claudeApiKey.isNotEmpty && ApiConfig.claudeApiKey != 'YOUR_API_KEY_HERE';

  /// メッセージを送り、返ってきた文章をつなげて返す。
  /// [messages] は [{'role': 'user' | 'assistant', 'content': 文字列 または ブロックの配列}]。
  static Future<String> send({
    String? system,
    required List<Map<String, dynamic>> messages,
    int maxTokens = 1024,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!hasKey) {
      throw Exception('APIキーが設定されていません（set_api_key.bat で設定してください）');
    }
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'messages': messages,
    };
    if (system != null && system.isNotEmpty) body['system'] = system;

    final response = await http
        .post(
          Uri.parse(_url),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': ApiConfig.claudeApiKey,
            'anthropic-version': '2023-06-01',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode != 200) {
      final message = (decoded is Map ? decoded['error']?['message'] : null) ?? response.statusCode;
      throw Exception('AIの呼び出しに失敗しました（${response.statusCode}）: $message');
    }
    final content = (decoded['content'] as List?) ?? const [];
    final text = content
        .whereType<Map>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'].toString())
        .join();
    if (text.trim().isEmpty) {
      throw Exception('AIから返事がありませんでした');
    }
    return text;
  }

  /// 返事の中から最初の JSON オブジェクトを取り出す（前後に説明文があっても読めるように）
  static Map<String, dynamic>? extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final v = jsonDecode(text.substring(start, end + 1));
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
}
