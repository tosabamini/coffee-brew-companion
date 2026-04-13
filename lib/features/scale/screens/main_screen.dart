import 'dart:async';

import 'package:flutter/material.dart';

import '../models/brew_recipe.dart';
import '../models/weight_point.dart';
import '../services/ble_scale_service.dart';
import '../services/session_storage.dart';
import '../widgets/weight_graph.dart';
import 'history_screen.dart';
import 'recipe_settings_screen.dart';
import 'save_session_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final BleScaleService _bleScaleService = BleScaleService();

  StreamSubscription<double>? _weightSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<String>? _statusSub;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isMeasuring = false;

  String _connectionText = 'Disconnected';

  double _rawWeightG = 0.0;
  double _tareOffsetG = 0.0;
  double _displayWeightG = 0.0;

  DateTime? _measurementStartTime;
  final List<WeightPoint> _points = [];

  BrewRecipe? _currentRecipe;
  double? _currentBeanQuantityG;

  @override
  void initState() {
    super.initState();
    _loadRecipe();
    _bindBleStreams();
  }

  void _bindBleStreams() {
    _weightSub = _bleScaleService.weightStream.listen((weight) {
      _rawWeightG = weight;
      _displayWeightG = _rawWeightG - _tareOffsetG;
      if (_displayWeightG < 0) _displayWeightG = 0;

      if (_isMeasuring && _measurementStartTime != null) {
        final elapsed = DateTime.now().difference(_measurementStartTime!);
        _points.add(
          WeightPoint(
            elapsedMs: elapsed.inMilliseconds,
            weightG: _displayWeightG,
          ),
        );
      }

      if (mounted) {
        setState(() {});
      }
    });

    _connectionSub = _bleScaleService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
          if (!connected) {
            _isConnecting = false;
          }
        });
      }
    });

    _statusSub = _bleScaleService.statusStream.listen((status) {
      if (mounted) {
        setState(() {
          _connectionText = status;
          if (status == 'Connected' || status == 'Scale not found') {
            _isConnecting = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _weightSub?.cancel();
    _connectionSub?.cancel();
    _statusSub?.cancel();
    _bleScaleService.dispose();
    super.dispose();
  }

  Future<void> _loadRecipe() async {
    final recipe = await SessionStorage.loadCurrentRecipe();
    if (!mounted) return;
    setState(() {
      _currentRecipe = recipe;
      _currentBeanQuantityG = recipe?.beanQuantityG;
    });
  }

  BrewRecipe? _effectiveRecipe() {
    if (_currentRecipe == null) return null;
    return _currentRecipe!.scaledForBeanQuantity(_currentBeanQuantityG);
  }

  Future<void> _toggleBluetooth() async {
    if (_isConnected) {
      await _disconnectScale();
    } else {
      await _connectScale();
    }
  }

  Future<void> _connectScale() async {
    if (_isConnecting || _isConnected) return;

    setState(() {
      _isConnecting = true;
      _connectionText = 'Connecting...';
    });

    try {
      await _bleScaleService.connect();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _connectionText = 'Connection failed';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('BLE connect failed: $e')),
      );
    }
  }

  Future<void> _disconnectScale() async {
    await _bleScaleService.disconnect();
    if (!mounted) return;
    setState(() {
      _isConnected = false;
      _connectionText = 'Disconnected';
      _isConnecting = false;
    });
  }

  Future<void> _toggleMeasurement() async {
    if (_isMeasuring) {
      await _stopMeasurement();
    } else {
      _startMeasurement();
    }
  }

  void _startMeasurement() {
    if (!_isConnected) return;

    setState(() {
      _points.clear();
      _measurementStartTime = DateTime.now();
      _isMeasuring = true;
    });
  }

  Future<void> _stopMeasurement() async {
    setState(() {
      _isMeasuring = false;
    });

    if (_points.isEmpty) return;

    final copiedPoints = _points
        .map((e) => WeightPoint(elapsedMs: e.elapsedMs, weightG: e.weightG))
        .toList();

    final recipeSnapshot = _effectiveRecipe()?.copy();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SaveSessionScreen(
          points: copiedPoints,
          recipe: recipeSnapshot,
        ),
      ),
    );

    setState(() {});
  }

  void _tare() {
    setState(() {
      _tareOffsetG = _rawWeightG;
      _displayWeightG = 0.0;
    });
  }

  void _clearSession() {
    setState(() {
      _points.clear();
      _measurementStartTime = null;
      _isMeasuring = false;
    });
  }

  String _formatDuration(Duration duration) {
    final totalSec = duration.inSeconds;
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _elapsedText() {
    if (_measurementStartTime == null) return '0:00';

    final Duration elapsed;
    if (_isMeasuring) {
      elapsed = DateTime.now().difference(_measurementStartTime!);
    } else if (_points.isNotEmpty) {
      elapsed = Duration(milliseconds: _points.last.elapsedMs);
    } else {
      elapsed = Duration.zero;
    }

    return _formatDuration(elapsed);
  }

  String _formatSec(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _recipeSummary() {
    if (_currentRecipe == null || _currentRecipe!.isEmpty) {
      return 'No recipe set';
    }

    final name = (_currentRecipe!.name == null || _currentRecipe!.name!.isEmpty)
        ? 'Unnamed recipe'
        : _currentRecipe!.name!;
    final pours = _currentRecipe!.steps.length;
    final endSec = _currentRecipe!.targetEndSec;
    final endText = endSec == null ? '-' : _formatSec(endSec);

    final baseQtyText = _currentRecipe!.beanQuantityG == null
        ? '-'
        : '${_currentRecipe!.beanQuantityG!.toStringAsFixed(0)}g';

    final currentQtyText = _currentBeanQuantityG == null
        ? '-'
        : '${_currentBeanQuantityG!.toStringAsFixed(0)}g';

    return '$name | $pours pours | end $endText | base $baseQtyText | now $currentQtyText';
  }

  void _increaseBeanQuantity() {
    if (_currentRecipe == null || _currentRecipe!.beanQuantityG == null) return;
    setState(() {
      _currentBeanQuantityG = (_currentBeanQuantityG ?? _currentRecipe!.beanQuantityG!) + 1;
    });
  }

  void _decreaseBeanQuantity() {
    if (_currentRecipe == null || _currentRecipe!.beanQuantityG == null) return;
    final current = _currentBeanQuantityG ?? _currentRecipe!.beanQuantityG!;
    if (current <= 1) return;
    setState(() {
      _currentBeanQuantityG = current - 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectionColor = _isConnected ? Colors.green : Colors.red;
    final effectiveRecipe = _effectiveRecipe();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coffee Scale'),
        actions: [
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RecipeSettingsScreen()),
              );
              await _loadRecipe();
            },
            icon: const Icon(Icons.tune),
            tooltip: 'Recipe Settings',
          ),
          IconButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
              setState(() {});
            },
            icon: const Icon(Icons.folder_open),
            tooltip: 'Saved Sessions',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.circle, size: 14, color: connectionColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _connectionText,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _isMeasuring ? 'MEASURING' : 'IDLE',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _isMeasuring ? Colors.orange : Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.menu_book),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _recipeSummary(),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      if (_currentRecipe != null && _currentRecipe!.beanQuantityG != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Bean Quantity',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              onPressed: _decreaseBeanQuantity,
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(
                              '${(_currentBeanQuantityG ?? _currentRecipe!.beanQuantityG!).toStringAsFixed(0)} g',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              onPressed: _increaseBeanQuantity,
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Current Weight',
                                style: TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '${_displayWeightG.toStringAsFixed(1)} g',
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Time',
                                style: TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _elapsedText(),
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: _isConnecting ? null : _toggleBluetooth,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      minimumSize: const Size(0, 44),
                    ),
                    child: Icon(
                      _isConnected ? Icons.bluetooth_disabled : Icons.bluetooth,
                      size: 20,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: (_isConnected && !_isConnecting) ? _toggleMeasurement : null,
                    icon: Icon(_isMeasuring ? Icons.stop : Icons.play_arrow),
                    label: Text(_isMeasuring ? 'Stop' : 'Start'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isConnected ? _tare : null,
                    icon: const Icon(Icons.exposure_zero),
                    label: const Text('Tare'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _clearSession,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Clear Session'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: WeightGraph(
                        points: _points,
                        recipe: effectiveRecipe,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}