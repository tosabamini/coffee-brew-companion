import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/flavor_category.dart';

class FlavorStorage {
  static const _categoriesFile = 'flavor_wheel.json';
  static const _uncategorizedFile = 'flavor_uncategorized.json';

  static Future<Directory> _getDir() async =>
      getApplicationDocumentsDirectory();

  // ── Categories ─────────────────────────────────────────────────────────

  static Future<List<FlavorCategory>> loadCategories() async {
    try {
      final dir = await _getDir();
      final file = File('${dir.path}/$_categoriesFile');
      if (!await file.exists()) return FlavorCategory.defaults;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return FlavorCategory.defaults;
      final decoded = jsonDecode(text) as List;
      return decoded
          .map((e) => FlavorCategory.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return FlavorCategory.defaults;
    }
  }

  static Future<void> saveCategories(List<FlavorCategory> categories) async {
    final dir = await _getDir();
    final file = File('${dir.path}/$_categoriesFile');
    await file.writeAsString(
        jsonEncode(categories.map((e) => e.toJson()).toList()));
  }

  // ── Uncategorized ───────────────────────────────────────────────────────

  static Future<List<String>> loadUncategorized() async {
    try {
      final dir = await _getDir();
      final file = File('${dir.path}/$_uncategorizedFile');
      if (!await file.exists()) return [];
      final text = await file.readAsString();
      if (text.trim().isEmpty) return [];
      return (jsonDecode(text) as List).cast<String>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveUncategorized(List<String> names) async {
    final dir = await _getDir();
    final file = File('${dir.path}/$_uncategorizedFile');
    await file.writeAsString(jsonEncode(names));
  }
}
