import 'dart:math';

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../data/flavor_labels_ja.dart';
import '../models/flavor_category.dart';

/// サンバーストの1区画（大分類・中分類・小分類のどれか）。
///
/// [x0]〜[x1] は全周を 0〜1 とした位置。角度は「小分類1つ＝同じ幅」で割り当てるので、
/// 項目の多い大分類ほど広くなり、外周の文字がつぶれにくい。
class SunburstNode {
  final String key; // "cat/sub/item" 形式（id は階層をまたいで重複しうるため）
  final int depth; // 1=大分類 2=中分類 3=小分類
  final int depthEnd; // 外側の端の深さ（小分類を持たない中分類は 3 まで伸ばす）
  final double x0, x1;
  final Color color;
  final String label;
  final FlavorCategory category;
  final FlavorSubCategory? sub;
  final FlavorItem? item;
  final SunburstNode? parent;

  SunburstNode({
    required this.key,
    required this.depth,
    required this.depthEnd,
    required this.x0,
    required this.x1,
    required this.color,
    required this.label,
    required this.category,
    this.sub,
    this.item,
    this.parent,
  });

  bool get hasChildren =>
      depth == 1 || (depth == 2 && (sub?.items.isNotEmpty ?? false));

  /// ルートからのパンくず（自分を含む）
  List<SunburstNode> get path {
    final out = <SunburstNode>[];
    SunburstNode? n = this;
    while (n != null) {
      out.insert(0, n);
      n = n.parent;
    }
    return out;
  }
}

/// カテゴリ一覧からサンバーストの区画を作る。
List<SunburstNode> buildSunburstNodes(
  List<FlavorCategory> categories, {
  required bool japanese,
}) {
  final nodes = <SunburstNode>[];
  int weightOfSub(FlavorSubCategory s) => max(1, s.items.length);
  int weightOfCat(FlavorCategory c) =>
      max(1, c.subCategories.fold(0, (a, s) => a + weightOfSub(s)));
  final total = categories.fold<int>(0, (a, c) => a + weightOfCat(c));
  if (total == 0) return nodes;

  double x = 0;
  for (final cat in categories) {
    final cw = weightOfCat(cat) / total;
    final catNode = SunburstNode(
      key: cat.id,
      depth: 1,
      depthEnd: 1,
      x0: x,
      x1: x + cw,
      color: cat.color,
      label: flavorLabel(cat.id, cat.name, japanese: japanese),
      category: cat,
    );
    nodes.add(catNode);

    double sx = x;
    final subs = cat.subCategories;
    for (int si = 0; si < subs.length; si++) {
      final sub = subs[si];
      final sw = weightOfSub(sub) / total;
      // 中分類は大分類色を少し明るく。隣同士で明るさを変えて境目を分かりやすく
      final subColor =
          Color.lerp(cat.color, Colors.white, si.isEven ? 0.22 : 0.32)!;
      final subNode = SunburstNode(
        key: '${cat.id}/${sub.id}',
        depth: 2,
        depthEnd: sub.items.isEmpty ? 3 : 2,
        x0: sx,
        x1: sx + sw,
        color: subColor,
        label: flavorLabel(sub.id, sub.name, japanese: japanese),
        category: cat,
        sub: sub,
        parent: catNode,
      );
      nodes.add(subNode);

      final n = sub.items.length;
      for (int ii = 0; ii < n; ii++) {
        final item = sub.items[ii];
        nodes.add(SunburstNode(
          key: '${cat.id}/${sub.id}/${item.id}',
          depth: 3,
          depthEnd: 3,
          x0: sx + sw * ii / n,
          x1: sx + sw * (ii + 1) / n,
          color: Color.lerp(cat.color, Colors.white, ii.isEven ? 0.50 : 0.60)!,
          label: flavorLabel(item.id, item.name, japanese: japanese),
          category: cat,
          sub: sub,
          item: item,
          parent: subNode,
        ));
      }
      sx += sw;
    }
    x += cw;
  }
  return nodes;
}

/// 表示中の範囲（ズーム状態）。[f0]〜[f1] の範囲を全周に広げ、[fd] より浅い階層は中心へ隠す。
class SunburstView {
  final double f0, f1, fd;
  const SunburstView(this.f0, this.f1, this.fd);

  static const root = SunburstView(0, 1, 0);

  factory SunburstView.of(SunburstNode? focus) =>
      focus == null ? root : SunburstView(focus.x0, focus.x1, focus.depth.toDouble());

  static SunburstView lerp(SunburstView a, SunburstView b, double t) =>
      SunburstView(
        a.f0 + (b.f0 - a.f0) * t,
        a.f1 + (b.f1 - a.f1) * t,
        a.fd + (b.fd - a.fd) * t,
      );
}

/// 区画の画面上の形（中心からの半径と角度）
class SunburstArc {
  final double r0, r1, a0, a1;
  const SunburstArc(this.r0, this.r1, this.a0, this.a1);
}

/// 描画と当たり判定で共有するジオメトリ
class SunburstGeometry {
  static const maxDepth = 3;

  /// 中心円の半径（全体半径に対する比）
  static const holeRatio = 0.24;

  final Offset center;
  final double radius;
  final SunburstView view;

  const SunburstGeometry(this.center, this.radius, this.view);

  double get holeR => radius * holeRatio;

  SunburstArc? arcOf(SunburstNode n) {
    final span = view.f1 - view.f0;
    if (span <= 0) return null;
    final u0 = ((n.x0 - view.f0) / span).clamp(0.0, 1.0);
    final u1 = ((n.x1 - view.f0) / span).clamp(0.0, 1.0);
    if (u1 - u0 <= 1e-6) return null;

    final levels = max(1.0, maxDepth - view.fd);
    final t = (radius - holeR) / levels;
    final r0 = holeR + (n.depth - view.fd - 1) * t;
    final r1 = holeR + (n.depthEnd - view.fd) * t;
    if (r1 <= holeR + 0.5) return null;
    return SunburstArc(
      max(r0, holeR),
      min(r1, radius),
      -pi / 2 + u0 * 2 * pi,
      -pi / 2 + u1 * 2 * pi,
    );
  }

  /// タップ位置の区画。中心円なら null を返し [isCenter] で判定する。
  bool isCenter(Offset p) => (p - center).distance < holeR;

  SunburstNode? hitTest(Offset p, List<SunburstNode> nodes) {
    final d = p - center;
    final r = d.distance;
    if (r < holeR || r > radius) return null;
    // atan2 は -π〜π。表示の開始角 -π/2 からの角度に直す
    double a = atan2(d.dy, d.dx);
    while (a < -pi / 2) {
      a += 2 * pi;
    }
    for (final n in nodes) {
      final arc = arcOf(n);
      if (arc == null) continue;
      if (r >= arc.r0 && r <= arc.r1 && a >= arc.a0 && a <= arc.a1) return n;
    }
    return null;
  }
}

class FlavorSunburstPainter extends CustomPainter {
  final List<SunburstNode> nodes;
  final SunburstView view;

  /// 中心円に表示する内容（null = ルート）
  final SunburstNode? focus;
  final String? selectedKey;

  /// アニメーション中は文字を描かない（毎フレームの文字レイアウトを避ける）
  final bool showLabels;
  final bool japanese;

  /// 文字のベース（アプリのテーマのフォントを使うため画面から渡す）
  final TextStyle baseStyle;

  FlavorSunburstPainter({
    this.baseStyle = const TextStyle(),
    required this.nodes,
    required this.view,
    required this.focus,
    required this.selectedKey,
    required this.showLabels,
    required this.japanese,
  });

  static SunburstGeometry geometryFor(Size size, SunburstView view) => SunburstGeometry(
        Offset(size.width / 2, size.height / 2),
        size.shortestSide / 2 - 2,
        view,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometryFor(size, view);
    final sep = Paint()
      ..color = BrewColors.crema
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    SunburstNode? selected;
    for (final n in nodes) {
      final arc = g.arcOf(n);
      if (arc == null) continue;
      final path = _segment(g.center, arc);
      canvas.drawPath(path, Paint()..color = n.color);
      canvas.drawPath(path, sep);
      if (n.key == selectedKey) selected = n;
    }

    if (selected != null) {
      final arc = g.arcOf(selected);
      if (arc != null) {
        final path = _segment(g.center, arc);
        canvas.drawPath(
            path,
            Paint()
              ..color = BrewColors.espresso
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
    }

    if (showLabels) {
      for (final n in nodes) {
        final arc = g.arcOf(n);
        if (arc == null) continue;
        _label(canvas, g.center, arc, n);
      }
    }

    _center(canvas, g);
  }

  Path _segment(Offset c, SunburstArc a) {
    final sweep = a.a1 - a.a0;
    // 全周（ズームした中分類が1つだけのとき等）は arcTo が退化するので分けて描く
    if (sweep >= 2 * pi - 1e-4) {
      return Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: c, radius: a.r1))
        ..addOval(Rect.fromCircle(center: c, radius: a.r0));
    }
    return Path()
      ..moveTo(c.dx + a.r0 * cos(a.a0), c.dy + a.r0 * sin(a.a0))
      ..arcTo(Rect.fromCircle(center: c, radius: a.r1), a.a0, sweep, false)
      ..arcTo(Rect.fromCircle(center: c, radius: a.r0), a.a1, -sweep, false)
      ..close();
  }

  static Color textOn(Color bg) =>
      bg.computeLuminance() > 0.42 ? BrewColors.espresso : Colors.white;

  /// 区画に収まる最大の文字サイズを探して描く。
  /// 円周方向（接線）と半径方向の2通りを試し、大きく描ける方を使う。
  void _label(Canvas canvas, Offset c, SunburstArc a, SunburstNode n) {
    final thick = a.r1 - a.r0;
    final half = (a.a1 - a.a0) / 2;
    final mid = (a.a0 + a.a1) / 2;
    final midR = (a.r0 + a.r1) / 2;
    final color = textOn(n.color);
    final weight = n.depth == 1 ? FontWeight.w800 : FontWeight.w600;
    // 拡大して帯が太くなったら文字も大きくする
    final maxSize = (thick * 0.2).clamp(n.depth == 1 ? 16.0 : 14.0, 24.0);
    const minSize = 8.0;

    // 接線方向：幅は弧（はみ出さないよう角度と外周の両方で制限）、高さは帯の厚み
    double tanW(double h) {
      final byAngle = 2 * midR * tan(min(half, 1.2)) * 0.9;
      final outerLimit = a.r1 * a.r1 - pow(midR + h / 2, 2);
      final byOuter = outerLimit > 0 ? 2 * sqrt(outerLimit) : 0.0;
      return min(byAngle, byOuter * 0.95);
    }

    final tangential =
        _fit(n.label, color, weight, maxSize, minSize, tanW, thick * 0.86);

    // 半径方向：幅は帯の厚み、高さは内側の弧の幅
    final radialH = 2 * (a.r0 + 2) * sin(min(half, pi / 2)) * 0.9;
    final radial = _fit(
        n.label, color, weight, maxSize, minSize, (_) => thick * 0.88, radialH);

    TextPainter? tp;
    bool useRadial = false;
    if (tangential != null && radial != null) {
      useRadial = radial.$2 > tangential.$2 + 1.5;
      tp = useRadial ? radial.$1 : tangential.$1;
    } else if (tangential != null) {
      tp = tangential.$1;
    } else if (radial != null) {
      tp = radial.$1;
      useRadial = true;
    }
    if (tp == null) return;

    // 全周の区画は中心の真上（12時）に置く
    final ang = (a.a1 - a.a0) >= 2 * pi - 1e-4 ? -pi / 2 : mid;
    final px = c.dx + midR * cos(ang);
    final py = c.dy + midR * sin(ang);
    double rot;
    if (useRadial) {
      rot = cos(ang) >= 0 ? ang : ang + pi; // 左半分は逆さにならないよう反転
    } else {
      rot = sin(ang) > 0.05 ? ang - pi / 2 : ang + pi / 2; // 下半分は反転
    }
    canvas.save();
    canvas.translate(px, py);
    canvas.rotate(rot);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  /// 幅・高さの制限に収まる最大サイズを二分探索。1行と2行を試し、2行の方が
  /// はっきり大きく描けるときだけ2行にする。どちらも最小サイズで入らなければ null。
  (TextPainter, double)? _fit(
    String text,
    Color color,
    FontWeight weight,
    double maxSize,
    double minSize,
    double Function(double h) widthFor,
    double maxH,
  ) {
    final one = _fitLines(text, 1, color, weight, maxSize, minSize, widthFor, maxH);
    if (one != null && one.$2 >= 10.5) return one;
    if (text.length < 6) return one;
    final two = _fitLines(text, 2, color, weight, maxSize, minSize, widthFor, maxH);
    if (two == null) return one;
    if (one == null) return two;
    return two.$2 > one.$2 + 2 ? two : one;
  }

  (TextPainter, double)? _fitLines(
    String text,
    int lines,
    Color color,
    FontWeight weight,
    double maxSize,
    double minSize,
    double Function(double h) widthFor,
    double maxH,
  ) {
    TextPainter make(double s, double w) => TextPainter(
          text: TextSpan(
            text: text,
            style: baseStyle.copyWith(
                fontSize: s, height: 1.1, color: color, fontWeight: weight),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          maxLines: lines,
        )..layout(maxWidth: max(1, w));
    // 英字は単語の途中で折り返さない（"Flo/ral" のような改行を防ぐ）
    final latin = RegExp(r'^[\x00-\x7F]+$').hasMatch(text);
    final words = latin && lines > 1
        ? text.split(RegExp(r'(?<=[ /])')).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    if (latin && lines > 1 && words.length < 2) return null;
    bool wordsFit(double s, double w) {
      for (final wd in words) {
        final t = TextPainter(
          text: TextSpan(
              text: wd.trim(),
              style: baseStyle.copyWith(fontSize: s, fontWeight: weight)),
          textDirection: TextDirection.ltr,
        )..layout();
        if (t.width > w + 0.5) return false;
      }
      return true;
    }

    bool fits(TextPainter tp, double w) =>
        !tp.didExceedMaxLines &&
        tp.width <= w + 0.5 &&
        tp.height <= maxH &&
        wordsFit(tp.text!.style!.fontSize!, w);

    final w0 = widthFor(minSize * 1.1 * lines);
    final t0 = make(minSize, w0);
    if (!fits(t0, w0)) return null;
    TextPainter best = t0;
    double bestSize = minSize, lo = minSize, hi = maxSize;
    for (int i = 0; i < 6; i++) {
      final m = (lo + hi) / 2;
      final w = widthFor(m * 1.1 * lines);
      final t = make(m, w);
      if (fits(t, w)) {
        best = t;
        bestSize = m;
        lo = m;
      } else {
        hi = m;
      }
    }
    return (best, bestSize);
  }

  void _center(Canvas canvas, SunburstGeometry g) {
    final r = g.holeR - 3;
    final f = focus;
    final bg = f?.color ?? BrewColors.foam;
    canvas.drawCircle(g.center, r, Paint()..color = bg);
    canvas.drawCircle(
        g.center,
        r,
        Paint()
          ..color = BrewColors.oat
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
    if (!showLabels) return;

    final fg = f == null ? BrewColors.mocha : textOn(bg);
    final title = f?.label ?? (japanese ? 'フレーバー' : 'Flavor');
    final hint = f == null
        ? (japanese ? 'タップで拡大' : 'Tap to zoom')
        : (japanese ? '↩ 戻る' : '↩ Back');

    // 1行で収まるなら1行（12px以上）、だめなら2行で縮める
    TextPainter layoutTitle(double size, int lines) => TextPainter(
          text: TextSpan(
            text: title,
            style: baseStyle.copyWith(
                fontSize: size,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: fg),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          maxLines: lines,
        )..layout(maxWidth: r * 1.7);
    TextPainter? tp;
    for (double size = 17; size >= 12 && tp == null; size -= 1) {
      final t = layoutTitle(size, 1);
      if (!t.didExceedMaxLines && t.width <= r * 1.7) tp = t;
    }
    for (double size = 15; size >= 9 && tp == null; size -= 1) {
      final t = layoutTitle(size, 2);
      if ((!t.didExceedMaxLines && t.height < r * 0.95) || size <= 9) tp = t;
    }
    tp ??= layoutTitle(9, 2);
    final hp = TextPainter(
      text: TextSpan(
        text: hint,
        style: baseStyle.copyWith(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: fg.withValues(alpha: 0.75)),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: r * 1.8);
    final total = tp.height + 2 + hp.height;
    final top = g.center.dy - total / 2;
    tp.paint(canvas, Offset(g.center.dx - tp.width / 2, top));
    hp.paint(canvas, Offset(g.center.dx - hp.width / 2, top + tp.height + 2));
  }

  @override
  bool shouldRepaint(FlavorSunburstPainter old) =>
      old.nodes != nodes ||
      old.view.f0 != view.f0 ||
      old.view.f1 != view.f1 ||
      old.view.fd != view.fd ||
      old.focus != focus ||
      old.selectedKey != selectedKey ||
      old.showLabels != showLabels ||
      old.japanese != japanese ||
      old.baseStyle != baseStyle;
}
