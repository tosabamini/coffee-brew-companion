import 'dart:math';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/brew_recipe.dart';
import '../models/pour_step.dart';
import '../models/weight_point.dart';

class WeightGraph extends StatelessWidget {
  final List<WeightPoint> points;
  final BrewRecipe? recipe;

  /// 過去セッションの曲線を薄く重ねる（再現性チェック用）
  final List<WeightPoint>? ghostPoints;

  const WeightGraph({
    super.key,
    required this.points,
    this.recipe,
    this.ghostPoints,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty &&
        (recipe == null || recipe!.isEmpty) &&
        (ghostPoints == null || ghostPoints!.isEmpty)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.show_chart,
              size: 34,
              color: BrewColors.mocha.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              '計測を開始するとグラフが描かれます',
              style: TextStyle(
                fontSize: 13,
                color: BrewColors.mocha.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      );
    }

    return CustomPaint(
      painter: WeightGraphPainter(
        points: points,
        recipe: recipe,
        ghostPoints: ghostPoints,
      ),
      child: Container(),
    );
  }
}

class WeightGraphPainter extends CustomPainter {
  final List<WeightPoint> points;
  final BrewRecipe? recipe;
  final List<WeightPoint>? ghostPoints;

  WeightGraphPainter({
    required this.points,
    this.recipe,
    this.ghostPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 余白は最小限にして描画領域を最大化する
    const double leftPad = 38;
    const double rightPad = 8;
    const double topPad = 10;
    const double bottomPad = 22;

    final graphWidth = size.width - leftPad - rightPad;
    final graphHeight = size.height - topPad - bottomPad;

    if (graphWidth <= 0 || graphHeight <= 0) return;

    final axisPaint = Paint()
      ..color = BrewColors.mocha.withValues(alpha: 0.55)
      ..strokeWidth = 1.2;

    final gridPaint = Paint()
      ..color = BrewColors.oat.withValues(alpha: 0.65)
      ..strokeWidth = 1;

    final gridPaintFaint = Paint()
      ..color = BrewColors.oat.withValues(alpha: 0.35)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = BrewColors.caramel
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final recipeLinePaint = Paint()
      ..color = BrewColors.steam.withValues(alpha: 0.8)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final recipeEndPaint = Paint()
      ..color = BrewColors.sage.withValues(alpha: 0.9)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final textStyle = TextStyle(
      color: BrewColors.mocha.withValues(alpha: 0.85),
      fontSize: 10,
    );

    int maxTimeMs = max(points.isNotEmpty ? points.last.elapsedMs : 0, 1000);
    if (recipe != null && !recipe!.isEmpty) {
      maxTimeMs = max(maxTimeMs, recipe!.maxTargetTimeSec * 1000);
    }
    if (ghostPoints != null && ghostPoints!.isNotEmpty) {
      maxTimeMs = max(maxTimeMs, ghostPoints!.last.elapsedMs);
    }

    double maxWeight = 1.0;
    for (final p in points) {
      if (p.weightG > maxWeight) maxWeight = p.weightG;
    }
    if (recipe != null && !recipe!.isEmpty) {
      maxWeight = max(maxWeight, recipe!.maxTargetWeight);
    }
    if (ghostPoints != null) {
      for (final p in ghostPoints!) {
        if (p.weightG > maxWeight) maxWeight = p.weightG;
      }
    }
    maxWeight *= 1.1;

    final origin = Offset(leftPad, size.height - bottomPad);

    canvas.drawLine(origin, Offset(size.width - rightPad, origin.dy), axisPaint);
    canvas.drawLine(origin, Offset(origin.dx, topPad), axisPaint);

    const int xDivisions = 5;
    const int yDivisions = 5;

    // 縦グリッドは控えめに、横グリッドで重さを読みやすくする
    for (int i = 0; i <= xDivisions; i++) {
      final x = leftPad + graphWidth * i / xDivisions;
      canvas.drawLine(
        Offset(x, topPad),
        Offset(x, size.height - bottomPad),
        gridPaintFaint,
      );

      final timeSec = (maxTimeMs * i / xDivisions / 1000.0).round();
      _drawText(
        canvas,
        _formatSec(timeSec),
        Offset(x - 12, size.height - bottomPad + 6),
        textStyle,
      );
    }

    for (int i = 0; i <= yDivisions; i++) {
      final y = topPad + graphHeight * i / yDivisions;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        gridPaint,
      );

      final weight = maxWeight * (1 - i / yDivisions);
      _drawText(
        canvas,
        weight >= 100 ? weight.toStringAsFixed(0) : weight.toStringAsFixed(1),
        Offset(4, y - 5),
        textStyle,
      );
    }

    if (recipe != null && !recipe!.isEmpty) {
      _drawRecipeOverlay(
        canvas,
        size,
        recipe!,
        maxTimeMs,
        maxWeight,
        leftPad,
        rightPad,
        topPad,
        bottomPad,
        graphWidth,
        graphHeight,
        recipeLinePaint,
        recipeEndPaint,
      );
    }

    // ゴースト曲線（過去セッション）を薄く描く
    if (ghostPoints != null && ghostPoints!.isNotEmpty) {
      final ghostPaint = Paint()
        ..color = BrewColors.mocha.withValues(alpha: 0.38)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final ghostPath = Path();
      for (int i = 0; i < ghostPoints!.length; i++) {
        final p = ghostPoints![i];
        final x = leftPad + (p.elapsedMs / maxTimeMs) * graphWidth;
        final y =
            size.height - bottomPad - (p.weightG / maxWeight) * graphHeight;
        if (i == 0) {
          ghostPath.moveTo(x, y);
        } else {
          ghostPath.lineTo(x, y);
        }
      }
      canvas.drawPath(ghostPath, ghostPaint);
    }

    if (points.isNotEmpty) {
      final path = Path();
      for (int i = 0; i < points.length; i++) {
        final p = points[i];
        final x = leftPad + (p.elapsedMs / maxTimeMs) * graphWidth;
        final y = size.height - bottomPad - (p.weightG / maxWeight) * graphHeight;

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }

      // 曲線の下をグラデーションで塗る
      final firstX =
          leftPad + (points.first.elapsedMs / maxTimeMs) * graphWidth;
      final lastX = leftPad + (points.last.elapsedMs / maxTimeMs) * graphWidth;
      final fillPath = Path.from(path)
        ..lineTo(lastX, size.height - bottomPad)
        ..lineTo(firstX, size.height - bottomPad)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            BrewColors.caramel.withValues(alpha: 0.26),
            BrewColors.caramel.withValues(alpha: 0.02),
          ],
        ).createShader(
          Rect.fromLTWH(leftPad, topPad, graphWidth, graphHeight),
        );
      canvas.drawPath(fillPath, fillPaint);

      canvas.drawPath(path, linePaint);

      // 先端の点: グロー + 本体
      final last = points.last;
      final lastY =
          size.height - bottomPad - (last.weightG / maxWeight) * graphHeight;
      final tip = Offset(lastX, lastY);
      canvas.drawCircle(
        tip,
        9,
        Paint()..color = BrewColors.amber.withValues(alpha: 0.25),
      );
      canvas.drawCircle(tip, 4.5, Paint()..color = BrewColors.caramel);
      canvas.drawCircle(
        tip,
        2,
        Paint()..color = BrewColors.foam,
      );
    }
  }

  void _drawRecipeOverlay(
      Canvas canvas,
      Size size,
      BrewRecipe recipe,
      int maxTimeMs,
      double maxWeight,
      double leftPad,
      double rightPad,
      double topPad,
      double bottomPad,
      double graphWidth,
      double graphHeight,
      Paint recipeLinePaint,
      Paint recipeEndPaint,
      ) {
    final overlayLabelStyle = TextStyle(
      color: BrewColors.steam,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );

    for (final PourStep step in recipe.steps) {
      final x = leftPad + (step.startSec * 1000 / maxTimeMs) * graphWidth;
      final y = size.height - bottomPad - (step.targetTotalG / maxWeight) * graphHeight;

      _drawDashedLine(
        canvas,
        Offset(x, topPad),
        Offset(x, size.height - bottomPad),
        recipeLinePaint,
      );

      _drawDashedLine(
        canvas,
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        recipeLinePaint,
      );

      _drawText(
        canvas,
        _formatSec(step.startSec),
        Offset(x + 3, topPad + 2),
        overlayLabelStyle,
      );

      _drawText(
        canvas,
        '${step.targetTotalG.toStringAsFixed(0)}g',
        Offset(leftPad + 2, y - 12),
        overlayLabelStyle,
      );
    }

    if (recipe.targetEndSec != null) {
      final x = leftPad + (recipe.targetEndSec! * 1000 / maxTimeMs) * graphWidth;
      _drawDashedLine(
        canvas,
        Offset(x, topPad),
        Offset(x, size.height - bottomPad),
        recipeEndPaint,
      );

      _drawText(
        canvas,
        _formatSec(recipe.targetEndSec!),
        Offset(x + 3, topPad + 16),
        const TextStyle(
          color: BrewColors.sage,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      );
    }
  }

  static String _formatSec(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static void _drawDashedLine(
      Canvas canvas,
      Offset start,
      Offset end,
      Paint paint,
      ) {
    const double dashWidth = 5;
    const double dashSpace = 4;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final distance = sqrt(dx * dx + dy * dy);
    final dashCount = (distance / (dashWidth + dashSpace)).floor();

    for (int i = 0; i < dashCount; i++) {
      final t1 = (i * (dashWidth + dashSpace)) / distance;
      final t2 = ((i * (dashWidth + dashSpace)) + dashWidth) / distance;

      final p1 = Offset(start.dx + dx * t1, start.dy + dy * t1);
      final p2 = Offset(
        start.dx + dx * min(t2, 1.0),
        start.dy + dy * min(t2, 1.0),
      );
      canvas.drawLine(p1, p2, paint);
    }
  }

  static void _drawText(
      Canvas canvas,
      String text,
      Offset offset,
      TextStyle style,
      ) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant WeightGraphPainter oldDelegate) {
    return true;
  }
}
