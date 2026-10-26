import '../models/brew_recipe.dart';
import '../models/pour_step.dart';

/// アプリに内蔵する有名店・バリスタのレシピ（編集不可）。
///
/// 各店・各人が公開しているレシピを、アプリの形式（開始時刻＋累計目標量）に置き換えたもの。
/// 元のレシピに秒数がなく「前の湯が落ちたら次を注ぐ」形式のものは、
/// 時刻を目安で入れ、レシピ名に「（目安）」を付けている。
/// 保存ファイル（brew_recipes.json）には書き込まないので、ここを直せば次回起動から反映される。
class PresetRecipes {
  PresetRecipes._();

  static List<BrewRecipe> get all => [
        _r('preset_kasuya_46', '4:6メソッド', '粕谷哲（2016 World Brewers Cup 優勝）/ V60 / 92℃・粗挽き',
            20, 210, [(0, 60), (45, 120), (90, 180), (120, 240), (150, 300)]),
        _r('preset_hoffmann_v60', 'Ultimate V60', 'James Hoffmann / V60 / 沸騰直後・中細挽き',
            30, 210, [(0, 60), (45, 300), (75, 500)]),
        _r('preset_bluebottle', 'Blue Bottle Pour Over', 'Blue Bottle Coffee 公式ガイド / 豆20〜27g（22gで登録）・中挽き',
            22, 180, [(0, 50), (40, 150), (70, 250), (100, 350)]),
        _r('preset_lacabra_v60', 'La Cabra V60', 'La Cabra（デンマーク）公式ガイド / 96℃・中細挽き',
            15, 180, [(0, 60), (45, 155), (90, 250)]),
        _r('preset_3fe_v60', '3FE V60', '3FE（アイルランド）公式ガイド / 93℃・中挽き',
            15, 300, [(0, 50), (30, 100), (60, 150), (90, 200), (120, 250)]),
        _r('preset_squaremile_v60', 'Square Mile V60', 'Square Mile（ロンドン）公式ガイド / 豆60g:湯1L・30秒ごとに5等分',
            15, 210, [(0, 50), (30, 100), (60, 150), (90, 200), (120, 250)]),
        _r('preset_rao_v60', 'Scott Rao V60（目安）', 'Scott Rao / V60 / 97℃ / 3投目は「70%落ちたら」のため時刻は目安',
            20, 255, [(0, 60), (40, 200), (80, 330)]),
        _r('preset_glitch', 'GLITCH COFFEE（目安）', 'GLITCH COFFEE & ROASTERS（神保町）/ 86.5℃・中挽き / 3投目は「落ち着いたら」のため時刻は目安',
            16.5, null, [(0, 50), (50, 120), (90, 250)]),
      ];

  static BrewRecipe _r(String id, String name, String source, double beanG,
      int? endSec, List<(int, num)> steps) {
    return BrewRecipe(
      id: id,
      name: name,
      source: source,
      beanQuantityG: beanG,
      targetEndSec: endSec,
      steps: [
        for (int i = 0; i < steps.length; i++)
          PourStep(stepNumber: i + 1, startSec: steps[i].$1, targetTotalG: steps[i].$2.toDouble()),
      ],
    );
  }
}
