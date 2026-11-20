import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../services/live_brew.dart';
import 'weight_graph.dart';

/// 小窓（ピクチャーインピクチャー）で出す表示：重さ・経過時間とグラフだけ。
class MiniBrewView extends StatelessWidget {
  const MiniBrewView({super.key});

  @override
  Widget build(BuildContext context) {
    final live = LiveBrew.instance;
    return Material(
      color: BrewColors.foam,
      child: AnimatedBuilder(
        animation: live,
        builder: (context, _) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      '${live.weightG.toStringAsFixed(1)} g',
                      style: AppTheme.mono(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: BrewColors.espresso,
                      ),
                    ),
                    const Spacer(),
                    if (!live.connected)
                      Text(
                        '未接続',
                        style: AppTheme.mono(fontSize: 11, color: BrewColors.terracotta),
                      )
                    else
                      Text(
                        live.elapsed,
                        style: AppTheme.mono(
                          fontSize: 13,
                          color: live.measuring ? BrewColors.caramel : BrewColors.mocha,
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: WeightGraph(
                    points: live.points,
                    recipe: live.recipe,
                    ghostPoints: live.ghostPoints,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
