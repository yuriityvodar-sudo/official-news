/// The article format from docs/contract.md, as returned by the API.
class Source {
  const Source({required this.id, required this.name, required this.url});

  factory Source.fromJson(Map<String, dynamic> json) => Source(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
  );

  final String id;
  final String name;
  final String url;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};
}

class Article {
  const Article({
    required this.id,
    required this.country,
    required this.source,
    required this.publishedAt,
    required this.dateOnly,
    required this.headline,
    required this.shortSummary,
    required this.summary,
    required this.decisionType,
    required this.originalTitle,
    required this.originalLanguage,
    required this.topics,
    required this.tags,
    required this.importance,
    required this.imageUrl,
    required this.originalUrl,
    this.feedSeq,
    this.addedAt,
    this.lang,
    this.countries = const [],
    this.media = const [],
  });

  factory Article.fromJson(Map<String, dynamic> json) {
    final originalTitle = json['originalTitle'] as String? ?? '';
    return Article(
      id: json['id'] as String,
      country: json['country'] as String,
      source: Source.fromJson(json['source'] as Map<String, dynamic>),
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      dateOnly: json['dateOnly'] as bool? ?? false,
      // Before the AI step has run, the headline falls back to the original title.
      headline: (json['headline'] as String?) ?? originalTitle,
      shortSummary: json['shortSummary'] as String?,
      summary: json['summary'] as String?,
      decisionType: json['decisionType'] as String?,
      originalTitle: originalTitle,
      originalLanguage: json['originalLanguage'] as String? ?? 'en',
      topics: List<String>.from(json['topics'] as List? ?? const []),
      tags: List<String>.from(json['tags'] as List? ?? const []),
      importance: json['importance'] as int?,
      imageUrl: json['imageUrl'] as String?,
      originalUrl: json['originalUrl'] as String,
      feedSeq: json['feedSeq'] as int?,
      addedAt: json['addedAt'] == null
          ? null
          : DateTime.parse(json['addedAt'] as String),
      lang: json['lang'] as String?,
      countries: List<String>.from(json['countries'] as List? ?? const []),
      media: [
        for (final m in json['media'] as List? ?? const [])
          if (m is Map<String, dynamic> && MediaLink.isValid(m))
            MediaLink.fromJson(m),
      ],
    );
  }

  final String id;
  final String country;
  final Source source;
  final DateTime publishedAt;
  final bool dateOnly;
  final String headline;
  final String? shortSummary;
  final String? summary;

  /// One id from the fixed list in decision_types.dart, or null before the AI step.
  final String? decisionType;
  final String originalTitle;
  final String originalLanguage;
  final List<String> topics;
  final List<String> tags;
  final int? importance;
  final String? imageUrl;
  final String originalUrl;

  /// The article's place in the feed: given when it appeared, only rising (docs/contract.md).
  final int? feedSeq;

  /// When it appeared in the feed; the card still shows [publishedAt].
  final DateTime? addedAt;

  /// The language of the headline and summaries in a translated feed (`uk`, `ru`, #46);
  /// none in the English feed.
  final String? lang;

  /// The countries it concerns, the main one first (#230); empty before the
  /// AI step and from a server before #239. [country] stays the source's.
  final List<String> countries;

  /// "In the media" (#230 step 5): up to 3 of the reader's country's outlets
  /// about it, headline, outlet and link; only in For you's lists, and empty
  /// while there are none.
  final List<MediaLink> media;

  /// An event from Wikipedia's current events, not an official decision
  /// (#230): no official-source seal, and its link opens Wikipedia.
  bool get isEvent => decisionType == 'event';

  /// The contract format, so the last feed can be saved on the phone and read back.
  Map<String, dynamic> toJson() => {
    'id': id,
    'country': country,
    'source': source.toJson(),
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'dateOnly': dateOnly,
    'headline': headline,
    'shortSummary': shortSummary,
    'summary': summary,
    'decisionType': decisionType,
    'originalTitle': originalTitle,
    'originalLanguage': originalLanguage,
    'topics': topics,
    'tags': tags,
    'importance': importance,
    'imageUrl': imageUrl,
    'originalUrl': originalUrl,
    'feedSeq': feedSeq,
    'addedAt': addedAt?.toUtc().toIso8601String(),
    'lang': lang,
    'countries': countries,
    'media': [for (final m in media) m.toJson()],
  };
}

/// One of the media's articles about a decision (#230 step 5): its headline,
/// the outlet and the link, never its text.
class MediaLink {
  const MediaLink({required this.title, required this.outlet, required this.url});

  factory MediaLink.fromJson(Map<String, dynamic> json) => MediaLink(
    title: json['title'] as String,
    outlet: json['outlet'] as String,
    url: json['url'] as String,
  );

  /// Whether the server's entry has all three, with an http(s) link.
  static bool isValid(Map<String, dynamic> json) =>
      json['title'] is String &&
      json['outlet'] is String &&
      json['url'] is String &&
      RegExp(r'^https?://').hasMatch(json['url'] as String);

  final String title;
  final String outlet;
  final String url;

  Map<String, dynamic> toJson() => {'title': title, 'outlet': outlet, 'url': url};
}

class ArticlesPage {
  const ArticlesPage({
    required this.items,
    required this.nextCursor,
    required this.top,
  });

  factory ArticlesPage.fromJson(Map<String, dynamic> json) => ArticlesPage(
    items: [
      for (final item in json['items'] as List)
        Article.fromJson(item as Map<String, dynamic>),
    ],
    nextCursor: json['nextCursor'] as String?,
    // `top` may be missing or empty; the app must not depend on it.
    top: [
      for (final item in json['top'] as List? ?? const [])
        Article.fromJson(item as Map<String, dynamic>),
    ],
  );

  final List<Article> items;
  final String? nextCursor;
  final List<Article> top;

  /// Only the articles in [lang]. A translated feed lists nothing else (#46), but a
  /// server without translations ignores `lang` and sends the English feed: none of
  /// it is shown as [lang], and its cursor, which pages through that other feed, is
  /// not followed.
  ArticlesPage inLanguage(String lang) {
    bool inLang(Article a) => a.lang == lang;
    if (items.every(inLang) && top.every(inLang)) return this;
    return ArticlesPage(
      items: items.where(inLang).toList(),
      nextCursor: null,
      top: top.where(inLang).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'items': [for (final a in items) a.toJson()],
    'nextCursor': nextCursor,
    'top': [for (final a in top) a.toJson()],
  };
}
