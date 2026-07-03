import 'package:flutter/material.dart';

class FlavorItem {
  final String id;
  final String name;
  final bool isUserAdded;

  const FlavorItem({
    required this.id,
    required this.name,
    this.isUserAdded = false,
  });

  FlavorItem copyWith({bool? isUserAdded}) => FlavorItem(
        id: id,
        name: name,
        isUserAdded: isUserAdded ?? this.isUserAdded,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isUserAdded': isUserAdded,
      };

  factory FlavorItem.fromJson(Map<String, dynamic> json) => FlavorItem(
        id: json['id'] as String,
        name: json['name'] as String,
        isUserAdded: json['isUserAdded'] as bool? ?? false,
      );
}

class FlavorSubCategory {
  final String id;
  final String name;

  /// 空リストの場合は外側リングに子を持たないリーフノード
  final List<FlavorItem> items;

  const FlavorSubCategory({
    required this.id,
    required this.name,
    required this.items,
  });

  FlavorSubCategory copyWith({List<FlavorItem>? items}) =>
      FlavorSubCategory(id: id, name: name, items: items ?? this.items);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory FlavorSubCategory.fromJson(Map<String, dynamic> json) =>
      FlavorSubCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        items: (json['items'] as List)
            .map((e) => FlavorItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class FlavorCategory {
  final String id;
  final String name;
  final Color color;
  final List<FlavorSubCategory> subCategories;

  const FlavorCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.subCategories,
  });

  FlavorCategory copyWith({List<FlavorSubCategory>? subCategories}) =>
      FlavorCategory(
        id: id,
        name: name,
        color: color,
        subCategories: subCategories ?? this.subCategories,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': color.value,
        'subCategories': subCategories.map((e) => e.toJson()).toList(),
      };

  factory FlavorCategory.fromJson(Map<String, dynamic> json) => FlavorCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        color: Color(json['colorValue'] as int),
        subCategories: (json['subCategories'] as List)
            .map((e) =>
                FlavorSubCategory.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  static List<FlavorCategory> get defaults => [
        FlavorCategory(
          id: 'fruity',
          name: 'Fruity',
          color: const Color(0xFFE53935),
          subCategories: [
            FlavorSubCategory(id: 'berry', name: 'Berry', items: [
              const FlavorItem(id: 'strawberry', name: 'Strawberry'),
              const FlavorItem(id: 'raspberry', name: 'Raspberry'),
              const FlavorItem(id: 'blueberry', name: 'Blueberry'),
              const FlavorItem(id: 'blackberry', name: 'Blackberry'),
            ]),
            FlavorSubCategory(id: 'dried_fruit', name: 'Dried Fruit', items: [
              const FlavorItem(id: 'raisin', name: 'Raisin'),
              const FlavorItem(id: 'prune', name: 'Prune'),
            ]),
            FlavorSubCategory(id: 'other_fruit', name: 'Other Fruit', items: [
              const FlavorItem(id: 'coconut', name: 'Coconut'),
              const FlavorItem(id: 'cherry', name: 'Cherry'),
              const FlavorItem(id: 'pomegranate', name: 'Pomegranate'),
              const FlavorItem(id: 'pineapple', name: 'Pineapple'),
            ]),
            FlavorSubCategory(id: 'citrus_fruit', name: 'Citrus Fruit', items: [
              const FlavorItem(id: 'lemon', name: 'Lemon'),
              const FlavorItem(id: 'lime', name: 'Lime'),
              const FlavorItem(id: 'orange', name: 'Orange'),
              const FlavorItem(id: 'grapefruit', name: 'Grapefruit'),
            ]),
          ],
        ),
        FlavorCategory(
          id: 'sour_fermented',
          name: 'Sour/Fermented',
          color: const Color(0xFFFFB300),
          subCategories: [
            FlavorSubCategory(id: 'sour', name: 'Sour', items: [
              const FlavorItem(id: 'sour_aromatics', name: 'Sour Aromatics'),
              const FlavorItem(id: 'acetic_acid', name: 'Acetic Acid'),
            ]),
            FlavorSubCategory(
                id: 'alcohol_fermented',
                name: 'Alcohol/Fermented',
                items: [
                  const FlavorItem(id: 'winey', name: 'Winey'),
                  const FlavorItem(id: 'whiskey', name: 'Whiskey'),
                  const FlavorItem(id: 'fermented', name: 'Fermented'),
                ]),
            FlavorSubCategory(id: 'overripe', name: 'Overripe', items: [
              const FlavorItem(id: 'overripe_fruit', name: 'Overripe Fruit'),
            ]),
          ],
        ),
        FlavorCategory(
          id: 'green_vegetative',
          name: 'Green/Vegetative',
          color: const Color(0xFF43A047),
          subCategories: [
            const FlavorSubCategory(
                id: 'olive_oil', name: 'Olive Oil', items: []),
            FlavorSubCategory(id: 'raw', name: 'Raw', items: [
              const FlavorItem(id: 'green_bean', name: 'Green Bean'),
              const FlavorItem(id: 'peapod', name: 'Peapod'),
            ]),
            FlavorSubCategory(id: 'vegetative', name: 'Vegetative', items: [
              const FlavorItem(id: 'fresh', name: 'Fresh'),
              const FlavorItem(id: 'dark_green', name: 'Dark Green'),
              const FlavorItem(id: 'herbal', name: 'Herbal'),
            ]),
            const FlavorSubCategory(id: 'beany', name: 'Beany', items: []),
          ],
        ),
        FlavorCategory(
          id: 'other',
          name: 'Other',
          color: const Color(0xFF757575),
          subCategories: [
            FlavorSubCategory(id: 'papery_musty', name: 'Papery/Musty', items: [
              const FlavorItem(id: 'stale', name: 'Stale'),
              const FlavorItem(id: 'cardboard', name: 'Cardboard'),
              const FlavorItem(id: 'papery', name: 'Papery'),
            ]),
            FlavorSubCategory(id: 'chemical', name: 'Chemical', items: [
              const FlavorItem(id: 'phenolic', name: 'Phenolic'),
              const FlavorItem(id: 'medicinal', name: 'Medicinal'),
              const FlavorItem(id: 'petroleum', name: 'Petroleum'),
            ]),
            FlavorSubCategory(id: 'moldy_damp', name: 'Moldy/Damp', items: [
              const FlavorItem(id: 'moldy', name: 'Moldy'),
              const FlavorItem(id: 'damp', name: 'Damp'),
            ]),
          ],
        ),
        FlavorCategory(
          id: 'roasted',
          name: 'Roasted',
          color: const Color(0xFF4E342E),
          subCategories: [
            const FlavorSubCategory(
                id: 'pipe_tobacco', name: 'Pipe Tobacco', items: []),
            const FlavorSubCategory(
                id: 'tobacco', name: 'Tobacco', items: []),
            FlavorSubCategory(id: 'burnt', name: 'Burnt', items: [
              const FlavorItem(id: 'acrid', name: 'Acrid'),
              const FlavorItem(id: 'ashy', name: 'Ashy'),
            ]),
            FlavorSubCategory(id: 'cereal', name: 'Cereal', items: [
              const FlavorItem(id: 'grain', name: 'Grain'),
              const FlavorItem(id: 'malt', name: 'Malt'),
              const FlavorItem(id: 'toast', name: 'Toast'),
            ]),
          ],
        ),
        FlavorCategory(
          id: 'spices',
          name: 'Spices',
          color: const Color(0xFFE64A19),
          subCategories: [
            FlavorSubCategory(id: 'pungent', name: 'Pungent', items: [
              const FlavorItem(id: 'pepper', name: 'Pepper'),
              const FlavorItem(id: 'clove', name: 'Clove'),
            ]),
            FlavorSubCategory(id: 'brown_spice', name: 'Brown Spice', items: [
              const FlavorItem(id: 'cinnamon', name: 'Cinnamon'),
              const FlavorItem(id: 'nutmeg', name: 'Nutmeg'),
              const FlavorItem(id: 'anise', name: 'Anise'),
            ]),
          ],
        ),
        FlavorCategory(
          id: 'nutty_cocoa',
          name: 'Nutty/Cocoa',
          color: const Color(0xFF6D4C41),
          subCategories: [
            FlavorSubCategory(id: 'nutty', name: 'Nutty', items: [
              const FlavorItem(id: 'peanut', name: 'Peanut'),
              const FlavorItem(id: 'hazelnut', name: 'Hazelnut'),
              const FlavorItem(id: 'almond', name: 'Almond'),
            ]),
            FlavorSubCategory(id: 'cocoa', name: 'Cocoa', items: [
              const FlavorItem(id: 'chocolate', name: 'Chocolate'),
              const FlavorItem(id: 'dark_chocolate', name: 'Dark Chocolate'),
            ]),
          ],
        ),
        FlavorCategory(
          id: 'sweet',
          name: 'Sweet',
          color: const Color(0xFFF9A825),
          subCategories: [
            FlavorSubCategory(id: 'brown_sugar', name: 'Brown Sugar', items: [
              const FlavorItem(id: 'molasses', name: 'Molasses'),
              const FlavorItem(id: 'maple_syrup', name: 'Maple Syrup'),
              const FlavorItem(id: 'caramelized', name: 'Caramelized'),
            ]),
            FlavorSubCategory(id: 'vanilla', name: 'Vanilla', items: [
              const FlavorItem(id: 'vanilla', name: 'Vanilla'),
            ]),
            FlavorSubCategory(
                id: 'overall_sweet',
                name: 'Overall Sweet',
                items: [
                  const FlavorItem(
                      id: 'sweet_aromatics', name: 'Sweet Aromatics'),
                ]),
          ],
        ),
        FlavorCategory(
          id: 'floral',
          name: 'Floral',
          color: const Color(0xFF8E24AA),
          subCategories: [
            const FlavorSubCategory(
                id: 'black_tea', name: 'Black Tea', items: []),
            FlavorSubCategory(id: 'floral_sub', name: 'Floral', items: [
              const FlavorItem(id: 'chamomile', name: 'Chamomile'),
              const FlavorItem(id: 'rose', name: 'Rose'),
              const FlavorItem(id: 'jasmine', name: 'Jasmine'),
            ]),
          ],
        ),
      ];
}
