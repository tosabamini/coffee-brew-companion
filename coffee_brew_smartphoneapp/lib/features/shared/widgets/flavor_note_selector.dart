import 'package:flutter/material.dart';

import '../../flavor_wheel/models/flavor_category.dart';
import '../../flavor_wheel/services/flavor_storage.dart';
import '../models/flavor_note_tag.dart';

/// Bean Info 画面に埋め込む複数選択フレーバーノート入力ウィジェット。
/// 選択済みタグをチップ表示し、ボタンでピッカーを開く。
class FlavorNoteSelector extends StatefulWidget {
  final List<FlavorNoteTag> selected;
  final ValueChanged<List<FlavorNoteTag>> onChanged;

  const FlavorNoteSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<FlavorNoteSelector> createState() => _FlavorNoteSelectorState();
}

class _FlavorNoteSelectorState extends State<FlavorNoteSelector> {
  List<FlavorCategory> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    final cats = await FlavorStorage.loadCategories();
    if (mounted) setState(() => _categories = cats);
  }

  Color _tagColor(FlavorNoteTag tag) {
    if (tag.categoryColorValue != null) return Color(tag.categoryColorValue!);
    return Colors.grey;
  }

  Future<void> _openPicker() async {
    final result = await showModalBottomSheet<List<FlavorNoteTag>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.80,
        child: _FlavorPickerSheet(
          initialSelected: widget.selected,
          initialCategories: _categories,
        ),
      ),
    );

    if (result != null) {
      widget.onChanged(result);
      // カスタムフレーバーが追加された可能性があるため再ロード
      await _loadCategories();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.selected.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: widget.selected.map((tag) {
              final color = _tagColor(tag);
              return InputChip(
                label: Text(tag.name, style: const TextStyle(fontSize: 12)),
                backgroundColor: color.withValues(alpha: 0.18),
                side: BorderSide(color: color.withValues(alpha: 0.6)),
                onDeleted: () {
                  final updated =
                      widget.selected.where((t) => t.name != tag.name).toList();
                  widget.onChanged(updated);
                },
                deleteIconColor: color,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: _openPicker,
          icon: const Icon(Icons.local_florist_outlined, size: 18),
          label: Text(
            widget.selected.isEmpty ? 'Add Flavor Notes' : 'Edit Flavor Notes',
          ),
        ),
      ],
    );
  }
}

// ── Picker Sheet ─────────────────────────────────────────────────────────

class _FlavorPickerSheet extends StatefulWidget {
  final List<FlavorNoteTag> initialSelected;
  final List<FlavorCategory> initialCategories;

  const _FlavorPickerSheet({
    required this.initialSelected,
    required this.initialCategories,
  });

  @override
  State<_FlavorPickerSheet> createState() => _FlavorPickerSheetState();
}

class _FlavorPickerSheetState extends State<_FlavorPickerSheet> {
  late List<FlavorNoteTag> _selected;
  late List<FlavorCategory> _categories;
  List<String> _uncategorized = [];

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.initialSelected);
    _categories = widget.initialCategories;
    _loadUncategorized();
  }

  Future<void> _loadUncategorized() async {
    final list = await FlavorStorage.loadUncategorized();
    if (mounted) setState(() => _uncategorized = list);
  }

  bool _isSelected(String name) => _selected.any((t) => t.name == name);

  void _toggle(String name, Color color, String? categoryName) {
    setState(() {
      if (_isSelected(name)) {
        _selected.removeWhere((t) => t.name == name);
      } else {
        _selected.add(FlavorNoteTag(
          name: name,
          categoryName: categoryName,
          categoryColorValue: color.value,
        ));
      }
    });
  }

  Future<void> _showAddCustomDialog() async {
    final result = await showDialog<({String name, String? categoryId})>(
      context: context,
      builder: (_) => _AddCustomFlavorDialog(categories: _categories),
    );

    if (result == null || !mounted) return;

    final name = result.name;
    final categoryId = result.categoryId;
    Color tagColor = Colors.grey;
    String? catName;

    if (categoryId != null) {
      final cat = _categories.firstWhere((c) => c.id == categoryId);
      tagColor = cat.color;
      catName = cat.name;

      // "Custom" サブカテゴリに追加（なければ作成）
      final newItem = FlavorItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        isUserAdded: true,
      );
      final updatedCats = _categories.map((c) {
        if (c.id != categoryId) return c;
        final customIdx = c.subCategories.indexWhere((s) => s.id == '__custom__');
        if (customIdx >= 0) {
          final subs = List<FlavorSubCategory>.from(c.subCategories);
          subs[customIdx] =
              subs[customIdx].copyWith(items: [...subs[customIdx].items, newItem]);
          return c.copyWith(subCategories: subs);
        } else {
          return c.copyWith(subCategories: [
            ...c.subCategories,
            FlavorSubCategory(
                id: '__custom__', name: 'Custom', items: [newItem]),
          ]);
        }
      }).toList();

      await FlavorStorage.saveCategories(updatedCats);
      if (mounted) setState(() => _categories = updatedCats);
    } else {
      // Uncategorized に追加
      final updated = [..._uncategorized, name];
      await FlavorStorage.saveUncategorized(updated);
      if (mounted) setState(() => _uncategorized = updated);
    }

    if (mounted) {
      setState(() {
        _selected.add(FlavorNoteTag(
          name: name,
          categoryName: catName,
          categoryColorValue: tagColor.value,
          isCustom: true,
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text('Select Flavor Notes',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              // SCA カテゴリ別チップ
              ..._categories.map((cat) => _CategorySection(
                    category: cat,
                    isSelected: _isSelected,
                    onToggle: (name) => _toggle(name, cat.color, cat.name),
                  )),

              // Uncategorized
              if (_uncategorized.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Uncategorized',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _uncategorized.map((name) {
                    final sel = _isSelected(name);
                    return FilterChip(
                      label: Text(name,
                          style: const TextStyle(fontSize: 12)),
                      selected: sel,
                      onSelected: (_) => setState(() {
                        if (sel) {
                          _selected.removeWhere((t) => t.name == name);
                        } else {
                          _selected.add(
                              FlavorNoteTag(name: name, isCustom: true));
                        }
                      }),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],

              OutlinedButton.icon(
                onPressed: _showAddCustomDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Custom Flavor'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── カテゴリセクション ────────────────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final FlavorCategory category;
  final bool Function(String) isSelected;
  final void Function(String) onToggle;

  const _CategorySection({
    required this.category,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    // リーフノード（items.isEmpty）はサブカテゴリ名を選択候補として扱う
    final names = <String>[];
    for (final sub in category.subCategories) {
      if (sub.items.isEmpty) {
        names.add(sub.name);
      } else {
        names.addAll(sub.items.map((item) => item.name));
      }
    }
    if (names.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: category.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                category.name,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: category.color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: names.map((name) {
              final sel = isSelected(name);
              return FilterChip(
                label: Text(name, style: const TextStyle(fontSize: 12)),
                selected: sel,
                selectedColor: category.color.withValues(alpha: 0.22),
                checkmarkColor: category.color,
                side: BorderSide(
                    color: sel
                        ? category.color
                        : Colors.grey.shade300),
                onSelected: (_) => onToggle(name),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── カスタムフレーバー追加ダイアログ ──────────────────────────────────────

class _AddCustomFlavorDialog extends StatefulWidget {
  final List<FlavorCategory> categories;

  const _AddCustomFlavorDialog({required this.categories});

  @override
  State<_AddCustomFlavorDialog> createState() => _AddCustomFlavorDialogState();
}

class _AddCustomFlavorDialogState extends State<_AddCustomFlavorDialog> {
  final _nameCtrl = TextEditingController();
  String? _selectedCategoryId;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Custom Flavor'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Flavor Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedCategoryId,
            decoration: const InputDecoration(
              labelText: 'Category (optional)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String>(
                  value: null, child: Text('None (Uncategorized)')),
              ...widget.categories.map(
                (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
              ),
            ],
            onChanged: (v) => setState(() => _selectedCategoryId = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
                context, (name: name, categoryId: _selectedCategoryId));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
