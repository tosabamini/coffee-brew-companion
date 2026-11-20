import 'package:flutter/material.dart';

import '../data/drippers.dart';

/// ドリッパーの入力欄（任意）。一覧から選ぶか、「その他」で自由に入力する。
class DripperField extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const DripperField({super.key, required this.value, required this.onChanged});

  @override
  State<DripperField> createState() => _DripperFieldState();
}

class _DripperFieldState extends State<DripperField> {
  static const String _none = '__none__';
  static const String _other = '__other__';

  late String _selected;
  final _customController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _syncFrom(widget.value);
  }

  @override
  void didUpdateWidget(covariant DripperField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外から値が変わったとき（「この条件でもう一度」など）だけ合わせ直す
    if (oldWidget.value != widget.value && widget.value != _currentValue()) {
      _syncFrom(widget.value);
    }
  }

  void _syncFrom(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) {
      _selected = _none;
      _customController.text = '';
    } else if (Drippers.all.contains(t)) {
      _selected = t;
      _customController.text = '';
    } else {
      _selected = _other;
      _customController.text = t;
    }
  }

  String? _currentValue() {
    if (_selected == _none) return null;
    if (_selected == _other) {
      final t = _customController.text.trim();
      return t.isEmpty ? null : t;
    }
    return _selected;
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: _selected,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'ドリッパー（任意）',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: _none, child: Text('指定なし')),
            for (final d in Drippers.all) DropdownMenuItem(value: d, child: Text(d)),
            const DropdownMenuItem(value: _other, child: Text('その他（自由に入力）')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _selected = v);
            widget.onChanged(_currentValue());
          },
        ),
        if (_selected == _other) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customController,
            decoration: const InputDecoration(
              labelText: 'ドリッパーの名前',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => widget.onChanged(_currentValue()),
          ),
        ],
      ],
    );
  }
}
