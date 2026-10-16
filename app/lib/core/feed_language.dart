/// The languages the feed can be read in (#46): Ukrainian, Russian and Spanish
/// via Groq (decided 15 Oct). German stays in the menu while it is off on the
/// server (Z.ai blocks Cloudflare Workers) and fills in once it has a provider
/// (Roman, #51). The server translates the headline and summaries; the app's
/// own words stay English for now.
enum FeedLanguage {
  en('en', 'English', 'EN'),
  uk('uk', 'Українська', 'УКР'),
  ru('ru', 'Русский', 'РУС'),
  es('es', 'Español', 'ES'),
  de('de', 'Deutsch', 'DE');

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
