import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';

import '../models/brew_recipe.dart';
import '../models/coffee_session.dart';
import '../services/session_storage.dart';
import '../widgets/weight_graph.dart';

class SessionDetailScreen extends StatefulWidget {
  final String sessionId;

  const SessionDetailScreen({
    super.key,
    required this.sessionId,
  });

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  CoffeeSession? _session;
  bool _isLoading = true;
  bool _isExporting = false;

  final _beanController = TextEditingController();
  final _countryController = TextEditingController();
  final _regionFarmController = TextEditingController();
  final _varietyController = TextEditingController();
  final _processController = TextEditingController();
  final _roastController = TextEditingController();
  final _grindSizeController = TextEditingController();
  final _flavorNoteController = TextEditingController();
  final _elevationController = TextEditingController();
  final _notesController = TextEditingController();

  final GlobalKey _exportKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _beanController.dispose();
    _countryController.dispose();
    _regionFarmController.dispose();
    _varietyController.dispose();
    _processController.dispose();
    _roastController.dispose();
    _grindSizeController.dispose();
    _flavorNoteController.dispose();
    _elevationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sessions = await SessionStorage.loadSessions();
    final session = sessions.where((e) => e.id == widget.sessionId).firstOrNull;

    if (session != null) {
      _beanController.text = session.beanName ?? '';
      _countryController.text = session.country ?? '';
      _regionFarmController.text = session.regionFarm ?? '';
      _varietyController.text = session.variety ?? '';
      _processController.text = session.process ?? '';
      _roastController.text = session.roastLevel ?? '';
      _grindSizeController.text = session.grindSize ?? '';
      _flavorNoteController.text = session.flavorNote ?? '';
      _elevationController.text =
      session.elevationM == null ? '' : session.elevationM!.toStringAsFixed(0);
      _notesController.text = session.notes ?? '';
    }

    setState(() {
      _session = session;
      _isLoading = false;
    });
  }

  Future<void> _saveEdits() async {
    if (_session == null) return;

    final elevationText = _elevationController.text.trim();
    final elevationValue =
    elevationText.isEmpty ? null : double.tryParse(elevationText);

    if (elevationText.isNotEmpty && elevationValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elevation must be numeric.')),
      );
      return;
    }

    _session!
      ..beanName = _beanController.text.trim().isEmpty ? null : _beanController.text.trim()
      ..country = _countryController.text.trim().isEmpty ? null : _countryController.text.trim()
      ..regionFarm = _regionFarmController.text.trim().isEmpty
          ? null
          : _regionFarmController.text.trim()
      ..variety = _varietyController.text.trim().isEmpty ? null : _varietyController.text.trim()
      ..process = _processController.text.trim().isEmpty ? null : _processController.text.trim()
      ..roastLevel = _roastController.text.trim().isEmpty ? null : _roastController.text.trim()
      ..grindSize = _grindSizeController.text.trim().isEmpty
          ? null
          : _grindSizeController.text.trim()
      ..flavorNote = _flavorNoteController.text.trim().isEmpty
          ? null
          : _flavorNoteController.text.trim()
      ..elevationM = elevationValue
      ..notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();

    await SessionStorage.updateSession(_session!);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session updated')),
    );
    setState(() {});
  }

  Future<void> _exportAsImage() async {
    if (_session == null || _isExporting) return;

    setState(() {
      _isExporting = true;
    });

    try {
      await Future.delayed(const Duration(milliseconds: 100));
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
      _exportKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      if (boundary.debugNeedsPaint) {
        await Future.delayed(const Duration(milliseconds: 100));
        await WidgetsBinding.instance.endOfFrame;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('Failed to convert image');
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/session_${_session!.id}.png');
      await file.writeAsBytes(pngBytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image exported:\n${file.path}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatSec(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildRecipeSummary(BrewRecipe? recipe) {
    if (recipe == null || recipe.isEmpty) {
      return const Text('Recipe: none');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recipe name: ${recipe.name ?? "-"}'),
        Text('Bean quantity: ${recipe.beanQuantityG?.toStringAsFixed(0) ?? "-"} g'),
        Text(
          'Target end: ${recipe.targetEndSec == null ? "-" : _formatSec(recipe.targetEndSec!)}',
        ),
        const SizedBox(height: 6),
        ...recipe.steps.map(
              (step) => Text(
            'P${step.stepNumber}: ${_formatSec(step.startSec)} / ${step.targetTotalG.toStringAsFixed(0)} g',
          ),
        ),
      ],
    );
  }

  Widget _buildExportCard(CoffeeSession session) {
    return RepaintBoundary(
      key: _exportKey,
      child: Material(
        color: Colors.white,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          width: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Coffee Extraction Session',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              Text('Saved at: ${_formatDate(session.createdAt)}'),
              Text('Bean: ${session.beanName ?? "-"}'),
              Text('Country: ${session.country ?? "-"}'),
              Text('Region / Farm: ${session.regionFarm ?? "-"}'),
              Text('Variety: ${session.variety ?? "-"}'),
              Text('Process: ${session.process ?? "-"}'),
              Text('Roast Level: ${session.roastLevel ?? "-"}'),
              Text('Grind Size: ${session.grindSize ?? "-"}'),
              Text('Flavor Note: ${session.flavorNote ?? "-"}'),
              Text(
                'Elevation: ${session.elevationM == null ? "-" : "${session.elevationM!.toStringAsFixed(0)} m"}',
              ),
              Text('Duration: ${session.durationSec.toStringAsFixed(1)} s'),
              Text('Max Weight: ${session.maxWeight.toStringAsFixed(1)} g'),
              const SizedBox(height: 8),
              Text('Notes: ${session.notes ?? "-"}'),
              const SizedBox(height: 16),
              const Text(
                'Recipe',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildRecipeSummary(session.recipe),
              const SizedBox(height: 16),
              SizedBox(
                height: 420,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: WeightGraph(
                      points: session.points,
                      recipe: session.recipe,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session Detail')),
        body: const Center(child: Text('Session not found')),
      );
    }

    final session = _session!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Detail'),
        actions: [
          IconButton(
            onPressed: _isExporting ? null : _exportAsImage,
            icon: const Icon(Icons.image),
            tooltip: 'Export Image',
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SizedBox(
                      height: 260,
                      child: WeightGraph(
                        points: session.points,
                        recipe: session.recipe,
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
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Saved: ${_formatDate(session.createdAt)}'),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Duration: ${session.durationSec.toStringAsFixed(1)} s',
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Max Weight: ${session.maxWeight.toStringAsFixed(1)} g',
                              ),
                            ),
                          ],
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
                        TextField(
                          controller: _countryController,
                          decoration: const InputDecoration(
                            labelText: 'Country',
                            border: OutlineInputBorder(),
                          ),
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
                        TextField(
                          controller: _varietyController,
                          decoration: const InputDecoration(
                            labelText: 'Variety',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _processController,
                          decoration: const InputDecoration(
                            labelText: 'Process',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _roastController,
                          decoration: const InputDecoration(
                            labelText: 'Roast Level',
                            border: OutlineInputBorder(),
                          ),
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
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Notes',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Recipe Summary',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _buildRecipeSummary(session.recipe),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton.icon(
                              onPressed: _saveEdits,
                              icon: const Icon(Icons.save),
                              label: const Text('Update Info'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _isExporting ? null : _exportAsImage,
                              icon: const Icon(Icons.image),
                              label: Text(
                                _isExporting ? 'Exporting...' : 'Export Image',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.0,
                child: _buildExportCard(session),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension FirstOrNullExtension<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}