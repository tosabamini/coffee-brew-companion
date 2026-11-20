import 'package:flutter/foundation.dart';

import '../models/brew_recipe.dart';
import '../models/weight_point.dart';
import 'pip_service.dart';

/// 小窓表示（ピクチャーインピクチャー）用に、いまの抽出の様子をまとめて持つ。
/// メイン画面が更新し、小窓の表示（MiniBrewView）が読む。
/// 小窓になっていないときは値を覚えるだけで、画面の描き直しは起こさない。
class LiveBrew extends ChangeNotifier {
  LiveBrew._();

  static final LiveBrew instance = LiveBrew._();

  List<WeightPoint> points = const [];
  BrewRecipe? recipe;
  List<WeightPoint>? ghostPoints;
  double weightG = 0;
  String elapsed = '0:00';
  bool measuring = false;
  bool connected = false;

  void update({
    required List<WeightPoint> points,
    required BrewRecipe? recipe,
    required List<WeightPoint>? ghostPoints,
    required double weightG,
    required String elapsed,
    required bool measuring,
    required bool connected,
  }) {
    this.points = points;
    this.recipe = recipe;
    this.ghostPoints = ghostPoints;
    this.weightG = weightG;
    this.elapsed = elapsed;
    this.measuring = measuring;
    this.connected = connected;
    if (PipService.inPip.value) notifyListeners();
  }
}
