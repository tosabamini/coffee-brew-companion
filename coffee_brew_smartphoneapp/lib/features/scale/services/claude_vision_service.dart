import 'dart:convert';
import 'dart:io';

import '../../shared/services/claude_api.dart';

/// パッケージ写真から読み取ったコーヒー豆情報
class CoffeePackageInfo {
  final String? beanName;
  final String? country;
  final String? regionFarm;
  final String? variety;
  final String? process;
  final String? roastLevel;
  final String? elevation;
  final List<String> flavorNotes;
  final String? notes;

  CoffeePackageInfo({
    this.beanName,
    this.country,
    this.regionFarm,
    this.variety,
    this.process,
    this.roastLevel,
    this.elevation,
    required this.flavorNotes,
    this.notes,
  });
}

/// パッケージ写真の読み取り（モデルは ClaudeApi.model ＝ Sonnet 5.5）
class ClaudeVisionService {
  /// コーヒーパッケージ画像を解析して豆情報を返す
  static Future<CoffeePackageInfo> analyzeCoffeePackage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);
    final ext = imageFile.path.split('.').last.toLowerCase();
    final mediaType = ext == 'png' ? 'image/png' : 'image/jpeg';

    const prompt = '''
このコーヒーパッケージの画像からコーヒー豆の情報を読み取り、以下のJSON形式だけで返してください。
説明文やマークダウンは不要です。JSONのみ出力してください。
読み取れない項目はnullにしてください。flavorNotesは空なら空配列にしてください。

{
  "beanName": "豆の商品名",
  "country": "生産国（英語で）",
  "regionFarm": "産地の地域名や農園名",
  "variety": "品種名",
  "process": "精製方法（Natural / Washed / Honey など）",
  "roastLevel": "焙煎度（Light Roast / Medium Roast / Dark Roast など）",
  "elevation": "標高（数字のみ、単位なし）",
  "flavorNotes": ["フレーバーノート1", "フレーバーノート2"],
  "notes": "その他の特記事項"
}
''';

    final text = await ClaudeApi.send(
      messages: [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': mediaType,
                'data': base64Image,
              },
            },
            {
              'type': 'text',
              'text': prompt,
            },
          ],
        },
      ],
      maxTokens: 1024,
    );

    final data = ClaudeApi.extractJson(text);
    if (data == null) {
      throw Exception('レスポンスからJSON情報を取得できませんでした。');
    }

    return CoffeePackageInfo(
      beanName: _str(data['beanName']),
      country: _str(data['country']),
      regionFarm: _str(data['regionFarm']),
      variety: _str(data['variety']),
      process: _str(data['process']),
      roastLevel: _str(data['roastLevel']),
      elevation: _str(data['elevation']),
      flavorNotes: (data['flavorNotes'] as List? ?? [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList(),
      notes: _str(data['notes']),
    );
  }

  static String? _str(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }
}
