import 'pour_step.dart';

class BrewRecipe {
  String? id;
  String? name;
  double? beanQuantityG;
  int? targetEndSec;
  List<PourStep> steps;

  /// 出典（店名・人物名・参照元など）。プリセットや、プリセットからコピーしたレシピで使う
  String? source;

  BrewRecipe({
    this.id,
    this.name,
    this.beanQuantityG,
    this.targetEndSec,
    required this.steps,
    this.source,
  });

  /// アプリ内蔵のプリセット（有名店・バリスタのレシピ）かどうか。編集不可
  bool get isPreset => id != null && id!.startsWith('preset_');

  bool get isEmpty {
    return (name == null || name!.trim().isEmpty) &&
        beanQuantityG == null &&
        targetEndSec == null &&
        steps.isEmpty;
  }

  double get maxTargetWeight {
    if (steps.isEmpty) return 0;
    double maxValue = 0;
    for (final step in steps) {
      if (step.targetTotalG > maxValue) maxValue = step.targetTotalG;
    }
    return maxValue;
  }

  int get maxTargetTimeSec {
    int maxValue = 0;
    for (final step in steps) {
      if (step.startSec > maxValue) maxValue = step.startSec;
    }
    if (targetEndSec != null && targetEndSec! > maxValue) maxValue = targetEndSec!;
    return maxValue;
  }

  BrewRecipe scaledForBeanQuantity(double? currentBeanQuantityG) {
    if (beanQuantityG == null ||
        currentBeanQuantityG == null ||
        beanQuantityG! <= 0 ||
        currentBeanQuantityG <= 0) {
      return copy();
    }
    final ratio = currentBeanQuantityG / beanQuantityG!;
    return BrewRecipe(
      id: id,
      name: name,
      beanQuantityG: currentBeanQuantityG,
      targetEndSec: targetEndSec,
      steps: steps
          .map((e) => PourStep(
                stepNumber: e.stepNumber,
                startSec: e.startSec,
                targetTotalG: e.targetTotalG * ratio,
              ))
          .toList(),
      source: source,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'beanQuantityG': beanQuantityG,
      'targetEndSec': targetEndSec,
      'steps': steps.map((e) => e.toJson()).toList(),
      if (source != null) 'source': source,
    };
  }

  factory BrewRecipe.fromJson(Map<String, dynamic> json) {
    return BrewRecipe(
      id: json['id'] as String?,
      name: json['name'] as String?,
      beanQuantityG: (json['beanQuantityG'] as num?)?.toDouble(),
      targetEndSec: json['targetEndSec'] as int?,
      steps: (json['steps'] as List? ?? [])
          .map((e) => PourStep.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      source: json['source'] as String?,
    );
  }

  BrewRecipe copy() {
    return BrewRecipe(
      id: id,
      name: name,
      beanQuantityG: beanQuantityG,
      targetEndSec: targetEndSec,
      steps: steps
          .map((e) => PourStep(
                stepNumber: e.stepNumber,
                startSec: e.startSec,
                targetTotalG: e.targetTotalG,
              ))
          .toList(),
      source: source,
    );
  }
}
