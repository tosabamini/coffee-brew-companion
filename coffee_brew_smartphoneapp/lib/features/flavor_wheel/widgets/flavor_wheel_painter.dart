import 'dart:math';

import 'package:flutter/material.dart';

import '../models/flavor_category.dart';

class FlavorWheelPainter extends CustomPainter {
  final List<FlavorCategory> categories;

  /// ホイール全体の回転オフセット（ラジアン）
  final double rotationOffset;

  /// 拡大モード用：中心座標を外部から指定（null = キャンバス中心）
  final Offset? overrideCenter;

  /// 拡大モード用：半径を外部から指定（null = shortestSide/2）
  final double? overrideRadius;

  /// ラベルのフォントサイズ倍率
  final double fontScale;

  /// 小分類ラベルを表示する対象の中分類 ID。
  /// null = 小分類ラベルを一切描画しない（通常モード）
  /// 非 null = その中分類の子フレーバーのみ描画（拡大モード）
  final String? activeSubCategoryId;

  // スクリーン側でアクティブ中分類を計算するために公開
  static const double catGap = 0.022;
  static const double subGap = 0.014;
  static const double itemGap = 0.008;

  const FlavorWheelPainter({
    required this.categories,
    this.rotationOffset = 0.0,
    this.overrideCenter,
    this.overrideRadius,
    this.fontScale = 1.0,
    this.activeSubCategoryId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (categories.isEmpty) return;

    final center = overrideCenter ?? Offset(size.width / 2, size.height / 2);
    final r = overrideRadius ?? size.shortestSide / 2;

    final innerHoleR = r * 0.18;
    final catOuterR  = r * 0.40;
    final subOuterR  = r * 0.66;
    final itemOuterR = r * 0.98;

    final n = categories.length;
    final sliceAngle = 2 * pi / n;
    double catAngle = -pi / 2 + rotationOffset;

    for (final category in categories) {
      final catEffective = sliceAngle - catGap;
      final catStart     = catAngle + catGap / 2;

      // ── 大分類リング（水平テキスト） ────────────────────────────────────
      _drawSegment(canvas, center, innerHoleR, catOuterR,
          catStart, catEffective, category.color);
      _drawHorizontalLabel(
        canvas, category.name, center,
        (innerHoleR + catOuterR) / 2, catStart + catEffective / 2,
        10, Colors.white,
        catEffective * (innerHoleR + catOuterR) / 2,
      );

      final numSubs = category.subCategories.length;
      if (numSubs > 0) {
        final subSlice = catEffective / numSubs;

        for (int si = 0; si < numSubs; si++) {
          final sub          = category.subCategories[si];
          final subStart     = catStart + si * subSlice + subGap / 2;
          final subEffective = subSlice - subGap;
          final subMidAngle  = subStart + subEffective / 2;
          final subColor     = Color.lerp(category.color, Colors.white, 0.28)!;

          if (sub.items.isEmpty) {
            // リーフノード：中間〜外側を一体描画、円弧テキスト
            _drawSegment(canvas, center, catOuterR, itemOuterR,
                subStart, subEffective, subColor);
            _drawArcLabel(
              canvas, sub.name, center,
              (catOuterR + itemOuterR) / 2, subMidAngle,
              9, Colors.black87,
              subEffective * (catOuterR + itemOuterR) / 2,
            );
          } else {
            // ── 中分類リング（円弧テキスト、常時表示） ───────────────────
            _drawSegment(canvas, center, catOuterR, subOuterR,
                subStart, subEffective, subColor);
            _drawArcLabel(
              canvas, sub.name, center,
              (catOuterR + subOuterR) / 2, subMidAngle,
              9, Colors.black87,
              subEffective * (catOuterR + subOuterR) / 2,
            );

            // ── 小分類リング（activeSubCategoryId と一致する場合のみ） ───
            if (activeSubCategoryId != null &&
                sub.id == activeSubCategoryId) {
              final numItems = sub.items.length;
              final itemSlice = subEffective / numItems;

              for (int ii = 0; ii < numItems; ii++) {
                final itemStart     = subStart + ii * itemSlice + itemGap / 2;
                final itemEffective = itemSlice - itemGap;
                final itemMidAngle  = itemStart + itemEffective / 2;
                final itemColor     = Color.lerp(
                  category.color, Colors.white,
                  0.50 + (ii.isEven ? 0.0 : 0.08),
                )!;

                _drawSegment(canvas, center, subOuterR, itemOuterR,
                    itemStart, itemEffective, itemColor);
                _drawRadialLabel(
                  canvas, sub.items[ii].name, center,
                  subOuterR, itemOuterR, itemMidAngle,
                  7, Colors.black87,
                );
              }
            } else {
              // 非アクティブな中分類の外側リングはセグメント色で塗りつぶすのみ
              final numItems = sub.items.length;
              final itemSlice = subEffective / numItems;
              for (int ii = 0; ii < numItems; ii++) {
                final itemStart     = subStart + ii * itemSlice + itemGap / 2;
                final itemEffective = itemSlice - itemGap;
                final itemColor     = Color.lerp(
                  category.color, Colors.white,
                  0.50 + (ii.isEven ? 0.0 : 0.08),
                )!;
                _drawSegment(canvas, center, subOuterR, itemOuterR,
                    itemStart, itemEffective, itemColor);
              }
            }
          }
        }
      }

      catAngle += sliceAngle;
    }

    // 中心の白円
    canvas.drawCircle(center, innerHoleR - 1, Paint()..color = Colors.white);
  }

  // ── セグメント描画 ────────────────────────────────────────────────────────

  void _drawSegment(
    Canvas canvas,
    Offset center,
    double innerR,
    double outerR,
    double startAngle,
    double sweepAngle,
    Color color,
  ) {
    if (sweepAngle <= 0) return;
    final path = Path()
      ..moveTo(center.dx + innerR * cos(startAngle),
               center.dy + innerR * sin(startAngle))
      ..arcTo(Rect.fromCircle(center: center, radius: outerR),
              startAngle, sweepAngle, false)
      ..arcTo(Rect.fromCircle(center: center, radius: innerR),
              startAngle + sweepAngle, -sweepAngle, false)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  // ── 水平テキスト（大分類用） ──────────────────────────────────────────────

  void _drawHorizontalLabel(
    Canvas canvas,
    String text,
    Offset center,
    double radius,
    double angle,
    double fontSize,
    Color color,
    double availableArcLength,
  ) {
    final scaledSize = fontSize * fontScale;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: scaledSize,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: 90 * fontScale);

    if (availableArcLength < tp.width * 0.8) return;

    final x = center.dx + radius * cos(angle) - tp.width / 2;
    final y = center.dy + radius * sin(angle) - tp.height / 2;
    tp.paint(canvas, Offset(x, y));
  }

  // ── 円弧テキスト（中分類・小分類用） ─────────────────────────────────────
  //
  // 角度 θ において：
  //   下半分 (sin θ > 0): textRotation = θ - π/2  → 上向きで読みやすい
  //   上半分 (sin θ ≤ 0): textRotation = θ + π/2  → 逆さにならない
  //
  // 例）θ = π/2（真下）→ rotation = 0 = 水平テキスト

  void _drawArcLabel(
    Canvas canvas,
    String text,
    Offset center,
    double radius,
    double midAngle,
    double fontSize,
    Color color,
    double arcLength,
  ) {
    final scaledSize = fontSize * fontScale;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: scaledSize,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: arcLength.clamp(20.0, 200.0 * fontScale));

    // 弧長がテキスト幅の75%未満なら描画しない
    if (arcLength < tp.width * 0.75) return;

    // テキスト中心座標
    final px = center.dx + radius * cos(midAngle);
    final py = center.dy + radius * sin(midAngle);

    // 円弧接線方向への回転（逆さにならないよう半分で補正）
    final textRotation =
        sin(midAngle) >= 0 ? midAngle - pi / 2 : midAngle + pi / 2;

    canvas.save();
    canvas.translate(px, py);
    canvas.rotate(textRotation);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  // ── 半径方向テキスト（小分類用） ──────────────────────────────────────────
  //
  // テキストの x 軸を半径方向（中心→外側）に向けて描画する。
  // 右半分: rotate(θ) で文字が外側へ流れる
  // 左半分: rotate(θ+π) で上下反転を防ぐ

  void _drawRadialLabel(
    Canvas canvas,
    String text,
    Offset center,
    double innerR,
    double outerR,
    double midAngle,
    double fontSize,
    Color color,
  ) {
    final scaledSize = fontSize * fontScale;
    final radialExtent = outerR - innerR;

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: scaledSize,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: radialExtent);

    final midR = (innerR + outerR) / 2;
    final px = center.dx + midR * cos(midAngle);
    final py = center.dy + midR * sin(midAngle);

    final textRotation = cos(midAngle) >= 0 ? midAngle : midAngle + pi;

    canvas.save();
    canvas.translate(px, py);
    canvas.rotate(textRotation);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(FlavorWheelPainter oldDelegate) =>
      oldDelegate.categories         != categories         ||
      oldDelegate.rotationOffset      != rotationOffset      ||
      oldDelegate.overrideCenter      != overrideCenter      ||
      oldDelegate.overrideRadius      != overrideRadius      ||
      oldDelegate.fontScale           != fontScale           ||
      oldDelegate.activeSubCategoryId != activeSubCategoryId;
}
