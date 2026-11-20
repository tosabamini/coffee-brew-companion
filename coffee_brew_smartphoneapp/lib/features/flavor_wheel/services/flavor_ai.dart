import '../../shared/services/claude_api.dart';
import '../models/flavor_category.dart';

/// AI が提案するフレーバーの置き場所
class FlavorPlacement {
  final String categoryId;

  /// 既存の中分類の id。null のときは [newSubName] で新しい中分類を作る
  final String? subId;
  final String? newSubName;

  /// なぜそこに置いたか（ひとこと）
  final String reason;

  const FlavorPlacement({
    required this.categoryId,
    this.subId,
    this.newSubName,
    required this.reason,
  });
}

/// フレーバーホイールの AI（Sonnet 5.5）。新しいフレーバーの置き場所を決める。
class FlavorAi {
  FlavorAi._();

  /// ホイールの中身を AI に渡す文（大分類 id:名前 → 中分類 id:名前（例））
  static String describeWheel(List<FlavorCategory> cats) {
    final b = StringBuffer();
    for (final c in cats) {
      b.writeln('- 大分類 ${c.id}: ${c.name}');
      for (final s in c.subCategories) {
        final ex = s.items.take(6).map((i) => i.name).join(', ');
        b.writeln('  - 中分類 ${s.id}: ${s.name}${ex.isEmpty ? '' : '（例: $ex）'}');
      }
    }
    return b.toString();
  }

  /// [name] をホイールのどこに置くかを提案する
  static Future<FlavorPlacement> suggest(String name, List<FlavorCategory> cats) async {
    final prompt = '''
コーヒーのフレーバーホイール（SCA の分類をもとにしたもの）に、ユーザーが新しいフレーバー「$name」を書きました。
これがどの大分類・中分類に入るのがふさわしいかを決めてください。

ホイールの中身:
${describeWheel(cats)}
次の JSON だけを返してください（説明文は不要）。
{"categoryId": "大分類の id", "subId": "既存の中分類の id（ふさわしいものがなければ null）", "newSubName": "subId が null のときだけ、新しく作る中分類の名前（英語、短く）", "reason": "そこに置いた理由（日本語で20字程度）"}
''';
    final text = await ClaudeApi.send(
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      maxTokens: 300,
      timeout: const Duration(seconds: 40),
    );
    final j = ClaudeApi.extractJson(text);
    if (j == null) throw Exception('AIの返事を読み取れませんでした');

    final catId = j['categoryId']?.toString();
    final catHits = cats.where((c) => c.id == catId).toList();
    if (catHits.isEmpty) throw Exception('AIが存在しない分類を返しました（$catId）');
    final cat = catHits.first;
    final subId = j['subId']?.toString();
    final subHits = cat.subCategories.where((s) => s.id == subId).toList();
    final sub = subHits.isEmpty ? null : subHits.first;
    final newSub = j['newSubName']?.toString().trim();
    return FlavorPlacement(
      categoryId: cat.id,
      subId: sub?.id,
      newSubName: sub == null ? ((newSub == null || newSub.isEmpty) ? 'Other' : newSub) : null,
      reason: j['reason']?.toString() ?? '',
    );
  }
}
