/// 豆の在庫1袋分。焙煎日からのエイジングと残量を管理する
class BeanStock {
  final String id;
  String name;
  String? roaster;
  DateTime? roastDate;
  double? totalG;
  double? remainingG;
  String? memo;

  BeanStock({
    required this.id,
    required this.name,
    this.roaster,
    this.roastDate,
    this.totalG,
    this.remainingG,
    this.memo,
  });

  /// 焙煎日からの経過日数。焙煎日未設定なら null
  int? get daysSinceRoast {
    if (roastDate == null) return null;
    return DateTime.now().difference(roastDate!).inDays;
  }

  /// 残量割合 0.0〜1.0。総量未設定なら null
  double? get remainingRatio {
    if (totalG == null || totalG! <= 0 || remainingG == null) return null;
    final ratio = remainingG! / totalG!;
    if (ratio < 0) return 0;
    if (ratio > 1) return 1;
    return ratio;
  }

  void consume(double grams) {
    if (remainingG == null) return;
    remainingG = remainingG! - grams;
    if (remainingG! < 0) remainingG = 0;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'roaster': roaster,
      'roastDate': roastDate?.toIso8601String(),
      'totalG': totalG,
      'remainingG': remainingG,
      'memo': memo,
    };
  }

  factory BeanStock.fromJson(Map<String, dynamic> json) {
    return BeanStock(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      roaster: json['roaster'] as String?,
      roastDate: json['roastDate'] == null
          ? null
          : DateTime.tryParse(json['roastDate'] as String),
      totalG: (json['totalG'] as num?)?.toDouble(),
      remainingG: (json['remainingG'] as num?)?.toDouble(),
      memo: json['memo'] as String?,
    );
  }
}
