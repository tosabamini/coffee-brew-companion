import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/scale/screens/main_screen.dart';
import 'theme/app_theme.dart';

/// 起動アニメーション画面。
/// 抽出カーブが描かれながら重量カウンターが回り、タイトルがフェードインする
/// （「重さを測って記録するアプリ」であることを約1.5秒で伝える演出）。
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curveProgress;
  late final Animation<double> _titleProgress;

  static const double _finalWeightG = 240.0;

  @override
  void initState() {
    super.initState();
    // スプラッシュ中はシステムバーもダークに合わせる
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: BrewColors.espresso,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _curveProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.78, curve: Curves.easeInOutCubic),
    );
    _titleProgress = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOutCubic),
    );

    _controller.forward().whenComplete(_goToMain);
  }

  void _goToMain() {
    if (!mounted) return;
    // メイン画面はライト基調なのでシステムバーを戻す
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: BrewColors.crema,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, __, ___) => const MainScreen(),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              BrewColors.roast,
              BrewColors.espresso,
            ],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _curveProgress.value;
              final titleT = _titleProgress.value;
              return Column(
                children: [
                  const Spacer(flex: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _SplashCurvePainter(progress: t),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  // 重量カウンター（カーブと同期して増える）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        (_finalWeightG * t).toStringAsFixed(1),
                        style: AppTheme.mono(
                          fontSize: 34,
                          color: BrewColors.creamText,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'g',
                        style: AppTheme.mono(
                          fontSize: 17,
                          color: BrewColors.creamTextDim,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Opacity(
                    opacity: titleT,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - titleT)),
                      child: Column(
                        children: [
                          Text(
                            'Brew Companion',
                            style: AppTheme.display(
                              fontSize: 26,
                              fontStyle: FontStyle.italic,
                              color: BrewColors.creamText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'POUR · MEASURE · LOG',
                            style: AppTheme.overline(
                              color: BrewColors.creamTextDim,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(flex: 4),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 抽出カーブが左から右へ描かれていくアニメーションのペインター
class _SplashCurvePainter extends CustomPainter {
  final double progress;

  _SplashCurvePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // うっすらとしたベースライン（グラフの雰囲気）
    final gridPaint = Paint()
      ..color = BrewColors.creamText.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (int i = 0; i < 4; i++) {
      final y = h * (0.15 + 0.25 * i);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // 抽出カーブ（蒸らし→注湯の階段状の伸び）
    final path = Path()
      ..moveTo(0, h * 0.94)
      ..cubicTo(w * 0.13, h * 0.92, w * 0.16, h * 0.58, w * 0.28, h * 0.53)
      ..cubicTo(w * 0.38, h * 0.49, w * 0.44, h * 0.46, w * 0.52, h * 0.37)
      ..cubicTo(w * 0.62, h * 0.26, w * 0.72, h * 0.23, w * 0.82, h * 0.15)
      ..cubicTo(w * 0.90, h * 0.09, w * 0.96, h * 0.07, w, h * 0.06);

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final drawLength = metric.length * progress.clamp(0.0, 1.0);
    if (drawLength <= 0) return;

    final partial = metric.extractPath(0, drawLength);

    final curvePaint = Paint()
      ..shader = const LinearGradient(
        colors: [BrewColors.caramel, BrewColors.amber],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(partial, curvePaint);

    // 先端のグロー
    final tangent = metric.getTangentForOffset(drawLength);
    if (tangent != null) {
      final tip = tangent.position;
      canvas.drawCircle(
        tip,
        10,
        Paint()..color = BrewColors.amber.withValues(alpha: 0.22),
      );
      canvas.drawCircle(tip, 4.5, Paint()..color = BrewColors.amber);
      canvas.drawCircle(tip, 2, Paint()..color = BrewColors.creamText);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashCurvePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
