import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/brew_widgets.dart';
import '../data/preset_recipes.dart';
import '../models/brew_recipe.dart';
import '../models/coffee_session.dart';
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
  Timer? _timerTick;

  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isMeasuring = false;

  List<BrewRecipe> _recipes = [];
  final List<BrewRecipe> _presetRecipes = PresetRecipes.all;

  String _connectionText = 'Disconnected';

  double _rawWeightG = 0.0;
  double _tareOffsetG = 0.0;
  double _displayWeightG = 0.0;

  bool _isMeasuringBeans = false;

  DateTime? _measurementStartTime;
  final List<WeightPoint> _points = [];

  BrewRecipe? _currentRecipe;
  double? _currentBeanQuantityG;

  /// 自動スタート: 武装中、直近サンプルの最小値から閾値以上増えたら計測開始。
  /// 自作スケールのノイズ（±0.5g程度）に対し十分なマージンを取る
  static const double _autoStartThresholdG = 2.0;
  bool _autoStartArmed = false;
  final List<double> _autoBaselineWindow = [];

  /// グラフに重ねる過去セッション（ゴースト）
  CoffeeSession? _ghostSession;

  /// 「この条件でもう一度」で選んだ記録。次の保存画面で豆情報の初期値にする（1回限り）
  CoffeeSession? _templateSession;

  /// 計測中に鳴らし済みの注湯合図（同じ合図を二度鳴らさないため）
  final Set<int> _firedCues = {};

  @override
  void initState() {
    super.initState();
    _loadRecipes();
    SessionStorage.recipesRevision.addListener(_onRecipesChanged);
    _bindBleStreams();
  }

  /// 設定タブなど別の画面でレシピが保存されたら読み直す
  void _onRecipesChanged() {
    if (mounted) _loadRecipes();
  }

  void _bindBleStreams() {
    _weightSub = _bleScaleService.weightStream.listen((weight) {
      _rawWeightG = weight;
      _displayWeightG = _rawWeightG - _tareOffsetG;

      // 自動スタート判定（豆量計測中は動作させない）
      if (_autoStartArmed &&
          _isConnected &&
          !_isMeasuring &&
          !_isMeasuringBeans) {
        _autoBaselineWindow.add(_displayWeightG);
        if (_autoBaselineWindow.length > 6) {
          _autoBaselineWindow.removeAt(0);
        }
        final baseline = _autoBaselineWindow.reduce(min);
        if (_displayWeightG - baseline >= _autoStartThresholdG) {
          _autoStartArmed = false;
          _autoBaselineWindow.clear();
          _startMeasurement();
        }
      }

      if (_isMeasuring && _measurementStartTime != null) {
        _checkPourCues();
        final elapsed = DateTime.now().difference(_measurementStartTime!);
        _points.add(
          WeightPoint(
            elapsedMs: elapsed.inMilliseconds,
            weightG: _displayWeightG < 0 ? 0 : _displayWeightG,
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
            _autoStartArmed = false;
            _autoBaselineWindow.clear();
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
    SessionStorage.recipesRevision.removeListener(_onRecipesChanged);
    _timerTick?.cancel();
    _weightSub?.cancel();
    _connectionSub?.cancel();
    _statusSub?.cancel();
    _bleScaleService.dispose();
    super.dispose();
  }

  Future<void> _loadRecipes() async {
    final recipes = await SessionStorage.loadRecipes();
    final currentId = await SessionStorage.loadCurrentRecipeId();
    if (!mounted) return;
    setState(() {
      _recipes = recipes;
      if (currentId != null) {
        // マイレシピ → プリセットの順に探す
        try {
          _currentRecipe = [...recipes, ..._presetRecipes]
              .firstWhere((r) => r.id == currentId);
        } catch (_) {
          _currentRecipe = null;
        }
      } else {
        _currentRecipe = null;
      }
      _currentBeanQuantityG = _currentRecipe?.beanQuantityG;
    });
  }

  Future<void> _selectRecipe(BrewRecipe? recipe) async {
    setState(() {
      _currentRecipe = recipe;
      _currentBeanQuantityG = recipe?.beanQuantityG;
    });
    await SessionStorage.saveCurrentRecipeId(recipe?.id);
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
      _firedCues.clear();
      _measurementStartTime = DateTime.now();
      _isMeasuring = true;
    });

    _timerTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _stopMeasurement() async {
    _timerTick?.cancel();
    _timerTick = null;
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
          initialDoseG: _currentBeanQuantityG,
          template: _templateSession,
        ),
      ),
    );

    // 引き継ぎは1回限り
    setState(() => _templateSession = null);
  }

  /// レシピの次の注湯時刻の3秒前と、その時刻に振動＋クリック音で知らせる。
  /// 端末の「タッチ時の振動・操作音」の設定がオフだと鳴らないことがある
  void _checkPourCues() {
    final recipe = _effectiveRecipe();
    if (recipe == null || _measurementStartTime == null) return;
    final elapsedMs =
        DateTime.now().difference(_measurementStartTime!).inMilliseconds;
    for (final step in recipe.steps) {
      if (step.startSec <= 0) continue;
      final atMs = step.startSec * 1000;
      final preMs = atMs - 3000;
      if (preMs > 0 &&
          elapsedMs >= preMs &&
          elapsedMs < atMs &&
          _firedCues.add(step.startSec * 10 + 1)) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
      }
      if (elapsedMs >= atMs &&
          elapsedMs < atMs + 1500 &&
          _firedCues.add(step.startSec * 10 + 2)) {
        HapticFeedback.vibrate();
        SystemSound.play(SystemSoundType.click);
      }
    }
  }

  /// 「この条件でもう一度」：記録のレシピ・豆量をセットし、その抽出をゴーストに重ねる
  void _applyTemplate(CoffeeSession session) {
    BrewRecipe? recipe;
    final r = session.recipe;
    if (r != null && !r.isEmpty) {
      // 同じIDのレシピ（マイレシピ・プリセット）があればそれを、なければ記録時のレシピを使う
      final match = [..._recipes, ..._presetRecipes]
          .where((e) => e.id != null && e.id == r.id)
          .toList();
      recipe = match.isNotEmpty ? match.first : r.copy();
    }
    setState(() {
      _templateSession = session;
      if (session.points.isNotEmpty) _ghostSession = session;
      if (recipe != null) _currentRecipe = recipe;
      _currentBeanQuantityG =
          session.doseG ?? recipe?.beanQuantityG ?? _currentBeanQuantityG;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '「${session.beanName ?? '前回の記録'}」の条件をセットしました（レシピ・豆量・ゴースト）',
        ),
      ),
    );
  }

  void _tare() {
    setState(() {
      _tareOffsetG = _rawWeightG;
      _displayWeightG = 0.0;
      _autoBaselineWindow.clear();
    });
  }

  void _toggleAutoStart() {
    setState(() {
      _autoStartArmed = !_autoStartArmed;
      _autoBaselineWindow.clear();
    });
  }

  void _startBeanMeasurement() {
    if (!_isConnected) return;
    setState(() {
      _tareOffsetG = _rawWeightG;
      _displayWeightG = 0.0;
      _isMeasuringBeans = true;
      _autoBaselineWindow.clear();
    });
  }

  void _confirmBeanQuantity() {
    final quantity = _displayWeightG;
    if (quantity <= 0) return;
    setState(() {
      _currentBeanQuantityG = quantity;
      _isMeasuringBeans = false;
      _autoBaselineWindow.clear();
    });
  }

  void _cancelBeanMeasurement() {
    setState(() {
      _isMeasuringBeans = false;
      _autoBaselineWindow.clear();
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

  /// 直近約1秒間の重量変化から流量（g/s）を求める。計測中のみ
  double? _currentFlowRate() {
    if (!_isMeasuring || _points.length < 2) return null;
    final lastMs = _points.last.elapsedMs;
    WeightPoint ref = _points[_points.length - 2];
    for (int i = _points.length - 2; i >= 0; i--) {
      ref = _points[i];
      if (lastMs - _points[i].elapsedMs >= 1000) break;
    }
    final dtSec = (lastMs - ref.elapsedMs) / 1000.0;
    if (dtSec < 0.3) return null;
    final flow = (_points.last.weightG - ref.weightG) / dtSec;
    return flow < 0 ? 0 : flow;
  }

  /// レシピの目標注湯曲線上の、経過時間 elapsedMs 時点の目標累計重量。
  /// 各ステップの目標量へ「次のステップ開始まで」に到達する想定で線形補間する
  double? _recipeTargetAt(BrewRecipe recipe, int elapsedMs) {
    final steps = [...recipe.steps]
      ..sort((a, b) => a.startSec.compareTo(b.startSec));
    if (steps.isEmpty) return null;

    final times = <double>[steps.first.startSec.toDouble()];
    final weights = <double>[0];
    for (int i = 0; i < steps.length; i++) {
      final endSec = i + 1 < steps.length
          ? steps[i + 1].startSec.toDouble()
          : (recipe.targetEndSec?.toDouble() ?? steps[i].startSec + 30.0);
      times.add(endSec);
      weights.add(steps[i].targetTotalG);
    }

    final t = elapsedMs / 1000.0;
    if (t <= times.first) return weights.first;
    for (int i = 1; i < times.length; i++) {
      if (t <= times[i]) {
        final span = times[i] - times[i - 1];
        if (span <= 0) return weights[i];
        final ratio = (t - times[i - 1]) / span;
        return weights[i - 1] + (weights[i] - weights[i - 1]) * ratio;
      }
    }
    return weights.last;
  }

  /// レシピとの差分（+なら先行、-なら遅れ）。計測中かつレシピありのみ
  double? _paceDiff(BrewRecipe? recipe) {
    if (!_isMeasuring ||
        recipe == null ||
        recipe.isEmpty ||
        _points.isEmpty) {
      return null;
    }
    final target = _recipeTargetAt(recipe, _points.last.elapsedMs);
    if (target == null) return null;
    return _points.last.weightG - target;
  }

  /// ゴースト表示する過去セッションを選ぶボトムシート
  Future<void> _pickGhostSession() async {
    final sessions = await SessionStorage.loadSessions();
    if (!mounted) return;
    if (sessions.isEmpty && _ghostSession == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存済みセッションがありません')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: BrewColors.foam,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text('ゴースト表示（過去の曲線を重ねる）',
                    style: AppTheme.display(
                        fontSize: 17, color: BrewColors.espresso)),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.layers_clear,
                          color: BrewColors.mocha),
                      title: const Text('なし'),
                      selected: _ghostSession == null,
                      onTap: () {
                        setState(() => _ghostSession = null);
                        Navigator.pop(ctx);
                      },
                    ),
                    for (final session in sessions.take(30))
                      ListTile(
                        leading:
                            const Icon(Icons.coffee, color: BrewColors.caramel),
                        title: Text(
                          (session.beanName == null ||
                                  session.beanName!.isEmpty)
                              ? 'Untitled Session'
                              : session.beanName!,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${session.createdAt.year}/${session.createdAt.month.toString().padLeft(2, '0')}/${session.createdAt.day.toString().padLeft(2, '0')}'
                          ' | ${session.maxWeight.toStringAsFixed(1)} g',
                          style: AppTheme.mono(
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: BrewColors.mocha),
                        ),
                        selected: _ghostSession?.id == session.id,
                        onTap: () {
                          setState(() => _ghostSession = session);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRecipe = _effectiveRecipe();

    // グラフを最優先に、上部要素はできる限りコンパクトにまとめる。
    // AppBarは使わず薄いカスタムヘッダーにして縦空間をグラフへ譲る。
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(),
              const SizedBox(height: 10),
              _buildRecipeRow(),
              const SizedBox(height: 10),
              _buildHeroCard(effectiveRecipe),
              const SizedBox(height: 10),
              _buildControls(),
              const SizedBox(height: 12),
              Expanded(child: _buildGraphCard(effectiveRecipe)),
            ],
          ),
        ),
      ),
    );
  }

  // --- コンパクトヘッダー（タイトル + 接続状態 + ナビゲーション） ---
  Widget _buildTopBar() {
    return Row(
      children: [
        PulsingDot(
          color: _isConnected ? BrewColors.sage : BrewColors.terracotta,
          pulsing: _isConnected,
          size: 9,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'Brew Companion',
                  style: AppTheme.display(
                    fontSize: 19,
                    fontStyle: FontStyle.italic,
                    color: BrewColors.espresso,
                  ),
                ),
              ),
              Text(
                _connectionText,
                style: AppTheme.mono(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w400,
                  color: BrewColors.mocha.withValues(alpha: 0.75),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () async {
            final result = await Navigator.push<CoffeeSession>(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            );
            if (!mounted) return;
            if (result != null) {
              _applyTemplate(result);
            } else {
              setState(() {});
            }
          },
          icon: const Icon(Icons.history, size: 22, color: BrewColors.mocha),
          tooltip: 'Saved Sessions',
        ),
        // 豆の在庫・豆情報・フレーバーホイール・レシピ設定は下部ナビゲーションへ移動
      ],
    );
  }

  // 【撤去済みUI・復元用】
  // 旧ステータス行（接続ピル + IDLE / BREWING / AUTO待機中 バッジ）は撤去した。
  // 理由: 接続状態はヘッダーのドット+テキスト、計測中はヒーローカードの発光枠と
  // Stopボタンの色、AUTO武装は「自動」ボタンのハイライトで判別でき、冗長なため。
  // 復元する場合は下のコメントを解除し、build() の _buildTopBar() の直後に
  // `_buildStatusRow(),` を戻すこと。
  /*
  Widget _buildStatusRow() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: BrewColors.foam,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: BrewColors.oat),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PulsingDot(
                color: _isConnected ? BrewColors.sage : BrewColors.terracotta,
                pulsing: _isConnected,
                size: 9,
              ),
              const SizedBox(width: 9),
              Text(
                _connectionText,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: BrewColors.mocha,
                      fontWeight: FontWeight.w600,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const Spacer(),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim, child: ScaleTransition(scale: anim, child: child)),
          child: _isMeasuring
              ? Container(
                  key: const ValueKey('measuring'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: BrewColors.amber.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: BrewColors.amber.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const PulsingDot(color: BrewColors.amber, size: 7),
                      const SizedBox(width: 7),
                      Text('BREWING',
                          style: AppTheme.overline(
                              color: BrewColors.caramel, fontSize: 10)),
                    ],
                  ),
                )
              : (_autoStartArmed
                  ? Container(
                      key: const ValueKey('auto-wait'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: BrewColors.sage.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: BrewColors.sage.withValues(alpha: 0.55)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const PulsingDot(color: BrewColors.sage, size: 7),
                          const SizedBox(width: 7),
                          Text('AUTO 待機中',
                              style: AppTheme.overline(
                                  color: BrewColors.sage, fontSize: 10)),
                        ],
                      ),
                    )
                  : Padding(
                      key: const ValueKey('idle'),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text('IDLE',
                          style: AppTheme.overline(
                              color: BrewColors.mocha.withValues(alpha: 0.5),
                              fontSize: 10)),
                    )),
        ),
      ],
    );
  }
  */

  // --- レシピ選択ピル（タップでボトムシート） + 豆量ステッパー ---
  Widget _buildRecipeRow() {
    final hasBeanQty = _currentRecipe?.beanQuantityG != null;
    return Row(
      children: [
        Expanded(
          child: Material(
            color: BrewColors.foam,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
              side: const BorderSide(color: BrewColors.oat),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _pickRecipe,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book_outlined,
                        size: 16, color: BrewColors.caramel),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentRecipe == null
                            ? 'レシピなし'
                            : (_currentRecipe!.name ?? '無題'),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: _currentRecipe == null
                                  ? BrewColors.mocha.withValues(alpha: 0.6)
                                  : BrewColors.espresso,
                              fontWeight: FontWeight.w600,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.expand_more,
                        size: 18, color: BrewColors.mocha),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (hasBeanQty) ...[
          const SizedBox(width: 8),
          _buildBeanQuantityStepper(),
        ],
      ],
    );
  }

  /// レシピ選択のボトムシート（一覧 + 管理画面への導線）
  Future<void> _pickRecipe() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      backgroundColor: BrewColors.foam,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
                child: Row(
                  children: [
                    Text('レシピを選択',
                        style: AppTheme.display(
                            fontSize: 17, color: BrewColors.espresso)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RecipeSettingsScreen()),
                        );
                        await _loadRecipes();
                      },
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('管理'),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.not_interested,
                          size: 20, color: BrewColors.mocha),
                      title: const Text('レシピなし'),
                      selected: _currentRecipe == null,
                      onTap: () {
                        _selectRecipe(null);
                        Navigator.pop(ctx);
                      },
                    ),
                    _recipeSectionHeader('マイレシピ'),
                    if (_recipes.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                        child: Text(
                          'まだありません。「管理」から0から作るか、下のレシピをコピーして作れます。',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: BrewColors.mocha,
                              ),
                        ),
                      ),
                    for (final recipe in _recipes) _recipeTile(ctx, recipe),
                    _recipeSectionHeader('有名店・バリスタ'),
                    for (final recipe in _presetRecipes)
                      _recipeTile(ctx, recipe),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _recipeSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: BrewColors.caramel,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
      ),
    );
  }

  Widget _recipeTile(BuildContext sheetContext, BrewRecipe recipe) {
    final bean = recipe.beanQuantityG;
    final beanText = bean == null
        ? '-'
        : (bean == bean.roundToDouble()
            ? bean.toStringAsFixed(0)
            : bean.toStringAsFixed(1));
    final summary =
        '豆 ${beanText}g / ${recipe.steps.length}投 / 目標 ${recipe.maxTargetWeight.toStringAsFixed(0)}g';
    return ListTile(
      leading: Icon(
          recipe.isPreset ? Icons.storefront_outlined : Icons.menu_book_outlined,
          size: 20,
          color: BrewColors.caramel),
      title: Text(recipe.name ?? '無題', overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary,
            style: AppTheme.mono(
              fontSize: 10.5,
              fontWeight: FontWeight.w400,
              color: BrewColors.mocha,
            ),
          ),
          if (recipe.source != null && recipe.source!.isNotEmpty)
            Text(
              recipe.source!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: BrewColors.mocha.withValues(alpha: 0.8),
                  ),
            ),
        ],
      ),
      isThreeLine: recipe.source != null && recipe.source!.isNotEmpty,
      selected: _currentRecipe?.id == recipe.id,
      onTap: () {
        _selectRecipe(recipe);
        Navigator.pop(sheetContext);
      },
    );
  }

  // --- 豆量ステッパー（コンパクト） ---
  Widget _buildBeanQuantityStepper() {
    final q = _currentBeanQuantityG ?? _currentRecipe!.beanQuantityG!;
    final quantity =
        q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: BrewColors.foam,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: BrewColors.oat),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: _decreaseBeanQuantity,
            icon: const Icon(Icons.remove_circle_outline, size: 19),
            color: BrewColors.caramel,
            padding: const EdgeInsets.all(7),
            constraints: const BoxConstraints(),
          ),
          Text(
            '$quantity g',
            style: AppTheme.mono(fontSize: 14, color: BrewColors.espresso),
          ),
          IconButton(
            onPressed: _increaseBeanQuantity,
            icon: const Icon(Icons.add_circle_outline, size: 19),
            color: BrewColors.caramel,
            padding: const EdgeInsets.all(7),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // --- ヒーローカード（重量 + 時間 + 抽出メトリクス） ---
  Widget _buildHeroCard(BrewRecipe? recipe) {
    final targetG = (recipe != null && !recipe.isEmpty) ? recipe.maxTargetWeight : null;
    final nextStep = _nextStepText(recipe);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BrewColors.roastLight, BrewColors.roast, BrewColors.espresso],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _isMeasuring
              ? BrewColors.amber.withValues(alpha: 0.75)
              : (_isMeasuringBeans
                  ? BrewColors.sage.withValues(alpha: 0.75)
                  : Colors.transparent),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: BrewColors.espresso.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isMeasuringBeans ? 'BEAN DOSE' : 'WEIGHT',
                  style: AppTheme.overline(
                    color: _isMeasuringBeans
                        ? BrewColors.sage
                        : BrewColors.creamTextDim,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: _displayWeightG),
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    builder: (context, value, _) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            value.toStringAsFixed(1),
                            style: AppTheme.mono(
                              fontSize: 42,
                              color: BrewColors.creamText,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'g',
                            style: AppTheme.mono(
                              fontSize: 20,
                              color: BrewColors.creamTextDim,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                // 抽出中に一番知りたい「次に何gまで注ぐか」をここに出す
                if (_isMeasuringBeans)
                  Text(
                    '豆をスケールに載せてください',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: BrewColors.sage,
                        ),
                  )
                else if (nextStep != null)
                  Text(
                    '次: $nextStep',
                    style: AppTheme.mono(
                      fontSize: 11.5,
                      color: BrewColors.amber,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (targetG != null)
                  Text(
                    'target ${targetG.toStringAsFixed(0)} g',
                    style: AppTheme.mono(
                      fontSize: 11.5,
                      color: BrewColors.creamTextDim,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 54,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: BrewColors.creamText.withValues(alpha: 0.14),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('TIME',
                    style: AppTheme.overline(color: BrewColors.creamTextDim)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _elapsedText(),
                    style: AppTheme.mono(
                      fontSize: 30,
                      color: BrewColors.creamText,
                      height: 1.05,
                    ),
                  ),
                ),
                if (recipe?.targetEndSec != null)
                  Text(
                    'end ${_formatSec(recipe!.targetEndSec!)}',
                    style: AppTheme.mono(
                      fontSize: 11.5,
                      color: BrewColors.creamTextDim,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: BrewColors.creamText.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 9),
          _buildHeroStatsRow(recipe),
        ],
      ),
    );
  }

  /// 抽出中、次に到達すべき注湯ステップの目安（例: "0:45 までに 120g"）
  String? _nextStepText(BrewRecipe? recipe) {
    if (recipe == null || recipe.isEmpty || !_isMeasuring || _points.isEmpty) {
      return null;
    }
    final elapsedSec = _points.last.elapsedMs / 1000.0;
    final steps = [...recipe.steps]
      ..sort((a, b) => a.startSec.compareTo(b.startSec));
    for (int i = 0; i < steps.length; i++) {
      final endSec = i + 1 < steps.length
          ? steps[i + 1].startSec
          : (recipe.targetEndSec ?? steps[i].startSec + 30);
      if (elapsedSec < endSec) {
        return '${_formatSec(endSec)} までに ${steps[i].targetTotalG.toStringAsFixed(0)}g';
      }
    }
    return null;
  }

  // --- ヒーローカード下段: 流量 / ペース / レシオ ---
  Widget _buildHeroStatsRow(BrewRecipe? recipe) {
    final flow = _currentFlowRate();
    final pace = _paceDiff(recipe);

    final dose = _currentBeanQuantityG;
    final water = _isMeasuring
        ? _displayWeightG
        : (_points.isNotEmpty ? _points.last.weightG : _displayWeightG);
    double? ratio;
    if (dose != null && dose > 0 && water > 0.5) {
      ratio = water / dose;
    }

    String paceText = '—';
    Color paceColor = BrewColors.creamTextDim;
    if (pace != null) {
      if (pace.abs() <= 2.0) {
        paceText = 'ON PACE';
        paceColor = BrewColors.sage;
      } else if (pace > 0) {
        paceText = '+${pace.toStringAsFixed(1)}g 先行';
        paceColor = BrewColors.amber;
      } else {
        paceText = '${pace.toStringAsFixed(1)}g 遅れ';
        paceColor = BrewColors.steam;
      }
    }

    return Row(
      children: [
        Expanded(
          child: _heroStat(
              'FLOW', flow == null ? '—' : '${flow.toStringAsFixed(1)} g/s'),
        ),
        Expanded(
          child: _heroStat('PACE', paceText, valueColor: paceColor),
        ),
        Expanded(
          child: _heroStat(
              'RATIO', ratio == null ? '—' : '1:${ratio.toStringAsFixed(1)}'),
        ),
      ],
    );
  }

  Widget _heroStat(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style:
                AppTheme.overline(color: BrewColors.creamTextDim, fontSize: 9)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: AppTheme.mono(
              fontSize: 15,
              color: valueColor ?? BrewColors.creamText,
            ),
          ),
        ),
      ],
    );
  }

  // --- 操作ボタン群 ---
  Widget _buildControls() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildStartStopButton(),
        const SizedBox(width: 14),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _isMeasuringBeans
                ? Row(
                    key: const ValueKey('bean-actions'),
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              _displayWeightG > 0 ? _confirmBeanQuantity : null,
                          style: FilledButton.styleFrom(
                              backgroundColor: BrewColors.sage),
                          icon: const Icon(Icons.check, size: 20),
                          label: const Text('決定'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _cancelBeanMeasurement,
                          child: const Text('キャンセル'),
                        ),
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('normal-actions'),
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSecondaryAction(
                        icon: _isConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth,
                        label: _isConnected ? '切断' : '接続',
                        onTap: _isConnecting ? null : _toggleBluetooth,
                        highlighted: _isConnected,
                      ),
                      _buildSecondaryAction(
                        icon: Icons.exposure_zero,
                        label: 'Tare',
                        onTap: _isConnected ? _tare : null,
                      ),
                      _buildSecondaryAction(
                        icon: Icons.coffee,
                        label: '豆量計測',
                        onTap: (_isConnected && !_isMeasuring)
                            ? _startBeanMeasurement
                            : null,
                      ),
                      _buildSecondaryAction(
                        icon: Icons.motion_photos_auto,
                        label: '自動',
                        onTap: (_isConnected && !_isMeasuring)
                            ? _toggleAutoStart
                            : null,
                        highlighted: _autoStartArmed,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildStartStopButton() {
    final enabled = _isConnected && !_isConnecting && !_isMeasuringBeans;
    final color = !enabled
        ? BrewColors.oat
        : (_isMeasuring ? BrewColors.terracotta : BrewColors.caramel);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? _toggleMeasurement : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  _isMeasuring ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(_isMeasuring),
                  color: enabled ? BrewColors.foam : BrewColors.mocha.withValues(alpha: 0.4),
                  size: 27,
                ),
              ),
              Text(
                _isMeasuring ? 'Stop' : 'Start',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: enabled
                          ? BrewColors.foam
                          : BrewColors.mocha.withValues(alpha: 0.4),
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryAction({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool highlighted = false,
  }) {
    final enabled = onTap != null;
    final bg = highlighted ? BrewColors.espresso : BrewColors.foam;
    final fg = highlighted
        ? BrewColors.creamText
        : (enabled ? BrewColors.mocha : BrewColors.oat);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: CircleBorder(
            side: BorderSide(
                color: highlighted ? BrewColors.espresso : BrewColors.oat),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 20, color: fg),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: enabled
                    ? BrewColors.mocha
                    : BrewColors.mocha.withValues(alpha: 0.35),
                fontSize: 10,
              ),
        ),
      ],
    );
  }

  // --- グラフカード ---
  Widget _buildGraphCard(BrewRecipe? recipe) {
    final hasRecipe = recipe != null && !recipe.isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: 4),
                const SectionLabel('Brew Curve'),
                const Spacer(),
                if (hasRecipe) ...[
                  _legendDot(BrewColors.steam, 'レシピ'),
                  const SizedBox(width: 8),
                ],
                if (_ghostSession != null) ...[
                  _legendDot(
                      BrewColors.mocha.withValues(alpha: 0.5), 'ゴースト'),
                  const SizedBox(width: 2),
                ],
                IconButton(
                  onPressed: _pickGhostSession,
                  icon: Icon(
                    Icons.layers,
                    size: 19,
                    color: _ghostSession != null
                        ? BrewColors.caramel
                        : BrewColors.mocha.withValues(alpha: 0.55),
                  ),
                  padding: const EdgeInsets.all(7),
                  constraints: const BoxConstraints(),
                  tooltip: 'ゴースト表示',
                ),
                IconButton(
                  onPressed: _isMeasuringBeans ? null : _clearSession,
                  icon: Icon(
                    Icons.refresh,
                    size: 19,
                    color: BrewColors.mocha.withValues(alpha: 0.55),
                  ),
                  padding: const EdgeInsets.all(7),
                  constraints: const BoxConstraints(),
                  tooltip: 'Clear Session',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: WeightGraph(
                points: _points,
                recipe: recipe,
                ghostPoints: _ghostSession?.points,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: BrewColors.mocha, fontSize: 11),
        ),
      ],
    );
  }
}
