import 'dart:ui' show Locale;

/// The languages the app can be read in: the news (#46) and, since #52, the
/// app's own words too, chosen once in Settings. Ukrainian, Russian and Spanish
/// news come through Groq (decided 15 Oct). German stays in the list while it
/// is off on the server (Z.ai blocks Cloudflare Workers): its app words are
/// German, and its news fills in once it has a provider (Roman, #51). Each one
/// has its words in `lib/l10n/app_<code>.arb`.
enum FeedLanguage {
  en('en', 'English', 'EN'),
  uk('uk', 'Українська', 'УКР'),
  ru('ru', 'Русский', 'РУС'),
  es('es', 'Español', 'ES'),
  de('de', 'Deutsch', 'DE');

  const FeedLanguage(this.code, this.nativeName, this.shortLabel);

  /// The API's `lang` value; English is the feed without one.
  final String code;

  /// The language's own name, in the language list: "Українська".
  final String nativeName;

  /// A short label: "УКР".
  final String shortLabel;

  /// The app's words and dates in this language.
  Locale get locale => Locale(code);

  /// A saved code; anything unknown is English.
  static FeedLanguage fromCode(String? code) => FeedLanguage.values.firstWhere(
    (l) => l.code == code,
    orElse: () => FeedLanguage.en,
  );

  /// The language for a phone whose languages, in the order set in its
  /// settings, are [locales]: the first one the app has, as iOS picks an
  /// app's language; English when it has none (#52). "uk-UA" is Ukrainian.
  static FeedLanguage forPhone(List<Locale> locales) {
    for (final locale in locales) {
      for (final lang in FeedLanguage.values) {
        if (lang.code == locale.languageCode) return lang;
      }
    }
    return FeedLanguage.en;
  }
}
