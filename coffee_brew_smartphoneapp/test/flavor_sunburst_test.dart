import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcoffee_scale_app01/features/flavor_wheel/models/flavor_category.dart';
import 'package:fcoffee_scale_app01/features/flavor_wheel/widgets/flavor_sunburst.dart';

void main() {
  final cats = FlavorCategory.defaults;
  final nodes = buildSunburstNodes(cats, japanese: true);

  test('角度は小分類の数に比例し、全周を隙間なく埋める', () {
    final top = nodes.where((n) => n.depth == 1).toList();
    expect(top.first.x0, 0);
    expect(top.last.x1, closeTo(1, 1e-9));
    for (int i = 1; i < top.length; i++) {
      expect(top[i].x0, closeTo(top[i - 1].x1, 1e-9));
    }
    final fruity = top.firstWhere((n) => n.category.id == 'fruity');
    final spices = top.firstWhere((n) => n.category.id == 'spices');
    // Fruity は14項目、Spices は5項目
    expect((fruity.x1 - fruity.x0) / (spices.x1 - spices.x0), closeTo(14 / 5, 1e-9));
  });

  test('キーは階層をまたいでも一意（vanilla の重複対策）', () {
    final keys = nodes.map((n) => n.key).toSet();
    expect(keys.length, nodes.length);
  });

  test('日本語名と英語名の切り替え', () {
    expect(nodes.firstWhere((n) => n.key == 'fruity').label, 'フルーティー');
    final en = buildSunburstNodes(cats, japanese: false);
    expect(en.firstWhere((n) => n.key == 'fruity').label, 'Fruity');
  });

  test('当たり判定：中心・各リング・ズーム後', () {
    const size = Size(400, 400);
    final g = FlavorSunburstPainter.geometryFor(size, SunburstView.root);
    final c = g.center;
    expect(g.isCenter(c), isTrue);

    // 真上のすぐ右（Fruity の先頭）の大分類リング
    Offset at(SunburstGeometry g, double r, double x) {
      final a = -pi / 2 + x * 2 * pi;
      return c + Offset(r * cos(a), r * sin(a));
    }

    final rCat = g.holeR + (g.radius - g.holeR) / 6;
    expect(g.hitTest(at(g, rCat, 0.01), nodes)!.key, 'fruity');
    final rItem = g.radius - 3;
    expect(g.hitTest(at(g, rItem, 0.001), nodes)!.key, 'fruity/berry/strawberry');

    // Berry に寄ると小分類が全周に広がる
    final berry = nodes.firstWhere((n) => n.key == 'fruity/berry');
    final gz = FlavorSunburstPainter.geometryFor(size, SunburstView.of(berry));
    final hit = gz.hitTest(at(gz, gz.radius - 5, 0.6), nodes)!;
    expect(hit.parent, berry);
    expect(hit.item!.id, 'blueberry'); // 4項目中3番目（0.5〜0.75）
    // 大分類はもう見えない（中心に隠れる）
    expect(gz.hitTest(at(gz, gz.holeR + 2, 0.1), nodes)!.depth, 3);
  });
}
