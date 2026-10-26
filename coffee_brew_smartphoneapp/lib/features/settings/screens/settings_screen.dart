import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../scale/screens/recipe_settings_screen.dart';
import '../../scale/services/backup_service.dart';

/// 全体設定（レシピ管理、データのバックアップ・復元）
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      final count = await BackupService.exportAndShare();
      _snack('$count 個のデータをバックアップしました。共有先（Googleドライブなど）に保存してください。');
    } catch (e) {
      _snack('バックアップに失敗しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('バックアップから復元'),
        content: const Text('今のアプリ内のデータ（記録・レシピ・豆の在庫など）は、選んだバックアップの内容で上書きされます。続けますか？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ファイルを選ぶ')),
        ],
      ),
    );
    if (ok != true) return;

    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return;

    setState(() => _busy = true);
    try {
      final count = await BackupService.restoreFrom(File(path));
      _snack('$count 個のデータを復元しました。すべての画面に反映するため、アプリを一度閉じて開き直してください。');
    } on FormatException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('復元に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '設定',
          style: AppTheme.display(fontSize: 22, color: BrewColors.espresso),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _SectionLabel('抽出'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined,
                    color: BrewColors.caramel),
                title: const Text('レシピ管理'),
                subtitle: const Text('マイレシピの作成・編集・削除。有名店のレシピをコピーして作ることもできます'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RecipeSettingsScreen()),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _SectionLabel('データ'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.backup_outlined,
                        color: BrewColors.caramel),
                    title: const Text('バックアップを作る'),
                    subtitle: const Text('記録・レシピ・豆の在庫などを1つのファイルにまとめて保存します'),
                    trailing: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: _backup,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.restore,
                        color: BrewColors.caramel),
                    title: const Text('バックアップから復元'),
                    subtitle: const Text('機種変更や再インストールの後に、保存したファイルから戻します'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _restore,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: BrewColors.caramel,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}
