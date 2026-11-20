import '../models/brew_recipe.dart';
import '../models/coffee_session.dart';
import '../models/pour_step.dart';
import 'session_storage.dart';

/// 抽出の詳細画面の AI チャット用：記録を AI に渡す文と、AI が作ったレシピの保存。
class BrewAi {
  BrewAi._();

  static String _sec(num s) {
    final t = s.round();
    return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
  }

  /// 抽出の記録を、AI が読める文にする（重さの推移は5秒ごと）
  static String describeSession(CoffeeSession s) {
    final b = StringBuffer();
    void line(String k, Object? v) {
      if (v == null) return;
      final t = v.toString().trim();
      if (t.isNotEmpty) b.writeln('- $k: $t');
    }

    line('豆', s.beanName);
    line('生産国', s.country);
    line('地域・農園', s.regionFarm);
    line('品種', s.variety);
    line('精製', s.process);
    line('焙煎度', s.roastLevel);
    line('挽き目', s.grindSize);
    line('ドリッパー', s.dripper);
    line('豆量', s.doseG == null ? null : '${s.doseG!.toStringAsFixed(1)} g');
    line('最終の重さ（注湯量）', '${s.maxWeight.toStringAsFixed(1)} g');
    line('抽出時間', _sec(s.durationSec));
    line('レシオ', s.brewRatio == null ? null : '1:${s.brewRatio!.toStringAsFixed(1)}');
    line('TDS', s.tdsPercent == null ? null : '${s.tdsPercent} %');
    line('収率', s.extractionYieldPercent == null ? null : '${s.extractionYieldPercent!.toStringAsFixed(1)} %');
    line('評価', s.rating == null ? null : CoffeeSession.ratingLabel(s.rating!));
    line('フレーバー',
        s.flavorNotes.isNotEmpty ? s.flavorNotes.map((t) => t.name).join(', ') : s.flavorNote);
    line('今回の抽出メモ', s.brewNotes);
    line('豆のメモ', s.notes);

    final r = s.recipe;
    if (r != null && !r.isEmpty) {
      b.writeln('- 使ったレシピ: ${r.name ?? '名前なし'}（豆 ${r.beanQuantityG?.toStringAsFixed(1) ?? '-'} g'
          '${r.targetEndSec == null ? '' : '、終了 ${_sec(r.targetEndSec!)}'}）');
      final steps = [...r.steps]..sort((a, c) => a.startSec.compareTo(c.startSec));
      for (final p in steps) {
        b.writeln('  - ${_sec(p.startSec)} から注いで合計 ${p.targetTotalG.toStringAsFixed(0)} g まで');
      }
    }

    if (s.points.isNotEmpty) {
      b.writeln('- 実際の重さの推移（経過時間: 合計の重さ）:');
      var next = 0;
      final parts = <String>[];
      for (final p in s.points) {
        if (p.elapsedMs >= next) {
          parts.add('${_sec(p.elapsedMs / 1000)} ${p.weightG.toStringAsFixed(0)}g');
          next += 5000;
        }
      }
      final last = s.points.last;
      parts.add('${_sec(last.elapsedMs / 1000)} ${last.weightG.toStringAsFixed(0)}g（終了）');
      b.writeln('  ${parts.join(' / ')}');
    }
    return b.toString();
  }

  static String systemPrompt(CoffeeSession s) => '''あなたはハンドドリップのコーヒー抽出に詳しいアシスタントです。日本語で、具体的に、短めに答えてください。
ユーザーが見ている抽出の記録は次のとおりです。
${describeSession(s)}
ユーザーがレシピを作ってほしいと言ったときや、レシピを提案するときは、説明のあとに次の形のブロックを1つだけ付けてください。
targetTotalG はその時点までの合計の湯量（g）、startSec はその注ぎを始める時間（秒）です。
```recipe
{"name": "レシピ名（短く）", "beanQuantityG": 15, "targetEndSec": 180, "steps": [{"startSec": 0, "targetTotalG": 40}, {"startSec": 40, "targetTotalG": 120}]}
```''';

  /// AI が提案したレシピをマイレシピに保存する。成功したら画面に出す文を返す
  static Future<String> saveRecipeFromJson(Map<String, dynamic> j, CoffeeSession base) async {
    final raw = (j['steps'] as List?) ?? const [];
    final steps = <PourStep>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final start = (e['startSec'] as num?)?.round();
      final total = (e['targetTotalG'] as num?)?.toDouble();
      if (start == null || total == null || start < 0 || total <= 0) continue;
      steps.add(PourStep(stepNumber: 0, startSec: start, targetTotalG: total));
    }
    if (steps.isEmpty) throw Exception('注ぐ手順が入っていませんでした');
    steps.sort((a, c) => a.startSec.compareTo(c.startSec));
    final numbered = [
      for (var i = 0; i < steps.length; i++)
        PourStep(stepNumber: i + 1, startSec: steps[i].startSec, targetTotalG: steps[i].targetTotalG),
    ];
    final name = (j['name']?.toString().trim().isNotEmpty ?? false) ? j['name'].toString().trim() : 'AIのレシピ';
    final recipe = BrewRecipe(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      beanQuantityG: (j['beanQuantityG'] as num?)?.toDouble() ?? base.doseG ?? base.recipe?.beanQuantityG,
      targetEndSec: (j['targetEndSec'] as num?)?.round(),
      steps: numbered,
      source: 'AI（${base.beanName ?? '過去の抽出'}の記録から）',
    );
    final recipes = await SessionStorage.loadRecipes();
    await SessionStorage.saveRecipes([...recipes, recipe]);
    return 'マイレシピに「$name」を保存しました（ホームのレシピから選べます）';
  }
}
