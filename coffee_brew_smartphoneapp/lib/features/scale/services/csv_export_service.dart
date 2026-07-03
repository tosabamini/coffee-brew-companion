import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/coffee_session.dart';

/// セッションデータをCSVファイルとして書き出し、共有シートで送る
class CsvExportService {
  CsvExportService._();

  /// 全セッションのサマリCSV（1行 = 1セッション）を共有する
  static Future<void> shareSessionsSummary(
      List<CoffeeSession> sessions) async {
    final buffer = StringBuffer();
    // ExcelでUTF-8日本語を正しく開くためのBOM
    buffer.write('﻿');
    buffer.writeln([
      'createdAt',
      'beanName',
      'country',
      'regionFarm',
      'variety',
      'process',
      'roastLevel',
      'grindSize',
      'elevationM',
      'flavorNotes',
      'doseG',
      'tdsPercent',
      'extractionYieldPercent',
      'brewRatio',
      'maxWeightG',
      'durationSec',
      'recipeName',
      'notes',
    ].map(_escape).join(','));

    for (final s in sessions) {
      final flavors = s.flavorNotes.isNotEmpty
          ? s.flavorNotes.map((t) => t.name).join('; ')
          : (s.flavorNote ?? '');
      buffer.writeln([
        s.createdAt.toIso8601String(),
        s.beanName ?? '',
        s.country ?? '',
        s.regionFarm ?? '',
        s.variety ?? '',
        s.process ?? '',
        s.roastLevel ?? '',
        s.grindSize ?? '',
        s.elevationM?.toStringAsFixed(0) ?? '',
        flavors,
        s.doseG?.toStringAsFixed(1) ?? '',
        s.tdsPercent?.toString() ?? '',
        s.extractionYieldPercent?.toStringAsFixed(2) ?? '',
        s.brewRatio?.toStringAsFixed(2) ?? '',
        s.maxWeight.toStringAsFixed(1),
        s.durationSec.toStringAsFixed(1),
        s.recipe?.name ?? '',
        s.notes ?? '',
      ].map(_escape).join(','));
    }

    final stamp = DateTime.now();
    final name =
        'coffee_sessions_${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}.csv';
    await _shareCsv(buffer.toString(), name, 'Coffee Brew Companion 抽出記録');
  }

  /// 1セッション分の重量点データCSV（elapsedMs, weightG）を共有する
  static Future<void> shareSessionPoints(CoffeeSession session) async {
    final buffer = StringBuffer();
    buffer.write('﻿');
    buffer.writeln('elapsedMs,weightG');
    for (final p in session.points) {
      buffer.writeln('${p.elapsedMs},${p.weightG.toStringAsFixed(2)}');
    }

    final name = 'brew_curve_${session.id}.csv';
    await _shareCsv(
        buffer.toString(), name, '抽出カーブ: ${session.beanName ?? session.id}');
  }

  static Future<void> _shareCsv(
      String content, String fileName, String subject) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: subject,
    );
  }

  static String _escape(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
