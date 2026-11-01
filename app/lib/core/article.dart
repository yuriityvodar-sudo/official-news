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
    this.author,
    this.credit,
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
      author: json['author'] as String?,
      credit: json['credit'] is Map<String, dynamic>
          ? Credit.fromJson(json['credit'] as Map<String, dynamic>)
          : null,
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

  /// A news story's author (#230: Global Voices), whom its licence asks to
  /// name; null for anything else.
  final String? author;

  /// What the source's licence asks to be shown with it (#230), as the site
  /// shows it; null for a source with neither licence nor wording.
  final Credit? credit;

  /// An event, not an official decision (#230): from Wikipedia's current
  /// events or a news outlet ([isStory]); no official-source seal.
  bool get isEvent => decisionType == 'event';

  /// A news story (#230: Global Voices, RFE/RL): an event whose link is not
  /// Wikipedia's, so its outlet is named where an event names Wikipedia.
  bool get isStory {
    if (!isEvent) return false;
    final host = Uri.tryParse(originalUrl)?.host ?? '';
    return host != 'wikipedia.org' && !host.endsWith('.wikipedia.org');
  }

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
    'author': author,
    'credit': credit?.toJson(),
  };
}

/// What a source's licence asks to be shown with its articles (#230): Global
/// Voices' CC BY 3.0, RFE/RL's "Used with the permission of…".
class Credit {
  const Credit({this.licence, this.licenceUrl, this.wording});

  factory Credit.fromJson(Map<String, dynamic> json) => Credit(
    licence: json['licence'] as String?,
    licenceUrl: json['licenceUrl'] as String?,
    wording: json['wording'] as String?,
  );

  /// The licence's name, a link when there is [licenceUrl].
  final String? licence;
  final String? licenceUrl;

  /// The exact words the source asks for.
  final String? wording;

  Map<String, dynamic> toJson() => {
    'licence': licence,
    'licenceUrl': licenceUrl,
    'wording': wording,
  };
}

/// One of the media's articles about a decision (#230 step 5): its headline,
/// the outlet and the link, never its text.
class MediaLink {
  const MediaLink({
    required this.title,
    required this.outlet,
    required this.url,
  });

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

  Map<String, dynamic> toJson() => {
    'title': title,
    'outlet': outlet,
    'url': url,
  };
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
