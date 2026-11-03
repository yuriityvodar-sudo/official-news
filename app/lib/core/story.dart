import '../l10n/app_localizations.dart';
import 'article.dart';
import 'countries.dart';
import 'news_widgets.dart';

/// A story (#230, the aggregator): what several of a country's news outlets
/// report about one event, from For you's `stories` (docs/contract.md). Only
/// each outlet's own headline and link, never its text.
class Story {
  const Story({
    required this.id,
    required this.title,
    required this.aiTitle,
    required this.lastSeen,
    required this.items,
  });

  factory Story.fromJson(Map<String, dynamic> json) => Story(
    id: json['id'] as String,
    title: json['title'] as String,
    aiTitle: json['aiTitle'] == true,
    lastSeen: DateTime.parse(json['lastSeen'] as String),
    items: [
      for (final item in json['items'] as List)
        if (item is Map<String, dynamic> && StoryItem.isValid(item))
          StoryItem.fromJson(item),
    ],
  );

  /// Whether [json] can be read as a story with at least one outlet: an
  /// older or a broken answer is left out, never shown half.
  static bool isValid(Map<String, dynamic> json) =>
      json['id'] is String &&
      json['title'] is String &&
      json['lastSeen'] is String &&
      DateTime.tryParse(json['lastSeen'] as String) != null &&
      json['items'] is List &&
      (json['items'] as List).any(
        (i) => i is Map<String, dynamic> && StoryItem.isValid(i),
      );

  final String id;

  /// In the reader's language when the model wrote it ([aiTitle]), else the
  /// outlets' own headline.
  final String title;
  final bool aiTitle;

  /// The latest outlet's headline on the story.
  final DateTime lastSeen;

  /// One headline per outlet, the most recent first.
  final List<StoryItem> items;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'aiTitle': aiTitle,
    'lastSeen': lastSeen.toUtc().toIso8601String(),
    'items': [for (final i in items) i.toJson()],
  };

  /// The story as the chat takes what it is about ([Article.isMediaStory]),
  /// as a tick's ([Tick.asArticle]; Roman, 3 Nov: a story's card opens the
  /// chat, as a tick's): its headline, also as its summary; its outlets as
  /// its source; their headlines as its media; and [country], whose outlets
  /// these are, as its place, which a question sends with its id. Kept with
  /// the conversation, so the Conversations screen opens it again.
  Article asArticle(AppLocalizations l10n, String country, {String? lang}) =>
      Article(
        id: id,
        country: country,
        source: Source(
          id: Article.mediaStoryType,
          name: _outletNames(this, l10n),
          url: '',
        ),
        publishedAt: lastSeen,
        dateOnly: false,
        headline: title,
        shortSummary: null,
        summary: title,
        decisionType: Article.mediaStoryType,
        originalTitle: title,
        originalLanguage: lang ?? 'en',
        topics: const [],
        tags: const [],
        importance: null,
        imageUrl: null,
        originalUrl: items.first.url,
        lang: lang,
        countries: [country],
        media: [
          for (final i in items)
            MediaLink(title: i.title, outlet: i.outlet, url: i.url),
        ],
      );
}

/// One outlet's headline on a story, and its link.
class StoryItem {
  const StoryItem({
    required this.title,
    required this.url,
    required this.publishedAt,
    required this.outlet,
  });

  factory StoryItem.fromJson(Map<String, dynamic> json) {
    final outlet = json['outlet'] as Map<String, dynamic>;
    return StoryItem(
      title: json['title'] as String,
      url: json['url'] as String,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      outlet: outlet['name'] as String,
    );
  }

  /// Only an https or http link: it comes from an outlet's feed.
  static bool isValid(Map<String, dynamic> json) {
    final outlet = json['outlet'];
    final url = json['url'];
    return json['title'] is String &&
        url is String &&
        (url.startsWith('https://') || url.startsWith('http://')) &&
        json['publishedAt'] is String &&
        DateTime.tryParse(json['publishedAt'] as String) != null &&
        outlet is Map<String, dynamic> &&
        outlet['name'] is String;
  }

  final String title;
  final String url;
  final DateTime publishedAt;

  /// The outlet's name, as the outlet writes it (ČT24, Seznam Zprávy).
  final String outlet;

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'outlet': {'name': outlet},
  };
}

/// Two letters for an outlet's mark: its words' first ones (Seznam Zprávy:
/// SZ), or one word's first two (ČT24: ČT), without a domain's ending.
String outletInitials(String name) {
  final words = name
      .replaceFirst(RegExp(r'\.[a-z]+$'), '')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  final letters = words.length > 1
      ? words.map((w) => w.runes.first)
      : words.first.runes.take(2);
  return String.fromCharCodes(letters.take(2)).toUpperCase();
}

/// A story's outlets, the first two and how many more ("ČT24, Seznam Zprávy
/// and 2 more").
String _outletNames(Story story, AppLocalizations l10n) => outletNames(
  [for (final i in story.items) i.outlet],
  story.items.length,
  l10n,
);

/// The first two of [names] and how many more of [count] in all: a story's
/// outlets, or a tick's, which lists only its latest 20.
String outletNames(List<String> names, int count, AppLocalizations l10n) =>
    names.length > 1 && count > 2
    ? l10n.storyOutletNames(names[0], names[1], count - 2)
    : names.take(2).join(', ');

/// A story card's first line, where a decision's has its country and
/// institution: "Czechia · ČT24, Seznam Zprávy and 2 more".
String storyMeta(Story story, String? country, AppLocalizations l10n) => [
  if (country != null) countryName(country, l10n),
  _outletNames(story, l10n),
].join(' · ');

/// What VoiceOver reads for a story's card, once: its headline, where it
/// comes from, how many outlets and when.
String storySpoken(Story story, String? country, AppLocalizations l10n) {
  // One sentence each; a text that already ends in a full stop keeps one.
  String sentence(String s) => RegExp(r'[.!?…]$').hasMatch(s) ? s : '$s.';
  return [
    story.title,
    [
      if (country != null) countryName(country, l10n),
      _outletNames(story, l10n),
    ].join(', '),
    l10n.storyOutletsSpoken(story.items.length),
    timeAgo(story.lastSeen, l10n),
  ].map(sentence).join(' ');
}
