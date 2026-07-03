import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/brew_widgets.dart';
import '../models/bean_stock.dart';
import '../services/session_storage.dart';

/// 豆の在庫・エイジング管理画面
class BeanInventoryScreen extends StatefulWidget {
  const BeanInventoryScreen({super.key});

  @override
  State<BeanInventoryScreen> createState() => _BeanInventoryScreenState();
}

class _BeanInventoryScreenState extends State<BeanInventoryScreen> {
  List<BeanStock> _stocks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stocks = await SessionStorage.loadBeanStocks();
    if (!mounted) return;
    setState(() {
      _stocks = stocks;
      _isLoading = false;
    });
  }

  Future<void> _persist() async {
    await SessionStorage.saveBeanStocks(_stocks);
  }

  Future<void> _addOrEditStock({BeanStock? existing}) async {
    final result = await showModalBottomSheet<BeanStock>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BrewColors.foam,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _BeanStockForm(existing: existing),
    );
    if (result == null) return;

    setState(() {
      if (existing == null) {
        _stocks.insert(0, result);
      } else {
        final index = _stocks.indexWhere((s) => s.id == existing.id);
        if (index != -1) _stocks[index] = result;
      }
    });
    await _persist();
  }

  Future<void> _consume(BeanStock stock) async {
    final controller = TextEditingController(text: '15');
    final grams = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${stock.name} を消費'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '消費量 (g)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              Navigator.pop(ctx, value);
            },
            child: const Text('記録'),
          ),
        ],
      ),
    );
    if (grams == null || grams <= 0) return;

    setState(() {
      stock.consume(grams);
    });
    await _persist();
  }

  Future<void> _delete(BeanStock stock) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('在庫を削除'),
        content: Text('「${stock.name}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: BrewColors.terracotta),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _stocks.removeWhere((s) => s.id == stock.id);
    });
    await _persist();
  }

  /// 焙煎日からの経過日数に応じた鮮度ラベルと色
  (String, Color)? _freshness(BeanStock stock) {
    final days = stock.daysSinceRoast;
    if (days == null) return null;
    if (days <= 3) return ('休ませ中', BrewColors.amber);
    if (days <= 21) return ('飲み頃', BrewColors.sage);
    if (days <= 35) return ('そろそろ', BrewColors.caramel);
    return ('経過長め', BrewColors.terracotta);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Bean Cellar',
          style: AppTheme.display(
            fontSize: 22,
            fontStyle: FontStyle.italic,
            color: BrewColors.espresso,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditStock(),
        backgroundColor: BrewColors.caramel,
        foregroundColor: BrewColors.foam,
        icon: const Icon(Icons.add),
        label: const Text('豆を追加'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stocks.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                  itemCount: _stocks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return FadeSlideIn(
                      delay:
                          Duration(milliseconds: 40 * (index < 8 ? index : 8)),
                      child: _buildStockCard(_stocks[index]),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 44,
            color: BrewColors.mocha.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            '在庫がまだありません',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: BrewColors.mocha),
          ),
          const SizedBox(height: 4),
          Text(
            '「豆を追加」から焙煎日と量を登録しましょう',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: BrewColors.mocha.withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockCard(BeanStock stock) {
    final freshness = _freshness(stock);
    final days = stock.daysSinceRoast;
    final ratio = stock.remainingRatio;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _addOrEditStock(existing: stock),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stock.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: BrewColors.espresso,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (stock.roaster != null &&
                            stock.roaster!.isNotEmpty)
                          Text(
                            stock.roaster!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: BrewColors.mocha),
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (freshness != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: freshness.$2.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: freshness.$2.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        '焙煎後$days日 · ${freshness.$1}',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                              color: freshness.$2,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (ratio != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          backgroundColor:
                              BrewColors.oat.withValues(alpha: 0.5),
                          color: ratio > 0.25
                              ? BrewColors.caramel
                              : BrewColors.terracotta,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${stock.remainingG!.toStringAsFixed(0)} / ${stock.totalG!.toStringAsFixed(0)} g',
                      style: AppTheme.mono(
                          fontSize: 12, color: BrewColors.mocha),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed:
                        stock.remainingG == null ? null : () => _consume(stock),
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: const Text('消費を記録'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: BrewColors.mocha.withValues(alpha: 0.6),
                    onPressed: () => _delete(stock),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 在庫の追加・編集フォーム（ボトムシート）
class _BeanStockForm extends StatefulWidget {
  final BeanStock? existing;

  const _BeanStockForm({this.existing});

  @override
  State<_BeanStockForm> createState() => _BeanStockFormState();
}

class _BeanStockFormState extends State<_BeanStockForm> {
  late final TextEditingController _nameController;
  late final TextEditingController _roasterController;
  late final TextEditingController _totalController;
  late final TextEditingController _remainingController;
  late final TextEditingController _memoController;
  DateTime? _roastDate;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameController = TextEditingController(text: e?.name ?? '');
    _roasterController = TextEditingController(text: e?.roaster ?? '');
    _totalController = TextEditingController(
        text: e?.totalG == null ? '' : e!.totalG!.toStringAsFixed(0));
    _remainingController = TextEditingController(
        text: e?.remainingG == null ? '' : e!.remainingG!.toStringAsFixed(0));
    _memoController = TextEditingController(text: e?.memo ?? '');
    _roastDate = e?.roastDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roasterController.dispose();
    _totalController.dispose();
    _remainingController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _pickRoastDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _roastDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _roastDate = picked);
    }
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('豆の名前を入力してください')),
      );
      return;
    }

    final total = double.tryParse(_totalController.text.trim());
    final remainingInput = double.tryParse(_remainingController.text.trim());
    // 新規登録時に残量未入力なら総量をそのまま残量にする
    final remaining = remainingInput ?? total;

    final stock = BeanStock(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      roaster: _roasterController.text.trim().isEmpty
          ? null
          : _roasterController.text.trim(),
      roastDate: _roastDate,
      totalG: total,
      remainingG: remaining,
      memo: _memoController.text.trim().isEmpty
          ? null
          : _memoController.text.trim(),
    );
    Navigator.pop(context, stock);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? '在庫を編集' : '豆を追加',
              style: AppTheme.display(fontSize: 19, color: BrewColors.espresso),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '豆の名前 *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _roasterController,
              decoration: const InputDecoration(labelText: 'ロースター / 購入店'),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickRoastDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: '焙煎日'),
                child: Row(
                  children: [
                    const Icon(Icons.event, size: 18, color: BrewColors.mocha),
                    const SizedBox(width: 8),
                    Text(
                      _roastDate == null
                          ? '未設定（タップして選択）'
                          : '${_roastDate!.year}/${_roastDate!.month.toString().padLeft(2, '0')}/${_roastDate!.day.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: _roastDate == null
                            ? BrewColors.mocha.withValues(alpha: 0.6)
                            : BrewColors.espresso,
                      ),
                    ),
                    const Spacer(),
                    if (_roastDate != null)
                      GestureDetector(
                        onTap: () => setState(() => _roastDate = null),
                        child: const Icon(Icons.close,
                            size: 18, color: BrewColors.mocha),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _totalController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '購入量 (g)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _remainingController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '残量 (g)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _memoController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'メモ'),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: Text(isEdit ? '更新' : '追加'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
