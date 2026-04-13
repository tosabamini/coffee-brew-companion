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

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _startTimeControllers[0].text = '0:00';
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _beanQuantityController.dispose();
    _targetEndController.dispose();
    for (final c in _startTimeControllers) {
      c.dispose();
    }
    for (final c in _targetGControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final recipe = await SessionStorage.loadCurrentRecipe();
    if (recipe == null) return;

    _nameController.text = recipe.name ?? '';
    _beanQuantityController.text =
    recipe.beanQuantityG == null ? '' : recipe.beanQuantityG!.toStringAsFixed(0);
    _targetEndController.text =
    recipe.targetEndSec == null ? '' : _formatSec(recipe.targetEndSec!);

    for (int i = 0; i < recipe.steps.length && i < 6; i++) {
      if (i == 0) {
        _startTimeControllers[i].text = '0:00';
      } else {
        _startTimeControllers[i].text = _formatSec(recipe.steps[i].startSec);
      }
      _targetGControllers[i].text = recipe.steps[i].targetTotalG.toStringAsFixed(0);
    }

    if (_startTimeControllers[0].text.trim().isEmpty) {
      _startTimeControllers[0].text = '0:00';
    }

    if (mounted) {
      setState(() {});
    }
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
      case 0:
        return 'Blooming';
      case 1:
        return 'The 2nd Pour';
      case 2:
        return 'The 3rd Pour';
      case 3:
        return 'The 4th Pour';
      case 4:
        return 'The 5th Pour';
      case 5:
        return 'The 6th Pour';
      default:
        return 'Step ${index + 1}';
    }
  }

  Future<void> _save() async {
    final steps = <PourStep>[];

    final beanQuantityText = _beanQuantityController.text.trim();
    final beanQuantityG =
    beanQuantityText.isEmpty ? null : double.tryParse(beanQuantityText);

    if (beanQuantityText.isNotEmpty &&
        (beanQuantityG == null || beanQuantityG <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bean Quantity must be a positive number.')),
      );
      return;
    }

    for (int i = 0; i < 6; i++) {
      final startText = i == 0 ? '0:00' : _startTimeControllers[i].text.trim();
      final targetText = _targetGControllers[i].text.trim();

      if (i == 0) {
        if (targetText.isEmpty) {
          continue;
        }

        final targetG = double.tryParse(targetText);
        if (targetG == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Blooming target weight must be numeric.'),
            ),
          );
          return;
        }

        steps.add(
          PourStep(
            stepNumber: 1,
            startSec: 0,
            targetTotalG: targetG,
          ),
        );
        continue;
      }

      if (startText.isEmpty && targetText.isEmpty) {
        continue;
      }

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

      steps.add(
        PourStep(
          stepNumber: i + 1,
          startSec: startSec,
          targetTotalG: targetG,
        ),
      );
    }

    final targetEndText = _targetEndController.text.trim();
    final targetEndSec = targetEndText.isEmpty ? null : _parseMmSs(targetEndText);

    if (targetEndText.isNotEmpty && targetEndSec == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target end time must be MM:SS.')),
      );
      return;
    }

    final recipe = BrewRecipe(
      name: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      beanQuantityG: beanQuantityG,
      targetEndSec: targetEndSec,
      steps: steps,
    );

    setState(() {
      _isSaving = true;
    });

    await SessionStorage.saveCurrentRecipe(recipe.isEmpty ? null : recipe);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _clearRecipe() async {
    await SessionStorage.saveCurrentRecipe(null);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    _startTimeControllers[0].text = '0:00';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipe Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Optional target recipe',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Recipe Name (optional)',
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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
                  label: const Text('Save Recipe'),
                ),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _clearRecipe,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear Recipe'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}