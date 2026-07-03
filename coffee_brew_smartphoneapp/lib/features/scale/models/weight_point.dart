class WeightPoint {
  final int elapsedMs;
  final double weightG;

  WeightPoint({
    required this.elapsedMs,
    required this.weightG,
  });

  Map<String, dynamic> toJson() {
    return {
      'elapsedMs': elapsedMs,
      'weightG': weightG,
    };
  }

  factory WeightPoint.fromJson(Map<String, dynamic> json) {
    return WeightPoint(
      elapsedMs: json['elapsedMs'] as int,
      weightG: (json['weightG'] as num).toDouble(),
    );
  }
}