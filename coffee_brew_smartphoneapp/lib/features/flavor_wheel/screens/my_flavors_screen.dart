import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../scale/services/session_storage.dart';
import '../data/flavor_labels_ja.dart';
import '../models/flavor_category.dart';
import '../services/flavor_wheel_prefs.dart';

/// よく使うフレーバー：自分の抽出記録に出てくるフレーバーだけを、大分類ごとにまとめて表示する。
/// ホイールは全項目を並べるので文字が小さくなるが、ここは使ったものだけなので大きく読める。
/// よく使うものほど文字を大きくする。
class MyFlavorsScreen extends StatefulWidget {
  final List<FlavorCategory> categories;

  const MyFlavorsScreen({super.key, required this.categories});

  @override
  State<MyFlavorsScreen> createState() => _MyFlavorsScreenState();
}

class _Entry {
  final String name;
  int count = 0;
  _Entry(this.name);
}

class _Group {
  final String title;
  final Color color;
  final Map<String, _Entry> entries = {};
  _Group(this.title, this.color);
  int get total => entries.values.fold(0, (a, e) => a + e.count);
}

class _MyFlavorsScreenState extends State<MyFlavorsScreen> {
  bool _loading = true;
  List<_Group> _groups = [];
  int _sessions = 0;

  bool get _ja => FlavorWheelPrefs.japaneseLabels.value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await SessionStorage.loadSessions();

    // ホイールの名前（英語・日本語、大中小すべて）→ 大分類
    final where = <String, FlavorCategory>{};
    void put(String id, String name, FlavorCategory c) {
      where[name.toLowerCase()] = c;
      where[flavorLabel(id, name, japanese: true).toLowerCase()] = c;
    }

    for (final c in widget.categories) {
      put(c.id, c.name, c);
      for (final s in c.subCategories) {
        put(s.id, s.name, c);
        for (final i in s.items) {
          put(i.id, i.name, c);
        }
      }
    }
    final byCatName = {for (final c in widget.categories) c.name.toLowerCase(): c};

    final groups = <String, _Group>{};
    final other = _Group(_ja ? '分類なし' : 'Other', BrewColors.mocha);
    var used = 0;
    for (final s in sessions) {
      final tags = s.flavorNotes.isNotEmpty
          ? s.flavorNotes.map((t) => (t.name, t.categoryName)).toList()
          : (s.flavorNote ?? '')
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .map((e) => (e, null as String?))
              .toList();
      if (tags.isEmpty) continue;
      used++;
      for (final (name, catName) in tags) {
        final key = name.toLowerCase();
        final cat = where[key] ?? (catName == null ? null : byCatName[catName.toLowerCase()]);
        final g = cat == null
            ? other
            : groups.putIfAbsent(cat.id, () => _Group(flavorLabel(cat.id, cat.name, japanese: _ja), cat.color));
        g.entries.putIfAbsent(key, () => _Entry(name)).count++;
      }
    }

    // ホイールの並び順、最後に「分類なし」
    final ordered = <_Group>[
      for (final c in widget.categories)
        if (groups[c.id] != null) groups[c.id]!,
      if (other.entries.isNotEmpty) other,
    ];
    if (!mounted) return;
    setState(() {
      _groups = ordered;
      _sessions = used;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxCount = _groups
        .expand((g) => g.entries.values)
        .fold<int>(1, (a, e) => e.count > a ? e.count : a);
    return Scaffold(
      appBar: AppBar(
        title: Text('よく使うフレーバー',
            style: AppTheme.display(fontSize: 20, color: BrewColors.espresso)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('フレーバーを付けた抽出の記録がまだありません。\n保存画面で Flavor Notes を選ぶと、ここに集まります。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: BrewColors.mocha, height: 1.5)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Text('$_sessions 杯の記録から。文字が大きいほどよく出てきたフレーバーです。',
                        style: const TextStyle(color: BrewColors.mocha, fontSize: 12)),
                    const SizedBox(height: 12),
                    for (final g in _groups) _groupCard(g, maxCount),
                  ],
                ),
    );
  }

  Widget _groupCard(_Group g, int maxCount) {
    final entries = g.entries.values.toList()..sort((a, b) => b.count.compareTo(a.count));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 7, backgroundColor: g.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(g.title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                Text('${g.total} 回', style: const TextStyle(color: BrewColors.mocha, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final e in entries)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: g.color.withValues(alpha: 0.16),
                      border: Border.all(color: g.color.withValues(alpha: 0.45)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      e.count > 1 ? '${e.name}  ×${e.count}' : e.name,
                      style: TextStyle(
                        fontSize: 13 + 13 * (e.count - 1) / (maxCount > 1 ? maxCount - 1 : 1),
                        fontWeight: FontWeight.w600,
                        color: BrewColors.espresso,
                      ),
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
