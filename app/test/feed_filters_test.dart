import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/core/news_widgets.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// The feed's filters (#67, #68): the Where and Topics chips under the date,
/// the requests they make, the Country in Settings, the choices saved on the
/// phone, the empty filtered feed, and a server without the new endpoints.

Map<String, dynamic> _article(
  String id, {
  required String country,
  List<String> topics = const [],
  required int feedSeq,
  String? lang,
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
  'importance': 3,
  'imageUrl': null,
  'originalUrl': 'https://gov.test/$id',
  'lang': ?lang,
};

/// The week's feed, newest first: two from Germany, one from the EU, two from
/// the US. Economy is the busiest topic, then health, then trade.
final _week = [
  _article('de1', country: 'DE', topics: ['economy'], feedSeq: 9),
  _article('us1', country: 'US', topics: ['economy', 'health'], feedSeq: 8),
  _article('eu1', country: 'EU', topics: ['trade'], feedSeq: 7),
  _article('de2', country: 'DE', topics: ['health'], feedSeq: 6),
  _article('us2', country: 'US', topics: ['economy'], feedSeq: 5),
];

/// EU members, whose Local feed has the EU's articles too; Poland has no
/// sources of its own.
const _eu = {'DE', 'FR', 'PL'};

const _topicNames = {
  'en': {'economy': 'Economy', 'health': 'Health', 'trade': 'Trade'},
  'uk': {'economy': 'Економіка', 'health': 'Здоров’я', 'trade': 'Торгівля'},
};

const _countryNames = {
  'en': {
    'DE': 'Germany',
    'FR': 'France',
    'US': 'United States',
    'NZ': 'New Zealand',
  },
  'uk': {
    'DE': 'Німеччина',
    'FR': 'Франція',
    'US': 'США',
    'NZ': 'Нова Зеландія',
  },
};

http.Response _ok(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// A server that follows the contract for the filters: `?country=` (with the
/// EU's articles for EU members) and `?topic=` on every article request,
/// `GET /topics` busiest first under the country, `GET /countries` (the
/// countries with sources, no bloc, by name in the language asked). Without
/// [menus], a server from before them: both answer 404 and the filters are
/// ignored. Pages of [pageSize]; the cursor is the next offset.
class _Server {
  _Server({
    List<Map<String, dynamic>>? articles,
    this.countries = const ['DE', 'FR', 'US'],
    this.menus = true,
    this.pageSize = 20,
  }) : articles = articles ?? _week;

  List<Map<String, dynamic>> articles;
  final List<String> countries;
  final bool menus;
  final int pageSize;
  final log = <Uri>[];
  bool offline = false;

  /// The article requests only.
  List<Uri> get feedRequests =>
      log.where((u) => u.path == '/articles').toList();

  ApiClient get api => ApiClient(
    baseUrl: 'https://api.test',
    client: MockClient((request) async {
      log.add(request.url);
      if (offline) return http.Response('offline', 503);
      final q = request.url.queryParameters;
      final lang = q['lang'] ?? 'en';
      switch (request.url.path) {
        case '/countries':
          if (!menus) return http.Response('{"error":"Not found"}', 404);
          final names = _countryNames[lang]!;
          return _ok({
            'countries': [
              for (final c in countries) {'code': c, 'name': names[c]!},
            ]..sort((a, b) => a['name']!.compareTo(b['name']!)),
          });
        case '/topics':
          if (!menus) return http.Response('{"error":"Not found"}', 404);
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
              for (final id in ids) {'id': id, 'name': _topicNames[lang]![id]},
            ],
          });
        case '/articles':
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
            'top': [],
          });
      }
      return http.Response('{"error":"Not found"}', 404);
    }),
  );

  List<Map<String, dynamic>> _matching(
    Map<String, String> q, {
    bool topic = true,
  }) {
    if (!menus) return articles;
    final country = q['country'];
    final id = topic ? q['topic'] : null;
    return [
      for (final a in articles)
        if ((country == null ||
                a['country'] == country ||
                (a['country'] == 'EU' && _eu.contains(country))) &&
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

/// A phone-sized screen (iPhone 15, 393 x 852 pt).
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 852) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<FeedController> _pump(
  WidgetTester tester,
  _Server server, {
  String? region = 'DE',
  FeedLanguage words = FeedLanguage.en,
}) async {
  _phone(tester);
  final feed = FeedController(api: server.api, phoneRegion: () => region);
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

const _where = ValueKey('filter-where');
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

/// The chip's colour: red while it narrows the feed.
Color? _fill(WidgetTester tester, Key chip) {
  final box = tester.widget<Container>(
    find
        .descendant(of: find.byKey(chip), matching: find.byType(Container))
        .first,
  );
  return (box.decoration! as BoxDecoration).color;
}

String _label(WidgetTester tester, Key chip) => tester
    .widgetList<Text>(
      find.descendant(of: find.byKey(chip), matching: find.byType(Text)),
    )
    .single
    .data!;

Iterable<String> _shown(WidgetTester tester) => tester
    .widgetList<Text>(find.textContaining('Decision '))
    .map((t) => t.data!.replaceFirst('Decision ', ''));

/// The menu's items, top to bottom.
List<String> _menu(WidgetTester tester) => [
  for (final item in tester.widgetList<CupertinoMenuItem>(
    find.byType(CupertinoMenuItem),
  ))
    ((item.child as Semantics).child! as Text).data!,
];

void main() {
  late List<(String, Map<String, Object>)> events;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    events = [];
    analytics = Analytics((name, parameters) async {
      events.add((name, parameters));
    });
  });
  tearDown(() => analytics = Analytics());

  testWidgets('a new reader sees Global and All topics, nothing narrowed', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);
    expect(_label(tester, _where), 'Global');
    expect(_label(tester, _topics), 'All topics');
    expect(_fill(tester, _where), isNot(AppColors.accent));
    expect(_fill(tester, _topics), isNot(AppColors.accent));
    expect(_shown(tester), ['de1', 'us1', 'eu1', 'de2', 'us2']);
    final first = server.feedRequests.single.queryParameters;
    expect(first.containsKey('country'), isFalse);
    expect(first.containsKey('topic'), isFalse);
    // Under the date.
    expect(
      tester.getRect(find.byKey(_where)).top,
      greaterThan(
        tester.getRect(find.text(longDay(DateTime.now(), l10nFor()))).bottom -
            4,
      ),
    );
  });

  testWidgets(
    'the Where menu: Global for all countries, Local for the phone region',
    (tester) async {
      await _pump(tester, _Server());
      await tester.tap(find.byKey(_where));
      await tester.pumpAndSettle();
      expect(_menu(tester), ['Global', 'Local']);
      expect(find.text('All countries'), findsOneWidget);
      expect(find.text('Germany'), findsOneWidget);
      // The checkmark is on the current choice, and VoiceOver says so.
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Global').last,
            matching: find.byType(CupertinoMenuItem),
          ),
          matching: find.byIcon(CupertinoIcons.checkmark_alt),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'the Topics menu: All topics, then the busiest first, no counts',
    (tester) async {
      await _pump(tester, _Server());
      await tester.tap(find.byKey(_topics));
      await tester.pumpAndSettle();
      expect(_menu(tester), ['All topics', 'Economy', 'Health', 'Trade']);
      // Names only: no counts, no second line.
      expect(
        tester
            .widgetList<CupertinoMenuItem>(find.byType(CupertinoMenuItem))
            .map((i) => i.subtitle),
        everyElement(isNull),
      );
    },
  );

  testWidgets('Local asks for the country and the chip turns red', (
    tester,
  ) async {
    final server = _Server();
    final feed = await _pump(tester, server);
    await _pick(tester, _where, 'Local');
    expect(_label(tester, _where), 'Germany');
    expect(_fill(tester, _where), AppColors.accent);
    expect(server.feedRequests.last.queryParameters['country'], 'DE');
    expect(feed.scope, FeedScope.local);
    // Germany's, and the EU's: Germany is a member.
    expect(_shown(tester), ['de1', 'eu1', 'de2']);
  });

  test('every request of a filtered feed carries its filters', () async {
    final server = _Server(pageSize: 1);
    final feed = FeedController(api: server.api, phoneRegion: () => 'DE');
    await feed.start();
    await feed.setScope(FeedScope.local);
    await feed.setTopic('health');
    await _settle();
    server.log.clear();
    // The next page (de2 is the only one, so none), then Global's.
    await feed.setScope(FeedScope.global);
    await _settle();
    await feed.loadMore();
    await feed.checkForNew();
    await _settle();
    expect(server.feedRequests, hasLength(3));
    for (final request in server.feedRequests) {
      expect(request.queryParameters['topic'], 'health', reason: '$request');
      expect(request.queryParameters.containsKey('country'), isFalse);
    }
    expect(server.feedRequests[1].queryParameters['cursor'], '1');
    expect(server.feedRequests[2].queryParameters['after'], isNotNull);
    expect(feed.items.map((a) => a.id), ['us1', 'de2']);

    server.log.clear();
    await feed.setScope(FeedScope.local);
    await _settle();
    await feed.checkForNew();
    expect(server.feedRequests.map((u) => u.queryParameters['country']), [
      'DE',
      'DE',
    ]);
    // The new check and more pages ask for no menu.
    expect(server.log.where((u) => u.path == '/topics'), hasLength(1));
  });

  testWidgets('Local shows the topics of that country only', (tester) async {
    final server = _Server();
    await _pump(tester, server);
    await _pick(tester, _where, 'Local');
    final asked = server.log.where((u) => u.path == '/topics').last;
    expect(asked.queryParameters['country'], 'DE');
    await tester.tap(find.byKey(_topics));
    await tester.pumpAndSettle();
    // de1 economy, eu1 trade, de2 health: one each.
    expect(_menu(tester).first, 'All topics');
    expect(_menu(tester).skip(1).toSet(), {'Economy', 'Trade', 'Health'});
  });

  testWidgets('one topic at a time; All topics clears it', (tester) async {
    final server = _Server();
    await _pump(tester, server);
    await _pick(tester, _topics, 'Health');
    expect(_label(tester, _topics), 'Health');
    expect(_fill(tester, _topics), AppColors.accent);
    expect(server.feedRequests.last.queryParameters['topic'], 'health');
    expect(_shown(tester), ['us1', 'de2']);

    await _pick(tester, _topics, 'Trade');
    expect(server.feedRequests.last.queryParameters['topic'], 'trade');
    expect(_shown(tester), ['eu1']);

    await _pick(tester, _topics, 'All topics');
    expect(_label(tester, _topics), 'All topics');
    expect(
      server.feedRequests.last.queryParameters.containsKey('topic'),
      isFalse,
    );
    expect(_shown(tester), hasLength(5));
  });

  testWidgets('Local and a topic together', (tester) async {
    final server = _Server();
    await _pump(tester, server);
    await _pick(tester, _where, 'Local');
    await _pick(tester, _topics, 'Economy');
    final last = server.feedRequests.last.queryParameters;
    expect(last['country'], 'DE');
    expect(last['topic'], 'economy');
    expect(_shown(tester), ['de1']);
  });

  testWidgets('an empty filtered feed says so, with the ways back', (
    tester,
  ) async {
    // Nothing from France or the EU this week.
    final server = _Server(
      articles: [
        for (final a in _week)
          if (a['country'] != 'EU') a,
      ],
    );
    await _pump(tester, server, region: 'FR');
    await _pick(tester, _topics, 'Health');
    expect(_shown(tester), ['us1', 'de2']);
    await _pick(tester, _where, 'Local');
    expect(_label(tester, _where), 'France');
    expect(_shown(tester), isEmpty);
    expect(find.text('No decisions here in the last 7 days.'), findsOneWidget);
    expect(find.text('Show all countries'), findsOneWidget);
    expect(find.text('Show all topics'), findsOneWidget);
    expect(find.text('No decisions yet today.'), findsNothing);

    await tester.tap(find.text('Show all topics'));
    await tester.pumpAndSettle();
    expect(_label(tester, _topics), 'All topics');
    expect(find.text('No decisions here in the last 7 days.'), findsOneWidget);
    expect(find.text('Show all topics'), findsNothing);

    await tester.tap(find.text('Show all countries'));
    await tester.pumpAndSettle();
    expect(_label(tester, _where), 'Global');
    expect(_shown(tester), ['de1', 'us1', 'de2', 'us2']);
    expect(find.text('No decisions here in the last 7 days.'), findsNothing);
  });

  testWidgets(
    'the choices are saved; the next launch opens with them, not the saved feed',
    (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _pick(tester, _where, 'Local');
      await _pick(tester, _topics, 'Economy');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('feed.scope'), 'local');
      expect(prefs.getString('feed.topic'), 'economy');
      // The first page kept on the phone is still the unfiltered one.
      expect(prefs.getString('feed.lastPage'), contains('"us2"'));

      // The next launch, offline: the filtered feed is not saved, so it says
      // it could not load, rather than showing other countries' news.
      final next = _Server()..offline = true;
      await tester.pumpWidget(const SizedBox());
      final feed = await _pump(tester, next);
      expect(feed.scope, FeedScope.local);
      expect(feed.topic, 'economy');
      expect(_label(tester, _where), 'Germany');
      expect(_label(tester, _topics), 'Economy'); // the saved menu's name
      expect(_shown(tester), isEmpty);
      expect(
        find.text("Couldn't load the news. Pull down to retry."),
        findsOneWidget,
      );
      expect(next.feedRequests.first.queryParameters['country'], 'DE');
      expect(next.feedRequests.first.queryParameters['topic'], 'economy');

      // Global and all topics open from the saved page at once, still offline.
      await _pick(tester, _where, 'Global');
      await _pick(tester, _topics, 'All topics');
      expect(_shown(tester), ['de1', 'us1', 'eu1', 'de2', 'us2']);
    },
  );

  testWidgets('the analytics event says what the filters are now', (
    tester,
  ) async {
    await _pump(tester, _Server());
    await _pick(tester, _where, 'Local');
    await _pick(tester, _topics, 'Health');
    await _pick(tester, _topics, 'Health'); // no change: no event
    await _pick(tester, _where, 'Global');
    final changes = [
      for (final e in events)
        if (e.$1 == 'filter_changed') e.$2,
    ];
    expect(changes, [
      {'scope': 'local', 'country': 'DE', 'topic': 'all'},
      {'scope': 'local', 'country': 'DE', 'topic': 'health'},
      {'scope': 'global', 'country': 'DE', 'topic': 'health'},
    ]);
  });

  group('the Local country', () {
    test('the phone region when it has sources', () async {
      final feed = FeedController(api: _Server().api, phoneRegion: () => 'us');
      await feed.start();
      await _settle();
      expect(feed.localCountry, 'US');
    });

    testWidgets(
      "an EU member without sources: its own country, with the EU's decisions",
      (tester) async {
        final server = _Server();
        await _pump(tester, server, region: 'PL');
        await _pick(tester, _where, 'Local');
        expect(_label(tester, _where), 'Poland');
        expect(server.feedRequests.last.queryParameters['country'], 'PL');
        expect(_shown(tester), ['eu1']);
      },
    );

    testWidgets(
      'a country with no sources: its own, empty, with the way back',
      (tester) async {
        final server = _Server();
        await _pump(tester, server, region: 'UA');
        await tester.tap(find.byKey(_where));
        await tester.pumpAndSettle();
        expect(find.text('Ukraine'), findsOneWidget); // under Local
        await tester.tapAt(const Offset(20, 20));
        await tester.pumpAndSettle();
        await _pick(tester, _where, 'Local');
        expect(_label(tester, _where), 'Ukraine');
        expect(server.feedRequests.last.queryParameters['country'], 'UA');
        expect(_shown(tester), isEmpty);
        expect(
          find.text('No decisions here in the last 7 days.'),
          findsOneWidget,
        );
        expect(find.text('Show all countries'), findsOneWidget);
      },
    );

    test(
      'a Local feed asks once, before and after the countries arrive',
      () async {
        SharedPreferences.setMockInitialValues({'feed.scope': 'local'});
        final server = _Server();
        final feed = FeedController(api: server.api, phoneRegion: () => 'UA');
        await feed.start();
        await _settle();
        expect(server.feedRequests.map((u) => u.queryParameters['country']), [
          'UA',
        ]);
        expect(feed.localCountry, 'UA');
      },
    );

    test('a language change keeps the country and asks once', () async {
      SharedPreferences.setMockInitialValues({'feed.scope': 'local'});
      final server = _Server();
      final feed = FeedController(api: server.api, phoneRegion: () => 'UA');
      await feed.start();
      await _settle();
      server.log.clear();
      await feed.setLanguage(FeedLanguage.uk);
      await _settle();
      expect(feed.localCountry, 'UA');
      expect(
        server.feedRequests.map(
          (u) => (u.queryParameters['lang'], u.queryParameters['country']),
        ),
        [('uk', 'UA')],
      );
    });

    testWidgets('a region the app cannot name: Global only, never a code', (
      tester,
    ) async {
      final feed = await _pump(tester, _Server(), region: 'CH');
      expect(feed.localCountry, isNull);
      expect(find.byKey(_where), findsNothing);
      expect(find.text('CH'), findsNothing);
    });

    test(
      "a region only the server names: Local, with the server's name",
      () async {
        final server = _Server(countries: const ['DE', 'FR', 'US', 'NZ']);
        final feed = FeedController(api: server.api, phoneRegion: () => 'NZ');
        await feed.start();
        expect(feed.localCountry, isNull); // no list yet
        await _settle();
        expect(feed.localCountry, 'NZ');
        expect(
          feed.countryChanges.value.nameOf('NZ', l10nFor()),
          'New Zealand',
        );
      },
    );

    testWidgets('no country at all: no Where chip, Global only', (
      tester,
    ) async {
      await _pump(tester, _Server(countries: const []), region: null);
      expect(find.byKey(_where), findsNothing);
      expect(find.byKey(_topics), findsOneWidget);
    });
  });

  group('a server without /topics and /countries', () {
    testWidgets('no Where or Topics chip, and no Country in Settings', (
      tester,
    ) async {
      final server = _Server(menus: false);
      final feed = await _pump(tester, server);
      expect(find.byKey(_topics), findsNothing);
      expect(feed.topics, isNull);
      // Such a server ignores country=: Local would show every country.
      expect(find.byKey(_where), findsNothing);
      expect(feed.localCountry, isNull);
      expect(
        server.feedRequests.where((u) => u.queryParameters['country'] != null),
        isEmpty,
      );
      await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
      await tester.pumpAndSettle();
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Country'), findsNothing);
    });

    test('a Local feed turns Global, and the next launch starts so', () async {
      SharedPreferences.setMockInitialValues({'feed.scope': 'local'});
      final server = _Server(menus: false);
      final feed = FeedController(api: server.api, phoneRegion: () => 'DE');
      await feed.start();
      await _settle();
      // DE before the answer, every country after it.
      expect(server.feedRequests.map((u) => u.queryParameters['country']), [
        'DE',
        null,
      ]);
      expect(feed.scope, FeedScope.global);

      server.log.clear();
      final next = FeedController(api: server.api, phoneRegion: () => 'DE');
      await next.start();
      await _settle();
      expect(server.feedRequests.map((u) => u.queryParameters['country']), [
        null,
      ]);

      // A server with the filters again: Local is back, as it was chosen.
      final updated = _Server();
      final later = FeedController(api: updated.api, phoneRegion: () => 'DE');
      await later.start();
      await _settle();
      expect(updated.feedRequests.map((u) => u.queryParameters['country']), [
        null,
        'DE',
      ]);
      expect(later.scope, FeedScope.local);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('feed.noCountries'), isNull);
    });

    testWidgets('a topic chosen before stays, so it can be cleared', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'feed.topic': 'health'});
      final server = _Server(menus: false);
      await _pump(tester, server);
      expect(_label(tester, _topics), 'Health'); // the app's own name
      await _pick(tester, _topics, 'All topics');
      expect(find.byKey(_topics), findsNothing);
    });
  });

  group("topic names in the app's language", () {
    testWidgets('a topic not in the menu, also after a restart', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
      final server = _Server();
      await _pump(tester, server, region: 'US', words: FeedLanguage.uk);
      await _pick(tester, _topics, 'Торгівля');
      // The US has no trade decisions: the menu under Local has none.
      await _pick(tester, _where, 'Моя країна');
      expect(_label(tester, _topics), 'Торгівля');

      await tester.pumpWidget(const SizedBox());
      await _pump(
        tester,
        _Server()..offline = true,
        region: 'US',
        words: FeedLanguage.uk,
      );
      expect(_label(tester, _topics), 'Торгівля');
    });

    test('another language, offline: names in it, not the old one', () async {
      SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
      final server = _Server();
      final feed = FeedController(api: server.api, phoneRegion: () => 'DE');
      await feed.start();
      await _settle();
      await feed.setTopic('economy');
      await feed.setScope(FeedScope.local);
      await _settle();
      server.offline = true;
      await feed.setLanguage(FeedLanguage.de);
      await _settle();
      final de = l10nFor(FeedLanguage.de);
      expect(topicName('economy', feed.topics, de), 'Wirtschaft');
      expect(
        [for (final t in feed.topics!) topicName(t.id, feed.topics, de)],
        ['Wirtschaft', 'Handel', 'Gesundheit'],
      );
      expect(feed.countryChanges.value.nameOf('DE', de), 'Deutschland');
    });
  });

  testWidgets('the menus and chips are in the feed language', (tester) async {
    SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
    final server = _Server();
    await _pump(tester, server, words: FeedLanguage.uk);
    final topics = server.log.where((u) => u.path == '/topics').single;
    final countries = server.log.where((u) => u.path == '/countries').single;
    expect(topics.queryParameters['lang'], 'uk');
    expect(countries.queryParameters['lang'], 'uk');
    expect(_label(tester, _where), 'Увесь світ');
    expect(_label(tester, _topics), 'Усі теми');
    await tester.tap(find.byKey(_topics));
    await tester.pumpAndSettle();
    expect(_menu(tester), ['Усі теми', 'Економіка', 'Здоров’я', 'Торгівля']);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await _pick(tester, _where, 'Моя країна');
    expect(_label(tester, _where), 'Німеччина');
  });

  group('Settings: Country', () {
    Future<void> openCountry(WidgetTester tester) async {
      await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Country'));
      await tester.pumpAndSettle();
    }

    Future<void> backToFeed(WidgetTester tester) async {
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    testWidgets('lists the countries with sources, the phone region checked', (
      tester,
    ) async {
      await _pump(tester, _Server());
      await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
      await tester.pumpAndSettle();
      expect(find.text('Country'), findsOneWidget);
      expect(find.text('Germany'), findsOneWidget); // the row's value
      await tester.tap(find.text('Country'));
      await tester.pumpAndSettle();
      for (final name in ['Germany', 'France', 'United States']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Germany')),
        isSemantics(label: 'Germany', isSelected: true),
      );
      expect(
        find.text(
          '“Local” in the feed shows the chosen country\'s decisions, and for '
          'an EU member state the EU\'s as well.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'a country chosen while Local is shown reloads the feed in it',
      (tester) async {
        final server = _Server();
        await _pump(tester, server);
        await _pick(tester, _where, 'Local');
        await openCountry(tester);
        await tester.tap(find.text('United States'));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.text('United States')),
          isSemantics(label: 'United States', isSelected: true),
        );
        await backToFeed(tester);
        expect(_label(tester, _where), 'United States');
        expect(server.feedRequests.last.queryParameters['country'], 'US');
        expect(_shown(tester), ['us1', 'us2']);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('feed.country'), 'US');
        expect(events.where((e) => e.$1 == 'filter_changed').last.$2, {
          'scope': 'local',
          'country': 'US',
          'topic': 'all',
        });
      },
    );

    testWidgets('a country chosen while Global is shown only changes Local', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server);
      final asked = server.feedRequests.length;
      await openCountry(tester);
      await tester.tap(find.text('France'));
      await tester.pumpAndSettle();
      await backToFeed(tester);
      expect(_label(tester, _where), 'Global');
      expect(server.feedRequests, hasLength(asked)); // the same feed
      await tester.tap(find.byKey(_where));
      await tester.pumpAndSettle();
      expect(find.text('France'), findsOneWidget); // under Local
    });

    testWidgets('the phone region chosen in Settings is saved too', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server);
      await openCountry(tester);
      await tester.tap(find.text('Germany'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('feed.country'), 'DE');
      expect(events.where((e) => e.$1 == 'filter_changed'), isEmpty);
    });

    testWidgets('offline with no list: says so, keeps the country, retries', (
      tester,
    ) async {
      final server = _Server()..offline = true;
      await _pump(tester, server);
      await openCountry(tester);
      const failed = "Couldn't load the list of countries. Tap to try again.";
      expect(find.text(failed), findsOneWidget);
      expect(find.text('Germany'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
      // Back online: a tap on the message loads the list.
      server.offline = false;
      await tester.tap(find.text(failed));
      await tester.pumpAndSettle();
      expect(find.text(failed), findsNothing);
      for (final name in ['Germany', 'France', 'United States']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
    });

    testWidgets('the page asks again when it opens, after a failure', (
      tester,
    ) async {
      final server = _Server()..offline = true;
      await _pump(tester, server);
      await openCountry(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      server.offline = false;
      await tester.tap(find.text('Country'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't load"), findsNothing);
      expect(find.text('United States'), findsOneWidget);
    });

    testWidgets('the phone region without sources is first, and stays', (
      tester,
    ) async {
      final server = _Server();
      await _pump(tester, server, region: 'UA');
      await openCountry(tester);
      expect(
        tester.getSemantics(find.text('Ukraine')),
        isSemantics(label: 'Ukraine', isSelected: true),
      );
      expect(
        tester.getTopLeft(find.text('Ukraine')).dy,
        lessThan(tester.getTopLeft(find.text('France')).dy),
      );
      await tester.tap(find.text('Germany'));
      await tester.pumpAndSettle();
      expect(find.text('Ukraine'), findsOneWidget);
      await tester.tap(find.text('Ukraine'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('feed.country'), 'UA');
    });
  });
}
