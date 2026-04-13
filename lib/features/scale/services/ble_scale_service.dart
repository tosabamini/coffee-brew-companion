import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleScaleService {
  static const String serviceUuid = "12345678-1234-1234-1234-1234567890ab";
  static const String characteristicUuid = "abcdefab-1234-1234-1234-abcdefabcdef";
  static const String deviceName = "CoffeeScale";

  BluetoothDevice? _device;
  BluetoothCharacteristic? _weightCharacteristic;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;

  final StreamController<double> _weightController =
  StreamController<double>.broadcast();
  final StreamController<bool> _connectionController =
  StreamController<bool>.broadcast();
  final StreamController<String> _statusController =
  StreamController<String>.broadcast();

  Stream<double> get weightStream => _weightController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String> get statusStream => _statusController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid) return;

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final locationOk =
        statuses[Permission.locationWhenInUse]?.isGranted ?? false;
    final scanOk = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectOk = statuses[Permission.bluetoothConnect]?.isGranted ?? false;

    if (!locationOk) {
      throw Exception('Location permission not granted');
    }
    if (!scanOk) {
      throw Exception('Bluetooth scan permission not granted');
    }
    if (!connectOk) {
      throw Exception('Bluetooth connect permission not granted');
    }
  }

  bool _matchesTarget(ScanResult result) {
    final platformName = result.device.platformName.trim();
    final advName = result.advertisementData.advName.trim();

    final names = <String>[
      platformName,
      advName,
    ].where((e) => e.isNotEmpty).map((e) => e.toLowerCase()).toList();

    final targetName = deviceName.toLowerCase();

    final matchesName =
    names.any((name) => name == targetName || name.contains(targetName));

    final advertisedServices = result.advertisementData.serviceUuids
        .map((e) => e.str.toLowerCase())
        .toList();

    final matchesService =
    advertisedServices.any((uuid) => uuid == serviceUuid.toLowerCase());

    return matchesName || matchesService;
  }

  Future<void> connect() async {
    await _requestPermissions();

    _statusController.add('Scanning...');
    _connectionController.add(false);

    await disconnect();

    final completer = Completer<ScanResult?>();

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final platformName = result.device.platformName;
        final advName = result.advertisementData.advName;
        final serviceList =
        result.advertisementData.serviceUuids.map((e) => e.str).join(', ');

        _statusController.add(
          'Found: platform="$platformName", adv="$advName", services=[$serviceList]',
        );

        if (_matchesTarget(result) && !completer.isCompleted) {
          completer.complete(result);
          break;
        }
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 8),
    );

    final result = await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );

    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;

    if (result == null) {
      _statusController.add('Scale not found');
      throw Exception('CoffeeScale not found');
    }

    _device = result.device;
    _statusController.add(
      'Connecting to ${_device!.platformName.isNotEmpty ? _device!.platformName : result.advertisementData.advName}...',
    );

    _connectionSub = _device!.connectionState.listen((state) {
      final connected = state == BluetoothConnectionState.connected;
      _isConnected = connected;
      _connectionController.add(connected);
      _statusController.add(connected ? 'Connected' : 'Disconnected');
    });

    try {
      await _device!.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
    } catch (_) {
      // ignore
    }

    final services = await _device!.discoverServices();

    BluetoothCharacteristic? found;
    for (final service in services) {
      if (service.uuid.str.toLowerCase() == serviceUuid.toLowerCase()) {
        for (final c in service.characteristics) {
          if (c.uuid.str.toLowerCase() == characteristicUuid.toLowerCase()) {
            found = c;
            break;
          }
        }
      }
    }

    if (found == null) {
      _statusController.add('Characteristic not found');
      throw Exception('Weight characteristic not found');
    }

    _weightCharacteristic = found;

    await _weightCharacteristic!.setNotifyValue(true);

    _notifySub = _weightCharacteristic!.lastValueStream.listen((value) {
      try {
        final text = utf8.decode(value).trim();
        final weight = double.tryParse(text);
        if (weight != null) {
          _weightController.add(weight);
        }
      } catch (_) {
        // ignore parse errors
      }
    });

    try {
      final initialValue = await _weightCharacteristic!.read();
      final text = utf8.decode(initialValue).trim();
      final weight = double.tryParse(text);
      if (weight != null) {
        _weightController.add(weight);
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;

    await _connectionSub?.cancel();
    _connectionSub = null;

    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {
        // ignore
      }
    }

    _weightCharacteristic = null;
    _device = null;
    _isConnected = false;
    _connectionController.add(false);
  }

  Future<void> dispose() async {
    await disconnect();
    await _scanSub?.cancel();
    await _weightController.close();
    await _connectionController.close();
    await _statusController.close();
  }
}