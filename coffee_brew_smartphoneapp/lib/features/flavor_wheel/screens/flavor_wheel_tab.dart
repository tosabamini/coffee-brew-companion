import 'package:flutter/material.dart';

import '../services/flavor_wheel_prefs.dart';
import 'flavor_wheel_screen.dart';
import 'flavor_wheel_v2_screen.dart';

/// フレーバータブの中身。設定（FlavorWheelPrefs.useLegacy）で新旧のデザインを切り替える。
/// 旧デザイン（FlavorWheelScreen）は変更せずに残してあるので、いつでも元に戻せる。
class FlavorWheelTab extends StatefulWidget {
  const FlavorWheelTab({super.key});

  @override
  State<FlavorWheelTab> createState() => _FlavorWheelTabState();
}

class _FlavorWheelTabState extends State<FlavorWheelTab> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    FlavorWheelPrefs.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ValueListenableBuilder<bool>(
      valueListenable: FlavorWheelPrefs.useLegacy,
      builder: (_, legacy, __) => legacy
          ? const FlavorWheelScreen(key: ValueKey('legacy'))
          : const FlavorWheelV2Screen(key: ValueKey('v2')),
    );
  }
}
