import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/brew_widgets.dart';
import '../models/coffee_session.dart';

/// 抽出記録の統計ダッシュボード
class StatsScreen extends StatelessWidget {
  final List<CoffeeSession> sessions;

  const StatsScreen({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final total = sessions.length;
    final thisMonth = sessions
        .where((s) =>
            s.createdAt.year == now.year && s.createdAt.month == now.month)
        .length;

    double totalDose = 0;
    for (final s in sessions) {
      totalDose += s.doseG ?? 0;
    }

    final durations = sessions
        .where((s) => s.points.isNotEmpty)
        .map((s) => s.durationSec)
        .toList();
    final avgDuration = durations.isEmpty
        ? null
        : durations.reduce((a, b) => a + b) / durations.length;

    final ratios =
        sessions.map((s) => s.brewRatio).whereType<double>().toList();
    final avgRatio =
        ratios.isEmpty ? null : ratios.reduce((a, b) => a + b) / ratios.length;

    final eys = sessions
        .map((s) => s.extractionYieldPercent)
        .whereType<double>()
        .toList();
    final avgEy =
        eys.isEmpty ? null : eys.reduce((a, b) => a + b) / eys.length;

    final topBean = _mostFrequent(sessions
        .map((s) => s.beanName)
        .whereType<String>()
        .where((n) => n.trim().isNotEmpty));

    final weeklyCounts = _weeklyCounts(now);
    final roastCounts = _frequencyMap(sessions
        .map((s) => s.roastLevel)
        .whereType<String>()
        .where((r) => r.trim().isNotEmpty));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Brew Stats',
          style: AppTheme.display(
            fontSize: 22,
            fontStyle: FontStyle.italic,
            color: BrewColors.espresso,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          FadeSlideIn(child: _buildHeroCard(total, thisMonth, totalDose)),
          const SizedBox(height: 14),
          FadeSlideIn(
            delay: const Duration(milliseconds: 60),
            child: Row(
              children: [
                Expanded(
                  child: _statTile(
                    context,
                    icon: Icons.timer_outlined,
                    label: '平均抽出時間',
                    value: avgDuration == null
                        ? '—'
                        : _formatSec(avgDuration.round()),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statTile(
                    context,
                    icon: Icons.balance,
                    label: '平均レシオ',
                    value: avgRatio == null
                        ? '—'
                        : '1:${avgRatio.toStringAsFixed(1)}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FadeSlideIn(
            delay: const Duration(milliseconds: 120),
            child: Row(
              children: [
                Expanded(
                  child: _statTile(
                    context,
                    icon: Icons.science_outlined,
                    label: '平均収率 (EY)',
                    value:
                        avgEy == null ? '—' : '${avgEy.toStringAsFixed(1)} %',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statTile(
                    context,
                    icon: Icons.favorite_outline,
                    label: 'よく淹れる豆',
                    value: topBean ?? '—',
                    isSmallValue: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FadeSlideIn(
            delay: const Duration(milliseconds: 180),
            child: _buildWeeklyChart(context, weeklyCounts, now),
          ),
          if (roastCounts.isNotEmpty) ...[
            const SizedBox(height: 14),
            FadeSlideIn(
              delay: const Duration(milliseconds: 240),
              child: _buildRoastDistribution(context, roastCounts),
            ),
          ],
        ],
      ),
    );
  }

  // --- 集計ヘルパー ---

  String? _mostFrequent(Iterable<String> values) {
    final map = _frequencyMap(values);
    if (map.isEmpty) return null;
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  Map<String, int> _frequencyMap(Iterable<String> values) {
    final map = <String, int>{};
    for (final v in values) {
      map[v] = (map[v] ?? 0) + 1;
    }
    return map;
  }

  /// 直近8週間の週別セッション数（古い週 → 今週）
  List<int> _weeklyCounts(DateTime now) {
    // 今週の月曜0時を基準にする
    final thisWeekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final counts = List<int>.filled(8, 0);
    for (final s in sessions) {
      final diffDays = thisWeekStart.difference(s.createdAt).inDays;
      // diffDays < 0 なら今週、0〜6 なら1週前…
      final weeksAgo = diffDays < 0 ? 0 : diffDays ~/ 7 + 1;
      if (weeksAgo <= 7) {
        counts[7 - weeksAgo] += 1;
      }
    }
    return counts;
  }

  String _formatSec(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  // --- ウィジェット ---

  Widget _buildHeroCard(int total, int thisMonth, double totalDose) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BrewColors.roastLight,
            BrewColors.roast,
            BrewColors.espresso
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: BrewColors.espresso.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _heroStat('TOTAL BREWS', '$total', suffix: '杯'),
          ),
          Container(
            width: 1,
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: BrewColors.creamText.withValues(alpha: 0.14),
          ),
          Expanded(
            child: _heroStat('THIS MONTH', '$thisMonth', suffix: '杯'),
          ),
          Container(
            width: 1,
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: BrewColors.creamText.withValues(alpha: 0.14),
          ),
          Expanded(
            child: _heroStat(
              'BEANS USED',
              totalDose <= 0 ? '—' : totalDose.toStringAsFixed(0),
              suffix: totalDose <= 0 ? null : 'g',
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value, {String? suffix}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              style: AppTheme.overline(
                  color: BrewColors.creamTextDim, fontSize: 9)),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style:
                      AppTheme.mono(fontSize: 26, color: BrewColors.creamText)),
              if (suffix != null) ...[
                const SizedBox(width: 2),
                Text(suffix,
                    style: AppTheme.mono(
                        fontSize: 12, color: BrewColors.creamTextDim)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _statTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool isSmallValue = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: BrewColors.caramel),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: BrewColors.mocha,
                          fontSize: 11,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: isSmallValue
                  ? Text(
                      value,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: BrewColors.espresso,
                          ),
                    )
                  : Text(
                      value,
                      style: AppTheme.mono(
                          fontSize: 22, color: BrewColors.espresso),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyChart(
      BuildContext context, List<int> counts, DateTime now) {
    final maxCount =
        counts.fold<int>(0, (prev, c) => c > prev ? c : prev);
    final thisWeekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Weekly Brews'),
            const SizedBox(height: 14),
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int i = 0; i < counts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _weekBar(
                        context,
                        count: counts[i],
                        maxCount: maxCount,
                        weekStart: thisWeekStart
                            .subtract(Duration(days: 7 * (7 - i))),
                        isCurrentWeek: i == counts.length - 1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekBar(
    BuildContext context, {
    required int count,
    required int maxCount,
    required DateTime weekStart,
    required bool isCurrentWeek,
  }) {
    const double maxBarHeight = 64;
    final barHeight =
        maxCount == 0 ? 3.0 : (count / maxCount) * maxBarHeight + 3.0;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          '$count',
          style: AppTheme.mono(
            fontSize: 11,
            color: count > 0
                ? BrewColors.espresso
                : BrewColors.mocha.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 4),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: barHeight),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) => Container(
            height: value,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: isCurrentWeek
                    ? [BrewColors.caramel, BrewColors.amber]
                    : [
                        BrewColors.caramel.withValues(alpha: 0.45),
                        BrewColors.caramel.withValues(alpha: 0.3),
                      ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${weekStart.month}/${weekStart.day}',
          style: AppTheme.mono(
            fontSize: 9,
            fontWeight: FontWeight.w400,
            color: BrewColors.mocha.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildRoastDistribution(
      BuildContext context, Map<String, int> roastCounts) {
    final sorted = roastCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(5).toList();
    final maxCount = top.first.value;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionLabel('Roast Levels'),
            const SizedBox(height: 12),
            for (final entry in top) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        entry.key,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: BrewColors.espresso),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: LinearProgressIndicator(
                          value: entry.value / maxCount,
                          minHeight: 8,
                          backgroundColor: BrewColors.oat.withValues(alpha: 0.5),
                          color: BrewColors.caramel,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${entry.value}',
                      style: AppTheme.mono(
                          fontSize: 12, color: BrewColors.mocha),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
