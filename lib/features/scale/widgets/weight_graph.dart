import 'dart:math';
import 'package:flutter/material.dart';

import '../models/brew_recipe.dart';
import '../models/pour_step.dart';
import '../models/weight_point.dart';

class WeightGraph extends StatelessWidget {
  final List<WeightPoint> points;
  final BrewRecipe? recipe;

  const WeightGraph({
    super.key,
    required this.points,
    this.recipe,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty && (recipe == null || recipe!.isEmpty)) {
      return const Center(
        child: Text(
          'No graph data',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return CustomPaint(
      painter: WeightGraphPainter(
        points: points,
        recipe: recipe,
      ),
      child: Container(),
    );
  }
}

class WeightGraphPainter extends CustomPainter {
  final List<WeightPoint> points;
  final BrewRecipe? recipe;

  WeightGraphPainter({
    required this.points,
    this.recipe,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double leftPad = 48;
    const double rightPad = 12;
    const double topPad = 12;
    const double bottomPad = 32;

    final graphWidth = size.width - leftPad - rightPad;
    final graphHeight = size.height - topPad - bottomPad;

    if (graphWidth <= 0 || graphHeight <= 0) return;

    final axisPaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 1.2;

    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.25)
      ..strokeWidth = 1;

    final linePaint = Paint()
      ..color = Colors.brown
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = Colors.brown
      ..style = PaintingStyle.fill;

    final recipeLinePaint = Paint()
      ..color = Colors.blue.withOpacity(0.7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final recipeEndPaint = Paint()
      ..color = Colors.green.withOpacity(0.8)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final textStyle = const TextStyle(
      color: Colors.black87,
      fontSize: 11,
    );

    int maxTimeMs = max(points.isNotEmpty ? points.last.elapsedMs : 0, 1000);
    if (recipe != null && !recipe!.isEmpty) {
      maxTimeMs = max(maxTimeMs, recipe!.maxTargetTimeSec * 1000);
    }

    double maxWeight = 1.0;
    for (final p in points) {
      if (p.weightG > maxWeight) maxWeight = p.weightG;
    }
    if (recipe != null && !recipe!.isEmpty) {
      maxWeight = max(maxWeight, recipe!.maxTargetWeight);
    }
    maxWeight *= 1.1;

    final origin = Offset(leftPad, size.height - bottomPad);

    canvas.drawLine(origin, Offset(size.width - rightPad, origin.dy), axisPaint);
    canvas.drawLine(origin, Offset(origin.dx, topPad), axisPaint);

    const int xDivisions = 5;
    const int yDivisions = 5;

    for (int i = 0; i <= xDivisions; i++) {
      final x = leftPad + graphWidth * i / xDivisions;
      canvas.drawLine(
        Offset(x, topPad),
        Offset(x, size.height - bottomPad),
        gridPaint,
      );

      final timeSec = (maxTimeMs * i / xDivisions / 1000.0).round();
      _drawText(
        canvas,
        _formatSec(timeSec),
        Offset(x - 14, size.height - bottomPad + 8),
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
        weight.toStringAsFixed(1),
        Offset(4, y - 6),
        textStyle,
      );
    }

    _drawText(
      canvas,
      'Time',
      Offset(size.width / 2 - 16, size.height - 18),
      textStyle,
    );

    _drawText(
      canvas,
      'Weight (g)',
      const Offset(4, 0),
      textStyle,
    );

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

      canvas.drawPath(path, linePaint);

      final last = points.last;
      final lastX = leftPad + (last.elapsedMs / maxTimeMs) * graphWidth;
      final lastY = size.height - bottomPad - (last.weightG / maxWeight) * graphHeight;
      canvas.drawCircle(Offset(lastX, lastY), 4, pointPaint);
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
      color: Colors.blue.withOpacity(0.9),
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
        TextStyle(
          color: Colors.green.withOpacity(0.9),
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