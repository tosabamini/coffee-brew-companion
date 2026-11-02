import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'light_link.dart';

/// PC の撮影受信サーバー（analysis/coffee_lab/server.py）とのやりとり。
class LabClient {
  static const int defaultPort = 47130;
  static const int discoveryPort = 47131;

  /// "192.168.1.10:47130" の形
  String? address;
  String? hostName;

  LabClient(this.address);

  Uri _uri(String path, [Map<String, String>? q]) {
    final a = address!;
    final withPort = a.contains(':') ? a : '$a:$defaultPort';
    return Uri.parse('http://$withPort$path').replace(queryParameters: q);
  }

  String previewUrl(String kind, String folder, String file) =>
      _uri('/preview', {'kind': kind, 'folder': folder, 'file': file}).toString();

  /// 同じ Wi-Fi のサーバーを探す（UDP ブロードキャスト）。見つかったら "ip:port" を返す。
  static Future<String?> discover() => discoverService(
        query: 'COFFEELAB?',
        replyPrefix: 'COFFEELAB',
        port: discoveryPort,
        defaultHttpPort: defaultPort,
      );

  Future<Map<String, dynamic>> _send(String method, Uri uri,
      {Uint8List? body, Duration timeout = const Duration(seconds: 8)}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final req = await client.openUrl(method, uri).timeout(timeout);
      if (body != null) {
        req.headers.contentType = ContentType('image', 'jpeg');
        req.contentLength = body.length;
        req.add(body);
      } else if (method == 'POST') {
        req.contentLength = 0;
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      final data = jsonDecode(text) as Map<String, dynamic>;
      if (res.statusCode != 200 || data['error'] != null && data['file'] == null) {
        throw LabException('${data['error'] ?? 'エラー ${res.statusCode}'}');
      }
      return data;
    } on LabException {
      rethrow;
    } on TimeoutException {
      throw LabException('PC から応答がありません');
    } on SocketException {
      throw LabException('PC につながりません');
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> ping() async {
    if (address == null) return false;
    try {
      final d = await _send('GET', _uri('/ping'), timeout: const Duration(seconds: 3));
      hostName = d['host'] as String?;
      return d['app'] == 'coffee_lab';
    } catch (_) {
      return false;
    }
  }

  /// {フォルダ名: {条件名: 枚数}}
  Future<Map<String, Map<String, int>>> folders(String kind) async {
    final d = await _send('GET', _uri('/folders', {'kind': kind}));
    final out = <String, Map<String, int>>{};
    for (final f in (d['folders'] as List)) {
      final m = f as Map<String, dynamic>;
      out[m['name'] as String] =
          (m['groups'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toInt()));
    }
    return out;
  }

  Future<Map<String, dynamic>> upload({
    required String kind,
    required String folder,
    required String group,
    required Uint8List jpeg,
    Map<String, dynamic>? meta,
  }) {
    return _send(
      'POST',
      _uri('/upload', {
        'kind': kind,
        'folder': folder,
        'group': group,
        if (meta != null) 'meta': jsonEncode(meta),
      }),
      body: jpeg,
      timeout: const Duration(seconds: 90),
    );
  }

  Future<void> undo(String kind, String folder, String file) async {
    await _send('POST', _uri('/undo', {'kind': kind, 'folder': folder, 'file': file}));
  }

  /// 方眼（実寸 gridMm）を写した写真から 1画素の大きさを求める。保存はしない。
  Future<Map<String, dynamic>> calibrateGrid(Uint8List jpeg, double gridMm) {
    return _send('POST', _uri('/calibrate', {'grid_mm': gridMm.toString()}), body: jpeg, timeout: const Duration(seconds: 60));
  }

  Future<void> saveScale(double umPerPx) async {
    await _send('POST', _uri('/config', {'um_per_px': umPerPx.toString()}));
  }

  Future<void> report(String kind, {String? folder}) async {
    await _send('POST', _uri('/report', {'kind': kind, if (folder != null) 'folder': folder}),
        timeout: const Duration(seconds: 300));
  }
}

class LabException implements Exception {
  final String message;
  LabException(this.message);
  @override
  String toString() => message;
}
