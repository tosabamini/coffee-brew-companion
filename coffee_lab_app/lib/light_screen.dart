import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'light_link.dart';
import 'main.dart';
import 'platform.dart';

/// 背景ライト：画面全体を指定の色・模様で光らせる。タップで設定を出す／隠す。
/// 同じ Wi-Fi のカメラ（撮影モード）から色・模様を変えられる。
class LightScreen extends StatefulWidget {
  const LightScreen({super.key});

  @override
  State<LightScreen> createState() => _LightScreenState();
}

class _LightScreenState extends State<LightScreen> {
  LightState s = const LightState();
  bool panel = true;
  Map<String, dynamic> display = {};
  String? myIp;
  DateTime? lastRemote;
  late final LightServer server = LightServer(
    getState: () => s,
    onSet: _remoteSet,
    displayInfo: () => display,
    onVibrate: () {
      if (mounted) setState(() => lastRemote = DateTime.now());
    },
    onStatus: () {
      if (mounted) setState(() {});
    },
  );

  @override
  void initState() {
    super.initState();
    final saved = Prefs.get<Map>('light_state');
    if (saved != null) s = LightState.fromJson(Map<String, dynamic>.from(saved));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Screen.keepOn(true);
    Screen.setBrightness(s.brightness);
    _init();
  }

  Future<void> _init() async {
    final d = await Screen.displayInfo();
    String? ip;
    try {
      for (final nif in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in nif.addresses) {
          if (!a.isLoopback) ip ??= a.address;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      display = d;
      myIp = ip;
    });
    await server.start(); // Bluetooth の許可を求める画面が出ることがある
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Screen.vibrateCancel();
    server.stop();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Screen.keepOn(false);
    Screen.setBrightness(-1);
    super.dispose();
  }

  void _apply(LightState n, {bool save = true}) {
    final brightnessChanged = n.brightness != s.brightness;
    setState(() => s = n);
    if (brightnessChanged) Screen.setBrightness(n.brightness);
    if (save) Prefs.set('light_state', n.toJson());
  }

  void _remoteSet(LightState n) {
    if (!mounted) return;
    lastRemote = DateTime.now();
    _apply(n);
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return Scaffold(
      backgroundColor: Color.fromARGB(255, s.r, s.g, s.b),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => panel = !panel),
        child: Stack(
          children: [
            if (s.mode == 'grid')
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(
                    pxPerMmX: _pxPerMm('xdpi', dpr),
                    pxPerMmY: _pxPerMm('ydpi', dpr),
                    gridMm: s.gridMm,
                    lineMm: s.lineMm,
                  ),
                ),
              )
            else
              const SizedBox.expand(),
            if (panel) Align(alignment: Alignment.bottomCenter, child: _panel(context)),
          ],
        ),
      ),
    );
  }

  /// 論理ピクセル / mm。端末の値が取れないときは 160dpi 相当で仮に描く。
  double _pxPerMm(String key, double dpr) {
    final dpi = (display[key] as num?)?.toDouble() ?? 160 * dpr;
    return dpi / 25.4 / dpr;
  }

  Widget _panel(BuildContext context) {
    final bt = server.bleStatus;
    final btText = switch (bt) {
      'connected' => 'Bluetooth：カメラとつながっています',
      'advertising' || 'starting' || 'ok' => 'Bluetooth：カメラからの接続を待っています',
      'off' => 'Bluetooth：オフです（オンにして「やり直す」を押してください）',
      'denied' => 'Bluetooth：許可されていません（アプリの権限で「付近のデバイス」を許可してください）',
      'unsupported' => 'Bluetooth：この端末では使えません（Wi-Fi でつなぎます）',
      _ => 'Bluetooth：開始できませんでした（$bt）',
    };
    final btRetry = !(bt == 'connected' || bt == 'advertising' || bt == 'starting' || bt == 'ok' || bt == 'unsupported');
    final wifiText = server.running
        ? 'Wi-Fi：予備として待っています（このスマホ：${myIp ?? '?'}）'
        : 'Wi-Fi：使えません';
    final remoteText = '$btText\n$wifiText${lastRemote != null ? '\n操作を受けました' : ''}';
    return GestureDetector(
      onTap: () {}, // パネルの中のタップでは閉じない
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        decoration: BoxDecoration(color: kCard.withValues(alpha: 0.96), borderRadius: BorderRadius.circular(14)),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: kText),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '戻る',
                ),
                Expanded(child: Text('ライト  ${s.label}', style: const TextStyle(color: kText, fontSize: 14))),
                TextButton(onPressed: () => setState(() => panel = false), child: const Text('隠す')),
              ]),
              Row(children: [
                Expanded(child: Text(remoteText, style: const TextStyle(color: kSub, fontSize: 11, height: 1.4))),
                if (btRetry) TextButton(onPressed: server.startBle, child: const Text('やり直す')),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in kLightPresets)
                  _swatch(p.name, Color.fromARGB(255, p.r, p.g, p.b), p.r == s.r && p.g == s.g && p.b == s.b,
                      () => _apply(s.copyWith(r: p.r, g: p.g, b: p.b))),
              ]),
              const SizedBox(height: 8),
              _slider('R', s.r, const Color(0xFFE57373), (v) => _apply(s.copyWith(r: v), save: false)),
              _slider('G', s.g, const Color(0xFF81C784), (v) => _apply(s.copyWith(g: v), save: false)),
              _slider('B', s.b, const Color(0xFF64B5F6), (v) => _apply(s.copyWith(b: v), save: false)),
              Row(children: [
                const SizedBox(width: 44, child: Text('明るさ', style: TextStyle(color: kSub, fontSize: 12))),
                Expanded(
                  child: Slider(
                    value: s.brightness,
                    min: 0.05,
                    max: 1.0,
                    onChanged: (v) => _apply(s.copyWith(brightness: v), save: false),
                    onChangeEnd: (_) => _apply(s),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text('${(s.brightness * 100).round()}%',
                      textAlign: TextAlign.right, style: const TextStyle(color: kText, fontSize: 12)),
                ),
              ]),
              Row(children: [
                const SizedBox(width: 44, child: Text('模様', style: TextStyle(color: kSub, fontSize: 12))),
                ChoiceChip(
                  label: const Text('無地'),
                  selected: s.mode == 'solid',
                  onSelected: (_) => _apply(s.copyWith(mode: 'solid')),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text('方眼 ${s.gridMm.toStringAsFixed(0)}mm'),
                  selected: s.mode == 'grid',
                  onSelected: (_) => _apply(s.copyWith(mode: 'grid')),
                ),
              ]),
              const SizedBox(height: 4),
              Text(
                  '画面のどこかをタップすると、この設定が消えて全面が光ります。測るときは明るさ 100% のままがおすすめです。'
                  '${display['xdpi'] == null ? '\n（この端末の画面の細かさが分からないため、方眼の寸法は目安です）' : ''}',
                  style: const TextStyle(color: kSub, fontSize: 11, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(String name, Color color, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? kAccent : const Color(0x33FFFFFF), width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: const Color(0x55FFFFFF)),
            ),
          ),
          const SizedBox(width: 6),
          Text(name, style: const TextStyle(color: kText, fontSize: 13)),
        ]),
      ),
    );
  }

  Widget _slider(String label, int value, Color color, ValueChanged<int> onChanged) {
    return Row(children: [
      SizedBox(width: 44, child: Text(label, style: TextStyle(color: color, fontSize: 13))),
      Expanded(
        child: Slider(
          value: value.toDouble(),
          min: 0,
          max: 255,
          divisions: 255,
          activeColor: color,
          onChanged: (v) => onChanged(v.round()),
          onChangeEnd: (_) => _apply(s),
        ),
      ),
      SizedBox(
        width: 40,
        child: Text('$value', textAlign: TextAlign.right, style: const TextStyle(color: kText, fontSize: 12)),
      ),
    ]);
  }
}

/// 実寸 gridMm ごとの黒い線（画面の中央から外へ）。
class _GridPainter extends CustomPainter {
  final double pxPerMmX, pxPerMmY, gridMm, lineMm;
  _GridPainter({required this.pxPerMmX, required this.pxPerMmY, required this.gridMm, required this.lineMm});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    final stepX = gridMm * pxPerMmX, stepY = gridMm * pxPerMmY;
    final wX = (lineMm * pxPerMmX).clamp(1.0, 50.0), wY = (lineMm * pxPerMmY).clamp(1.0, 50.0);
    final cx = size.width / 2, cy = size.height / 2;
    for (var k = 0; cx - k * stepX >= -stepX; k++) {
      for (final x in {cx + k * stepX, cx - k * stepX}) {
        canvas.drawRect(Rect.fromLTWH(x - wX / 2, 0, wX, size.height), paint);
      }
    }
    for (var k = 0; cy - k * stepY >= -stepY; k++) {
      for (final y in {cy + k * stepY, cy - k * stepY}) {
        canvas.drawRect(Rect.fromLTWH(0, y - wY / 2, size.width, wY), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) =>
      o.pxPerMmX != pxPerMmX || o.pxPerMmY != pxPerMmY || o.gridMm != gridMm || o.lineMm != lineMm;
}
