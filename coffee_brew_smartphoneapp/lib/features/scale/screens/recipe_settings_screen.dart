import 'package:flutter/material.dart';

import '../models/brew_recipe.dart';
import '../models/pour_step.dart';
import '../services/session_storage.dart';

class RecipeSettingsScreen extends StatefulWidget {
  const RecipeSettingsScreen({super.key});

  @override
  State<RecipeSettingsScreen> createState() => _RecipeSettingsScreenState();
}

class _RecipeSettingsScreenState extends State<RecipeSettingsScreen> {
  final _nameController = TextEditingController();
  final _beanQuantityController = TextEditingController();
  final _targetEndController = TextEditingController();

  final List<TextEditingController> _startTimeControllers =
      List.generate(6, (_) => TextEditingController());
  final List<TextEditingController> _targetGControllers =
      List.generate(6, (_) => TextEditingController());

  List<BrewRecipe> _recipes = [];
  String? _editingId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _startTimeControllers[0].text = '0:00';
    _loadAll();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _beanQuantityController.dispose();
    _targetEndController.dispose();
    for (final c in _startTimeControllers) c.dispose();
    for (final c in _targetGControllers) c.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final recipes = await SessionStorage.loadRecipes();
    final currentId = await SessionStorage.loadCurrentRecipeId();
    if (!mounted) return;
    setState(() {
      _recipes = recipes;
    });
    if (currentId != null) {
      try {
        final current = recipes.firstWhere((r) => r.id == currentId);
        _loadIntoForm(current);
      } catch (_) {}
    }
  }

  void _loadIntoForm(BrewRecipe recipe) {
    setState(() {
      _editingId = recipe.id;
      _nameController.text = recipe.name ?? '';
      _beanQuantityController.text =
          recipe.beanQuantityG == null ? '' : recipe.beanQuantityG!.toStringAsFixed(0);
      _targetEndController.text =
          recipe.targetEndSec == null ? '' : _formatSec(recipe.targetEndSec!);
      for (int i = 0; i < 6; i++) {
        _startTimeControllers[i].text = i == 0 ? '0:00' : '';
        _targetGControllers[i].text = '';
      }
      for (int i = 0; i < recipe.steps.length && i < 6; i++) {
        if (i != 0) {
          _startTimeControllers[i].text = _formatSec(recipe.steps[i].startSec);
        }
        _targetGControllers[i].text = recipe.steps[i].targetTotalG.toStringAsFixed(0);
      }
    });
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _nameController.clear();
      _beanQuantityController.clear();
      _targetEndController.clear();
      for (int i = 0; i < 6; i++) {
        _startTimeControllers[i].text = i == 0 ? '0:00' : '';
        _targetGControllers[i].text = '';
      }
    });
  }

  String _formatSec(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  int? _parseMmSs(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length != 2) return null;
    final mm = int.tryParse(parts[0]);
    final ss = int.tryParse(parts[1]);
    if (mm == null || ss == null) return null;
    if (mm < 0 || ss < 0 || ss >= 60) return null;
    return mm * 60 + ss;
  }

  String _stepTitle(int index) {
    switch (index) {
      case 0: return 'Blooming';
      case 1: return 'The 2nd Pour';
      case 2: return 'The 3rd Pour';
      case 3: return 'The 4th Pour';
      case 4: return 'The 5th Pour';
      case 5: return 'The 6th Pour';
      default: return 'Step ${index + 1}';
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('レシピ名を入力してください。')),
      );
      return;
    }

    final steps = <PourStep>[];
    final beanQuantityText = _beanQuantityController.text.trim();
    final beanQuantityG =
        beanQuantityText.isEmpty ? null : double.tryParse(beanQuantityText);

    if (beanQuantityText.isNotEmpty && (beanQuantityG == null || beanQuantityG <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bean Quantity must be a positive number.')),
      );
      return;
    }

    for (int i = 0; i < 6; i++) {
      final startText = i == 0 ? '0:00' : _startTimeControllers[i].text.trim();
      final targetText = _targetGControllers[i].text.trim();

      if (i == 0) {
        if (targetText.isEmpty) continue;
        final targetG = double.tryParse(targetText);
        if (targetG == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Blooming target weight must be numeric.')),
          );
          return;
        }
        steps.add(PourStep(stepNumber: 1, startSec: 0, targetTotalG: targetG));
        continue;
      }

      if (startText.isEmpty && targetText.isEmpty) continue;

      if (startText.isEmpty || targetText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_stepTitle(i)} needs both time and weight.')),
        );
        return;
      }

      final startSec = _parseMmSs(startText);
      final targetG = double.tryParse(targetText);

      if (startSec == null || targetG == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_stepTitle(i)} is invalid. Time must be MM:SS and weight must be numeric.',
            ),
          ),
        );
        return;
      }

      steps.add(PourStep(stepNumber: i + 1, startSec: startSec, targetTotalG: targetG));
    }

    final targetEndText = _targetEndController.text.trim();
    final targetEndSec = targetEndText.isEmpty ? null : _parseMmSs(targetEndText);

    if (targetEndText.isNotEmpty && targetEndSec == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target end time must be MM:SS.')),
      );
      return;
    }

    final id = _editingId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final recipe = BrewRecipe(
      id: id,
      name: name,
      beanQuantityG: beanQuantityG,
      targetEndSec: targetEndSec,
      steps: steps,
    );

    setState(() => _isSaving = true);

    final recipes = List<BrewRecipe>.from(_recipes);
    final existingIndex = recipes.indexWhere((r) => r.id == id);
    if (existingIndex != -1) {
      recipes[existingIndex] = recipe;
    } else {
      recipes.add(recipe);
    }

    await SessionStorage.saveRecipes(recipes);
    await SessionStorage.saveCurrentRecipeId(id);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _deleteRecipe(BrewRecipe recipe) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('レシピを削除'),
        content: Text('「${recipe.name ?? '無題'}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final recipes = List<BrewRecipe>.from(_recipes)
      ..removeWhere((r) => r.id == recipe.id);
    await SessionStorage.saveRecipes(recipes);

    final currentId = await SessionStorage.loadCurrentRecipeId();
    if (currentId == recipe.id) {
      await SessionStorage.saveCurrentRecipeId(null);
    }

    setState(() {
      _recipes = recipes;
      if (_editingId == recipe.id) _clearForm();
    });
  }

  @override
  Widget build(BuildContext context) {
    _startTimeControllers[0].text = '0:00';

    final editingName = _nameController.text.trim();

    return Scaffold(
      appBar: AppBar(title: const Text('Recipe Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 保存済みレシピ一覧
            if (_recipes.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '保存済みレシピ',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      for (final r in _recipes)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(r.name ?? '無題'),
                          selected: _editingId == r.id,
                          selectedColor: Theme.of(context).colorScheme.primary,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton(
                                onPressed: () => _loadIntoForm(r),
                                child: const Text('編集'),
                              ),
                              TextButton(
                                onPressed: () => _deleteRecipe(r),
                                style: TextButton.styleFrom(
                                    foregroundColor:
                                        Theme.of(context).colorScheme.error),
                                child: const Text('削除'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_recipes.isNotEmpty) const SizedBox(height: 12),

            // フォーム
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _editingId == null
                          ? '新規レシピ'
                          : '編集中: ${editingName.isEmpty ? '...' : editingName}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'レシピ名 (必須)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _beanQuantityController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Bean Quantity (g, optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Pour steps (max 6)\nExample: Blooming = 0:00 / 60 g, 2nd Pour = 0:45 / 120 g',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Pour steps
            for (int i = 0; i < 6; i++)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _stepTitle(i),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _startTimeControllers[i],
                        enabled: i != 0,
                        decoration: InputDecoration(
                          labelText: i == 0 ? 'Start Time (fixed at 0:00)' : 'Start Time (MM:SS)',
                          hintText: i == 0 ? '0:00' : '01:30',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _targetGControllers[i],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Target Total Weight (g)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Target end time
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _targetEndController,
                  decoration: const InputDecoration(
                    labelText: 'Target End Time (MM:SS, optional)',
                    hintText: '03:45',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: const Text('保存'),
                ),
                if (_editingId != null)
                  OutlinedButton.icon(
                    onPressed: _clearForm,
                    icon: const Icon(Icons.add),
                    label: const Text('新規作成'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
