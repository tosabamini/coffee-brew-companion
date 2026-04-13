import 'package:flutter/material.dart';

import '../models/brew_recipe.dart';
import '../models/coffee_session.dart';
import '../models/weight_point.dart';
import '../services/session_storage.dart';
import '../widgets/weight_graph.dart';

class SaveSessionScreen extends StatefulWidget {
  final List<WeightPoint> points;
  final BrewRecipe? recipe;

  const SaveSessionScreen({
    super.key,
    required this.points,
    this.recipe,
  });

  @override
  State<SaveSessionScreen> createState() => _SaveSessionScreenState();
}

class _SaveSessionScreenState extends State<SaveSessionScreen> {
  static const String _customValue = '__custom__';

  static const List<String> _countryOptions = [
    'Brazil',
    'Colombia',
    'Ethiopia',
    'Kenya',
    'Guatemala',
    'Costa Rica',
    'El Salvador',
    'Honduras',
    'Nicaragua',
    'Panama',
    'Peru',
    'Bolivia',
    'Mexico',
    'Rwanda',
    'Burundi',
    'Tanzania',
    'Uganda',
    'Indonesia',
    'Yemen',
    'Jamaica',
  ];

  static const List<String> _varietyOptions = [
    'Catuai',
    'Caturra',
    'SL28',
    'SL34',
    'Geisha',
    'Maragogipe',
    'Bourbon',
    'Typica',
    'Pacamara',
    'Castillo',
    'Catimor',
    'Mundo Novo',
    'Yellow Bourbon',
    'Pink Bourbon',
    'Heirloom',
  ];

  static const List<String> _processOptions = [
    'Natural',
    'Washed',
    'Honey',
    'Anaerobic',
    'Anaerobic Natural',
    'Anaerobic Washed',
    'Carbonic Maceration',
    'Semi-Washed',
    'Wet-Hulled',
    'Pulped Natural',
    'Experimental',
  ];

  static const List<String> _roastLevelOptions = [
    'Cinnamon Roast',
    'Light Roast',
    'Medium-Light Roast',
    'Medium Roast',
    'Medium-Dark Roast',
    'City Roast',
    'Full City Roast',
    'French Roast',
    'Italian Roast',
  ];

  final _beanController = TextEditingController();
  final _countryCustomController = TextEditingController();
  final _regionFarmController = TextEditingController();
  final _varietyCustomController = TextEditingController();
  final _processCustomController = TextEditingController();
  final _grindSizeController = TextEditingController();
  final _flavorNoteController = TextEditingController();
  final _elevationController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedCountry;
  String? _selectedVariety;
  String? _selectedProcess;
  String? _selectedRoastLevel;

  bool _isSaving = false;
  bool _useSavedPreset = false;
  List<Map<String, String?>> _beanPresets = [];
  int? _selectedPresetIndex;

  @override
  void initState() {
    super.initState();
    _loadPresets();
  }

  Future<void> _loadPresets() async {
    final presets = await SessionStorage.loadBeanPresets();
    if (!mounted) return;
    setState(() {
      _beanPresets = presets;
      if (_beanPresets.isEmpty) {
        _useSavedPreset = false;
      }
    });
  }

  @override
  void dispose() {
    _beanController.dispose();
    _countryCustomController.dispose();
    _regionFarmController.dispose();
    _varietyCustomController.dispose();
    _processCustomController.dispose();
    _grindSizeController.dispose();
    _flavorNoteController.dispose();
    _elevationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _normalizeDropdownValue(String? value, List<String> options) {
    if (value == null || value.trim().isEmpty) return _customValue;
    final match = options.where((e) => e.toLowerCase() == value.toLowerCase()).toList();
    if (match.isNotEmpty) return match.first;
    return _customValue;
  }

  String? _normalizeFixedDropdownValue(String? value, List<String> options) {
    if (value == null || value.trim().isEmpty) return null;
    final match = options.where((e) => e.toLowerCase() == value.toLowerCase()).toList();
    if (match.isNotEmpty) return match.first;
    return null;
  }

  void _applyPreset(int index) {
    final preset = _beanPresets[index];

    final country = preset['country'] ?? '';
    final variety = preset['variety'] ?? '';
    final process = preset['process'] ?? '';
    final roast = preset['roastLevel'] ?? '';

    setState(() {
      _selectedPresetIndex = index;

      _beanController.text = preset['beanName'] ?? '';
      _selectedCountry = _normalizeDropdownValue(country, _countryOptions);
      _countryCustomController.text =
      _selectedCountry == _customValue ? country : '';
      _regionFarmController.text = preset['regionFarm'] ?? '';

      _selectedVariety = _normalizeDropdownValue(variety, _varietyOptions);
      _varietyCustomController.text =
      _selectedVariety == _customValue ? variety : '';

      _selectedProcess = _normalizeDropdownValue(process, _processOptions);
      _processCustomController.text =
      _selectedProcess == _customValue ? process : '';

      _selectedRoastLevel = _normalizeFixedDropdownValue(roast, _roastLevelOptions);
      _grindSizeController.text = preset['grindSize'] ?? '';
      _flavorNoteController.text = preset['flavorNote'] ?? '';
      _elevationController.text = preset['elevationM'] ?? '';
      _notesController.text = preset['notes'] ?? '';
    });
  }

  String? _resolvedDropdownValue(String? selected, TextEditingController customController) {
    if (selected == null) return null;
    if (selected == _customValue) {
      final text = customController.text.trim();
      return text.isEmpty ? null : text;
    }
    return selected;
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
    });

    final elevationText = _elevationController.text.trim();
    final elevationValue =
    elevationText.isEmpty ? null : double.tryParse(elevationText);

    if (elevationText.isNotEmpty && elevationValue == null) {
      setState(() {
        _isSaving = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elevation must be numeric.')),
      );
      return;
    }

    final session = CoffeeSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      beanName: _beanController.text.trim().isEmpty ? null : _beanController.text.trim(),
      country: _resolvedDropdownValue(_selectedCountry, _countryCustomController),
      regionFarm: _regionFarmController.text.trim().isEmpty
          ? null
          : _regionFarmController.text.trim(),
      variety: _resolvedDropdownValue(_selectedVariety, _varietyCustomController),
      process: _resolvedDropdownValue(_selectedProcess, _processCustomController),
      roastLevel: _selectedRoastLevel,
      grindSize: _grindSizeController.text.trim().isEmpty
          ? null
          : _grindSizeController.text.trim(),
      flavorNote: _flavorNoteController.text.trim().isEmpty
          ? null
          : _flavorNoteController.text.trim(),
      elevationM: elevationValue,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      recipe: widget.recipe?.copy(),
      points: widget.points,
    );

    await SessionStorage.addSession(session);

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _discard() {
    Navigator.pop(context, false);
  }

  String _formatRecipeSummary() {
    if (widget.recipe == null || widget.recipe!.isEmpty) {
      return 'No recipe attached';
    }

    final recipe = widget.recipe!;
    final name = (recipe.name == null || recipe.name!.isEmpty)
        ? 'Unnamed recipe'
        : recipe.name!;
    final endText = recipe.targetEndSec == null ? '-' : _formatSec(recipe.targetEndSec!);

    return '$name | ${recipe.steps.length} pours | end $endText';
  }

  String _formatSec(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _presetLabel(Map<String, String?> preset) {
    final bean = (preset['beanName'] == null || preset['beanName']!.isEmpty)
        ? 'Unnamed Bean'
        : preset['beanName']!;
    final country =
    (preset['country'] == null || preset['country']!.isEmpty) ? '-' : preset['country']!;
    final variety =
    (preset['variety'] == null || preset['variety']!.isEmpty) ? '-' : preset['variety']!;
    final process =
    (preset['process'] == null || preset['process']!.isEmpty) ? '-' : preset['process']!;
    return '$bean | $country | $variety | $process';
  }

  Widget _buildDropdownWithCustom({
    required String label,
    required List<String> options,
    required String? selectedValue,
    required ValueChanged<String?> onChanged,
    required TextEditingController customController,
    required String customLabel,
  }) {
    final dropdownItems = [
      ...options,
      'Other',
    ];

    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: selectedValue,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          items: dropdownItems
              .map(
                (e) => DropdownMenuItem<String>(
              value: e == 'Other' ? _customValue : e,
              child: Text(e),
            ),
          )
              .toList(),
          onChanged: onChanged,
        ),
        if (selectedValue == _customValue) ...[
          const SizedBox(height: 12),
          TextField(
            controller: customController,
            decoration: InputDecoration(
              labelText: customLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final finalWeight = widget.points.isEmpty ? 0.0 : widget.points.last.weightG;
    final durationSec = widget.points.isEmpty ? 0.0 : widget.points.last.elapsedMs / 1000.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Save Session'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 240,
                  child: WeightGraph(
                    points: widget.points,
                    recipe: widget.recipe,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Duration: ${durationSec.toStringAsFixed(1)} s')),
                        Expanded(child: Text('Final Weight: ${finalWeight.toStringAsFixed(1)} g')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Recipe: ${_formatRecipeSummary()}'),
                    ),
                    const SizedBox(height: 16),

                    if (_beanPresets.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              label: Text('New Input'),
                              icon: Icon(Icons.edit),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              label: Text('Use Saved Bean Info'),
                              icon: Icon(Icons.history),
                            ),
                          ],
                          selected: {_useSavedPreset},
                          onSelectionChanged: (selection) {
                            setState(() {
                              _useSavedPreset = selection.first;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (_useSavedPreset && _beanPresets.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        value: _selectedPresetIndex,
                        decoration: const InputDecoration(
                          labelText: 'Saved Bean Info',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(
                          _beanPresets.length,
                              (index) => DropdownMenuItem<int>(
                            value: index,
                            child: Text(_presetLabel(_beanPresets[index])),
                          ),
                        ),
                        onChanged: (value) {
                          if (value == null) return;
                          _applyPreset(value);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    TextField(
                      controller: _beanController,
                      decoration: const InputDecoration(
                        labelText: 'Bean Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildDropdownWithCustom(
                      label: 'Country',
                      options: _countryOptions,
                      selectedValue: _selectedCountry,
                      onChanged: (value) {
                        setState(() {
                          _selectedCountry = value;
                        });
                      },
                      customController: _countryCustomController,
                      customLabel: 'Custom Country',
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _regionFarmController,
                      decoration: const InputDecoration(
                        labelText: 'Region / Farm',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildDropdownWithCustom(
                      label: 'Variety',
                      options: _varietyOptions,
                      selectedValue: _selectedVariety,
                      onChanged: (value) {
                        setState(() {
                          _selectedVariety = value;
                        });
                      },
                      customController: _varietyCustomController,
                      customLabel: 'Custom Variety',
                    ),
                    const SizedBox(height: 12),

                    _buildDropdownWithCustom(
                      label: 'Process',
                      options: _processOptions,
                      selectedValue: _selectedProcess,
                      onChanged: (value) {
                        setState(() {
                          _selectedProcess = value;
                        });
                      },
                      customController: _processCustomController,
                      customLabel: 'Custom Process',
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<String>(
                      value: _selectedRoastLevel,
                      decoration: const InputDecoration(
                        labelText: 'Roast Level',
                        border: OutlineInputBorder(),
                      ),
                      items: _roastLevelOptions
                          .map(
                            (e) => DropdownMenuItem<String>(
                          value: e,
                          child: Text(e),
                        ),
                      )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedRoastLevel = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _grindSizeController,
                      decoration: const InputDecoration(
                        labelText: 'Grind Size',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _flavorNoteController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Flavor Note',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _elevationController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Elevation (m)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
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
                  label: Text(_isSaving ? 'Saving...' : 'Save'),
                ),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _discard,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Do Not Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}