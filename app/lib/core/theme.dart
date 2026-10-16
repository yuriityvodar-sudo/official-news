import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The Apple News look (docs/decisions.md, docs/design/mvp.png): white or
/// black background, red accent, serif headlines, bold sans labels, and iOS
/// navigation, gestures and scrolling on both iOS and Android. Light and dark
/// follow the phone's setting.
abstract final class AppColors {
  static const accent = Color(0xFFFA2D48);
  static const verified = Color(0xFF1A8CFF);

  /// The brand red made deeper, for small text on light grounds and white
  /// text on red (design B): 4.7:1 on B's grey page, 5.3:1 with white.
  static const deepRed = Color(0xFFD1203A);
}

/// The system serif: Georgia on iOS, Noto Serif on Android.
const _serif = 'Georgia';
const _serifFallback = ['serif'];

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: brightness,
      ).copyWith(
        primary: AppColors.accent,
        surface: dark ? Colors.black : Colors.white,
        onSurface: dark ? Colors.white : Colors.black,
        onSurfaceVariant: dark
            ? const Color(0xFF98989F)
            : const Color(0xFF6C6C70),
        outlineVariant: dark
            ? const Color(0xFF38383A)
            : const Color(0xFFE5E5EA),
        surfaceContainerHighest: dark
            ? const Color(0xFF2C2C2E)
            : const Color(0xFFE3E8EF),
      );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    platform: TargetPlatform.iOS,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values)
          p: const CupertinoPageTransitionsBuilder(),
      },
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: AppColors.accent,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 0.5,
      space: 1,
    ),
    extensions: [NewsText.of(scheme)],
  );
}

/// Text styles for the feed and article screens: `NewsText.from(context).headline`.
class NewsText extends ThemeExtension<NewsText> {
  const NewsText({
    required this.masthead,
    required this.dateLine,
    required this.section,
    required this.kindLabel,
    required this.publisher,
    required this.headline,
    required this.articleHeadline,
    required this.meta,
    required this.body,
  });

  factory NewsText.of(ColorScheme scheme) {
    final secondary = scheme.onSurfaceVariant;
    return NewsText(
      masthead: TextStyle(
        fontFamily: _serif,
        fontFamilyFallback: _serifFallback,
        fontSize: 36,
        fontWeight: FontWeight.w800,
        height: 1.1,
        color: scheme.onSurface,
      ),
      dateLine: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: secondary,
      ),
      section: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: AppColors.accent,
      ),
      kindLabel: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.accent,
      ),
      publisher: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
      headline: TextStyle(
        fontFamily: _serif,
        fontFamilyFallback: _serifFallback,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        height: 1.2,
        color: scheme.onSurface,
      ),
      articleHeadline: TextStyle(
        fontFamily: _serif,
        fontFamilyFallback: _serifFallback,
        fontSize: 31,
        fontWeight: FontWeight.w700,
        height: 1.15,
        color: scheme.onSurface,
      ),
      meta: TextStyle(fontSize: 14, color: secondary),
      body: TextStyle(
        fontFamily: _serif,
        fontFamilyFallback: _serifFallback,
        fontSize: 19,
        height: 1.5,
        color: scheme.onSurface,
      ),
    );
  }

  static NewsText from(BuildContext context) =>
      Theme.of(context).extension<NewsText>()!;

  /// "Official News" at the top of the feed.
  final TextStyle masthead;
  final TextStyle dateLine;

  /// Red section titles: "Top stories", "Latest".
  final TextStyle section;

  /// The decision type above a headline, upper case: "CABINET DECISION".
  final TextStyle kindLabel;

  /// "Federal Government · Germany".
  final TextStyle publisher;
  final TextStyle headline;
  final TextStyle articleHeadline;

  /// "2h ago", dates, image credits.
  final TextStyle meta;

  /// The summary on the article screen.
  final TextStyle body;

  @override
  NewsText copyWith() => this;

  @override
  NewsText lerp(NewsText? other, double t) =>
      t < 0.5 || other == null ? this : other;
}
