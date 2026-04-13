import 'pour_step.dart';

class BrewRecipe {
  String? name;
  double? beanQuantityG;
  int? targetEndSec;
  List<PourStep> steps;

  BrewRecipe({
    this.name,
    this.beanQuantityG,
    this.targetEndSec,
    required this.steps,
  });

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
      if (step.targetTotalG > maxValue) {
        maxValue = step.targetTotalG;
      }
    }
    return maxValue;
  }

  int get maxTargetTimeSec {
    int maxValue = 0;
    for (final step in steps) {
      if (step.startSec > maxValue) {
        maxValue = step.startSec;
      }
    }
    if (targetEndSec != null && targetEndSec! > maxValue) {
      maxValue = targetEndSec!;
    }
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
      name: name,
      beanQuantityG: currentBeanQuantityG,
      targetEndSec: targetEndSec,
      steps: steps
          .map(
            (e) => PourStep(
          stepNumber: e.stepNumber,
          startSec: e.startSec,
          targetTotalG: e.targetTotalG * ratio,
        ),
      )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'beanQuantityG': beanQuantityG,
      'targetEndSec': targetEndSec,
      'steps': steps.map((e) => e.toJson()).toList(),
    };
  }

  factory BrewRecipe.fromJson(Map<String, dynamic> json) {
    return BrewRecipe(
      name: json['name'] as String?,
      beanQuantityG: (json['beanQuantityG'] as num?)?.toDouble(),
      targetEndSec: json['targetEndSec'] as int?,
      steps: (json['steps'] as List? ?? [])
          .map((e) => PourStep.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  BrewRecipe copy() {
    return BrewRecipe(
      name: name,
      beanQuantityG: beanQuantityG,
      targetEndSec: targetEndSec,
      steps: steps
          .map(
            (e) => PourStep(
          stepNumber: e.stepNumber,
          startSec: e.startSec,
          targetTotalG: e.targetTotalG,
        ),
      )
          .toList(),
    );
  }
}