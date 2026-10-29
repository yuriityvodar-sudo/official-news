import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/countries.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/core/home_country.dart';
import 'package:official_news/core/news_widgets.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/topics.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_filters.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// The feed's menu under the date (#67, #170): For you (the default), the
/// whole world, or one topic across the world; the reader's home country
/// (the phone's region, else `GET /locate`); the requests they make, the
/// compact chip, the choices saved on the phone, the empty filtered feed,
/// For you's top stories, and servers without the menus.

Map<String, dynamic> _article(
  String id, {
  required String country,
  List<String> topics = const [],
  required int feedSeq,
  String? lang,
  int importance = 3,
}) => {
  'feedSeq': feedSeq,
  'addedAt': DateTime.now()
      .subtract(Duration(minutes: 100 - feedSeq))
      .toUtc()
      .toIso8601String(),
  'id': id,
  'country': country,
  'source': {
    'id': '${country.toLowerCase()}-gov',
    'name': 'Government $country',
    'url': 'https://gov.test/$country',
  },
  'publishedAt': DateTime.now().toUtc().toIso8601String(),
  'dateOnly': false,
  'headline': lang == null ? 'Decision $id' : 'Рішення $id',
  'shortSummary': null,
  'summary': 'Summary $id',
  'decisionType': 'decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'en',
  'topics': topics,
  'tags': <String>[],
  'importance': importance,
  'imageUrl': null,
  'originalUrl': 'https://gov.test/$id',
  'lang': ?lang,
};

/// The week's feed, newest first: Germany, the US, the EU institutions, the
/// UK, Japan and Türkiye. Economy is the busiest topic, then health. Japan's
/// and Türkiye's matter less (importance 2): For you leaves them out.
final _week = [
  _article('de1', country: 'DE', topics: ['economy'], feedSeq: 10),
  _article('us1', country: 'US', topics: ['economy', 'health'], feedSeq: 9),
  _article('eu1', country: 'EU', topics: ['trade'], feedSeq: 8),
  _article('gb1', country: 'GB', topics: ['economy'], feedSeq: 7),
  _article('de2', country: 'DE', topics: ['health'], feedSeq: 6),
  _article(
    'jp1',
    country: 'JP',
    topics: ['security-defence'],
    feedSeq: 5,
    importance: 2,
  ),
  _article('us2', country: 'US', topics: ['economy'], feedSeq: 4),
  _article('tr1', country: 'TR', topics: ['health'], feedSeq: 3, importance: 2),
];

/// The groups as the server defines them (`GROUPS`), with the members these
/// tests have articles for; `EU` is the EU institutions.
const _topicNames = {
  'en': {
    'economy': 'Economy',
    'health': 'Health',
    'trade': 'Trade',
    'security-defence': 'Security and defence',
    'housing': 'Housing',
  },
  'uk': {
    'economy': 'Економіка',
    'health': 'Здоров’я',
    'trade': 'Торгівля',
    'security-defence': 'Безпека та оборона',
    'housing': 'Житло',
  },
};

http.Response _ok(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _bad(String message) => http.Response.bytes(
  utf8.encode(jsonEncode({'error': message})),
  400,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// A server that follows the contract for the filters: `topic=` on every
/// article request, and `GET /topics` busiest first. It refuses `country=`
/// and `group=` (#68), which builds from before For you sent: this one never
/// does (#170). Without [menus], a server from before them: `/topics`
/// answers 404 and every filter is ignored. Pages of [pageSize]; the cursor
/// is the next offset.
/// `for=XX` (#170): XX's own, the EU institutions' for a member, and the
/// world's of importance 3 or more; `GET /locate` answers [located]; the
/// first page's `top` is [topIds] among what the page's filters show.
class _Server {
  _Server({
    List<Map<String, dynamic>>? articles,
    this.menus = true,
    this.extraTopics = const [],
    this.pageSize = 20,
    this.located,
    this.topIds = const [],
    this.holdForYou,
  }) : articles = articles ?? _week;

  List<Map<String, dynamic>> articles;
  final bool menus;
  final List<String> extraTopics;
  final int pageSize;
  final String? located;
  final List<String> topIds;

  /// For you's pages wait for it, when given.
  final Completer<void>? holdForYou;
  final log = <Uri>[];
  bool offline = false;

  /// The article requests only.
  List<Uri> get feedRequests =>
      log.where((u) => u.path == '/articles').toList();

  List<Uri> get topicRequests => log.where((u) => u.path == '/topics').toList();

  ApiClient get api => ApiClient(
    baseUrl: 'https://api.test',
    client: MockClient((request) async {
      log.add(request.url);
      if (offline) return http.Response('offline', 503);
      final q = request.url.queryParameters;
      final lang = q['lang'] ?? 'en';
      if (!menus && request.url.path != '/articles') {
        return http.Response('{"error":"Not found"}', 404);
      }
      final error = _check(q);
      if (error != null) return _bad(error);
      switch (request.url.path) {
        case '/locate':
          return _ok({'country': located});
        case '/topics':
          final counts = <String, int>{};
          for (final a in _matching(q, topic: false)) {
            for (final t in a['topics'] as List) {
              counts[t as String] = (counts[t] ?? 0) + 1;
            }
          }
          final ids = counts.keys.toList()
            ..sort((x, y) => counts[y]!.compareTo(counts[x]!));
          return _ok({
            'topics': [
              for (final id in [...ids, ...extraTopics])
                {'id': id, 'name': _topicNames[lang]![id]},
            ],
          });
        case '/articles':
          if (q.containsKey('for')) await holdForYou?.future;
          var shown = _matching(q);
          if (lang != 'en') {
            shown = [for (final a in shown) _translated(a, lang)];
          }
          final after = int.tryParse(q['after'] ?? '');
          if (after != null) {
            return _ok({
              'items': shown
                  .where((a) => (a['feedSeq'] as int) > after)
                  .toList(),
              'nextCursor': null,
              'top': [],
            });
          }
          final from = int.tryParse(q['cursor'] ?? '') ?? 0;
          final page = shown.skip(from).take(pageSize).toList();
          final next = from + pageSize;
          return _ok({
            'items': page,
            'nextCursor': next < shown.length ? '$next' : null,
            'top': [
              if (from == 0)
                for (final id in topIds) ...shown.where((a) => a['id'] == id),
            ],
          });
      }
      return http.Response('{"error":"Not found"}', 404);
    }),
  );

  /// A 400 for the Where filter of 16 Oct (#68), which this build never
  /// sends: For you replaced it (#170).
  String? _check(Map<String, String> q) =>
      q.containsKey('country') || q.containsKey('group')
      ? 'this build sends neither country= nor group='
      : null;

  List<Map<String, dynamic>> _matching(
    Map<String, String> q, {
    bool topic = true,
  }) {
    if (!menus) return articles;
    final id = topic ? q['topic'] : null;
    final home = q['for'];
    bool forYou(Map<String, dynamic> a) =>
        a['country'] == home ||
        (a['country'] == 'EU' && euMembers.contains(home)) ||
        (a['importance'] as int) >= 3;
    return [
      for (final a in articles)
        if ((home == null || forYou(a)) &&
            (id == null || (a['topics'] as List).contains(id)))
          a,
    ];
  }

  static Map<String, dynamic> _translated(
    Map<String, dynamic> a,
    String lang,
  ) => {...a, 'lang': lang, 'headline': 'Рішення ${a['id']}'};
}

/// Lets the menus' requests, which the feed does not wait for, finish.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A phone-wide screen (iPhone 15, 393 pt), tall enough for the whole week.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 1600) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<FeedController> _pump(
  WidgetTester tester,
  _Server server, {
  FeedLanguage words = FeedLanguage.en,
}) async {
  _phone(tester);
  final feed = FeedController(api: server.api);
  await tester.pumpWidget(
    testApp(
      language: words,
      onGenerateRoute: onGenerateRoute,
      home: FeedScreen(
        controller: feed,
        newCheckEvery: const Duration(hours: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return feed;
}

/// The menu's chip: For you, the whole world or a topic.
const _topics = ValueKey('filter-topic');

/// Opens a chip's pull-down and picks [item].
Future<void> _pick(WidgetTester tester, Key chip, String item) async {
  await tester.tap(find.byKey(chip));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(CupertinoMenuItem),
      matching: find.text(item),
    ),
  );
  await tester.pumpAndSettle();
}

/// Closes an open menu without picking.
Future<void> _close(WidgetTester tester) async {
  await tester.tapAt(const Offset(20, 20));
  await tester.pumpAndSettle();
}

/// The chip's line: its label and icon, the chevron after them.
Text _line(WidgetTester tester, Key chip) => tester.widget<Text>(
  find.descendant(of: find.byKey(chip), matching: find.byType(Text)).first,
);

/// What the chip shows as text; empty when it shows an icon.
String _label(WidgetTester tester, Key chip) {
  final span = _line(tester, chip).textSpan!;
  return span is TextSpan ? span.toPlainText() : '';
}

/// The chip's icon in place of a label, or null.
IconData? _icon(WidgetTester tester, Key chip) {
  final span = _line(tester, chip).textSpan;
  return span is WidgetSpan ? (span.child as Icon).icon : null;
}

/// The colour of the chip's label (or icon), and of its chevron, as ARGB.
int _ink(WidgetTester tester, Key chip) =>
    _line(tester, chip).style!.color!.toARGB32();

int _chevron(WidgetTester tester, Key chip) => tester
    .widget<Icon>(
      find.descendant(
        of: find.byKey(chip),
        matching: find.byIcon(CupertinoIcons.chevron_down),
      ),
    )
    .color!
    .toARGB32();

Finder _box(Key chip) => find
    .descendant(of: find.byKey(chip), matching: find.byType(Container))
    .first;

/// What VoiceOver says for the chip.
String _spoken(WidgetTester tester, Key chip) =>
    tester.getSemantics(_box(chip)).label;

Iterable<String> _shown(WidgetTester tester) => {
  for (final t in tester.widgetList<Text>(find.textContaining('Decision ')))
    t.data!.replaceFirst('Decision ', ''),
};

/// The open menu's items, top to bottom.
List<String> _menu(WidgetTester tester) => [
  for (final item in tester.widgetList<CupertinoMenuItem>(
    find.byType(CupertinoMenuItem),
  ))
    ((item.child as Semantics).child! as Text).data!,
];

/// The icon before [title] in the open menu, or null.
IconData? _menuIcon(WidgetTester tester, String title) {
  final item = tester
      .widgetList<CupertinoMenuItem>(find.byType(CupertinoMenuItem))
      .singleWhere(
        (i) => ((i.child as Semantics).child! as Text).data == title,
      );
  return (item.leading as Icon?)?.icon;
}

/// The colour of the open menu's checkmark, as ARGB.
int _checkmark(WidgetTester tester) => tester
    .widget<Icon>(find.byIcon(CupertinoIcons.checkmark_alt))
    .color!
    .toARGB32();

/// The WCAG contrast of [fg] on [bg] (both opaque).
double _contrast(Color fg, Color bg) {
  final a = fg.computeLuminance(), b = bg.computeLuminance();
  return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
}

/// The checked item of the open menu.
String _checked(WidgetTester tester) => [
  for (final item in tester.widgetList<CupertinoMenuItem>(
    find.byType(CupertinoMenuItem),
  ))
    if (item.trailing != null) ((item.child as Semantics).child! as Text).data!,
].single;

const _black = 0xFF000000;
const _lightRed = 0xFFC41230;
const _darkRed = 0xFFFF3B55;

void main() {
  late List<(String, Map<String, Object>)> events;
  late Map<String, String> userProperties;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    events = [];
    userProperties = {};
    analytics = Analytics(
      (name, parameters) async => events.add((name, parameters)),
      (name, value) async => userProperties[name] = value,
    );
  });
  tearDown(() {
    analytics = Analytics();
    readPhoneRegion = () async => null;
  });

  List<Map<String, Object>> filterEvents() => [
    for (final e in events)
      if (e.$1 == 'filter_changed') e.$2,
  ];

  /// A phone whose region is [country] (#170).
  void region(String country) => readPhoneRegion = () async => country;

  /// For you for a reader in Germany: Japan and Türkiye matter less.
  const forGermany = ['de1', 'us1', 'eu1', 'gb1', 'de2', 'us2'];

  testWidgets('a new reader sees For you, in grey; with no home country it '
      "is the whole world's feed", (tester) async {
    final server = _Server();
    final feed = await _pump(tester, server);
    expect(feed.where, FeedWhere.forYou);
    expect(feed.homeCountry, isNull);
    expect(_label(tester, _topics), 'For you');
    expect(_ink(tester, _topics), _black);
    expect(_chevron(tester, _topics), _black);
    expect(_icon(tester, _topics), isNull);
    expect(_spoken(tester, _topics), 'For you');
    expect(_shown(tester), [...forGermany.take(5), 'jp1', 'us2', 'tr1']);
    final first = server.feedRequests.single.queryParameters;
    for (final param in ['country', 'group', 'topic', 'for']) {
      expect(first.containsKey(param), isFalse, reason: param);
    }
    // No Where chip any more (Yurii, 27 Oct, #170).
    expect(find.byKey(const ValueKey('filter-where')), findsNothing);
    // Under the date.
    expect(
      tester.getRect(find.byKey(_topics)).top,
      greaterThan(
        tester.getRect(find.text(longDay(DateTime.now(), l10nFor()))).bottom -
            4,
      ),
    );
  });

  testWidgets("with the phone's region, For you asks for that country: its "
      "own, the EU's for a member, the world's that matter", (tester) async {
    region('DE');
    final server = _Server();
    final feed = await _pump(tester, server);
    expect(feed.homeCountry, 'DE');
    expect(server.feedRequests.single.queryParameters['for'], 'DE');
    expect(_shown(tester), forGermany);
    // The region is enough: the server is not asked where the phone is.
    expect(server.log.where((u) => u.path == '/locate'), isEmpty);
    expect(userProperties['home_country'], 'DE');
  });

  testWidgets('a phone without a region asks the server where it is; For you '
      'then shows that country, and the next launch starts with it', (
    tester,
  ) async {
    final server = _Server(located: 'DE');
    final feed = await _pump(tester, server);
    expect(feed.homeCountry, 'DE');
    // The feed first, then the country, then For you for it.
    expect(server.feedRequests.map((u) => u.queryParameters['for']), [
      null,
      'DE',
    ]);
    expect(_shown(tester), forGermany);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('feed.located'), 'DE');
    expect(userProperties['home_country'], 'DE');

    server.log.clear();
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, server);
    expect(server.feedRequests.map((u) => u.queryParameters['for']), ['DE']);
    // Asked again, quietly, in case the phone has moved.
    expect(server.log.where((u) => u.path == '/locate'), hasLength(1));
  });

  testWidgets("the phone's region is iOS's Region setting, asked of iOS: "
      'not the first language\'s', (tester) async {
    const channel = MethodChannel('official_news/region');
    final messenger = tester.binding.defaultBinaryMessenger;
    String? answer;
    var asked = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked++;
      return answer;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // A phone in English (UK) set to Germany (Yurii, #201): iOS says DE.
    answer = 'DE';
    expect(await phoneRegion(), 'DE');
    // Anything but two capital letters is no country: the server is asked.
    for (final odd in ['en-GB', '419', '', null]) {
      answer = odd;
      expect(await phoneRegion(), isNull, reason: odd);
    }
    // Android keeps no region apart from its languages: not asked.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    asked = 0;
    expect(await phoneRegion(), isNull);
    expect(asked, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('when the server tells the country, the feed on screen stays '
      "until For you's page arrives", (tester) async {
    final server = _Server(located: 'DE', holdForYou: Completer<void>());
    await _pump(tester, server);
    // The whole world's feed, readable, while For you's page is on its way.
    expect(server.feedRequests.last.queryParameters['for'], 'DE');
    expect(_shown(tester), contains('tr1'));
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    server.holdForYou!.complete();
    await tester.pumpAndSettle();
    expect(_shown(tester), forGermany);
  });

  testWidgets('the menu: For you, the whole world, then the topics, busiest '
      'first, no counts', (tester) async {
    await _pump(tester, _Server());
    await tester.tap(find.byKey(_topics));
    await tester.pumpAndSettle();
    expect(_menu(tester), [
      'For you',
      'The whole world',
      'Economy',
      'Health',
      'Trade',
      'Security and defence',
    ]);
    expect(find.byType(CupertinoMenuDivider), findsOneWidget);
    // Names only: no counts, no second line.
    expect(
      tester
          .widgetList<CupertinoMenuItem>(find.byType(CupertinoMenuItem))
          .map((i) => i.subtitle),
      everyElement(isNull),
    );
    // Each one after its icon; a topic's is the one its chip shows.
    expect(_menuIcon(tester, 'For you'), CupertinoIcons.sparkles);
    expect(_menuIcon(tester, 'The whole world'), CupertinoIcons.globe);
    for (final (name, id) in [
      ('Economy', 'economy'),
      ('Health', 'health'),
      ('Trade', 'trade'),
      ('Security and defence', 'security-defence'),
    ]) {
      expect(_menuIcon(tester, name), topicIcons[id], reason: name);
    }
    // The checkmark is on the choice, in the filters' red, and VoiceOver
    // says so.
    expect(_checked(tester), 'For you');
    expect(_checkmark(tester), _lightRed);
    expect(
      tester.getSemantics(find.text('For you').last),
      isSemantics(label: 'For you', isSelected: true),
    );
  });

  testWidgets('the long menu stays below the status bar', (tester) async {
    _phone(tester);
    // An iPhone's status bar and home indicator, on a screen shorter than
    // the menu.
    tester.view.physicalSize = const Size(393, 300) * 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    final feed = FeedController(api: _Server().api);
    await tester.pumpWidget(
      testApp(
        home: FeedScreen(
          controller: feed,
          newCheckEvery: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_topics));
    await tester.pumpAndSettle();
    // Taller than the screen: it starts just under the status bar, and
    // scrolls.
    final first = tester.getRect(find.byType(CupertinoMenuItem).first);
    expect(first.top, greaterThanOrEqualTo(62 + 8));
  });

  testWidgets('the whole world: every country, without for=, kept for the '
      'next launch', (tester) async {
    region('DE');
    final server = _Server();
    final feed = await _pump(tester, server);
    await _pick(tester, _topics, 'The whole world');
    expect(feed.where, FeedWhere.all);
    expect(
      server.feedRequests.last.queryParameters.containsKey('for'),
      isFalse,
    );
    expect(_shown(tester), hasLength(8));
    expect(_label(tester, _topics), 'The whole world');
    expect(_ink(tester, _topics), _black);
    expect(_spoken(tester, _topics), 'The whole world');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('feed.where'), 'world');

    await _pick(tester, _topics, 'For you');
    expect(feed.where, FeedWhere.forYou);
    expect(server.feedRequests.last.queryParameters['for'], 'DE');
    expect(_shown(tester), forGermany);
    expect(prefs.getString('feed.where'), isNull);
  });

  testWidgets('one topic at a time, across the world: the chip shows its icon '
      'in red', (tester) async {
    region('DE');
    final server = _Server();
    final feed = await _pump(tester, server);
    await _pick(tester, _topics, 'Health');
    final asked = server.feedRequests.last.queryParameters;
    expect(asked['topic'], 'health');
    expect(asked.containsKey('for'), isFalse);
    expect(feed.where, FeedWhere.all);
    expect(_shown(tester), ['us1', 'de2', 'tr1']);
    expect(_icon(tester, _topics), CupertinoIcons.staroflife_fill);
    expect(_label(tester, _topics), '');
    expect(
      find.descendant(of: find.byKey(_topics), matching: find.text('Health')),
      findsNothing,
    );
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(_topics),
        matching: find.byIcon(CupertinoIcons.staroflife_fill),
      ),
    );
    expect(icon.color!.toARGB32(), _lightRed);
    expect(_chevron(tester, _topics), _lightRed);
    expect(_spoken(tester, _topics), 'Topic: Health');
    await tester.tap(find.byKey(_topics));
    await tester.pumpAndSettle();
    expect(_menuIcon(tester, 'Health'), _icon(tester, _topics));
    expect(_checked(tester), 'Health');
    await _close(tester);

    await _pick(tester, _topics, 'Trade');
    expect(server.feedRequests.last.queryParameters['topic'], 'trade');
    expect(_icon(tester, _topics), CupertinoIcons.arrow_right_arrow_left);
    expect(_shown(tester), ['eu1']);

    await _pick(tester, _topics, 'For you');
    expect(_label(tester, _topics), 'For you');
    expect(_icon(tester, _topics), isNull);
    final back = server.feedRequests.last.queryParameters;
    expect(back.containsKey('topic'), isFalse);
    expect(back['for'], 'DE');
    expect(_shown(tester), forGermany);
  });

  test('every request of a feed carries its choice', () async {
    region('DE');
    final server = _Server(pageSize: 1);
    final feed = FeedController(api: server.api);
    await feed.start();
    await _settle();
    expect(feed.items.map((a) => a.id), ['de1']);
    await feed.loadMore();
    await feed.checkForNew();
    await _settle();
    expect(server.feedRequests, hasLength(3));
    for (final request in server.feedRequests) {
      expect(request.queryParameters['for'], 'DE', reason: '$request');
    }
    expect(server.feedRequests[1].queryParameters['cursor'], '1');
    expect(server.feedRequests[2].queryParameters['after'], isNotNull);

    server.log.clear();
    await feed.setFeed(FeedWhere.all, topic: 'health');
    await _settle();
    await feed.loadMore();
    await feed.checkForNew();
    await _settle();
    expect(server.feedRequests, hasLength(3));
    for (final request in server.feedRequests) {
      final q = request.queryParameters;
      expect(q['topic'], 'health', reason: '$request');
      expect(q.containsKey('for'), isFalse, reason: '$request');
      expect(q.containsKey('country'), isFalse, reason: '$request');
      expect(q.containsKey('group'), isFalse, reason: '$request');
    }
    expect(feed.items.map((a) => a.id), ['us1', 'de2']);
    // The topics are the whole world's either way: not asked again.
    expect(server.topicRequests, isEmpty);
  });

  testWidgets('a topic with nothing in it says so, with a way back', (
    tester,
  ) async {
    final server = _Server(extraTopics: const ['housing']);
    await _pump(tester, server);
    await _pick(tester, _topics, 'Housing');
    expect(_shown(tester), isEmpty);
    expect(find.text('No decisions here in the last 7 days.'), findsOneWidget);
    // The button that undoes a filter is the filters' red.
    expect(
      tester
          .widget<Text>(find.text('Show all topics'))
          .style!
          .color!
          .toARGB32(),
      _lightRed,
    );
    expect(find.text('No decisions yet today.'), findsNothing);
    await tester.tap(find.byKey(_topics));
    await tester.pumpAndSettle();
    expect(_checked(tester), 'Housing');
    await _close(tester);

    await tester.tap(find.text('Show all topics'));
    await tester.pumpAndSettle();
    expect(_label(tester, _topics), 'The whole world');
    expect(_shown(tester), hasLength(8));
    expect(find.text('No decisions here in the last 7 days.'), findsNothing);
  });

  testWidgets(
    'the choices are saved; the next launch opens with them, not the saved feed',
    (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _pick(tester, _topics, 'Economy');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('feed.where'), 'world');
      expect(prefs.getString('feed.topic'), 'economy');
      // The first page kept on the phone is still the one without a topic.
      expect(prefs.getString('feed.lastPage'), contains('"tr1"'));

      // The next launch, offline: a topic's feed is not saved, so it says it
      // could not load, rather than showing other topics' news.
      final next = _Server()..offline = true;
      await tester.pumpWidget(const SizedBox());
      final feed = await _pump(tester, next);
      expect(feed.where, FeedWhere.all);
      expect(feed.topic, 'economy');
      expect(_icon(tester, _topics), CupertinoIcons.chart_bar_alt_fill);
      expect(_spoken(tester, _topics), 'Topic: Economy');
      expect(_shown(tester), isEmpty);
      expect(
        find.text("Couldn't load the news. Pull down to retry."),
        findsOneWidget,
      );
      expect(next.feedRequests.first.queryParameters['topic'], 'economy');

      // For you, with no home country here, opens from the saved page at once.
      await _pick(tester, _topics, 'For you');
      expect(_shown(tester), hasLength(8));
      expect(prefs.getString('feed.where'), isNull);
      expect(prefs.getString('feed.topic'), isNull);
    },
  );

  testWidgets("For you's first page is kept for its country, and opens "
      'offline', (tester) async {
    region('DE');
    await _pump(tester, _Server());
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('feed.lastPage.for.DE'),
      allOf(contains('"de1"'), isNot(contains('"tr1"'))),
    );
    expect(prefs.getString('feed.lastPage'), isNull);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _Server()..offline = true);
    expect(_shown(tester), forGermany);
  });

  test("a saved choice: 'world' is the whole world, anything else For you", () {
    expect(FeedWhere.fromSaved('world'), FeedWhere.all);
    for (final saved in [
      null,
      '',
      'all',
      'foryou',
      'local',
      'global',
      'country:GB',
      'group:g20',
      'x:y',
    ]) {
      expect(FeedWhere.fromSaved(saved), FeedWhere.forYou, reason: saved);
    }
    for (final where in [FeedWhere.all, FeedWhere.forYou]) {
      expect(FeedWhere.fromSaved(where.saved), where);
    }
  });

  test('a country or a group saved before For you opens For you; a saved '
      'topic stays, across the world', () async {
    region('DE');
    SharedPreferences.setMockInitialValues({'feed.where': 'country:JP'});
    final server = _Server();
    final feed = FeedController(api: server.api);
    await feed.start();
    await _settle();
    expect(feed.where, FeedWhere.forYou);
    final asked = server.feedRequests.single.queryParameters;
    expect(asked['for'], 'DE');
    expect(asked.containsKey('country'), isFalse);

    SharedPreferences.setMockInitialValues({
      'feed.where': 'group:g7',
      'feed.topic': 'health',
      'feed.scope': 'local',
      // The Where menus and the flag kept for them (#68).
      'feed.whereMenu.en': '{"groups":null,"countries":[]}',
      'feed.whereMenu.uk': '{"groups":null,"countries":[]}',
      'feed.noCountries': true,
    });
    final again = _Server();
    final next = FeedController(api: again.api);
    await next.start();
    await _settle();
    expect(next.where, FeedWhere.all);
    expect(next.topic, 'health');
    final q = again.feedRequests.single.queryParameters;
    expect(q['topic'], 'health');
    for (final param in ['group', 'country', 'for']) {
      expect(q.containsKey(param), isFalse, reason: param);
    }
    // The first filters build's Local is dropped as before, and the Where
    // menus with it; nothing asks for them any more.
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'feed.scope',
      'feed.whereMenu.en',
      'feed.whereMenu.uk',
      'feed.noCountries',
    ]) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }
    expect(again.log.where((u) => u.path == '/countries'), isEmpty);
  });

  testWidgets('the analytics event says what the choice is now', (
    tester,
  ) async {
    await _pump(tester, _Server());
    await _pick(tester, _topics, 'The whole world');
    await _pick(tester, _topics, 'Health');
    await _pick(tester, _topics, 'Health'); // no change: no event
    await _pick(tester, _topics, 'For you');
    expect(filterEvents(), [
      {'where': 'all', 'topic': 'all'},
      {'where': 'all', 'topic': 'health'},
      {'where': 'forYou', 'topic': 'all'},
    ]);
    // Never `value`: Google Analytics keeps it for a number and drops a text.
    for (final e in filterEvents()) {
      expect(e.containsKey('value'), isFalse);
    }
  });

  testWidgets("For you's top stories say whose they are; the whole world's "
      'say how they were picked', (tester) async {
    region('DE');
    await _pump(tester, _Server(topIds: const ['de1', 'us1', 'gb1']));
    expect(find.text('Top stories for you'), findsOneWidget);
    expect(
      find.text("Germany · European Union · the world's top stories"),
      findsOneWidget,
    );
    await _pick(tester, _topics, 'The whole world');
    expect(find.text('Top stories'), findsOneWidget);
    expect(
      find.text('By importance over three days, one per country'),
      findsOneWidget,
    );
    expect(find.text('Top stories for you'), findsNothing);
  });

  testWidgets('a reader outside the EU, or in a country the app has no name '
      'for', (tester) async {
    region('US');
    await _pump(tester, _Server(topIds: const ['de1', 'us1', 'gb1']));
    expect(
      find.text("United States · the world's top stories"),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    region('NO');
    await _pump(tester, _Server(topIds: const ['de1', 'us1', 'gb1']));
    expect(find.text("Your country · the world's top stories"), findsOneWidget);
    // Every EU member has its name (#170, part 3).
    await tester.pumpWidget(const SizedBox());
    region('SK');
    await _pump(tester, _Server(topIds: const ['de1', 'us1', 'gb1']));
    expect(
      find.text("Slovakia · European Union · the world's top stories"),
      findsOneWidget,
    );
  });

  group('a server without /topics', () {
    testWidgets('the menu has For you and the whole world only', (
      tester,
    ) async {
      final server = _Server(menus: false);
      final feed = await _pump(tester, server);
      expect(feed.topics, isNull);
      await tester.tap(find.byKey(_topics));
      await tester.pumpAndSettle();
      expect(_menu(tester), ['For you', 'The whole world']);
      await _close(tester);
      expect(
        server.feedRequests.where(
          (u) =>
              u.queryParameters.containsKey('country') ||
              u.queryParameters.containsKey('group'),
        ),
        isEmpty,
      );
    });

    testWidgets('a topic chosen before stays, so it can be cleared', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'feed.topic': 'health'});
      final server = _Server(menus: false);
      await _pump(tester, server);
      expect(_spoken(tester, _topics), 'Topic: Health'); // the app's own name
      await _pick(tester, _topics, 'For you');
      expect(_label(tester, _topics), 'For you');
      await tester.tap(find.byKey(_topics));
      await tester.pumpAndSettle();
      expect(_menu(tester), ['For you', 'The whole world']);
    });
  });

  group("names in the app's language", () {
    testWidgets('the menu and the chip, in Ukrainian', (tester) async {
      SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
      final server = _Server();
      await _pump(tester, server, words: FeedLanguage.uk);
      expect(server.topicRequests.single.queryParameters['lang'], 'uk');
      expect(_label(tester, _topics), 'Для вас');
      await tester.tap(find.byKey(_topics));
      await tester.pumpAndSettle();
      expect(_menu(tester), [
        'Для вас',
        'Увесь світ',
        'Економіка',
        'Здоров’я',
        'Торгівля',
        'Безпека та оборона',
      ]);
      expect(_menuIcon(tester, 'Економіка'), topicIcons['economy']);
      await _close(tester);
      await _pick(tester, _topics, 'Економіка');
      expect(_spoken(tester, _topics), 'Тема: Економіка');
      await _pick(tester, _topics, 'Увесь світ');
      expect(_label(tester, _topics), 'Увесь світ');
    });

    test('another language, offline: the topics named in it', () async {
      SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
      final server = _Server();
      final feed = FeedController(api: server.api);
      await feed.start();
      await _settle();
      await feed.setFeed(FeedWhere.all, topic: 'economy');
      await _settle();
      server.offline = true;
      await feed.setLanguage(FeedLanguage.de);
      await _settle();
      final de = l10nFor(FeedLanguage.de);
      expect(topicName('economy', feed.topics, de), 'Wirtschaft');
    });

    testWidgets('a topic not in the menu, also after a restart', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
      await _pump(tester, _Server(), words: FeedLanguage.uk);
      await _pick(tester, _topics, 'Торгівля');
      expect(_spoken(tester, _topics), 'Тема: Торгівля');
      // The next launch: no trade this week, and the chosen topic stays.
      await tester.pumpWidget(const SizedBox());
      await _pump(
        tester,
        _Server(
          articles: [
            for (final a in _week)
              if (a['id'] != 'eu1') a,
          ],
        ),
        words: FeedLanguage.uk,
      );
      expect(_spoken(tester, _topics), 'Тема: Торгівля');
      await tester.tap(find.byKey(_topics));
      await tester.pumpAndSettle();
      expect(_checked(tester), 'Торгівля');
    });
  });

  testWidgets('a new choice rolls into the chip as the old one rolls out, '
      'and the chip springs to its new width', (tester) async {
    Widget bar(FeedWhere where) => testApp(
      home: Center(
        child: FeedFilterBar(
          where: where,
          topic: null,
          topics: const [],
          onChoose: (_, _) {},
        ),
      ),
    );
    Finder words() => find.descendant(
      of: find.byKey(_topics),
      matching: find.byWidgetPredicate((w) => w is Text && w.textSpan != null),
    );
    await tester.pumpWidget(bar(FeedWhere.forYou));
    final narrow = tester.getSize(find.byKey(_topics)).width;

    await tester.pumpWidget(bar(FeedWhere.all));
    await tester.pump(const Duration(milliseconds: 80));
    // Both words for a moment, and a width on its way.
    expect(words(), findsNWidgets(2));
    final growing = tester.getSize(find.byKey(_topics)).width;

    await tester.pumpAndSettle();
    expect(words(), findsOneWidget);
    expect(_label(tester, _topics), 'The whole world');
    final wide = tester.getSize(find.byKey(_topics)).width;
    expect(growing, greaterThan(narrow));
    expect(growing, lessThan(wide));
  });

  testWidgets('in dark mode a chosen chip is the filter red, the rest white', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        home: CupertinoTheme(
          data: const CupertinoThemeData(brightness: Brightness.dark),
          child: Center(
            child: FeedFilterBar(
              where: FeedWhere.all,
              topic: 'health',
              topics: const [FeedTopic('health', 'Health')],
              onChoose: (_, _) {},
            ),
          ),
        ),
      ),
    );
    expect(_icon(tester, _topics), topicIcon('health'));
    expect(_chevron(tester, _topics), _darkRed);
    expect(filterRed.darkColor.toARGB32(), _darkRed);
    // The menu's checkmark is the same red.
    await tester.tap(find.byKey(_topics));
    await tester.pumpAndSettle();
    expect(_checkmark(tester), _darkRed);
    await _close(tester);
    await tester.pumpWidget(
      testApp(
        home: CupertinoTheme(
          data: const CupertinoThemeData(brightness: Brightness.dark),
          child: Center(
            child: FeedFilterBar(
              where: FeedWhere.forYou,
              topic: null,
              topics: const [],
              onChoose: (_, _) {},
            ),
          ),
        ),
      ),
    );
    // The new choice rolls in as the old one rolls out (#141).
    await tester.pumpAndSettle();
    expect(_ink(tester, _topics), 0xFFFFFFFF);
  });

  test('the filter red is at least 4.5:1 on the grey chip, light and dark', () {
    // The chip's grey over the feed's white or black page, as it is drawn.
    Color chip(Color fill, Color page) => Color.alphaBlend(fill, page);
    final light = chip(
      CupertinoColors.tertiarySystemFill.color,
      const Color(0xFFFFFFFF),
    );
    final dark = chip(
      CupertinoColors.tertiarySystemFill.darkColor,
      const Color(0xFF000000),
    );
    expect(filterRed.color.toARGB32(), _lightRed);
    expect(_contrast(filterRed.color, light), greaterThanOrEqualTo(4.5));
    expect(_contrast(filterRed.darkColor, dark), greaterThanOrEqualTo(4.5));
    // The brand red is not, in dark mode: why the filters have their own.
    expect(_contrast(const Color(0xFFFA2D48), dark), lessThan(4.5));
  });

  test('every topic of the fixed list has its own icon', () {
    expect(topicIcons.keys.toSet(), topicIds.toSet());
    expect(topicIcons.values.toSet(), hasLength(topicIds.length));
    expect(topicIcons.values, isNot(contains(otherTopicIcon)));
    // No icon that means something else in an app (Yurii's review, 16 Oct):
    // a heart reads as a favourite, a ticked box as chosen.
    for (final other in [
      CupertinoIcons.heart_fill,
      CupertinoIcons.checkmark_square_fill,
      CupertinoIcons.cloud_sun_fill,
    ]) {
      expect(topicIcons.values, isNot(contains(other)));
    }
  });

  testWidgets("a topic the app does not know yet: the server's name", (
    tester,
  ) async {
    final server = _Server(extraTopics: const ['housing']);
    await _pump(tester, server);
    await _pick(tester, _topics, 'Housing');
    expect(server.feedRequests.last.queryParameters['topic'], 'housing');
    expect(_icon(tester, _topics), otherTopicIcon);
    expect(_spoken(tester, _topics), 'Topic: Housing');
  });

  testWidgets('Settings → My country: the phone\'s region first, then the '
      'countries by name; a choice wins, and For you follows it', (
    tester,
  ) async {
    region('DE');
    final server = _Server();
    final feed = await _pump(tester, server);
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
    await tester.pumpAndSettle();
    final row = find.ancestor(
      of: find.text('My country'),
      matching: find.byType(CupertinoListTile),
    );
    expect(
      find.descendant(of: row, matching: find.text('Germany')),
      findsOneWidget,
    );
    await tester.tap(find.text('My country'));
    await tester.pumpAndSettle();
    final tiles = tester
        .widgetList<CupertinoListTile>(find.byType(CupertinoListTile))
        .toList();
    // The phone's region first, checked, with its country beside it.
    expect(
      ((tiles.first.title as Semantics).child! as Text).data,
      "By the phone's region",
    );
    expect((tiles.first.additionalInfo! as Text).data, 'Germany');
    expect(tiles.first.trailing, isNotNull);
    // Then the countries with sources and the EU's members, by name, once.
    final names = [
      for (final tile in tiles.skip(1))
        ((tile.title as Semantics).child! as Text).data!,
    ];
    expect(names, hasLength(homeCountries.length));
    expect(names, hasLength(42));
    expect(names, [...names]..sort());
    expect(names, containsAll(['Austria', 'Ukraine', 'United States']));
    // No EU (not a country), and no Russia or Saudi Arabia: no sources there.
    for (final none in ['European Union', 'Russia', 'Saudi Arabia']) {
      expect(names, isNot(contains(none)));
    }

    await tester.ensureVisible(find.text('Ukraine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ukraine'));
    await tester.pumpAndSettle();
    expect(feed.homeCountry, 'UA');
    expect(server.feedRequests.last.queryParameters['for'], 'UA');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('feed.home'), 'UA');
    expect(userProperties['home_country'], 'UA');

    // Back up the page's list: its first rows are built again.
    await tester.scrollUntilVisible(
      find.text("By the phone's region"),
      -300,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text("By the phone's region"));
    await tester.pumpAndSettle();
    expect(feed.homeCountry, 'DE');
    expect(server.feedRequests.last.queryParameters['for'], 'DE');
    expect(prefs.getString('feed.home'), isNull);
  });

  test("the countries sort by each language's alphabet (#206)", () {
    List<String> sorted(FeedLanguage lang) {
      final l10n = l10nFor(lang);
      return [for (final code in homeCountries) countryName(code, l10n)]..sort(
        (a, b) =>
            alphabetKey(a, lang.code).compareTo(alphabetKey(b, lang.code)),
      );
    }

    // A letter with a mark beside its own.
    final de = sorted(FeedLanguage.de);
    expect(de.indexOf('Österreich'), greaterThan(de.indexOf('Niederlande')));
    expect(de.indexOf('Österreich'), lessThan(de.indexOf('Polen')));
    expect(de.indexOf('Dänemark'), lessThan(de.indexOf('Deutschland')));
    final es = sorted(FeedLanguage.es);
    expect(es.indexOf('Bélgica'), lessThan(es.indexOf('Bulgaria')));
    // Ukrainian І after Е and before К, not before А.
    final uk = sorted(FeedLanguage.uk);
    expect(uk.first, 'Австралія');
    expect(uk.indexOf('Індія'), greaterThan(uk.indexOf('Естонія')));
    expect(uk.indexOf('Італія'), lessThan(uk.indexOf('Канада')));
    expect(sorted(FeedLanguage.ru).first, 'Австралия');
  });

  testWidgets('My country names a country the app does not know as Another '
      'country, and follows the server while Settings is open', (tester) async {
    region('NO');
    await _pump(tester, _Server());
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
    await tester.pumpAndSettle();
    expect(find.text('Another country'), findsOneWidget);
    expect(find.text('NO'), findsNothing);

    // A country chosen, no region: then back to the phone, and the server's
    // answer shows on the open page without reopening it.
    await tester.pumpWidget(const SizedBox());
    readPhoneRegion = () async => null;
    SharedPreferences.setMockInitialValues({'feed.home': 'UA'});
    await _pump(tester, _Server(located: 'DE'));
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My country'));
    await tester.pumpAndSettle();
    final phoneRow = find.ancestor(
      of: find.text("By the phone's region"),
      matching: find.byType(CupertinoListTile),
    );
    expect(
      find.descendant(of: phoneRow, matching: find.text('Not known')),
      findsOneWidget,
    );
    await tester.tap(find.text("By the phone's region"));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: phoneRow, matching: find.text('Germany')),
      findsOneWidget,
    );
  });

  test('a chosen country is kept, and the server is not asked where the '
      'phone is', () async {
    SharedPreferences.setMockInitialValues({'feed.home': 'UA'});
    final server = _Server(located: 'DE');
    final feed = FeedController(api: server.api);
    await feed.start();
    await _settle();
    expect(feed.homeCountry, 'UA');
    expect(feed.phoneCountry, isNull);
    expect(server.feedRequests.single.queryParameters['for'], 'UA');
    expect(server.log.where((u) => u.path == '/locate'), isEmpty);

    // Back to the phone's, which has no region: now it asks.
    await feed.setChosenCountry(null);
    await _settle();
    expect(feed.homeCountry, 'DE');
    expect(server.log.where((u) => u.path == '/locate'), hasLength(1));
    expect(server.feedRequests.last.queryParameters['for'], 'DE');
  });
}
