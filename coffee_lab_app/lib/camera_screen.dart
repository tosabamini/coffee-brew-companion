import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'lab_client.dart';
import 'ble_link.dart';
import 'light_link.dart';
import 'main.dart';
import 'platform.dart';

/// 撮影：撮る → PC に送る → PC が解析した結果を表示。
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _Pending {
  final String kind, folder, group;
  final Uint8List jpeg;
  final Map<String, dynamic> meta;
  _Pending(this.kind, this.folder, this.group, this.jpeg, this.meta);
}

class _Last {
  final String kind, folder, file;
  final Map<String, dynamic>? result;
  final String? error;
  _Last(this.kind, this.folder, this.file, this.result, this.error);
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  // カメラ
  List<CameraDescription> _cams = [];
  int _camIndex = 0;
  CameraController? _ctrl;
  String? _camError;
  double _zoom = 1, _zoomMin = 1, _zoomMax = 1;
  double _ev = 0, _evMin = 0, _evMax = 0;
  bool _afLocked = false, _aeLocked = false, _torch = false;
  Offset? _focusMark;

  // PC
  late final LabClient _client = LabClient(Prefs.get<String>('pc_address'));
  bool _connected = false;
  bool _searching = false;
  Map<String, Map<String, int>> _folders = {};

  // ライト（2台目のスマホ）
  late final LightClient _light = LightClient(Prefs.get<String>('light_address'));
  bool _lightOk = false;
  bool _lightSearching = false;

  // 名前
  String _kind = Prefs.get<String>('kind') ?? 'grind';
  String _folder = '';
  String _group = '';

  // 撮影・送信
  bool _busy = false;
  String? _status;
  _Last? _last;
  final List<_Pending> _pending = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Screen.keepOn(true);
    _loadNames();
    _initCameras();
    _connect();
    _connectLight();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_light.viaBle) BleLink.disconnect();
    Screen.keepOn(false);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (state == AppLifecycleState.paused) {
      if (c != null) {
        _ctrl = null;
        c.dispose();
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_ctrl == null && _cams.isNotEmpty) _openCamera(_camIndex);
      if (!_connected) _connect();
      if (!_lightOk) _connectLight();
    }
  }

  // ───────── 名前 ─────────

  void _loadNames() {
    _folder = Prefs.get<String>('folder_$_kind') ??
        (_kind == 'grind' ? 'bg1_white_paper' : 'roast_test');
    _group = Prefs.get<String>('group_$_kind') ?? (_kind == 'grind' ? 'dial10' : 'medium');
  }

  void _setKind(String k) {
    if (k == _kind) return;
    setState(() {
      _kind = k;
      _loadNames();
      _folders = {};
    });
    Prefs.set('kind', k);
    _refreshFolders();
  }

  void _setFolder(String f) {
    setState(() => _folder = f);
    Prefs.set('folder_$_kind', f);
  }

  void _setGroup(String g) {
    setState(() => _group = g);
    Prefs.set('group_$_kind', g);
  }

  /// 条件名の末尾の数字を増減する（dial12 → dial13）
  void _bumpGroup(int d) {
    final m = RegExp(r'^(.*?)(\d+)$').firstMatch(_group);
    if (m == null) {
      _setGroup('$_group${d > 0 ? 1 : 0}');
      return;
    }
    final digits = m.group(2)!;
    final n = (int.parse(digits) + d).clamp(0, 999999);
    _setGroup('${m.group(1)}${n.toString().padLeft(digits.length, '0')}');
  }

  int get _countInGroup => _folders[_folder]?[_group] ?? 0;

  // ───────── PC ─────────

  Future<void> _connect() async {
    if (_searching) return;
    setState(() {
      _searching = true;
      _status = 'PC を探しています…';
    });
    var ok = await _client.ping();
    if (!ok) {
      final found = await LabClient.discover();
      if (found != null) {
        _client.address = found;
        ok = await _client.ping();
        if (ok) Prefs.set('pc_address', found);
      }
    }
    if (!mounted) return;
    setState(() {
      _searching = false;
      _connected = ok;
      _status = ok ? null : 'PC が見つかりません（PC で撮影受信サーバーを起動してください）';
    });
    if (ok) {
      await _refreshFolders();
      _flushPending();
    }
  }

  Future<void> _refreshFolders() async {
    if (!_connected) return;
    try {
      final f = await _client.folders(_kind);
      if (mounted) setState(() => _folders = f);
    } catch (_) {}
  }

  Future<void> _editAddress() async {
    final ctl = TextEditingController(text: _client.address ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PC のアドレス'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('撮影受信サーバーの画面に出ているアドレスを入力してください（例：192.168.1.23:47130）。',
              style: TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          TextField(controller: ctl, keyboardType: TextInputType.url, autofocus: true),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, '__search'), child: const Text('自動で探す')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('つなぐ')),
        ],
      ),
    );
    if (v == null) return;
    if (v != '__search' && v.isNotEmpty) {
      _client.address = v;
      Prefs.set('pc_address', v);
    }
    _connected = false;
    _connect();
  }

  // ───────── カメラ ─────────

  Future<void> _initCameras() async {
    try {
      final all = await availableCameras();
      _cams = all.where((c) => c.lensDirection == CameraLensDirection.back).toList();
      if (_cams.isEmpty) _cams = all;
      if (_cams.isEmpty) {
        setState(() => _camError = 'カメラが見つかりません');
        return;
      }
      _camIndex = (Prefs.get<num>('cam_index') ?? 0).toInt().clamp(0, _cams.length - 1);
      await _openCamera(_camIndex);
    } catch (e) {
      setState(() => _camError = 'カメラを開けません：$e');
    }
  }

  Future<void> _openCamera(int index) async {
    final old = _ctrl;
    _ctrl = null;
    if (mounted) setState(() {});
    await old?.dispose();
    final c = CameraController(_cams[index], ResolutionPreset.max, enableAudio: false);
    try {
      await c.initialize();
      _zoomMin = await c.getMinZoomLevel();
      _zoomMax = await c.getMaxZoomLevel();
      _evMin = await c.getMinExposureOffset();
      _evMax = await c.getMaxExposureOffset();
      final z = (Prefs.get<num>('zoom') ?? 1.0).toDouble().clamp(_zoomMin, _zoomMax);
      _zoom = z;
      await c.setZoomLevel(z);
      _ev = (Prefs.get<num>('ev') ?? 0.0).toDouble().clamp(_evMin, _evMax);
      if (_ev != 0) await c.setExposureOffset(_ev);
      await c.setFlashMode(_torch ? FlashMode.torch : FlashMode.off);
      _afLocked = false;
      _aeLocked = false;
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _ctrl = c;
        _camIndex = index;
        _camError = null;
      });
    } on CameraException catch (e) {
      await c.dispose();
      if (mounted) {
        setState(() => _camError = e.code == 'CameraAccessDenied'
            ? 'カメラの使用が許可されていません。設定アプリで Coffee Lab のカメラを許可してください。'
            : 'カメラを開けません：${e.description ?? e.code}');
      }
    } catch (e) {
      await c.dispose();
      if (mounted) setState(() => _camError = 'カメラを開けません：$e');
    }
  }

  Future<void> _switchCamera() async {
    if (_cams.length < 2) return;
    final next = (_camIndex + 1) % _cams.length;
    Prefs.set('cam_index', next);
    await _openCamera(next);
    _toast('カメラ ${next + 1}/${_cams.length}');
  }

  Future<void> _tapFocus(TapDownDetails d, BoxConstraints box) async {
    final c = _ctrl;
    if (c == null) return;
    if (_afLocked) {
      _toast('ピント固定中です（「ピント固定」を外すと合わせ直せます）');
      return;
    }
    final p = Offset(d.localPosition.dx / box.maxWidth, d.localPosition.dy / box.maxHeight);
    setState(() => _focusMark = d.localPosition);
    try {
      await c.setFocusPoint(p);
      if (!_aeLocked) await c.setExposurePoint(p);
    } catch (_) {}
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _focusMark = null);
    });
  }

  Future<void> _toggleAf() async {
    final c = _ctrl;
    if (c == null) return;
    final v = !_afLocked;
    try {
      await c.setFocusMode(v ? FocusMode.locked : FocusMode.auto);
      setState(() => _afLocked = v);
    } catch (e) {
      _toast('ピント固定に対応していません');
    }
  }

  Future<void> _toggleAe() async {
    final c = _ctrl;
    if (c == null) return;
    final v = !_aeLocked;
    try {
      await c.setExposureMode(v ? ExposureMode.locked : ExposureMode.auto);
      setState(() => _aeLocked = v);
    } catch (e) {
      _toast('明るさ固定に対応していません');
    }
  }

  Future<void> _toggleTorch() async {
    final c = _ctrl;
    if (c == null) return;
    final v = !_torch;
    try {
      await c.setFlashMode(v ? FlashMode.torch : FlashMode.off);
      setState(() => _torch = v);
    } catch (e) {
      _toast('フラッシュを点けられません');
    }
  }

  // ───────── 撮影・送信 ─────────

  Future<Uint8List> _takeJpeg(CameraController c) async {
    final x = await c.takePicture();
    final bytes = await x.readAsBytes();
    try {
      await File(x.path).delete();
    } catch (_) {}
    return bytes;
  }

  Map<String, dynamic> _meta() => <String, dynamic>{
        'camera': '${_camIndex + 1}/${_cams.length} ${_cams[_camIndex].name}',
        'zoom': double.parse(_zoom.toStringAsFixed(2)),
        'exposure_offset': double.parse(_ev.toStringAsFixed(2)),
        'focus_locked': _afLocked,
        'exposure_locked': _aeLocked,
        'torch': _torch,
        'light': _lightOk ? _light.state?.toJson() : null,
        'taken': DateTime.now().toIso8601String(),
      };

  /// 撮って PC に送る。group を渡すとその条件名で送る（空のトレイは 'blank'）。
  Future<void> _shoot({String? group}) async {
    final c = _ctrl;
    if (c == null || _busy || c.value.isTakingPicture) return;
    final g = group ?? _group;
    if (g.trim().isEmpty || _folder.trim().isEmpty) {
      _toast('フォルダと条件名を決めてください');
      return;
    }
    setState(() {
      _busy = true;
      _status = '撮影中…';
    });
    try {
      final bytes = await _takeJpeg(c);
      await _upload(_Pending(_kind, _folder, g, bytes, _meta()));
    } catch (e) {
      _toast('撮影に失敗しました：$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (_status == '撮影中…') _status = null;
        });
      }
    }
  }

  // ───────── ライト（2台目のスマホ）との連携 ─────────

  Future<void> _connectLight({bool quiet = true}) async {
    if (_lightSearching) return;
    setState(() => _lightSearching = true);
    // まず Bluetooth、見つからなければ Wi-Fi で探す
    final ok = await _light.connect();
    if (ok && !_light.viaBle && _light.address != null) Prefs.set('light_address', _light.address);
    if (!mounted) return;
    setState(() {
      _lightSearching = false;
      _lightOk = ok;
    });
    if (!quiet) {
      final why = _light.bleError.isEmpty ? '' : bleReasonText(_light.bleError);
      _toast(!ok
          ? 'ライトにつながりません。Bluetooth：$why'
          : _light.viaBle
              ? 'ライトにつながりました（Bluetooth）'
              : 'Wi-Fi でつながりました（Bluetooth：$why）');
    }
  }

  Future<bool> _setLight(LightState s) async {
    try {
      await _light.set(s);
      if (mounted) setState(() => _lightOk = true);
      return true;
    } catch (_) {
      if (mounted) setState(() => _lightOk = false);
      _toast('ライトに届きませんでした');
      return false;
    }
  }

  /// 背景の色を順に変えながら撮る。写真は「screen_<色>」フォルダに入る。
  Future<void> _shootSequence(List<LightPreset> colors) async {
    final c = _ctrl;
    if (c == null || _busy || colors.isEmpty) return;
    if (_group.trim().isEmpty) {
      _toast('条件名を決めてください');
      return;
    }
    final before = _light.state;
    setState(() => _busy = true);
    var n = 0;
    try {
      for (final p in colors) {
        if (!mounted) break;
        setState(() => _status = '背景「${p.name}」で撮影中…（${n + 1}/${colors.length}）');
        final base = before ?? const LightState();
        if (!await _setLight(base.copyWith(mode: 'solid', r: p.r, g: p.g, b: p.b))) break;
        await Future.delayed(const Duration(milliseconds: 1200)); // 明るさの自動調整が落ち着くのを待つ
        final bytes = await _takeJpeg(c);
        final ok = await _upload(_Pending(_kind, 'screen_${p.key}', _group, bytes, _meta()));
        n++;
        if (!ok && !_connected) break;
      }
    } catch (e) {
      _toast('連続撮影を中断しました：$e');
    } finally {
      if (before != null) await _setLight(before);
      if (mounted) {
        setState(() {
          _busy = false;
          if (_status != null && _status!.startsWith('背景')) _status = null;
        });
        _toast('$n 枚撮りました（フォルダ：screen_<色>）');
        _refreshFolders();
      }
    }
  }

  /// ライトに実寸の方眼を出して撮り、1画素の大きさを PC で求める。
  Future<void> _calibrateScale() async {
    final c = _ctrl;
    if (c == null || _busy) return;
    if (!_connected) {
      _toast('PC につないでください（計算は PC でします）');
      return;
    }
    const gridMm = 5.0;
    final before = _light.state;
    setState(() {
      _busy = true;
      _status = 'ライトに方眼を出して撮っています…';
    });
    Map<String, dynamic>? res;
    String? err;
    try {
      final base = before ?? const LightState();
      if (await _setLight(base.copyWith(mode: 'grid', r: 255, g: 255, b: 255, gridMm: gridMm, lineMm: 0.3))) {
        await Future.delayed(const Duration(milliseconds: 1200));
        final bytes = await _takeJpeg(c);
        if (before != null) await _setLight(before);
        if (mounted) setState(() => _status = 'PC で方眼の間隔を測っています…');
        res = await _client.calibrateGrid(bytes, gridMm);
      } else {
        err = 'ライトにつながっていません';
      }
    } on LabException catch (e) {
      err = e.message;
    } catch (e) {
      err = '$e';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
    if (!mounted) return;
    final r = res;
    if (r == null) {
      _toast('大きさ合わせに失敗しました：${err ?? ''}');
      return;
    }
    final um = (r['um_per_px'] as num).toDouble();
    final cur = (r['current'] as num?)?.toDouble();
    final umX = (r['um_x'] as num).toDouble();
    final umY = (r['um_y'] as num).toDouble();
    final resid = (r['residual_px'] as num).toDouble();
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('大きさ合わせの結果'),
        content: Text('1画素 = ${um.toStringAsFixed(2)} µm\n'
            '（横 ${umX.toStringAsFixed(2)} / 縦 ${umY.toStringAsFixed(2)}、線の位置のずれ ${resid.toStringAsFixed(2)} 画素）\n'
            '今の設定：${cur?.toStringAsFixed(2) ?? '—'} µm\n\n'
            '方眼は、ライトのスマホが知らせる画面の細かさから描いています。粉を置く面（画面の上）で測った値です。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('使わない')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('この値を使う')),
        ],
      ),
    );
    if (yes == true) {
      try {
        await _client.saveScale(um);
        _toast('1画素 = ${um.toStringAsFixed(2)} µm にしました');
      } on LabException catch (e) {
        _toast('保存できませんでした：${e.message}');
      }
    }
  }

  Future<void> _openLightSheet() async {
    if (!_lightOk) await _connectLight(quiet: false);
    if (!mounted || !_lightOk) return;
    final selected = <String>{...(Prefs.get<List>('seq_colors') ?? const ['white', 'gray', 'lightbrown', 'brown']).cast<String>()};
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: kCard,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final s = _light.state ?? const LightState();
        Future<void> apply(LightState n) async {
          await _setLight(n);
          setSheet(() {});
        }

        return SafeArea(
          child: SingleChildScrollView(
           child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ライト：${s.label}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(
                  '${_light.linkName} でつながっています'
                  '${!_light.viaBle && _light.bleError.isNotEmpty ? '\nBluetooth：${bleReasonText(_light.bleError)}' : ''}',
                  style: const TextStyle(fontSize: 11, color: kSub)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in kLightPresets)
                  ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: Color.fromARGB(255, p.r, p.g, p.b), radius: 7),
                    label: Text(p.name),
                    selected: s.mode == 'solid' && s.r == p.r && s.g == p.g && s.b == p.b,
                    onSelected: (_) => apply(s.copyWith(mode: 'solid', r: p.r, g: p.g, b: p.b)),
                  ),
                ChoiceChip(
                  label: const Text('方眼 5mm'),
                  selected: s.mode == 'grid',
                  onSelected: (_) => apply(s.copyWith(mode: s.mode == 'grid' ? 'solid' : 'grid', gridMm: 5)),
                ),
              ]),
              Row(children: [
                const Text('明るさ', style: TextStyle(fontSize: 12, color: kSub)),
                Expanded(
                  child: Slider(
                    value: s.brightness,
                    min: 0.05,
                    max: 1,
                    onChanged: (v) {
                      _light.state = s.copyWith(brightness: v);
                      setSheet(() {});
                    },
                    onChangeEnd: (v) => apply(s.copyWith(brightness: v)),
                  ),
                ),
                Text('${(s.brightness * 100).round()}%', style: const TextStyle(fontSize: 12)),
              ]),
              const Divider(),
              const Text('背景を変えて連続撮影', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text('同じ粉を、選んだ背景の色で順に撮ります。写真は「screen_<色>」のフォルダに入ります。',
                  style: TextStyle(fontSize: 12, color: kSub)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in kLightPresets.where((p) => p.key != 'black'))
                  FilterChip(
                    label: Text(p.name),
                    selected: selected.contains(p.key),
                    onSelected: (v) => setSheet(() => v ? selected.add(p.key) : selected.remove(p.key)),
                  ),
              ]),
              const SizedBox(height: 6),
              FilledButton.icon(
                icon: const Icon(Icons.burst_mode_outlined),
                label: Text('${selected.length} 色で撮る'),
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        Prefs.set('seq_colors', selected.toList());
                        Navigator.pop(ctx);
                        _shootSequence(kLightPresets.where((p) => selected.contains(p.key)).toList());
                      },
              ),
              const Divider(),
              const Text('大きさ合わせ（方眼で自動）', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text('ライトに実寸 5mm の方眼を出して撮り、1画素が何 µm かを PC で求めます。粉を Redmi の画面に直接置くとき専用です（トレイを使うときは、トレイの上に硬貨を置いて合わせてください）。',
                  style: TextStyle(fontSize: 12, color: kSub)),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                icon: const Icon(Icons.straighten),
                label: const Text('大きさを合わせる'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _calibrateScale();
                },
              ),
            ]),
           ),
          ),
        );
      }),
    );
    if (mounted) setState(() {});
  }

  Future<bool> _upload(_Pending p) async {
    if (!mounted) {
      _pending.add(p);
      return false;
    }
    if (!_connected) {
      setState(() {
        _pending.add(p);
        _status = 'PC につながっていないので、スマホに一時保存しました';
      });
      return false;
    }
    setState(() => _status = '送信中…（PC で解析しています）');
    try {
      final d = await _client.upload(
          kind: p.kind, folder: p.folder, group: p.group, jpeg: p.jpeg, meta: p.meta);
      final file = d['file'] as String;
      final folder = d['folder'] as String;
      if (!mounted) return true;
      setState(() {
        _last = _Last(p.kind, folder, file, d['result'] as Map<String, dynamic>?, d['error'] as String?);
        _status = null;
        if (p.kind == _kind) {
          final g = _folders.putIfAbsent(folder, () => {});
          g[p.group] = (g[p.group] ?? 0) + 1;
        }
      });
      return true;
    } on LabException catch (e) {
      if (!mounted) {
        _pending.add(p);
        return false;
      }
      setState(() {
        _pending.add(p);
        _status = '送れませんでした（${e.message}）。スマホに一時保存しました';
        if (e.message.contains('つながりません') || e.message.contains('応答')) _connected = false;
      });
      return false;
    }
  }

  Future<void> _flushPending() async {
    if (_pending.isEmpty || !_connected) return;
    final list = List<_Pending>.from(_pending);
    _pending.clear();
    for (final p in list) {
      final ok = await _upload(p);
      if (!ok) break;
    }
  }

  Future<void> _undo() async {
    final l = _last;
    if (l == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('直前の写真を取り消しますか？'),
        content: Text('${l.folder}/${l.file} を PC の _trash フォルダへ移します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('取り消す')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _client.undo(l.kind, l.folder, l.file);
      setState(() => _last = null);
      _toast('取り消しました');
      _refreshFolders();
    } on LabException catch (e) {
      _toast('取り消せませんでした：${e.message}');
    }
  }

  Future<void> _report() async {
    setState(() => _status = 'PC でレポートを作っています…');
    try {
      await _client.report(_kind);
      _toast('PC のブラウザにレポートを開きました');
    } on LabException catch (e) {
      _toast('レポートを作れませんでした：${e.message}');
    } finally {
      if (mounted) setState(() => _status = null);
    }
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s), duration: Duration(seconds: s.length > 40 ? 6 : 2)));
  }

  // ───────── 名前の選択 ─────────

  Future<void> _pickFolder() async {
    final names = {..._folders.keys, _folder}.where((e) => e.isNotEmpty).toList()..sort();
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kCard,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(
              title: Text('保存するフォルダ', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('挽き目は背景の種類ごと、焙煎度は撮り方ごとに分けるのがおすすめです')),
          for (final n in names)
            ListTile(
              leading: Icon(n == _folder ? Icons.radio_button_checked : Icons.radio_button_off, color: kAccent),
              title: Text(n),
              subtitle: Text('${(_folders[n] ?? {}).values.fold<int>(0, (a, b) => a + b)} 枚'),
              onTap: () => Navigator.pop(ctx, n),
            ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined, color: kAccent),
            title: const Text('新しいフォルダ…'),
            onTap: () => Navigator.pop(ctx, '__new'),
          ),
        ]),
      ),
    );
    if (v == null) return;
    if (v == '__new') {
      final n = await _askText('新しいフォルダの名前', _kind == 'grind' ? '例：bg2_screen_backlight' : '例：top_light', '');
      if (n != null && n.isNotEmpty) _setFolder(n);
    } else {
      _setFolder(v);
    }
  }

  Future<void> _pickGroup() async {
    final existing = (_folders[_folder] ?? {}).keys.toList()..sort();
    final ctl = TextEditingController(text: _group);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('条件名'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              _kind == 'grind'
                  ? 'グラインダーの目盛りなど（例：dial12）。同じ条件名の写真はまとめて集計します。'
                  : '豆や焙煎度の名前（例：ethiopia_medium）。同じ条件名の写真はまとめて集計します。',
              style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          TextField(controller: ctl, autofocus: true),
          if (existing.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('このフォルダにある条件', style: TextStyle(fontSize: 12, color: kSub)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final g in existing)
                ActionChip(
                  label: Text('$g (${_folders[_folder]![g]})'),
                  onPressed: () => Navigator.pop(ctx, g),
                ),
            ]),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('決定')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) _setGroup(v);
  }

  Future<String?> _askText(String title, String hint, String initial) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('やめる')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('決定')),
        ],
      ),
    );
  }

  // ───────── 画面 ─────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: _preview()),
            _cameraControls(),
            _nameRow(),
            _bottom(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final pcText = _searching
        ? '探しています…'
        : _connected
            ? 'PC: ${_client.hostName ?? _client.address}'
            : 'PC 未接続';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
          Expanded(
            child: InkWell(
              onTap: _editAddress,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(children: [
                  Icon(Icons.circle, size: 10, color: _connected ? const Color(0xFF7BC67E) : const Color(0xFFE07A5F)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(pcText,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: kText)),
                  ),
                  if (_pending.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text('未送信 ${_pending.length}', style: const TextStyle(fontSize: 12, color: Color(0xFFE07A5F))),
                  ],
                ]),
              ),
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'grind', label: Text('挽き目')),
              ButtonSegment(value: 'roast', label: Text('焙煎度')),
            ],
            selected: {_kind},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => _setKind(s.first),
          ),
        ],
      ),
    );
  }

  Widget _preview() {
    final c = _ctrl;
    if (_camError != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_camError!, textAlign: TextAlign.center, style: const TextStyle(color: kSub))));
    }
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: CameraPreview(
        c,
        child: LayoutBuilder(
          builder: (ctx, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _tapFocus(d, box),
            child: Stack(children: [
              // 中央の目安（焙煎度は中央を測る）
              if (_kind == 'roast')
                Positioned(
                  left: box.maxWidth * 0.35,
                  top: box.maxHeight * 0.38,
                  width: box.maxWidth * 0.30,
                  height: box.maxHeight * 0.24,
                  child: Container(
                      decoration: BoxDecoration(border: Border.all(color: const Color(0xCC7BC67E), width: 1.5))),
                ),
              if (_focusMark != null)
                Positioned(
                  left: _focusMark!.dx - 28,
                  top: _focusMark!.dy - 28,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(border: Border.all(color: kAccent, width: 2), shape: BoxShape.circle),
                  ),
                ),
              if (_busy)
                const Positioned.fill(child: ColoredBox(color: Color(0x33000000))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _cameraControls() {
    final c = _ctrl;
    final ready = c != null && c.value.isInitialized;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
      child: Column(children: [
        if (ready && _zoomMax > _zoomMin)
          _sliderRow('ズーム', '${_zoom.toStringAsFixed(1)}x', _zoom, _zoomMin, _zoomMax.clamp(_zoomMin, 10.0), (v) {
            setState(() => _zoom = v);
            c!.setZoomLevel(v);
          }, () => Prefs.set('zoom', _zoom)),
        if (ready && _evMax > _evMin)
          _sliderRow('明るさ', (_ev >= 0 ? '+' : '') + _ev.toStringAsFixed(1), _ev, _evMin, _evMax, (v) {
            setState(() => _ev = v);
            c!.setExposureOffset(v);
          }, () => Prefs.set('ev', _ev)),
        Wrap(spacing: 6, children: [
          _chip('ピント固定', _afLocked, _toggleAf),
          _chip('明るさ固定', _aeLocked, _toggleAe),
          _chip('フラッシュ点灯', _torch, _toggleTorch),
          if (_kind == 'grind')
            ActionChip(
              avatar: const Icon(Icons.crop_free, size: 16),
              label: Text('空のトレイを撮る${(_folders[_folder]?['blank'] ?? 0) > 0 ? '（済）' : ''}'),
              tooltip: '粉を載せる前に撮ると、汚れや傷を粒と間違えずに済みます',
              onPressed: _busy ? null : () => _shoot(group: 'blank'),
              visualDensity: VisualDensity.compact,
            ),
          ActionChip(
            avatar: Icon(Icons.light_mode_outlined, size: 16, color: _lightOk ? kAccent : kSub),
            label: Text(_lightSearching
                ? 'ライトを探しています…'
                : _lightOk
                    ? '背景：${_light.state?.label ?? ''}${_light.viaBle ? '（BT）' : '（Wi-Fi）'}'
                    : '背景ライト未接続'),
            onPressed: _busy ? null : _openLightSheet,
            visualDensity: VisualDensity.compact,
          ),
          if (_cams.length > 1)
            ActionChip(
              avatar: const Icon(Icons.cameraswitch_outlined, size: 16),
              label: Text('カメラ ${_camIndex + 1}/${_cams.length}'),
              onPressed: _switchCamera,
              visualDensity: VisualDensity.compact,
            ),
        ]),
      ]),
    );
  }

  Widget _sliderRow(String label, String value, double v, double min, double max, ValueChanged<double> onChanged,
      VoidCallback onEnd) {
    return SizedBox(
      height: 34,
      child: Row(children: [
        SizedBox(width: 48, child: Text(label, style: const TextStyle(fontSize: 12, color: kSub))),
        Expanded(
          child: Slider(value: v.clamp(min, max), min: min, max: max, onChanged: onChanged, onChangeEnd: (_) => onEnd()),
        ),
        SizedBox(width: 40, child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
      ]),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: on,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      showCheckmark: false,
    );
  }

  Widget _nameRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Row(children: [
        Expanded(
          flex: 5,
          child: _nameBox('フォルダ', _folder, _pickFolder),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 6,
          child: Row(children: [
            _smallBtn(Icons.remove, () => _bumpGroup(-1)),
            Expanded(child: _nameBox('条件（次は ${_countInGroup + 1} 枚目）', _group, _pickGroup)),
            _smallBtn(Icons.add, () => _bumpGroup(1)),
          ]),
        ),
      ]),
    );
  }

  Widget _nameBox(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kSub)),
          Text(value.isEmpty ? '（未設定）' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
        ]),
      ),
    );
  }

  Widget _smallBtn(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 32,
      height: 40,
      child: IconButton(padding: EdgeInsets.zero, iconSize: 18, icon: Icon(icon), onPressed: onTap),
    );
  }

  Widget _bottom() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Row(children: [
        Expanded(child: _resultCard()),
        const SizedBox(width: 10),
        Column(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: _busy ? null : _shoot,
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _busy ? kSub : kAccent,
                border: Border.all(color: kText, width: 3),
              ),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.all(22), child: CircularProgressIndicator(strokeWidth: 3, color: kBg))
                  : const Icon(Icons.camera_alt, color: kBg, size: 30),
            ),
          ),
          const SizedBox(height: 4),
          Text(_connected ? '撮って送る' : '撮る（後で送る）', style: const TextStyle(fontSize: 11, color: kSub)),
        ]),
      ]),
    );
  }

  Widget _resultCard() {
    final l = _last;
    final children = <Widget>[];
    if (_status != null) {
      children.add(Text(_status!, style: const TextStyle(fontSize: 12, color: kAccent)));
    }
    if (_pending.isNotEmpty && _connected) {
      children.add(TextButton(onPressed: _flushPending, child: Text('未送信 ${_pending.length} 枚を送る')));
    } else if (!_connected && !_searching) {
      children.add(TextButton(onPressed: _connect, child: const Text('PC を探し直す')));
    }
    if (l != null) {
      children.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => _showPreview(l),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              _client.previewUrl(l.kind, l.folder, l.file),
              width: 62,
              height: 82,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(width: 62, height: 82, color: kCard, child: const Icon(Icons.image_not_supported)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${l.folder}/${l.file}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: kSub)),
            const SizedBox(height: 2),
            ..._resultLines(l),
            Row(children: [
              _linkBtn('取り消し', _undo),
              _linkBtn('レポート', _report),
            ]),
          ]),
        ),
      ]));
    } else if (_status == null) {
      children.add(Text(
          _kind == 'grind'
              ? '粉を薄く散らして、上から撮ってください。送ると PC が粒を数えて結果を返します。'
              : '粉を皿に平らにして、緑の枠の中に入るように撮ってください。',
          style: const TextStyle(fontSize: 12, color: kSub, height: 1.4)));
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 90),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  List<Widget> _resultLines(_Last l) {
    const big = TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kText);
    const small = TextStyle(fontSize: 11, color: kSub, height: 1.35);
    if (l.error != null) return [Text(l.error!, style: const TextStyle(fontSize: 12, color: Color(0xFFE07A5F)))];
    final r = l.result;
    if (r == null) return [];
    String f(Object? v) => v == null ? '—' : (v as num).toStringAsFixed(0);
    String f1(Object? v) => v == null ? '—' : (v as num).toStringAsFixed(1);
    final warnings = [
      for (final w in (r['warnings'] as List? ?? const []))
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('⚠ $w', style: const TextStyle(fontSize: 11, color: Color(0xFFE8B04A), height: 1.35)),
        ),
    ];
    if (l.kind == 'grind' && r['blank'] == true) {
      return [
        ...warnings,
        const Text('空のトレイを登録しました', style: big),
        Text('汚れ・傷 ${r['dirt_spots']} か所を、このフォルダでこのあと撮る写真から除きます。トレイを拭いたら撮り直してください。',
            style: small),
      ];
    }
    if (l.kind == 'grind') {
      return [
        ...warnings,
        Text('D50 ${f(r['vol_D50'])} µm  ・${r['n']}粒', style: big),
        Text('${r['group']} ${r['group_images']}枚の合計：D50 ${f(r['group_vol_D50'])} µm（D10 ${f(r['group_vol_D10'])} / D90 ${f(r['group_vol_D90'])}）',
            style: small),
        Text('細粒 ${f1(r['fine_vol_pct'])}%・大粒 ${f1(r['boulder_vol_pct'])}%・くっつき疑い ${f1(r['clump_suspect_pct'])}%・下限未満 ${r['n_below_limit']}',
            style: small),
        if (r['n_chaff'] != null || r['n_dirt'] != null)
          Text('除いたもの：皮 ${r['n_chaff'] ?? '—'}（面積 ${f1(r['chaff_area_pct'])}%）・汚れ ${r['n_dirt'] ?? '—'}'
              '${r['blank'] == null ? '（空のトレイ未登録）' : ''}',
              style: small),
      ];
    }
    return [
      ...warnings,
      Text('L* ${f1(r['L'])}   a* ${f1(r['a'])}   b* ${f1(r['b'])}', style: big),
      Text('${r['group']} ${r['group_images']}枚の平均 L* ${f1(r['group_L'])}'
          '${r['corrected'] == true ? '' : '・色の補正なし'}'
          '${((r['clipped_pct'] ?? 0) as num) > 1 ? '・白飛び ${f1(r['clipped_pct'])}%' : ''}',
          style: small),
    ];
  }

  Widget _linkBtn(String label, VoidCallback onTap) {
    return TextButton(
      style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: const Size(0, 30), visualDensity: VisualDensity.compact),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  void _showPreview(_Last l) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(children: [
          InteractiveViewer(
            maxScale: 8,
            child: Center(child: Image.network(_client.previewUrl(l.kind, l.folder, l.file))),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: SafeArea(
              child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: Text(
                  l.kind == 'grind'
                      ? '拾った粒を大きさで色分け：青<400 / 緑<800 / 黄<1200 / 赤≥1200 µm。ピンチで拡大できます。'
                      : '緑の枠＝粉として測った範囲。',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ),
        ]),
      ),
    );
  }
}
