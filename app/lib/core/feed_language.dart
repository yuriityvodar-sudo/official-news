/// The languages the feed can be read in (#46). The server translates the
/// headline and summaries; the app's own words stay English for now.
enum FeedLanguage {
  en('en', 'English', 'EN'),
  uk('uk', 'Українська', 'УКР'),
  ru('ru', 'Русский', 'РУС');

  const FeedLanguage(this.code, this.nativeName, this.shortLabel);

  /// The API's `lang` value; English is the feed without one.
  final String code;

  /// The language's own name, in the menu: "Українська".
  final String nativeName;

  /// Next to the globe in the feed header: "УКР".
  final String shortLabel;

  /// A saved code; anything unknown is English.
  static FeedLanguage fromCode(String? code) => FeedLanguage.values.firstWhere(
    (l) => l.code == code,
    orElse: () => FeedLanguage.en,
  );
}
