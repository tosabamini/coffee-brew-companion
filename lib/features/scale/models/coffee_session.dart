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

  BrewRecipe? recipe;
  final List<WeightPoint> points;

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
    this.recipe,
  });

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
      'recipe': recipe?.toJson(),
      'points': points.map((e) => e.toJson()).toList(),
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
      recipe: json['recipe'] == null
          ? null
          : BrewRecipe.fromJson(Map<String, dynamic>.from(json['recipe'])),
      points: (json['points'] as List)
          .map((e) => WeightPoint.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}