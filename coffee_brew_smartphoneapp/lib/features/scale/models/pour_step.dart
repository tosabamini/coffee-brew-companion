class PourStep {
  final int stepNumber;
  final int startSec;
  final double targetTotalG;

  PourStep({
    required this.stepNumber,
    required this.startSec,
    required this.targetTotalG,
  });

  Map<String, dynamic> toJson() {
    return {
      'stepNumber': stepNumber,
      'startSec': startSec,
      'targetTotalG': targetTotalG,
    };
  }

  factory PourStep.fromJson(Map<String, dynamic> json) {
    return PourStep(
      stepNumber: json['stepNumber'] as int,
      startSec: json['startSec'] as int,
      targetTotalG: (json['targetTotalG'] as num).toDouble(),
    );
  }
}