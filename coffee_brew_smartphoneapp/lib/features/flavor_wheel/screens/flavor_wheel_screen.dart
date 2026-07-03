import 'dart:math';

import 'package:flutter/material.dart';

import '../models/flavor_category.dart';
import '../services/flavor_storage.dart';
import '../widgets/flavor_wheel_painter.dart';

class FlavorWheelScreen extends StatefulWidget {
  const FlavorWheelScreen({super.key});

  @override
  State<FlavorWheelScreen> createState() => _FlavorWheelScreenState();
}

class _FlavorWheelScreenState extends State<FlavorWheelScreen> {
  List<FlavorCategory> _categories = [];
  List<String> _uncategorized = [];
  bool _loading = true;

  /// 拡大表示モード
  bool _isExpanded = false;

  /// ホイールの回転角度（ラジアン）
  double _rotationAngle = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final cats = await FlavorStorage.loadCategories();
    final uncat = await FlavorStorage.loadUncategorized();
    if (mounted) {
      setState(() {
        _categories = cats;
        _uncategorized = uncat;
        _loading = false;
      });
    }
  }

  Future<void> _saveCategories() async {
    await FlavorStorage.saveCategories(_categories);
  }

  Future<void> _saveUncategorized() async {
    await FlavorStorage.saveUncategorized(_uncategorized);
  }

  // ── アクティブカテゴリ（角度 π/2 = 真下に最も近いカテゴリ） ────────────

  int get _activeCategoryIndex {
    final n = _categories.length;
    if (n == 0) return 0;
    final sliceAngle = 2 * pi / n;
    int bestIdx = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < n; i++) {
      final midAngle = -pi / 2 + _rotationAngle + (i + 0.5) * sliceAngle;
      double delta = (midAngle - pi / 2) % (2 * pi);
      if (delta > pi) delta -= 2 * pi;
      if (delta.abs() < bestDist) {
        bestDist = delta.abs();
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// 拡大モード時：真下（π/2）に最も近い中分類の ID を返す
  /// 通常モード時は null（小分類ラベルを描画しない）
  String? get _activeSubCategoryId {
    if (!_isExpanded || _categories.isEmpty) return null;

    final n = _categories.length;
    final sliceAngle = 2 * pi / n;
    final catIdx = _activeCategoryIndex;
    final cat = _categories[catIdx];
    if (cat.subCategories.isEmpty) return null;

    // アクティブカテゴリの開始角度
    final catStart = -pi / 2 +
        _rotationAngle +
        catIdx * sliceAngle +
        FlavorWheelPainter.catGap / 2;
    final catEffective = sliceAngle - FlavorWheelPainter.catGap;
    final numSubs = cat.subCategories.length;
    final subSlice = catEffective / numSubs;

    int bestSubIdx = 0;
    double bestDist = double.infinity;
    for (int si = 0; si < numSubs; si++) {
      // midAngle = catStart + (si + 0.5) * subSlice（ギャップは中点計算でキャンセル）
      final subMid = catStart + (si + 0.5) * subSlice;
      double delta = (subMid - pi / 2) % (2 * pi);
      if (delta > pi) delta -= 2 * pi;
      if (delta.abs() < bestDist) {
        bestDist = delta.abs();
        bestSubIdx = si;
      }
    }

    return cat.subCategories[bestSubIdx].id;
  }

  /// 拡大モード時はアクティブカテゴリを先頭に並び替え
  List<FlavorCategory> get _orderedCategories {
    if (!_isExpanded || _categories.isEmpty) return _categories;
    final idx = _activeCategoryIndex;
    return [..._categories.sublist(idx), ..._categories.sublist(0, idx)];
  }

  // ── フレーバー追加ダイアログ ─────────────────────────────────────────────

  void _showAddFlavorDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => _AddFlavorDialog(
        categories: _categories,
        onAdd: (categoryId, subCategoryId, itemName, newSubCategoryName) async {
          List<FlavorCategory> updated;

          if (subCategoryId == _AddFlavorDialog.newSubId) {
            updated = _categories.map((cat) {
              if (cat.id != categoryId) return cat;
              return cat.copyWith(subCategories: [
                ...cat.subCategories,
                FlavorSubCategory(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: newSubCategoryName!,
                  items: [
                    FlavorItem(
                      id: '${DateTime.now().millisecondsSinceEpoch}_item',
                      name: itemName,
                      isUserAdded: true,
                    ),
                  ],
                ),
              ]);
            }).toList();
          } else {
            updated = _categories.map((cat) {
              if (cat.id != categoryId) return cat;
              return cat.copyWith(
                subCategories: cat.subCategories.map((sub) {
                  if (sub.id != subCategoryId) return sub;
                  return sub.copyWith(items: [
                    ...sub.items,
                    FlavorItem(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      name: itemName,
                      isUserAdded: true,
                    ),
                  ]);
                }).toList(),
              );
            }).toList();
          }

          setState(() => _categories = updated);
          await _saveCategories();
        },
      ),
    );
  }

  // ── Uncategorized 分類ダイアログ ─────────────────────────────────────────

  void _showClassifyDialog(String flavorName) {
    showDialog<void>(
      context: context,
      builder: (_) => _ClassifyFlavorDialog(
        flavorName: flavorName,
        categories: _categories,
        onClassify: (categoryId, subCategoryId, newSubName) async {
          final updatedUncat =
              _uncategorized.where((n) => n != flavorName).toList();

          final newItem = FlavorItem(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: flavorName,
            isUserAdded: true,
          );

          List<FlavorCategory> updatedCats;
          if (subCategoryId == _ClassifyFlavorDialog.newSubId) {
            updatedCats = _categories.map((cat) {
              if (cat.id != categoryId) return cat;
              return cat.copyWith(subCategories: [
                ...cat.subCategories,
                FlavorSubCategory(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: newSubName!,
                  items: [newItem],
                ),
              ]);
            }).toList();
          } else {
            updatedCats = _categories.map((cat) {
              if (cat.id != categoryId) return cat;
              return cat.copyWith(
                subCategories: cat.subCategories.map((sub) {
                  if (sub.id != subCategoryId) return sub;
                  return sub.copyWith(items: [...sub.items, newItem]);
                }).toList(),
              );
            }).toList();
          }

          setState(() {
            _categories = updatedCats;
            _uncategorized = updatedUncat;
          });
          await Future.wait([_saveCategories(), _saveUncategorized()]);
        },
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Flavor Wheel')),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFlavorDialog,
        tooltip: 'Add Flavor',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _isExpanded ? _buildExpandedWheel() : _buildNormalWheel(),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ..._orderedCategories.map((cat) => _CategoryTile(
                      cat: cat,
                      isActive: _isExpanded &&
                          _categories.isNotEmpty &&
                          cat == _categories[_activeCategoryIndex],
                    )),

                // Uncategorized セクション
                if (_uncategorized.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.help_outline,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        'Uncategorized',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._uncategorized.map((name) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(name,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                            TextButton(
                              onPressed: () => _showClassifyDialog(name),
                              child: const Text('Classify'),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 通常表示（全体ホイール） ─────────────────────────────────────────────

  Widget _buildNormalWheel() {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = true),
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                painter: FlavorWheelPainter(categories: _categories),
                child: const SizedBox.expand(),
              ),
              // タップヒント
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_in, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Tap to explore',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 拡大表示（部分ホイール＋回転） ───────────────────────────────────────

  Widget _buildExpandedWheel() {
    return LayoutBuilder(builder: (context, constraints) {
      final W = constraints.maxWidth;

      // 大きな円の半径。画面幅の1.1倍。
      final bigR = W * 1.1;

      // 中心を -bigR×0.30 に配置することで中分類リング（半径0.53R）が
      // キャンバス内（y = +0.23R）にしっかり収まる。
      // 可視弧は真下 ±72° ≒ 144°（カテゴリ3〜4個が見える）。
      final centerY = -bigR * 0.30;
      final visibleH = bigR * 0.68;

      // 通常モードの半径に対する倍率でフォントをスケール
      final normalR = W * 0.5;
      final scale = (bigR / normalR).clamp(1.0, 3.0);

      final activeIdx    = _activeCategoryIndex;
      final activeCat    = _categories.isEmpty ? null : _categories[activeIdx];
      final activeSubId  = _activeSubCategoryId;
      final activeSub    = activeCat?.subCategories
          .where((s) => s.id == activeSubId)
          .firstOrNull;

      return Column(
        children: [
          // ── ホイール本体 ────────────────────────────────────────────────
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                // 左ドラッグ → 右のカテゴリが中央へ来る（時計回り）
                _rotationAngle -= details.delta.dx / bigR;
              });
            },
            child: SizedBox(
              height: visibleH,
              width: W,
              child: ClipRect(
                child: Stack(
                  children: [
                    SizedBox.expand(
                      child: CustomPaint(
                        painter: FlavorWheelPainter(
                          categories: _categories,
                          rotationOffset: _rotationAngle,
                          overrideCenter: Offset(W / 2, centerY),
                          overrideRadius: bigR,
                          fontScale: scale,
                          activeSubCategoryId: activeSubId,
                        ),
                      ),
                    ),
                    // 下端中央のインジケータ（現在のカテゴリ位置を示す）
                    Positioned(
                      bottom: 2,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Icon(
                          Icons.arrow_drop_up,
                          color: Colors.white70,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── アクティブカテゴリ／中分類バー ───────────────────────────
          if (activeCat != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: activeCat.color.withValues(alpha: 0.08),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: activeCat.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 大分類名
                  Text(
                    activeCat.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: activeCat.color,
                    ),
                  ),
                  // 中分類名（存在する場合）
                  if (activeSub != null) ...[
                    Text(
                      ' › ',
                      style: TextStyle(
                          fontSize: 13, color: activeCat.color.withValues(alpha: 0.6)),
                    ),
                    Text(
                      activeSub.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: activeCat.color.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                  const Spacer(),
                  const Text(
                    '← drag →',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = false),
                    child: const Icon(Icons.close,
                        size: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }
}

// ── カテゴリタイル ───────────────────────────────────────────────────────

class _CategoryTile extends StatelessWidget {
  final FlavorCategory cat;

  /// 拡大モードで現在中央に表示されているカテゴリかどうか
  final bool isActive;

  const _CategoryTile({required this.cat, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: isActive
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(color: cat.color, width: 3),
                ),
                color: cat.color.withValues(alpha: 0.05),
              )
            : null,
        padding: isActive
            ? const EdgeInsets.only(left: 8)
            : EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration:
                      BoxDecoration(color: cat.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(cat.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isActive ? 15 : 14,
                    )),
              ],
            ),
            const SizedBox(height: 4),
            ...cat.subCategories.map((sub) => Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(sub.name,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w600)),
                          if (sub.items.any((i) => i.isUserAdded))
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Icon(Icons.person_outline,
                                  size: 12, color: Colors.grey),
                            ),
                        ],
                      ),
                      if (sub.items.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: Wrap(
                            spacing: 5,
                            runSpacing: 3,
                            children: sub.items
                                .map((item) => Chip(
                                      label: Text(item.name,
                                          style:
                                              const TextStyle(fontSize: 11)),
                                      backgroundColor:
                                          cat.color.withValues(alpha: 0.15),
                                      side: BorderSide(
                                          color: cat.color
                                              .withValues(alpha: 0.4)),
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                    ))
                                .toList(),
                          ),
                        ),
                      ],
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

// ── フレーバー追加ダイアログ ─────────────────────────────────────────────

class _AddFlavorDialog extends StatefulWidget {
  static const newSubId = '__new_sub__';

  final List<FlavorCategory> categories;
  final void Function(
    String categoryId,
    String subCategoryId,
    String itemName,
    String? newSubCategoryName,
  ) onAdd;

  const _AddFlavorDialog({required this.categories, required this.onAdd});

  @override
  State<_AddFlavorDialog> createState() => _AddFlavorDialogState();
}

class _AddFlavorDialogState extends State<_AddFlavorDialog> {
  final _itemNameCtrl = TextEditingController();
  final _newSubCtrl = TextEditingController();
  String? _selectedCategoryId;
  String? _selectedSubId;

  @override
  void dispose() {
    _itemNameCtrl.dispose();
    _newSubCtrl.dispose();
    super.dispose();
  }

  FlavorCategory? get _selectedCategory =>
      widget.categories.where((c) => c.id == _selectedCategoryId).firstOrNull;

  bool get _isNewSub => _selectedSubId == _AddFlavorDialog.newSubId;

  void _submit() {
    final name = _itemNameCtrl.text.trim();
    if (name.isEmpty || _selectedCategoryId == null || _selectedSubId == null) {
      return;
    }
    if (_isNewSub && _newSubCtrl.text.trim().isEmpty) return;

    widget.onAdd(
      _selectedCategoryId!,
      _selectedSubId!,
      name,
      _isNewSub ? _newSubCtrl.text.trim() : null,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final subs = _selectedCategory?.subCategories ?? [];

    return AlertDialog(
      title: const Text('Add Flavor'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(
                  labelText: 'Category', border: OutlineInputBorder()),
              items: widget.categories
                  .map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() {
                _selectedCategoryId = v;
                _selectedSubId = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedSubId,
              decoration: const InputDecoration(
                  labelText: 'Sub Category', border: OutlineInputBorder()),
              items: [
                ...subs.map((s) =>
                    DropdownMenuItem(value: s.id, child: Text(s.name))),
                const DropdownMenuItem(
                  value: _AddFlavorDialog.newSubId,
                  child: Text('+ New Sub Category'),
                ),
              ],
              onChanged: _selectedCategoryId == null
                  ? null
                  : (v) => setState(() => _selectedSubId = v),
            ),
            if (_isNewSub) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _newSubCtrl,
                decoration: const InputDecoration(
                    labelText: 'New Sub Category Name',
                    border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _itemNameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Flavor Name', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

// ── Uncategorized 分類ダイアログ ─────────────────────────────────────────

class _ClassifyFlavorDialog extends StatefulWidget {
  static const newSubId = '__new_sub__';

  final String flavorName;
  final List<FlavorCategory> categories;
  final void Function(
    String categoryId,
    String subCategoryId,
    String? newSubName,
  ) onClassify;

  const _ClassifyFlavorDialog({
    required this.flavorName,
    required this.categories,
    required this.onClassify,
  });

  @override
  State<_ClassifyFlavorDialog> createState() => _ClassifyFlavorDialogState();
}

class _ClassifyFlavorDialogState extends State<_ClassifyFlavorDialog> {
  final _newSubCtrl = TextEditingController();
  String? _selectedCategoryId;
  String? _selectedSubId;

  @override
  void dispose() {
    _newSubCtrl.dispose();
    super.dispose();
  }

  FlavorCategory? get _selectedCategory => widget.categories
      .where((c) => c.id == _selectedCategoryId)
      .firstOrNull;

  bool get _isNewSub => _selectedSubId == _ClassifyFlavorDialog.newSubId;

  void _submit() {
    if (_selectedCategoryId == null || _selectedSubId == null) return;
    if (_isNewSub && _newSubCtrl.text.trim().isEmpty) return;

    widget.onClassify(
      _selectedCategoryId!,
      _selectedSubId!,
      _isNewSub ? _newSubCtrl.text.trim() : null,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final subs = _selectedCategory?.subCategories ?? [];

    return AlertDialog(
      title: Text('Classify "${widget.flavorName}"'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(
                  labelText: 'Category', border: OutlineInputBorder()),
              items: widget.categories
                  .map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() {
                _selectedCategoryId = v;
                _selectedSubId = null;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedSubId,
              decoration: const InputDecoration(
                  labelText: 'Sub Category', border: OutlineInputBorder()),
              items: [
                ...subs.map((s) =>
                    DropdownMenuItem(value: s.id, child: Text(s.name))),
                const DropdownMenuItem(
                  value: _ClassifyFlavorDialog.newSubId,
                  child: Text('+ New Sub Category'),
                ),
              ],
              onChanged: _selectedCategoryId == null
                  ? null
                  : (v) => setState(() => _selectedSubId = v),
            ),
            if (_isNewSub) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _newSubCtrl,
                decoration: const InputDecoration(
                    labelText: 'New Sub Category Name',
                    border: OutlineInputBorder()),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Classify')),
      ],
    );
  }
}
