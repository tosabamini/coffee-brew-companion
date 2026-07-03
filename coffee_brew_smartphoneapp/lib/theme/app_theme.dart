import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Coffee Brew Companion のデザインシステム。
/// コンセプト: 「スペシャルティコーヒーのロースタリー」
/// クリーム色の温かい背景に、エスプレッソ色のダークなヒーロー要素を重ねる。
class BrewColors {
  BrewColors._();

  // --- Espresso（ダーク系: ヒーローカード・強調） ---
  static const espresso = Color(0xFF221510); // 最深部の焙煎色
  static const roast = Color(0xFF3A2A20); // ダークカードのグラデーション始点
  static const roastLight = Color(0xFF56402F); // 同・終点

  // --- Crema（ライト系: 背景・サーフェス） ---
  static const crema = Color(0xFFF6EFE4); // 画面背景（クレマ色）
  static const foam = Color(0xFFFFFCF6); // カード・入力欄
  static const oat = Color(0xFFE5D9C5); // 枠線・区切り線

  // --- アクセント ---
  static const caramel = Color(0xFFA9683A); // プライマリ（キャラメル）
  static const amber = Color(0xFFD99A4E); // ゴールド系アクセント
  static const mocha = Color(0xFF6E5846); // セカンダリテキスト

  // --- ステータス ---
  static const sage = Color(0xFF6F9268); // 接続中・成功
  static const terracotta = Color(0xFFC05B4D); // 停止・エラー
  static const steam = Color(0xFF7B93AC); // レシピ目標ライン（湯気の青灰）

  // ダークカード上のテキスト
  static const creamText = Color(0xFFF3E9D8);
  static const creamTextDim = Color(0xFFBCA98F);
}

class AppTheme {
  AppTheme._();

  /// 見出し用セリフ体（英字）。日本語はフォールバックで Zen Kaku Gothic New。
  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) =>
      GoogleFonts.fraunces(
        fontSize: fontSize,
        fontWeight: fontWeight ?? FontWeight.w600,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontStyle: fontStyle,
      );

  /// 数値表示用の等幅フォント（重量・タイマー）。桁が動いてもぶれない。
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.ibmPlexMono(
        fontSize: fontSize,
        fontWeight: fontWeight ?? FontWeight.w600,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// ラベル・オーバーライン用（英字小文字ラベルを想定）
  static TextStyle overline({Color? color, double fontSize = 11}) =>
      GoogleFonts.ibmPlexMono(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        letterSpacing: 2.2,
        color: color ?? BrewColors.mocha,
      );

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BrewColors.caramel,
        primary: BrewColors.caramel,
        secondary: BrewColors.mocha,
        surface: BrewColors.foam,
        error: BrewColors.terracotta,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: BrewColors.crema,
    );

    // 日本語対応の本文フォントをベースに、全体へ適用
    final textTheme = GoogleFonts.zenKakuGothicNewTextTheme(base.textTheme)
        .apply(
          bodyColor: BrewColors.espresso,
          displayColor: BrewColors.espresso,
        );

    return base.copyWith(
      textTheme: textTheme,
      // --- 画面遷移: フェード + わずかな上方向スライド ---
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeSlidePageTransitionsBuilder(),
          TargetPlatform.iOS: FadeSlidePageTransitionsBuilder(),
          TargetPlatform.windows: FadeSlidePageTransitionsBuilder(),
          TargetPlatform.macOS: FadeSlidePageTransitionsBuilder(),
          TargetPlatform.linux: FadeSlidePageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: BrewColors.crema,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: BrewColors.espresso,
        titleTextStyle: display(
          fontSize: 22,
          color: BrewColors.espresso,
          letterSpacing: 0.2,
        ),
        iconTheme: const IconThemeData(color: BrewColors.mocha, size: 22),
      ),
      cardTheme: CardThemeData(
        color: BrewColors.foam,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: BrewColors.oat, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BrewColors.caramel,
          foregroundColor: BrewColors.foam,
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          minimumSize: const Size(0, 46),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BrewColors.mocha,
          side: const BorderSide(color: BrewColors.oat, width: 1.2),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          minimumSize: const Size(0, 46),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: BrewColors.caramel),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: BrewColors.foam,
        selectedColor: BrewColors.espresso,
        side: const BorderSide(color: BrewColors.oat),
        labelStyle: textTheme.labelLarge?.copyWith(color: BrewColors.espresso),
        secondaryLabelStyle:
            textTheme.labelLarge?.copyWith(color: BrewColors.creamText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BrewColors.foam,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BrewColors.oat),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BrewColors.oat),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BrewColors.caramel, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BrewColors.espresso,
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: BrewColors.creamText),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(color: BrewColors.oat, thickness: 1),
      listTileTheme: const ListTileThemeData(iconColor: BrewColors.mocha),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: BrewColors.caramel),
      dialogTheme: DialogThemeData(
        backgroundColor: BrewColors.foam,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: display(fontSize: 20, color: BrewColors.espresso),
        contentTextStyle: textTheme.bodyMedium,
      ),
    );
  }
}

/// フェード + わずかな上方向スライドのページ遷移。
class FadeSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeSlidePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
