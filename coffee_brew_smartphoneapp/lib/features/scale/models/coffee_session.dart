import '../../../features/shared/models/flavor_note_tag.dart';
import 'brew_recipe.dart';
import 'weight_point.dart';

class CoffeeSession {
  final String id;
  final DateTime createdAt;

  String? beanName;
  String? country;
  String? regionFarm;
  String? variety;
  String? process;
  String? roastLevel;
  String? grindSize;
  String? flavorNote;
  double? elevationM;
  String? notes;

  /// 使用した豆量（ドース, g）
  double? doseG;

  /// 屈折計で測定した TDS（%）。収率計算に使用
  double? tdsPercent;

  BrewRecipe? recipe;
  final List<WeightPoint> points;

  /// 複数選択フレーバーノート（新形式）。空の場合は flavorNote（旧形式）を使用。
  List<FlavorNoteTag> flavorNotes;

  CoffeeSession({
    required this.id,
    required this.createdAt,
    required this.points,
    this.beanName,
    this.country,
    this.regionFarm,
    this.variety,
    this.process,
    this.roastLevel,
    this.grindSize,
    this.flavorNote,
    this.elevationM,
    this.notes,
    this.doseG,
    this.tdsPercent,
    this.recipe,
    List<FlavorNoteTag>? flavorNotes,
  }) : flavorNotes = flavorNotes ?? [];

  /// 粉1gあたりに保持される液体量の近似値（g/g）。ペーパードリップの一般値
  static const double liquidRetainedRatio = 2.0;

  double get maxWeight {
    if (points.isEmpty) return 0;
    double maxValue = 0;
    for (final p in points) {
      if (p.weightG > maxValue) {
        maxValue = p.weightG;
      }
    }
    return maxValue;
  }

  double get durationSec {
    if (points.isEmpty) return 0;
    return points.last.elapsedMs / 1000.0;
  }

  /// ブリューレシオ（湯量 ÷ 豆量）。計算不能なら null
  double? get brewRatio {
    if (doseG == null || doseG! <= 0 || maxWeight <= 0) return null;
    return maxWeight / doseG!;
  }

  /// 抽出液量の推定値（総注湯量 − 粉が保持する液体）
  double? get estimatedBeverageG {
    if (doseG == null || doseG! <= 0 || maxWeight <= 0) return null;
    final beverage = maxWeight - doseG! * liquidRetainedRatio;
    return beverage > 0 ? beverage : null;
  }

  /// 抽出収率 EY（%）= TDS × 抽出液量 ÷ 豆量
  double? get extractionYieldPercent {
    final beverage = estimatedBeverageG;
    if (tdsPercent == null || tdsPercent! <= 0 || beverage == null) return null;
    return tdsPercent! * beverage / doseG!;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'createdAt': createdAt.toIso8601String(),
      'beanName': beanName,
      'country': country,
      'regionFarm': regionFarm,
      'variety': variety,
      'process': process,
      'roastLevel': roastLevel,
      'grindSize': grindSize,
      'flavorNote': flavorNote,
      'elevationM': elevationM,
      'notes': notes,
      'doseG': doseG,
      'tdsPercent': tdsPercent,
      'recipe': recipe?.toJson(),
      'points': points.map((e) => e.toJson()).toList(),
      'flavorNotes': flavorNotes.map((e) => e.toJson()).toList(),
    };
  }

  factory CoffeeSession.fromJson(Map<String, dynamic> json) {
    return CoffeeSession(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      beanName: json['beanName'] as String?,
      country: json['country'] as String?,
      regionFarm: json['regionFarm'] as String?,
      variety: json['variety'] as String?,
      process: json['process'] as String?,
      roastLevel: json['roastLevel'] as String?,
      grindSize: json['grindSize'] as String?,
      flavorNote: json['flavorNote'] as String?,
      elevationM: (json['elevationM'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      doseG: (json['doseG'] as num?)?.toDouble(),
      tdsPercent: (json['tdsPercent'] as num?)?.toDouble(),
      recipe: json['recipe'] == null
          ? null
          : BrewRecipe.fromJson(Map<String, dynamic>.from(json['recipe'])),
      points: (json['points'] as List)
          .map((e) => WeightPoint.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      flavorNotes: (json['flavorNotes'] as List?)
              ?.map((e) =>
                  FlavorNoteTag.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }
}