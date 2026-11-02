import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_screen.dart';
import 'light_screen.dart';
import 'platform.dart';

const kBg = Color(0xFF17120F);
const kCard = Color(0xFF241C17);
const kAccent = Color(0xFFD9A066);
const kText = Color(0xFFF1E8DF);
const kSub = Color(0xFFA8998C);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Prefs.load();
  runApp(const CoffeeLabApp());
}

class CoffeeLabApp extends StatelessWidget {
  const CoffeeLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coffee Lab',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(
          primary: kAccent,
          secondary: kAccent,
          surface: kCard,
          onPrimary: Color(0xFF1B140F),
          onSurface: kText,
        ),
        useMaterial3: true,
      ),
      home: const ModeScreen(),
    );
  }
}

/// 起動画面：このスマホを「撮影」と「ライト」のどちらに使うか選ぶ。
class ModeScreen extends StatelessWidget {
  const ModeScreen({super.key});

  void _open(BuildContext context, String mode) {
    Prefs.set('mode', mode);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => mode == 'camera' ? const CameraScreen() : const LightScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final last = Prefs.get<String>('mode');
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Coffee Lab',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: kText)),
              const SizedBox(height: 6),
              const Text('このスマホの使い方を選んでください',
                  style: TextStyle(fontSize: 14, color: kSub)),
              const SizedBox(height: 24),
              _ModeCard(
                icon: Icons.photo_camera_outlined,
                title: '撮影',
                body: '挽き目・焙煎度の写真を撮って PC に送ります。\n送るとすぐ PC が解析して結果が返ってきます。',
                highlighted: last == 'camera',
                onTap: () => _open(context, 'camera'),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                icon: Icons.light_mode_outlined,
                title: 'ライト',
                body: '画面全体を指定の色・模様で光らせます（箱の下に置く背景用）。\n同じ Wi-Fi の「撮影」から色を変えられます。',
                highlighted: last == 'light',
                onTap: () => _open(context, 'light'),
              ),
              const Spacer(),
              const Text('PC 側で「撮影受信サーバー.bat」を起動しておくと、撮影した写真が自動で PC に保存されます。',
                  style: TextStyle(fontSize: 12, color: kSub, height: 1.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool highlighted;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: highlighted ? kAccent : Colors.transparent, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(icon, size: 36, color: kAccent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: kText)),
                    const SizedBox(height: 4),
                    Text(body, style: const TextStyle(fontSize: 13, color: kSub, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
