import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ble_link.dart';
import 'platform.dart';

/// ライト（2台目のスマホ）とカメラの連携（PC は不要）。
///   まず Bluetooth（BLE。ble_link.dart）でつなぐ。見つからないときだけ同じ Wi-Fi で探す。
///   ライト側：BLE の受け口と、HTTP サーバー（47132）・探されたときに返事をする UDP（47133）の両方を開く
///   カメラ側：BLE で探してつなぐ。だめなら UDP で探して HTTP で送る

const int kLightPort = 47132;
const int kLightDiscoveryPort = 47133;

class LightPreset {
  final String key; // フォルダ名などに使う英字
  final String name;
  final int r, g, b;
  const LightPreset(this.key, this.name, this.r, this.g, this.b);
}

const kLightPresets = [
  LightPreset('white', '白', 255, 255, 255),
  LightPreset('warmwhite', '暖かい白', 255, 236, 214),
  LightPreset('gray', '灰', 128, 128, 128),
  LightPreset('lightbrown', '薄い茶', 196, 160, 124),
  LightPreset('brown', '茶', 120, 82, 54),
  LightPreset('darkbrown', '濃い茶', 64, 42, 28),
  LightPreset('red', '赤', 255, 0, 0),
  LightPreset('green', '緑', 0, 255, 0),
  LightPreset('blue', '青', 0, 0, 255),
  LightPreset('black', '黒', 0, 0, 0),
];

/// 色が一致するプリセット（なければ null）
LightPreset? presetOf(int r, int g, int b) {
  for (final p in kLightPresets) {
    if (p.r == r && p.g == g && p.b == b) return p;
  }
  return null;
}

class LightState {
  /// 'solid'（無地）または 'grid'（方眼：実寸 gridMm ごとに黒い線）
  final String mode;
  final int r, g, b;
  final double brightness; // 0〜1
  final double gridMm;
  final double lineMm;

  const LightState({
    this.mode = 'solid',
    this.r = 255,
    this.g = 255,
    this.b = 255,
    this.brightness = 1.0,
    this.gridMm = 5.0,
    this.lineMm = 0.3,
  });

  LightState copyWith({String? mode, int? r, int? g, int? b, double? brightness, double? gridMm, double? lineMm}) =>
      LightState(
        mode: mode ?? this.mode,
        r: r ?? this.r,
        g: g ?? this.g,
        b: b ?? this.b,
        brightness: brightness ?? this.brightness,
        gridMm: gridMm ?? this.gridMm,
        lineMm: lineMm ?? this.lineMm,
      );

  Map<String, dynamic> toJson() =>
      {'mode': mode, 'r': r, 'g': g, 'b': b, 'brightness': brightness, 'grid_mm': gridMm, 'line_mm': lineMm};

  factory LightState.fromJson(Map<String, dynamic> j, [LightState base = const LightState()]) {
    int i(String k, int d) => (j[k] as num?)?.toInt().clamp(0, 255) ?? d;
    double f(String k, double d) => (j[k] as num?)?.toDouble() ?? d;
    return LightState(
      mode: (j['mode'] as String?) == 'grid' ? 'grid' : ((j['mode'] as String?) == 'solid' ? 'solid' : base.mode),
      r: i('r', base.r),
      g: i('g', base.g),
      b: i('b', base.b),
      brightness: f('brightness', base.brightness).clamp(0.05, 1.0),
      gridMm: f('grid_mm', base.gridMm).clamp(1.0, 50.0),
      lineMm: f('line_mm', base.lineMm).clamp(0.1, 3.0),
    );
  }

  String get label {
    final p = presetOf(r, g, b);
    final c = p?.name ?? 'RGB($r,$g,$b)';
    return mode == 'grid' ? '$c・方眼${gridMm.toStringAsFixed(gridMm == gridMm.roundToDouble() ? 0 : 1)}mm' : c;
  }
}

/// UDP ブロードキャストで相手を探す。見つかったら "ip:port" を返す。
/// 255.255.255.255 に加えて、つながっている各ネットワークの x.x.x.255 にも送る（テザリングの親機対策）。
Future<String?> discoverService({
  required String query,
  required String replyPrefix,
  required int port,
  required int defaultHttpPort,
  Duration timeout = const Duration(milliseconds: 1800),
}) async {
  RawDatagramSocket? sock;
  try {
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    sock = s;
    s.broadcastEnabled = true;
    final completer = Completer<String?>();
    s.listen((ev) {
      if (ev == RawSocketEvent.read) {
        final d = s.receive();
        if (d == null) return;
        final msg = utf8.decode(d.data, allowMalformed: true);
        if (msg.startsWith('$replyPrefix ') && !completer.isCompleted) {
          final parts = msg.split(' ');
          final p = parts.length > 1 ? parts[1] : '$defaultHttpPort';
          completer.complete('${d.address.address}:$p');
        }
      }
    });
    final payload = utf8.encode(query);
    final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
    try {
      for (final nif in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in nif.addresses) {
          if (a.isLoopback) continue;
          final p = a.address.split('.');
          if (p.length == 4) targets.add(InternetAddress('${p[0]}.${p[1]}.${p[2]}.255'));
        }
      }
    } catch (_) {}
    for (var i = 0; i < 3; i++) {
      for (final t in targets) {
        try {
          s.send(payload, t, port);
        } catch (_) {}
      }
      await Future.any([completer.future, Future.delayed(const Duration(milliseconds: 300))]);
      if (completer.isCompleted) break;
    }
    return await completer.future.timeout(timeout, onTimeout: () => null);
  } catch (_) {
    return null;
  } finally {
    sock?.close();
  }
}

// ───────── ライト側 ─────────

/// ライトのスマホで動かす小さなサーバー。カメラから色・模様の変更を受け付ける。
class LightServer {
  final LightState Function() getState;
  final void Function(LightState) onSet;
  final Map<String, dynamic> Function() displayInfo;
  final void Function()? onVibrate;
  /// Bluetooth の状態が変わったとき（画面の表示を更新する）
  final void Function()? onStatus;
  HttpServer? _http;
  RawDatagramSocket? _udp;

  /// 'starting' / 'advertising'（カメラ待ち） / 'connected' / 'off' / 'denied' / 'unsupported' / 'adv_failed:N' など
  String bleStatus = 'starting';

  LightServer({required this.getState, required this.onSet, required this.displayInfo, this.onVibrate, this.onStatus});

  /// Bluetooth の受け口を（開き直して）開く
  Future<void> startBle() async {
    BleLink.onServerStatus = (st) {
      bleStatus = st;
      onStatus?.call();
    };
    bleStatus = 'starting';
    onStatus?.call();
    final st = await BleLink.startServer(_bleRequest);
    if (st != 'ok') bleStatus = st;
    onStatus?.call();
  }

  Future<void> start() async {
    try {
      final h = await HttpServer.bind(InternetAddress.anyIPv4, kLightPort, shared: true);
      _http = h;
      h.listen(_handle, onError: (_) {});
    } catch (_) {}
    try {
      final u = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kLightDiscoveryPort, reuseAddress: true);
      _udp = u;
      u.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final d = u.receive();
        if (d == null) return;
        if (utf8.decode(d.data, allowMalformed: true).startsWith('COFFEELIGHT?')) {
          try {
            u.send(utf8.encode('COFFEELIGHT $kLightPort'), d.address, d.port);
          } catch (_) {}
        }
      });
    } catch (_) {}
    await startBle();
  }

  bool get running => _http != null;

  Future<void> stop() async {
    BleLink.onServerStatus = null;
    await BleLink.stopServer();
    _udp?.close();
    _udp = null;
    await _http?.close(force: true);
    _http = null;
  }

  /// 指示を1つ処理して返事を返す（Wi-Fi と Bluetooth で共通）。
  Future<Map<String, dynamic>> handleCommand(String path, Map<String, dynamic> j) async {
    if (path == '/info') {
      return {'app': 'coffee_lab_light', 'state': getState().toJson(), 'display': displayInfo()};
    }
    if (path == '/vibrate') {
      if (j['stop'] == true) {
        await Screen.vibrateCancel();
        return {'ok': true};
      }
      final ok = await Screen.vibrate(
        ms: (j['ms'] as num?)?.toInt().clamp(10, 60000) ?? 300,
        strength: (j['strength'] as num?)?.toDouble() ?? 1.0,
        pulses: (j['pulses'] as num?)?.toInt() ?? 1,
        gapMs: (j['gap_ms'] as num?)?.toInt().clamp(0, 5000) ?? 150,
      );
      onVibrate?.call();
      return {'ok': ok};
    }
    if (path == '/set') {
      final s = LightState.fromJson(j, getState());
      onSet(s);
      return {'state': s.toJson()};
    }
    throw const _NotFound();
  }

  Future<String> _bleRequest(String raw) async {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final b = m['b'];
      final r = await handleCommand('${m['p']}', b is Map ? Map<String, dynamic>.from(b) : <String, dynamic>{});
      return jsonEncode(r);
    } catch (e) {
      return jsonEncode({'error': e is _NotFound ? 'not found' : '$e'});
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final path = req.uri.path;
      if (path != '/info' && req.method != 'POST') throw const _NotFound();
      final body = req.method == 'POST' ? await utf8.decoder.bind(req).join() : '';
      final j = body.isEmpty ? <String, dynamic>{} : jsonDecode(body) as Map<String, dynamic>;
      _json(res, await handleCommand(path, j));
    } on _NotFound {
      res.statusCode = 404;
      _json(res, {'error': 'not found'});
    } catch (e) {
      res.statusCode = 400;
      _json(res, {'error': '$e'});
    }
  }

  void _json(HttpResponse res, Object o) {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(o));
    res.close();
  }
}

class _NotFound implements Exception {
  const _NotFound();
}

// ───────── カメラ側 ─────────

/// Bluetooth でつながらなかった理由を、やることが分かる文に
String bleReasonText(String r) {
  if (r == 'denied') return '許可がありません。設定 → アプリ → Coffee Lab → 権限 で「付近のデバイス」と「位置情報」を許可してください';
  if (r == 'off') return 'Bluetooth がオフです。オンにしてください';
  if (r == 'location_off') return '見つかりません。位置情報（GPS）をオンにしてもう一度試してください（この機種では必要なことがあります）';
  if (r == 'not_found') return 'ライトが見つかりません。ライトのスマホで「ライト」を開き、そちらの表示が「接続を待っています」か確認してください';
  if (r == 'unsupported') return 'この端末は Bluetooth LE に対応していません';
  if (r == 'no_reply') return 'ライトは見つかりましたが、返事がありません';
  if (r == 'busy') return '許可の確認中です。もう一度押してください';
  if (r.startsWith('scan_failed')) return '検索に失敗しました（$r）。数秒待ってからもう一度試してください';
  if (r.startsWith('gatt') || r == 'no_service') return 'ライトへの接続に失敗しました（$r）。もう一度試してください';
  return 'つながりませんでした（$r）';
}

class LightClient {
  /// Wi-Fi でつなぐときのライトの "ip:port"
  String? address;

  /// いま Bluetooth でつながっているか（false なら Wi-Fi）
  bool viaBle = false;

  /// 最後に Bluetooth でつながらなかった理由（つながったら空）
  String bleError = '';
  LightState? state;
  Map<String, dynamic>? display;

  LightClient(this.address);

  static Future<String?> discover() => discoverService(
        query: 'COFFEELIGHT?',
        replyPrefix: 'COFFEELIGHT',
        port: kLightDiscoveryPort,
        defaultHttpPort: kLightPort,
      );

  String get linkName => viaBle ? 'Bluetooth' : 'Wi-Fi';

  /// ライトにつなぐ。まず Bluetooth、だめなら Wi-Fi（覚えているアドレス → 探す）。
  Future<bool> connect() async {
    if (viaBle && await ping()) return true;
    viaBle = false;
    final r = await BleLink.connect();
    if (r == 'ok') {
      viaBle = true;
      if (await ping()) {
        bleError = '';
        return true;
      }
      viaBle = false;
      bleError = 'no_reply';
      await BleLink.disconnect();
    } else {
      bleError = r;
    }
    if (await ping()) return true;
    final found = await discover();
    if (found != null) {
      address = found;
      if (await ping()) return true;
    }
    return false;
  }

  Uri _uri(String path) {
    final a = address!;
    return Uri.parse('http://${a.contains(':') ? a : '$a:$kLightPort'}$path');
  }

  Future<Map<String, dynamic>> _req(String method, String path, [Object? body]) async {
    if (viaBle) {
      final text = await BleLink.request(jsonEncode({'p': path, 'b': body ?? <String, dynamic>{}}))
          .timeout(const Duration(seconds: 8));
      final d = jsonDecode(text) as Map<String, dynamic>;
      if (d.length == 1 && d['error'] != null) throw Exception('${d['error']}');
      return d;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.openUrl(method, _uri(path)).timeout(const Duration(seconds: 4));
      if (body != null) {
        final data = utf8.encode(jsonEncode(body));
        req.headers.contentType = ContentType.json;
        req.contentLength = data.length;
        req.add(data);
      }
      final res = await req.close().timeout(const Duration(seconds: 4));
      final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 4));
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> ping() async {
    if (!viaBle && address == null) return false;
    try {
      final d = await _req('GET', '/info');
      if (d['app'] != 'coffee_lab_light') return false;
      state = LightState.fromJson(d['state'] as Map<String, dynamic>);
      display = d['display'] as Map<String, dynamic>?;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ライトのスマホを振動させる。振動できたら true。
  Future<bool> vibrate({int ms = 300, double strength = 1.0, int pulses = 1, int gapMs = 150}) async {
    final d = await _req('POST', '/vibrate', {'ms': ms, 'strength': strength, 'pulses': pulses, 'gap_ms': gapMs});
    return d['ok'] == true;
  }

  Future<void> stopVibrate() async {
    await _req('POST', '/vibrate', {'stop': true});
  }

  Future<LightState> set(LightState s) async {
    final d = await _req('POST', '/set', s.toJson());
    state = LightState.fromJson(d['state'] as Map<String, dynamic>);
    return state!;
  }
}
