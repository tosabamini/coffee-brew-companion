import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../../shared/services/claude_api.dart';
import '../../shared/widgets/ai_chat_screen.dart';
import '../data/flavor_labels_ja.dart';
import '../models/flavor_category.dart';
import '../services/flavor_ai.dart';
import '../services/flavor_storage.dart';
import '../services/flavor_wheel_prefs.dart';
import '../widgets/flavor_sunburst.dart';
import 'my_flavors_screen.dart';

/// フレーバーホイール（新デザイン）。
///
/// - 角度は「小分類1つ＝同じ幅」で割り当て、項目の多い大分類ほど広くする
/// - 区画をタップするとその区画が全周に広がる（もう一度中心をタップで戻る）
/// - 文字は区画に収まる最大サイズで描き、背景の明るさで文字色を変える
///
/// 旧デザインは FlavorWheelScreen にそのまま残してあり、設定タブ（または右上メニュー）から
/// いつでも切り替えられる。データ（flavor_wheel.json）は新旧で共通。
class FlavorWheelV2Screen extends StatefulWidget {
  const FlavorWheelV2Screen({super.key});

  @override
  State<FlavorWheelV2Screen> createState() => _FlavorWheelV2ScreenState();
}

class _FlavorWheelV2ScreenState extends State<FlavorWheelV2Screen>
    with SingleTickerProviderStateMixin {
  List<FlavorCategory> _categories = [];
  List<String> _uncategorized = [];
  List<SunburstNode> _nodes = [];
  bool _loading = true;

  String? _focusKey;
  String? _selectedKey;

  late final AnimationController _anim;
  SunburstView _from = SunburstView.root;
  SunburstView _to = SunburstView.root;

  bool get _ja => FlavorWheelPrefs.japaneseLabels.value;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420))
      ..addListener(() => setState(() {}));
    FlavorWheelPrefs.japaneseLabels.addListener(_rebuildNodes);
    _load();
  }

  @override
  void dispose() {
    FlavorWheelPrefs.japaneseLabels.removeListener(_rebuildNodes);
    _anim.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cats = await FlavorStorage.loadCategories();
    final uncat = await FlavorStorage.loadUncategorized();
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _uncategorized = uncat;
      _loading = false;
    });
    _rebuildNodes();
  }

  void _rebuildNodes() {
    if (!mounted) return;
    setState(() {
      _nodes = buildSunburstNodes(_categories, japanese: _ja);
      // 追加・削除で範囲が変わるので、表示中のズームも作り直す
      final f = _node(_focusKey);
      if (f == null) _focusKey = null;
      if (_node(_selectedKey) == null) _selectedKey = null;
      _from = _to = SunburstView.of(f);
    });
  }

  SunburstNode? _node(String? key) {
    if (key == null) return null;
    for (final n in _nodes) {
      if (n.key == key) return n;
    }
    return null;
  }

  SunburstNode? get _focus => _node(_focusKey);
  SunburstNode? get _selected => _node(_selectedKey);

  SunburstView get _view => _anim.isAnimating
      ? SunburstView.lerp(
          _from, _to, Curves.easeInOutCubic.transform(_anim.value))
      : _to;

  void _zoomTo(SunburstNode? n) {
    final current = _view;
    setState(() {
      _focusKey = n?.key;
      _from = current;
      _to = SunburstView.of(n);
    });
    _anim.forward(from: 0);
  }

  void _onTap(Offset p, Size size) {
    final g = FlavorSunburstPainter.geometryFor(size, _to);
    if (g.isCenter(p)) {
      if (_focus != null) {
        HapticFeedback.selectionClick();
        _zoomTo(_focus!.parent);
      }
      return;
    }
    final n = g.hitTest(p, _nodes);
    if (n == null) return;
    HapticFeedback.selectionClick();
    if (n.hasChildren && n.key != _focusKey) {
      _zoomTo(n);
    } else {
      setState(() => _selectedKey = _selectedKey == n.key ? null : n.key);
    }
  }

  // ── データ更新 ──────────────────────────────────────────────────────────

  Future<void> _addFlavor({
    required String categoryId,
    String? subId,
    String? newSubName,
    required String name,
    FlavorItem? existing, // 移動のときは元の項目（id を保つ）
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final item = existing ?? FlavorItem(id: '${now}_item', name: name, isUserAdded: true);
    final updated = _categories.map((cat) {
      if (cat.id != categoryId) return cat;
      if (subId == null) {
        return cat.copyWith(subCategories: [
          ...cat.subCategories,
          FlavorSubCategory(id: '$now', name: newSubName!, items: [item]),
        ]);
      }
      return cat.copyWith(
        subCategories: cat.subCategories
            .map((s) =>
                s.id == subId ? s.copyWith(items: [...s.items, item]) : s)
            .toList(),
      );
    }).toList();
    _categories = updated;
    await FlavorStorage.saveCategories(updated);
    _rebuildNodes();
  }

  /// 自分で追加したフレーバーを長押ししたとき：移動か削除を選ぶ
  Future<void> _itemActions(SunburstNode n) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: BrewColors.foam,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(n.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${n.category.name} › ${n.sub?.name ?? ''}'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline, color: BrewColors.caramel),
              title: const Text('別の分類へ移動'),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: BrewColors.terracotta),
              title: const Text('削除'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (v == 'move') await _moveItem(n);
    if (v == 'delete') await _deleteItem(n);
  }

  /// 項目を今の場所から取り除いた分類の一覧
  List<FlavorCategory> _withoutItem(SunburstNode n) {
    final item = n.item!;
    return _categories.map((cat) {
      if (cat.id != n.category.id) return cat;
      return cat.copyWith(
        subCategories: cat.subCategories
            .map((s) => s.id == n.sub!.id
                ? s.copyWith(items: s.items.where((i) => i.id != item.id).toList())
                : s)
            .toList(),
      );
    }).toList();
  }

  /// 自分で追加したフレーバーを別の大分類・中分類へ動かす（AI の分類が違ったときなど）
  Future<void> _moveItem(SunburstNode n) async {
    final item = n.item;
    if (item == null || !item.isUserAdded) return;
    final result = await showModalBottomSheet<_AddResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrewColors.foam,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddFlavorSheet(
        categories: _categories,
        japanese: _ja,
        initialCategoryId: n.category.id,
        initialSubId: n.sub?.id,
        presetName: item.name,
        moveMode: true,
      ),
    );
    if (result == null) return;
    _categories = _withoutItem(n);
    await _addFlavor(
      categoryId: result.categoryId,
      subId: result.subId,
      newSubName: result.newSubName,
      name: result.name,
      existing: FlavorItem(id: item.id, name: result.name, isUserAdded: true),
    );
  }

  /// AI と相談：フレーバーの意味や分類、追加の提案
  void _openChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AiChatScreen(
          title: 'フレーバーの相談',
          intro: 'フレーバーの意味や、どの分類に入るか、似ている言葉などを聞いてください。ホイールに追加したほうがよいものは提案します（ボタンで追加できます）。',
          suggestions: const ['「白桃」と「ピーチ」の違いは？', '紅茶っぽい感じはどこに入る？', 'ナチュラル精製でよく出るフレーバーは？'],
          systemPrompt: '''あなたはコーヒーのフレーバー（香味表現）に詳しいアシスタントです。日本語で、短く分かりやすく答えてください。
ユーザーのフレーバーホイール（SCA の分類をもとにしたもの）は次のとおりです。
${FlavorAi.describeWheel(_categories)}
ホイールにフレーバーを追加することを提案するときだけ、答えの最後に次の形のブロックを付けてください（JSON の中身は既存の id を使う。ふさわしい中分類がなければ subId を null にして newSubName を英語で）:
```flavor_add
{"items": [{"name": "フレーバー名", "categoryId": "大分類の id", "subId": "中分類の id か null", "newSubName": "新しい中分類名 か null"}]}
```''',
          actionTag: 'flavor_add',
          actionLabel: 'ホイールに追加する',
          onAction: _applyChatAdds,
        ),
      ),
    );
  }

  Future<String> _applyChatAdds(Map<String, dynamic> json) async {
    final items = (json['items'] as List?) ?? const [];
    var added = 0;
    for (final raw in items) {
      if (raw is! Map) continue;
      final name = raw['name']?.toString().trim() ?? '';
      final catId = raw['categoryId']?.toString();
      final cats = _categories.where((c) => c.id == catId).toList();
      if (name.isEmpty || cats.isEmpty) continue;
      final subId = raw['subId']?.toString();
      final hasSub = cats.first.subCategories.any((s) => s.id == subId);
      final newSub = raw['newSubName']?.toString().trim();
      await _addFlavor(
        categoryId: cats.first.id,
        subId: hasSub ? subId : null,
        newSubName: hasSub ? null : ((newSub == null || newSub.isEmpty) ? 'Other' : newSub),
        name: name,
      );
      added++;
    }
    if (added == 0) throw Exception('追加できる項目がありませんでした');
    return '$added 件をホイールに追加しました';
  }

  Future<void> _deleteItem(SunburstNode n) async {
    final item = n.item;
    if (item == null || !item.isUserAdded) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('「${n.label}」を削除'),
        content: const Text('自分で追加したフレーバーを削除します。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('削除',
                  style: TextStyle(color: BrewColors.terracotta))),
        ],
      ),
    );
    if (ok != true) return;
    final updated = _withoutItem(n);
    _categories = updated;
    await FlavorStorage.saveCategories(updated);
    _rebuildNodes();
  }

  Future<void> _openAddSheet({String? presetName}) async {
    final focus = _focus;
    final result = await showModalBottomSheet<_AddResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrewColors.foam,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddFlavorSheet(
        categories: _categories,
        japanese: _ja,
        initialCategoryId: focus?.category.id,
        initialSubId: focus?.sub?.id,
        presetName: presetName,
      ),
    );
    if (result == null) return;
    await _addFlavor(
      categoryId: result.categoryId,
      subId: result.subId,
      newSubName: result.newSubName,
      name: result.name,
    );
    if (presetName != null) {
      _uncategorized = _uncategorized.where((e) => e != presetName).toList();
      await FlavorStorage.saveUncategorized(_uncategorized);
      if (mounted) setState(() {});
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('フレーバーホイール',
            style: AppTheme.display(fontSize: 22, color: BrewColors.espresso)),
        actions: [
          IconButton(
            tooltip: 'よく使うフレーバー',
            icon: const Icon(Icons.bubble_chart_outlined, color: BrewColors.caramel),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => MyFlavorsScreen(categories: _categories)),
            ),
          ),
          IconButton(
            tooltip: 'AIに相談',
            icon: const Icon(Icons.auto_awesome, color: BrewColors.caramel),
            onPressed: _openChat,
          ),
          TextButton(
            onPressed: () => FlavorWheelPrefs.setJapaneseLabels(!_ja),
            child: Text(_ja ? 'EN' : '日本語',
                style: const TextStyle(
                    color: BrewColors.caramel, fontWeight: FontWeight.w700)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'legacy') FlavorWheelPrefs.setUseLegacy(true);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'legacy',
                child: Text('旧デザインに戻す'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddSheet(),
        backgroundColor: BrewColors.caramel,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('フレーバーを追加'),
      ),
      body: LayoutBuilder(builder: (context, c) {
        final side = (c.maxWidth - 24).clamp(200.0, c.maxHeight * 0.56);
        return Column(
          children: [
            const SizedBox(height: 4),
            _buildWheel(side),
            _buildBreadcrumb(),
            const Divider(height: 1, color: BrewColors.oat),
            Expanded(child: _buildDetail()),
          ],
        );
      }),
    );
  }

  Widget _buildWheel(double side) {
    final size = Size(side, side);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) => _onTap(d.localPosition, size),
      child: SizedBox.fromSize(
        size: size,
        child: CustomPaint(
          painter: FlavorSunburstPainter(
            baseStyle: Theme.of(context).textTheme.bodyMedium ??
                const TextStyle(),
            nodes: _nodes,
            view: _view,
            focus: _focus,
            selectedKey: _selectedKey,
            showLabels: !_anim.isAnimating,
            japanese: _ja,
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final path = _focus?.path ?? const <SunburstNode>[];
    final sel = _selected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _crumb(_ja ? 'すべて' : 'All', null, path.isEmpty),
                  for (final n in path) ...[
                    const Icon(Icons.chevron_right,
                        size: 16, color: BrewColors.mocha),
                    _crumb(n.label, n, n == path.last),
                  ],
                ],
              ),
            ),
          ),
          if (sel != null)
            Flexible(
              child: Container(
                margin: const EdgeInsets.only(left: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: sel.color,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: BrewColors.espresso, width: 1.2),
                ),
                child: Text(
                  sel.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: FlavorSunburstPainter.textOn(sel.color),
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _crumb(String text, SunburstNode? n, bool current) {
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: current ? null : () => _zoomTo(n),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: current ? FontWeight.w800 : FontWeight.w600,
          color: current ? BrewColors.espresso : BrewColors.caramel,
        ),
      ),
    );
  }

  /// ホイールの下：今見ている階層の中身を一覧で出す（ホイールの文字が小さくても読める）
  Widget _buildDetail() {
    final focus = _focus;
    final children = _nodes.where((n) {
      if (focus == null) return n.depth == 1;
      return n.parent == focus;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        Text(
          focus == null
              ? (_ja ? '分類をタップすると拡大します' : 'Tap a category to zoom in')
              : (focus.depth == 1
                  ? (_ja ? '中分類' : 'Sub categories')
                  : (_ja ? 'フレーバー' : 'Flavors')),
          style: AppTheme.overline(color: BrewColors.caramel),
        ),
        const SizedBox(height: 8),
        if (focus == null)
          ...children.map(_categoryTile)
        else if (focus.depth == 1)
          ...children.map(_subTile)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: children.map((n) => _itemChip(n, large: true)).toList(),
          ),
        if (_uncategorized.isNotEmpty && focus == null) ...[
          const SizedBox(height: 16),
          Text(_ja ? '未分類' : 'Uncategorized',
              style: AppTheme.overline(color: BrewColors.mocha)),
          const SizedBox(height: 6),
          ..._uncategorized.map((name) => Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.help_outline,
                      color: BrewColors.mocha, size: 20),
                  title: Text(name),
                  trailing: TextButton(
                    onPressed: () => _openAddSheet(presetName: name),
                    child: const Text('分類する'),
                  ),
                ),
              )),
        ],
      ],
    );
  }

  Widget _categoryTile(SunburstNode n) {
    final subs = _nodes.where((s) => s.parent == n).map((s) => s.label);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _zoomTo(n),
        leading: CircleAvatar(radius: 9, backgroundColor: n.color),
        title: Text(n.label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subs.join(' ・ '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: BrewColors.mocha, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: BrewColors.mocha),
      ),
    );
  }

  Widget _subTile(SunburstNode n) {
    final items = _nodes.where((i) => i.parent == n).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => items.isEmpty
                  ? setState(() => _selectedKey = n.key)
                  : _zoomTo(n),
              child: Row(
                children: [
                  CircleAvatar(radius: 7, backgroundColor: n.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(n.label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  if (items.isNotEmpty)
                    const Icon(Icons.zoom_in,
                        size: 20, color: BrewColors.mocha),
                ],
              ),
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: items.map((i) => _itemChip(i)).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemChip(SunburstNode n, {bool large = false}) {
    final selected = n.key == _selectedKey;
    final userAdded = n.item?.isUserAdded ?? false;
    return GestureDetector(
      onLongPress: userAdded ? () => _itemActions(n) : null,
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) =>
            setState(() => _selectedKey = selected ? null : n.key),
        showCheckmark: false,
        avatar: userAdded
            ? const Icon(Icons.person_outline,
                size: 16, color: BrewColors.mocha)
            : null,
        label: Text(n.label),
        labelStyle: TextStyle(
          fontSize: large ? 15 : 13,
          fontWeight: FontWeight.w600,
          color: selected
              ? FlavorSunburstPainter.textOn(n.category.color)
              : BrewColors.espresso,
        ),
        backgroundColor: n.color.withValues(alpha: 0.35),
        selectedColor: n.category.color,
        side: BorderSide(color: n.category.color.withValues(alpha: 0.6)),
        padding: large
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
            : null,
      ),
    );
  }
}

// ── フレーバー追加シート ─────────────────────────────────────────────────

class _AddResult {
  final String categoryId;
  final String? subId; // null なら newSubName で新しい中分類を作る
  final String? newSubName;
  final String name;
  const _AddResult(this.categoryId, this.subId, this.newSubName, this.name);
}

class _AddFlavorSheet extends StatefulWidget {
  final List<FlavorCategory> categories;
  final bool japanese;
  final String? initialCategoryId;
  final String? initialSubId;
  final String? presetName;

  /// 追加済みのフレーバーを動かすとき（AI は自動では呼ばない）
  final bool moveMode;

  const _AddFlavorSheet({
    required this.categories,
    required this.japanese,
    this.initialCategoryId,
    this.initialSubId,
    this.presetName,
    this.moveMode = false,
  });

  @override
  State<_AddFlavorSheet> createState() => _AddFlavorSheetState();
}

class _AddFlavorSheetState extends State<_AddFlavorSheet> {
  static const _newSub = '__new__';
  late final TextEditingController _name =
      TextEditingController(text: widget.presetName ?? '');
  final _newSubName = TextEditingController();
  String? _catId;
  String? _subId;
  bool _aiBusy = false;
  String? _aiNote;

  @override
  void initState() {
    super.initState();
    _catId = widget.initialCategoryId;
    _subId = widget.initialSubId;
    // 未分類のフレーバーを分類するときは、開いたらすぐ AI に置き場所を聞く
    if (widget.presetName != null && !widget.moveMode && ClaudeApi.hasKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askAi());
    }
  }

  /// AI に置き場所を提案してもらい、大分類・中分類を選んだ状態にする（選び直せる）
  Future<void> _askAi() async {
    final name = _name.text.trim();
    if (name.isEmpty || _aiBusy) return;
    setState(() {
      _aiBusy = true;
      _aiNote = null;
    });
    try {
      final p = await FlavorAi.suggest(name, widget.categories);
      if (!mounted) return;
      final cat = widget.categories.firstWhere((c) => c.id == p.categoryId);
      String where = _label(cat.id, cat.name);
      setState(() {
        _catId = p.categoryId;
        if (p.subId != null) {
          _subId = p.subId;
          final sub = cat.subCategories.firstWhere((x) => x.id == p.subId);
          where += ' › ${_label(sub.id, sub.name)}';
        } else {
          _subId = _newSub;
          _newSubName.text = p.newSubName ?? '';
          where += ' › 新しい中分類「${p.newSubName ?? ''}」';
        }
        _aiNote = 'AIの提案：$where${p.reason.isEmpty ? '' : '（${p.reason}）'}\n違うと思ったら、下で選び直してください。';
      });
    } catch (e) {
      if (mounted) setState(() => _aiNote = 'AIに聞けませんでした：$e');
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _newSubName.dispose();
    super.dispose();
  }

  FlavorCategory? get _cat =>
      widget.categories.where((c) => c.id == _catId).firstOrNull;

  String _label(String id, String name) =>
      flavorLabel(id, name, japanese: widget.japanese);

  bool get _canSubmit {
    if (_name.text.trim().isEmpty || _catId == null || _subId == null) {
      return false;
    }
    if (_subId == _newSub && _newSubName.text.trim().isEmpty) return false;
    return true;
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(
      context,
      _AddResult(
        _catId!,
        _subId == _newSub ? null : _subId,
        _subId == _newSub ? _newSubName.text.trim() : null,
        _name.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cat = _cat;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: BrewColors.oat,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
                widget.moveMode
                    ? '移動する'
                    : (widget.presetName == null ? 'フレーバーを追加' : '分類する'),
                style: AppTheme.display(fontSize: 20)),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.presetName == null,
              decoration: const InputDecoration(
                labelText: 'フレーバー名',
                hintText: '例：白桃、黒蜜',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: (_aiBusy || _name.text.trim().isEmpty || !ClaudeApi.hasKey)
                      ? null
                      : _askAi,
                  icon: _aiBusy
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(_aiBusy ? 'AIが考えています…' : 'AIに分類してもらう'),
                ),
              ],
            ),
            if (_aiNote != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BrewColors.oat.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_aiNote!,
                    style: const TextStyle(fontSize: 13, height: 1.4, color: BrewColors.espresso)),
              ),
            const SizedBox(height: 12),
            Text('大分類', style: AppTheme.overline()),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: widget.categories.map((c) {
                final sel = c.id == _catId;
                return ChoiceChip(
                  selected: sel,
                  showCheckmark: false,
                  label: Text(_label(c.id, c.name)),
                  avatar: CircleAvatar(radius: 6, backgroundColor: c.color),
                  selectedColor: c.color.withValues(alpha: 0.35),
                  side: BorderSide(
                      color: sel ? c.color : BrewColors.oat, width: 1.2),
                  onSelected: (_) => setState(() {
                    _catId = c.id;
                    _subId = null;
                  }),
                );
              }).toList(),
            ),
            if (cat != null) ...[
              const SizedBox(height: 16),
              Text('中分類', style: AppTheme.overline()),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ...cat.subCategories.map((s) => ChoiceChip(
                        selected: s.id == _subId,
                        showCheckmark: false,
                        label: Text(_label(s.id, s.name)),
                        selectedColor: cat.color.withValues(alpha: 0.35),
                        onSelected: (_) => setState(() => _subId = s.id),
                      )),
                  ChoiceChip(
                    selected: _subId == _newSub,
                    showCheckmark: false,
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('新しい中分類'),
                    selectedColor: cat.color.withValues(alpha: 0.35),
                    onSelected: (_) => setState(() => _subId = _newSub),
                  ),
                ],
              ),
              if (_subId == _newSub) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _newSubName,
                  decoration: const InputDecoration(
                    labelText: '新しい中分類の名前',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                    backgroundColor: BrewColors.caramel,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(widget.moveMode
                    ? '移動する'
                    : (widget.presetName == null ? '追加する' : '分類する')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
