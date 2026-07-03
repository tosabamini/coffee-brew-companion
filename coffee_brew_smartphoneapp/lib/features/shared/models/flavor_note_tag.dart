class FlavorNoteTag {
  final String name;
  final String? categoryName;    // null = Uncategorized
  final int? categoryColorValue; // Color.value（JSON対応のためint保存）
  final bool isCustom;           // trueならユーザー手入力

  const FlavorNoteTag({
    required this.name,
    this.categoryName,
    this.categoryColorValue,
    this.isCustom = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'categoryName': categoryName,
        'categoryColorValue': categoryColorValue,
        'isCustom': isCustom,
      };

  factory FlavorNoteTag.fromJson(Map<String, dynamic> json) => FlavorNoteTag(
        name: json['name'] as String,
        categoryName: json['categoryName'] as String?,
        categoryColorValue: json['categoryColorValue'] as int?,
        isCustom: json['isCustom'] as bool? ?? false,
      );
}
