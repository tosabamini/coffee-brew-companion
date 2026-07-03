import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/brew_widgets.dart';
import '../models/coffee_session.dart';
import '../services/csv_export_service.dart';
import '../services/session_storage.dart';
import 'session_detail_screen.dart';
import 'stats_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<CoffeeSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sessions = await SessionStorage.loadSessions();
    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('記録を削除'),
        content: const Text('このセッションを削除しますか？この操作は元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: BrewColors.terracotta),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SessionStorage.deleteSession(id);
    await _load();
  }

  Future<void> _exportCsv() async {
    try {
      await CsvExportService.shareSessionsSummary(_sessions);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSVエクスポートに失敗しました: $e')),
      );
    }
  }

  String _titleFor(CoffeeSession session) {
    if (session.beanName != null && session.beanName!.isNotEmpty) {
      return session.beanName!;
    }
    return 'Untitled Session';
  }

  String _dateFor(CoffeeSession session) {
    final date = session.createdAt;
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Brew Journal',
          style: AppTheme.display(
            fontSize: 22,
            fontStyle: FontStyle.italic,
            color: BrewColors.espresso,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _sessions.isEmpty
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StatsScreen(sessions: _sessions),
                      ),
                    );
                  },
            icon: const Icon(Icons.insights),
            tooltip: '統計',
          ),
          IconButton(
            onPressed: _sessions.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.ios_share),
            tooltip: 'CSVエクスポート',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _sessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    return FadeSlideIn(
                      delay: Duration(milliseconds: 40 * (index < 8 ? index : 8)),
                      child: _buildSessionCard(session),
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
            Icons.menu_book_outlined,
            size: 44,
            color: BrewColors.mocha.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'まだ記録がありません',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: BrewColors.mocha,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '抽出を計測して、最初の1杯を記録しましょう',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: BrewColors.mocha.withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(CoffeeSession session) {
    final roast = (session.roastLevel == null || session.roastLevel!.isEmpty)
        ? null
        : session.roastLevel!;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SessionDetailScreen(sessionId: session.id),
            ),
          );
          await _load();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [BrewColors.roastLight, BrewColors.espresso],
                  ),
                ),
                child: const Icon(
                  Icons.coffee,
                  size: 20,
                  color: BrewColors.creamText,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _titleFor(session),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: BrewColors.espresso,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _dateFor(session),
                      style: AppTheme.mono(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: BrewColors.mocha.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (roast != null) ...[
                          _miniBadge(roast, BrewColors.caramel),
                          const SizedBox(width: 6),
                        ],
                        _miniBadge(
                          '${session.maxWeight.toStringAsFixed(1)} g',
                          BrewColors.mocha,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: BrewColors.mocha.withValues(alpha: 0.6),
                onPressed: () => _delete(session.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
      ),
    );
  }
}
