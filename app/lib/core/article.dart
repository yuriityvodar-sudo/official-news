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
    required this.originalTitle,
    required this.originalLanguage,
    required this.topics,
    required this.tags,
    required this.importance,
    required this.imageUrl,
    required this.originalUrl,
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
      originalTitle: originalTitle,
      originalLanguage: json['originalLanguage'] as String? ?? 'en',
      topics: List<String>.from(json['topics'] as List? ?? const []),
      tags: List<String>.from(json['tags'] as List? ?? const []),
      importance: json['importance'] as int?,
      imageUrl: json['imageUrl'] as String?,
      originalUrl: json['originalUrl'] as String,
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
  final String originalTitle;
  final String originalLanguage;
  final List<String> topics;
  final List<String> tags;
  final int? importance;
  final String? imageUrl;
  final String originalUrl;
}

class ArticlesPage {
  const ArticlesPage({required this.items, required this.nextCursor, required this.top});

  factory ArticlesPage.fromJson(Map<String, dynamic> json) => ArticlesPage(
        items: [
          for (final item in json['items'] as List) Article.fromJson(item as Map<String, dynamic>),
        ],
        nextCursor: json['nextCursor'] as String?,
        // `top` may be missing or empty; the app must not depend on it.
        top: [
          for (final item in json['top'] as List? ?? const []) Article.fromJson(item as Map<String, dynamic>),
        ],
      );

  final List<Article> items;
  final String? nextCursor;
  final List<Article> top;
}
