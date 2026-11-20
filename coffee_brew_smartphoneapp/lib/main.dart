import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/scale/services/pip_service.dart';
import 'features/scale/widgets/mini_brew_view.dart';
import 'features/settings/services/app_prefs.dart';
import 'splash_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PipService.init();
  AppPrefs.load();
  // Androidのナビゲーションバー / ステータスバーをアプリの配色に揃える
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: BrewColors.espresso,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const CoffeeScaleApp());
}

class CoffeeScaleApp extends StatelessWidget {
  const CoffeeScaleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Brew Companion',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const SplashScreen(),
      // ほかのアプリを使っている間の小窓では、グラフだけを出す。
      // 元の画面は IndexedStack の中にそのまま残すので、計測や入力中の内容は消えない
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: PipService.inPip,
        builder: (context, pip, _) => IndexedStack(
          index: pip ? 1 : 0,
          sizing: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            const MiniBrewView(),
          ],
        ),
      ),
    );
  }
}
