import 'package:flutter/material.dart';

import 'features/flavor_wheel/screens/flavor_wheel_screen.dart';
import 'features/scale/screens/bean_inventory_screen.dart';
import 'features/scale/screens/main_screen.dart';
import 'features/settings/screens/settings_screen.dart';
import 'theme/app_theme.dart';

/// 下部ナビゲーション（ホーム / 豆 / フレーバー / 設定）を持つアプリの外枠。
///
/// IndexedStack で各タブの状態を保持するので、タブを切り替えても
/// ホームのBLE接続・計測は途切れない。
/// 計測画面のグラフを潰さないよう、ナビゲーションバーは低め（62px）にしている。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _tabs = <Widget>[
    MainScreen(),
    BeanInventoryScreen(),
    FlavorWheelScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: BrewColors.oat)),
        ),
        child: NavigationBar(
          height: 62,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: BrewColors.crema,
          surfaceTintColor: Colors.transparent,
          indicatorColor: BrewColors.oat,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.scale_outlined, color: BrewColors.mocha),
              selectedIcon: Icon(Icons.scale, color: BrewColors.espresso),
              label: 'ホーム',
            ),
            NavigationDestination(
              icon: Icon(Icons.coffee_outlined, color: BrewColors.mocha),
              selectedIcon: Icon(Icons.coffee, color: BrewColors.espresso),
              label: '豆',
            ),
            NavigationDestination(
              icon: Icon(Icons.donut_large, color: BrewColors.mocha),
              selectedIcon: Icon(Icons.donut_large, color: BrewColors.espresso),
              label: 'フレーバー',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, color: BrewColors.mocha),
              selectedIcon: Icon(Icons.settings, color: BrewColors.espresso),
              label: '設定',
            ),
          ],
        ),
      ),
    );
  }
}
