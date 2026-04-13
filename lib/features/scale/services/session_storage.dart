import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/brew_recipe.dart';
import '../models/coffee_session.dart';

class SessionStorage {
  static const String _sessionsFileName = 'coffee_sessions.json';
  static const String _recipeFileName = 'current_brew_recipe.json';

  static Future<Directory> _getDir() async {
    return getApplicationDocumentsDirectory();
  }

  static Future<File> _getSessionsFile() async {
    final dir = await _getDir();
    return File('${dir.path}/$_sessionsFileName');
  }

  static Future<File> _getRecipeFile() async {
    final dir = await _getDir();
    return File('${dir.path}/$_recipeFileName');
  }

  static Future<List<CoffeeSession>> loadSessions() async {
    try {
      final file = await _getSessionsFile();
      if (!await file.exists()) return [];

      final text = await file.readAsString();
      if (text.trim().isEmpty) return [];

      final decoded = jsonDecode(text) as List;
      return decoded
          .map((e) => CoffeeSession.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveSessions(List<CoffeeSession> sessions) async {
    final file = await _getSessionsFile();
    final text = jsonEncode(sessions.map((e) => e.toJson()).toList());
    await file.writeAsString(text);
  }

  static Future<void> addSession(CoffeeSession session) async {
    final sessions = await loadSessions();
    sessions.insert(0, session);
    await saveSessions(sessions);
  }

  static Future<void> updateSession(CoffeeSession updated) async {
    final sessions = await loadSessions();
    final index = sessions.indexWhere((e) => e.id == updated.id);
    if (index != -1) {
      sessions[index] = updated;
      await saveSessions(sessions);
    }
  }

  static Future<void> deleteSession(String id) async {
    final sessions = await loadSessions();
    sessions.removeWhere((e) => e.id == id);
    await saveSessions(sessions);
  }

  static Future<BrewRecipe?> loadCurrentRecipe() async {
    try {
      final file = await _getRecipeFile();
      if (!await file.exists()) return null;

      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;

      final decoded = jsonDecode(text) as Map<String, dynamic>;
      final recipe = BrewRecipe.fromJson(decoded);
      return recipe.isEmpty ? null : recipe;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCurrentRecipe(BrewRecipe? recipe) async {
    final file = await _getRecipeFile();
    if (recipe == null || recipe.isEmpty) {
      await file.writeAsString('');
      return;
    }
    await file.writeAsString(jsonEncode(recipe.toJson()));
  }

  static Future<List<Map<String, String?>>> loadBeanPresets() async {
    final sessions = await loadSessions();
    final seen = <String>{};
    final presets = <Map<String, String?>>[];

    for (final session in sessions) {
      final beanName = session.beanName?.trim();
      final country = session.country?.trim();
      final regionFarm = session.regionFarm?.trim();
      final variety = session.variety?.trim();
      final process = session.process?.trim();
      final roastLevel = session.roastLevel?.trim();
      final grindSize = session.grindSize?.trim();
      final flavorNote = session.flavorNote?.trim();
      final elevationM =
      session.elevationM == null ? null : session.elevationM!.toStringAsFixed(0);
      final notes = session.notes?.trim();

      final hasAny = (beanName != null && beanName.isNotEmpty) ||
          (country != null && country.isNotEmpty) ||
          (regionFarm != null && regionFarm.isNotEmpty) ||
          (variety != null && variety.isNotEmpty) ||
          (process != null && process.isNotEmpty) ||
          (roastLevel != null && roastLevel.isNotEmpty) ||
          (grindSize != null && grindSize.isNotEmpty) ||
          (flavorNote != null && flavorNote.isNotEmpty) ||
          (elevationM != null && elevationM.isNotEmpty) ||
          (notes != null && notes.isNotEmpty);

      if (!hasAny) continue;

      final key = [
        beanName ?? '',
        country ?? '',
        regionFarm ?? '',
        variety ?? '',
        process ?? '',
        roastLevel ?? '',
        grindSize ?? '',
        flavorNote ?? '',
        elevationM ?? '',
        notes ?? '',
      ].join('||');

      if (seen.contains(key)) continue;
      seen.add(key);

      presets.add({
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
      });
    }

    return presets;
  }
}