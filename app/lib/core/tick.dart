import '../l10n/app_localizations.dart';
import 'article.dart';
import 'story.dart';

/// A tick (#230, the world's stories): an event that the news outlets of
/// several countries report, with the model's headline in the feed's
/// language, from For you's `ticks` (docs/contract.md). The feed shows it as
/// a light capsule among the Top stories block's rows, and a tap opens the AI
/// chat about it, the same chat as a decision's (Roman, 3 Nov: variant 1 of
/// `handoff/tick-strip.html`; «чат такой же как у нас уже есть»). Only the
/// outlets' own headlines and links, never their text.
class Tick {
  const Tick({
    required this.id,
    required this.title,
    required this.lastSeen,
    required this.countries,
    required this.outlets,
    required this.items,
  });

  factory Tick.fromJson(Map<String, dynamic> json) => Tick(
    id: json['id'] as String,
    title: json['title'] as String,
    lastSeen: DateTime.parse(json['lastSeen'] as String),
    countries: [
      for (final c in json['countries'] as List? ?? const [])
        if (c is String) c,
    ],
    outlets: (json['outlets'] as num?)?.toInt() ?? 0,
    items: [
      for (final item in json['items'] as List)
        if (item is Map<String, dynamic> && StoryItem.isValid(item))
          StoryItem.fromJson(item),
    ],
  );

  /// Whether [json] can be read as a tick with at least one outlet's
  /// headline: an older or a broken answer is left out, never shown half.
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

  /// The model's headline, in the feed's language.
  final String title;

  /// Its latest outlet's headline.
  final DateTime lastSeen;

  /// The countries whose outlets carry it, the most recent first; `WW` is
  /// the world's own outlets.
  final List<String> countries;

  /// How many outlets carry it, all its countries'.
  final int outlets;

  /// Each outlet's latest headline on it, the most recent first (at most 20).
  final List<StoryItem> items;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'lastSeen': lastSeen.toUtc().toIso8601String(),
    'countries': countries,
    'outlets': outlets,
    'items': [for (final i in items) i.toJson()],
  };

  /// The tick as a story's page shows one: its headline and each outlet's
  /// own, with its link; where the chat is not open yet ([ChatScreen.available]).
  Story asStory() => Story(
    id: id,
    title: title,
    aiTitle: true,
    lastSeen: lastSeen,
    items: items,
  );

  /// The tick as the chat takes what it is about ([Article.isTick]): its
  /// headline; its outlets as its source ("Tagesschau, Sky TG24 and 44
  /// more"), the chat's header; their headlines as its summary, which the
  /// paywall shows, and as its media, all the agent has of it (the server's
  /// prompt). Kept with the conversation, so the Conversations screen opens
  /// it again as it opens a decision's.
  Article asArticle(AppLocalizations l10n, {String? lang}) => Article(
    id: id,
    country: 'WW',
    source: Source(
      id: Article.tickType,
      name: outletNames([for (final i in items) i.outlet], outlets, l10n),
      url: '',
    ),
    publishedAt: lastSeen,
    dateOnly: false,
    headline: title,
    shortSummary: null,
    summary: [
      for (final i in items.take(4)) '${i.outlet}: ${i.title}',
    ].join('\n'),
    decisionType: Article.tickType,
    originalTitle: title,
    originalLanguage: lang ?? 'en',
    topics: const [],
    tags: const [],
    importance: null,
    imageUrl: null,
    originalUrl: items.first.url,
    lang: lang,
    countries: countries,
    media: [
      for (final i in items)
        MediaLink(title: i.title, outlet: i.outlet, url: i.url),
    ],
  );
}
