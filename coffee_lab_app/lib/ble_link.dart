import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

/// ライトとカメラの Bluetooth（BLE）連携。Android 側は BleLink.kt。
///   ライト側：BLE で「ここにいます」と知らせ続け（アドバタイズ）、カメラからの指示を受けて返事をする
///   カメラ側：ライトを探してつなぎ、指示（JSON）を書き込んで返事を読む
/// ペアリングは不要。中身は Wi-Fi のときと同じ {"p": "/set", "b": {...}} 形式。
class BleLink {
  static const _ch = MethodChannel('coffee_lab/ble');
  static Future<String> Function(String request)? _serverHandler;

  /// ライト側の状態の知らせ（'advertising' / 'connected' / 'adv_failed:N' など）
  static void Function(String status)? onServerStatus;
  static bool _installed = false;

  static void _install() {
    if (_installed) return;
    _installed = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'request') {
        final h = _serverHandler;
        if (h == null) return jsonEncode({'error': 'not ready'});
        try {
          return await h(call.arguments as String);
        } catch (e) {
          return jsonEncode({'error': '$e'});
        }
      }
      if (call.method == 'serverStatus') onServerStatus?.call('${call.arguments}');
      return null;
    });
  }

  /// 権限を確かめる（足りなければ許可を求める）。'ok' / 'off' / 'denied' / 'unsupported' / 'busy'
  static Future<String> ensure(String role) async {
    _install();
    try {
      return await _ch.invokeMethod<String>('ensure', {'role': role}) ?? 'unsupported';
    } catch (_) {
      return 'unsupported';
    }
  }

  // ───────── ライト側 ─────────

  static Future<String> startServer(Future<String> Function(String request) handler) async {
    _install();
    _serverHandler = handler;
    final st = await ensure('peripheral');
    if (st != 'ok') return st;
    try {
      return await _ch.invokeMethod<String>('serverStart') ?? 'unsupported';
    } catch (_) {
      return 'unsupported';
    }
  }

  static Future<void> stopServer() async {
    _serverHandler = null;
    try {
      await _ch.invokeMethod('serverStop');
    } catch (_) {}
  }

  // ───────── カメラ側 ─────────

  /// ライトを探してつなぐ。'ok' か、つながらなかった理由
  /// （'denied' / 'off' / 'location_off' / 'not_found' / 'gatt:133' / 'scan_failed:N' など。説明は bleReasonText）。
  static Future<String> connect({int timeoutMs = 8000}) async {
    final st = await ensure('central');
    if (st != 'ok') return st;
    try {
      return await _ch.invokeMethod<String>('connect', {'timeoutMs': timeoutMs}) ?? 'error';
    } catch (e) {
      return 'error';
    }
  }

  static Future<void> disconnect() async {
    try {
      await _ch.invokeMethod('disconnect');
    } catch (_) {}
  }

  static Future<void> _queue = Future.value();

  /// 指示を1つ送って返事を受け取る（同時には1つずつ）。
  static Future<String> request(String data) {
    final c = Completer<String>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await _ch.invokeMethod<String>('request', {'data': data}) ?? '{}');
      } catch (e) {
        c.completeError(e);
      }
    });
    return c.future;
  }
}
