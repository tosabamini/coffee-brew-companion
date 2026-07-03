import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../features/shared/models/flavor_note_tag.dart';
import '../../../features/shared/widgets/flavor_note_selector.dart';
import '../models/brew_recipe.dart';
import '../models/coffee_session.dart';
import '../models/weight_point.dart';
import '../services/claude_vision_service.dart';
import '../services/session_storage.dart';
import '../widgets/weight_graph.dart';

class SaveSessionScreen extends StatefulWidget {
  final List<WeightPoint> points;
  final BrewRecipe? recipe;

  /// 計測時の豆量（ドース初期値）。メイン画面の豆量計測・レシピ由来
  final double? initialDoseG;

  const SaveSessionScreen({
    super.key,
    required this.points,
    this.recipe,
    this.initialDoseG,
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
  final _elevationController = TextEditingController();
  final _notesController = TextEditingController();
  final _doseController = TextEditingController();
  final _tdsController = TextEditingController();

  String? _selectedCountry;
  String? _selectedVariety;
  String? _selectedProcess;
  String? _selectedRoastLevel;

  List<FlavorNoteTag> _selectedFlavorNotes = [];

  bool _isSaving = false;
  bool _isScanning = false;
  bool _useSavedPreset = false;
  List<Map<String, String?>> _beanPresets = [];
  int? _selectedPresetIndex;

  bool get _isStandalone => widget.points.isEmpty;

  @override
  void initState() {
    super.initState();
    _loadPresets();
    final initialDose = widget.initialDoseG ?? widget.recipe?.beanQuantityG;
    if (initialDose != null && initialDose > 0) {
      _doseController.text = initialDose.toStringAsFixed(1);
    }
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
    _elevationController.dispose();
    _notesController.dispose();
    _doseController.dispose();
    _tdsController.dispose();
    super.dispose();
  }

  String _normalizeDropdownValue(String? value, List<String> options) {
    if (value == null || value.trim().isEmpty) return _customValue;
    final match =
        options.where((e) => e.toLowerCase() == value.toLowerCase()).toList();
    if (match.isNotEmpty) return match.first;
    return _customValue;
  }

  String? _normalizeFixedDropdownValue(String? value, List<String> options) {
    if (value == null || value.trim().isEmpty) return null;
    final match =
        options.where((e) => e.toLowerCase() == value.toLowerCase()).toList();
    if (match.isNotEmpty) return match.first;
    return null;
  }

  void _applyPreset(int index) {
    final preset = _beanPresets[index];

    final country = preset['country'] ?? '';
    final variety = preset['variety'] ?? '';
    final process = preset['process'] ?? '';
    final roast = preset['roastLevel'] ?? '';

    // 旧形式の flavorNote をタグに変換
    final oldNote = preset['flavorNote'] ?? '';
    final tags = oldNote.isEmpty
        ? <FlavorNoteTag>[]
        : oldNote
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => FlavorNoteTag(name: s, isCustom: true))
            .toList();

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

      _selectedRoastLevel =
          _normalizeFixedDropdownValue(roast, _roastLevelOptions);
      _grindSizeController.text = preset['grindSize'] ?? '';
      _selectedFlavorNotes = tags;
      _elevationController.text = preset['elevationM'] ?? '';
      _notesController.text = preset['notes'] ?? '';
    });
  }

  /// パッケージ写真を撮影 or 選択して Claude Vision API で解析し、フォームに反映する
  Future<void> _scanPackage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('カメラで撮影'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('ライブラリから選択'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (picked == null || !mounted) return;

    setState(() => _isScanning = true);

    try {
      final info = await ClaudeVisionService.analyzeCoffeePackage(File(picked.path));
      if (!mounted) return;
      _applyPackageInfo(info);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('パッケージ情報を読み取りました。内容を確認して修正してください。')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('読み取りに失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  /// Vision API の結果をフォームフィールドに反映する
  void _applyPackageInfo(CoffeePackageInfo info) {
    setState(() {
      if (info.beanName != null) _beanController.text = info.beanName!;

      if (info.country != null) {
        _selectedCountry = _normalizeDropdownValue(info.country, _countryOptions);
        _countryCustomController.text =
            _selectedCountry == _customValue ? info.country! : '';
      }

      if (info.regionFarm != null) _regionFarmController.text = info.regionFarm!;

      if (info.variety != null) {
        _selectedVariety = _normalizeDropdownValue(info.variety, _varietyOptions);
        _varietyCustomController.text =
            _selectedVariety == _customValue ? info.variety! : '';
      }

      if (info.process != null) {
        _selectedProcess = _normalizeDropdownValue(info.process, _processOptions);
        _processCustomController.text =
            _selectedProcess == _customValue ? info.process! : '';
      }

      if (info.roastLevel != null) {
        _selectedRoastLevel =
            _normalizeFixedDropdownValue(info.roastLevel, _roastLevelOptions);
      }

      if (info.elevation != null) _elevationController.text = info.elevation!;

      if (info.flavorNotes.isNotEmpty) {
        _selectedFlavorNotes = info.flavorNotes
            .map((name) => FlavorNoteTag(name: name, isCustom: true))
            .toList();
      }

      if (info.notes != null) _notesController.text = info.notes!;
    });
  }

  String? _resolvedDropdownValue(
      String? selected, TextEditingController customController) {
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

    final doseText = _doseController.text.trim();
    final doseValue = doseText.isEmpty ? null : double.tryParse(doseText);
    final tdsText = _tdsController.text.trim();
    final tdsValue = tdsText.isEmpty ? null : double.tryParse(tdsText);

    if ((doseText.isNotEmpty && doseValue == null) ||
        (tdsText.isNotEmpty && tdsValue == null)) {
      setState(() {
        _isSaving = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('豆量とTDSは数値で入力してください。')),
      );
      return;
    }

    // flavorNote は backward compat のためにタグ名を","結合で保持
    final flavorNoteString = _selectedFlavorNotes.isEmpty
        ? null
        : _selectedFlavorNotes.map((t) => t.name).join(', ');

    final session = CoffeeSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      beanName: _beanController.text.trim().isEmpty
          ? null
          : _beanController.text.trim(),
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
      flavorNote: flavorNoteString,
      flavorNotes: _selectedFlavorNotes,
      elevationM: elevationValue,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      doseG: doseValue,
      tdsPercent: tdsValue,
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
    final endText =
        recipe.targetEndSec == null ? '-' : _formatSec(recipe.targetEndSec!);

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
        (preset['country'] == null || preset['country']!.isEmpty)
            ? '-'
            : preset['country']!;
    final variety =
        (preset['variety'] == null || preset['variety']!.isEmpty)
            ? '-'
            : preset['variety']!;
    final process =
        (preset['process'] == null || preset['process']!.isEmpty)
            ? '-'
            : preset['process']!;
    return '$bean | $country | $variety | $process';
  }

  /// 入力中の豆量・TDSから レシオ / 収率(EY) をライブ計算して表示
  Widget _buildBrewMetricsPreview(double finalWeight) {
    final dose = double.tryParse(_doseController.text.trim());
    final tds = double.tryParse(_tdsController.text.trim());

    String ratioText = '—';
    String eyText = '—';
    if (dose != null && dose > 0 && finalWeight > 0) {
      ratioText = '1:${(finalWeight / dose).toStringAsFixed(1)}';
      if (tds != null && tds > 0) {
        final beverage =
            finalWeight - dose * CoffeeSession.liquidRetainedRatio;
        if (beverage > 0) {
          eyText = '${(tds * beverage / dose).toStringAsFixed(1)} %';
        }
      }
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'ブリューレシオ: $ratioText   抽出収率 (EY): $eyText',
        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
      ),
    );
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
    final finalWeight =
        widget.points.isEmpty ? 0.0 : widget.points.last.weightG;
    final durationSec = widget.points.isEmpty
        ? 0.0
        : widget.points.last.elapsedMs / 1000.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isStandalone ? 'Bean Info' : 'Save Session'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ブリューデータがある場合のみグラフを表示
            if (!_isStandalone) ...[
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
            ],

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (!_isStandalone) ...[
                      Row(
                        children: [
                          Expanded(
                              child: Text(
                                  'Duration: ${durationSec.toStringAsFixed(1)} s')),
                          Expanded(
                              child: Text(
                                  'Final Weight: ${finalWeight.toStringAsFixed(1)} g')),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child:
                            Text('Recipe: ${_formatRecipeSummary()}'),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _doseController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: '豆量 / Dose (g)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _tdsController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'TDS (%)',
                                border: OutlineInputBorder(),
                                helperText: '屈折計の測定値（任意）',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildBrewMetricsPreview(finalWeight),
                      const SizedBox(height: 16),
                    ],

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

                    // パッケージ写真スキャンボタン
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed: _isScanning ? null : _scanPackage,
                        icon: _isScanning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.camera_alt),
                        label: Text(_isScanning ? '解析中...' : 'パッケージ写真から自動入力'),
                      ),
                    ),
                    const SizedBox(height: 12),

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

                    // Flavor Notes（複数選択）
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Flavor Notes',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FlavorNoteSelector(
                      selected: _selectedFlavorNotes,
                      onChanged: (tags) =>
                          setState(() => _selectedFlavorNotes = tags),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: _elevationController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
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
