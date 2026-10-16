import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/news_widgets.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

final _today = localDay(DateTime.now());

Map<String, dynamic> _article(
  String id,
  DateTime publishedAt, {
  String? headline,
  String? imageUrl,
  String country = 'DE',
  int? feedSeq,
  DateTime? addedAt,
  bool dateOnly = false,
}) => {
  'feedSeq': feedSeq,
  'addedAt': addedAt?.toUtc().toIso8601String(),
  'id': id,
  'country': country,
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': publishedAt.toUtc().toIso8601String(),
  'dateOnly': dateOnly,
  'headline': headline ?? 'Decision $id',
  'shortSummary': null,
  'summary': 'Summary $id',
  'decisionType': 'cabinet-decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'de',
  'topics': <String>[],
  'tags': <String>[],
  'importance': 3,
  'imageUrl': imageUrl,
  'originalUrl': 'https://www.bundesregierung.de/$id',
};

/// A fake API: answers /articles from `pages` (keyed by cursor, '' for the first page).
ApiClient _api(
  Map<String, Map<String, dynamic>> pages, {
  List<Uri>? log,
  Map<String, dynamic>? since,
}) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    log?.add(request.url);
    final query = request.url.queryParameters;
    if (query.containsKey('since') || query.containsKey('after')) {
      return http.Response(
        jsonEncode(since ?? {'items': [], 'nextCursor': null, 'top': []}),
        200,
      );
    }
    final page = pages[query['cursor'] ?? ''];
    return page == null
        ? http.Response('{"error":"Internal error"}', 500)
        : http.Response(jsonEncode(page), 200);
  }),
);

/// The same decision as the server sends it in a translated feed.
Map<String, dynamic> _translated(
  String id,
  DateTime publishedAt,
  String headline, {
  String lang = 'uk',
  int? feedSeq,
}) => {
  ..._article(id, publishedAt, headline: headline, feedSeq: feedSeq),
  'lang': lang,
};

/// A 200 answer in UTF-8, as the API sends it (Cyrillic needs it).
http.Response _ok(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _page(List<Map<String, dynamic>> items, {String? next}) =>
    {'items': items, 'nextCursor': next, 'top': <Object>[]};

/// A fake API with one feed per language (docs/contract.md, #46): `feeds['uk']`
/// answers `lang=uk`, `feeds['en']` the requests without `lang`. Pages are keyed
/// by cursor, '' for the first; the new check gets `newer`, or nothing.
ApiClient _langApi(
  Map<String, Map<String, Map<String, dynamic>>> feeds, {
  List<Uri>? log,
  Map<String, Map<String, dynamic>> newer = const {},
}) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    log?.add(request.url);
    final query = request.url.queryParameters;
    final lang = query['lang'] ?? 'en';
    if (query.containsKey('since') || query.containsKey('after')) {
      return _ok(newer[lang] ?? _page([]));
    }
    final page = feeds[lang]?[query['cursor'] ?? ''];
    return page == null
        ? http.Response('{"error":"Internal error"}', 500)
        : _ok(page);
  }),
);

/// A phone-sized screen (iPhone 15, 393 x 852 pt), or an iPad's (820 x 1180).
void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

const _phone = Size(393, 852);

/// The feed in English, whatever its language: a language's own words are
/// checked through the whole app in app_localization_test.dart.
Future<FeedController> _pump(WidgetTester tester, FeedController feed) async {
  await tester.pumpWidget(
    testApp(
      onGenerateRoute: onGenerateRoute,
      home: FeedScreen(
        controller: feed,
        newCheckEvery: const Duration(hours: 1),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return feed;
}

/// Chooses the feed language the way a reader does (#64): the settings button
/// at the top right, Language, the language, then back to the feed.
Future<void> _chooseLanguage(WidgetTester tester, String name) async {
  await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Language'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  await tester.pageBack();
  await tester.pumpAndSettle();
  await tester.pageBack();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows top stories, then one Latest list without day headings', (
    tester,
  ) async {
    final top = _article(
      't1',
      _today.add(const Duration(minutes: 1)),
      headline: 'Cabinet approves budget',
    );
    await _pump(
      tester,
      FeedController(
        api: _api({
          '': {
            'items': [
              top,
              _article(
                'a1',
                _today.add(const Duration(minutes: 1)),
                headline: 'Law on water signed',
              ),
              _article(
                'b1',
                _today.subtract(const Duration(hours: 12)),
                headline: 'Decree on visas',
              ),
            ],
            'nextCursor': null,
            'top': [top],
          },
        }),
      ),
    );

    expect(find.text('Top stories'), findsOneWidget);
    expect(
      find.text('Cabinet approves budget'),
      findsOneWidget,
    ); // only once: top articles are not repeated below
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Law on water signed'), findsOneWidget);
    // No day heading: the older article shows its own time on the card.
    expect(find.text('Yesterday'), findsNothing);
    expect(find.text('Decree on visas'), findsOneWidget);
    expect(find.text('CABINET DECISION'), findsNWidgets(3));
    expect(find.text('Federal Government · Germany'), findsNWidgets(3));
    await tester.dragUntilVisible(
      find.text("You're all caught up"),
      find.byType(CustomScrollView),
      const Offset(0, -300),
    );
    expect(find.text("You're all caught up"), findsOneWidget);
  });

  testWidgets('shows an error with nothing saved, and keeps pull to refresh', (
    tester,
  ) async {
    await _pump(tester, FeedController(api: _api({})));
    expect(
      find.text("Couldn't load the news. Pull down to retry."),
      findsOneWidget,
    );
  });

  testWidgets('says so when there are no decisions', (tester) async {
    await _pump(
      tester,
      FeedController(
        api: _api({
          '': {'items': [], 'nextCursor': null, 'top': []},
        }),
      ),
    );
    expect(find.text('No decisions yet today.'), findsOneWidget);
  });

  testWidgets('opens from the feed saved on the phone when the network fails', (
    tester,
  ) async {
    final saved = {
      'items': [
        _article(
          's1',
          _today.add(const Duration(minutes: 1)),
          headline: 'Saved decision',
        ),
      ],
      'nextCursor': null,
      'top': [],
    };
    SharedPreferences.setMockInitialValues({
      'feed.lastPage': jsonEncode(saved),
    });
    await _pump(tester, FeedController(api: _api({})));
    expect(find.text('Saved decision'), findsOneWidget);
    expect(find.text("Couldn't refresh. Pull down to retry."), findsOneWidget);
  });

  testWidgets('loads the next page near the end of the list', (tester) async {
    final log = <Uri>[];
    final first = [
      for (var i = 0; i < 20; i++)
        _article('p$i', _today.add(Duration(minutes: 60 - i))),
    ];
    await _pump(
      tester,
      FeedController(
        api: _api({
          '': {'items': first, 'nextCursor': 'c2', 'top': []},
          'c2': {
            'items': [
              _article(
                'last',
                _today.add(const Duration(minutes: 1)),
                headline: 'Oldest decision',
              ),
            ],
            'nextCursor': null,
            'top': [],
          },
        }, log: log),
      ),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pump();
    await tester.pump();
    expect(log.map((u) => u.queryParameters['cursor']), contains('c2'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Oldest decision'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Oldest decision'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text("You're all caught up"),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text("You're all caught up"), findsOneWidget);
  });

  testWidgets('shows a pill for new decisions instead of moving the list', (
    tester,
  ) async {
    final feed = await _pump(
      tester,
      FeedController(
        api: _api(
          {
            '': {
              'items': [_article('n0', _today.add(const Duration(minutes: 1)))],
              'nextCursor': null,
              'top': [],
            },
          },
          since: {
            'items': [
              _article('n1', DateTime.now()),
              _article('n2', DateTime.now()),
            ],
            'nextCursor': null,
            'top': [],
          },
        ),
      ),
    );
    await feed.checkForNew();
    await tester.pump();
    expect(find.text('2 new decisions'), findsOneWidget);
  });

  testWidgets('dims an opened article and remembers it', (tester) async {
    final feed = await _pump(
      tester,
      FeedController(
        api: _api({
          '': {
            'items': [
              _article(
                'r1',
                _today.add(const Duration(minutes: 1)),
                headline: 'Read me',
              ),
            ],
            'nextCursor': null,
            'top': [],
          },
        }),
      ),
    );
    await tester.tap(find.text('Read me'));
    await tester.pumpAndSettle();
    expect(feed.readIds, contains('r1'));
    expect(
      (await SharedPreferences.getInstance()).getStringList('feed.readIds'),
      ['r1'],
    );
  });

  test('an article survives saving and reading back', () {
    final a = Article.fromJson(
      _article('x', DateTime.utc(2026, 10, 14, 9), imageUrl: 'https://x/i.jpg'),
    );
    final back = Article.fromJson(
      jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>,
    );
    expect(back.toJson(), a.toJson());
  });

  testWidgets(
    'after a failed page, offers a retry instead of retrying on every scroll',
    (tester) async {
      final log = <Uri>[];
      var failing = true;
      final first = [
        for (var i = 0; i < 20; i++)
          _article('f$i', _today.add(Duration(minutes: 60 - i))),
      ];
      final api = ApiClient(
        baseUrl: 'https://api.test',
        client: MockClient((request) async {
          log.add(request.url);
          if (request.url.queryParameters['cursor'] == 'c2') {
            return failing
                ? http.Response('offline', 503)
                : http.Response(
                    jsonEncode({
                      'items': [
                        _article(
                          'back',
                          _today.add(const Duration(minutes: 1)),
                          headline: 'Back online',
                        ),
                      ],
                      'nextCursor': null,
                      'top': [],
                    }),
                    200,
                  );
          }
          return http.Response(
            jsonEncode({'items': first, 'nextCursor': 'c2', 'top': []}),
            200,
          );
        }),
      );
      await _pump(tester, FeedController(api: api));
      final retry = find.text("Couldn't load more. Tap to try again.");
      await tester.scrollUntilVisible(
        retry,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pump();
      expect(
        log.where((u) => u.queryParameters['cursor'] == 'c2'),
        hasLength(1),
      );

      failing = false;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Back online'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Back online'), findsOneWidget);
    },
  );

  test('a page that arrives after a refresh is dropped', () async {
    final page2 = Completer<http.Response>();
    final api = ApiClient(
      baseUrl: 'https://api.test',
      client: MockClient((request) async {
        if (request.url.queryParameters['cursor'] == 'c2') return page2.future;
        return http.Response(
          jsonEncode({
            'items': [_article('new1', DateTime.now())],
            'nextCursor': 'c2',
            'top': [],
          }),
          200,
        );
      }),
    );
    final feed = FeedController(api: api);
    await feed.start();
    final loading = feed.loadMore();
    await feed.refresh();
    page2.complete(
      http.Response(
        jsonEncode({
          'items': [_article('stale', DateTime.utc(2026, 10, 10))],
          'nextCursor': null,
          'top': [],
        }),
        200,
      ),
    );
    await loading;
    expect(feed.items.map((a) => a.id), ['new1']);
    expect(feed.hasMore, isTrue);
  });

  test(
    'an article opened before the store is ready is still remembered',
    () async {
      final feed = FeedController(
        api: _api({
          '': {'items': [], 'nextCursor': null, 'top': []},
        }),
      );
      final article = Article.fromJson(_article('early', DateTime.now()));
      await feed.markRead(article);
      await feed.start();
      expect(feed.readIds, contains('early'));
      expect(
        (await SharedPreferences.getInstance()).getStringList('feed.readIds'),
        contains('early'),
      );
    },
  );

  // Meaningful in a time zone with a clock change: CI runs the app tests with
  // TZ=Europe/Berlin, where 29 March 2026 has 23 hours.
  test('day labels count calendar days, not 24-hour blocks', () {
    final now = DateTime(2026, 3, 30, 9);
    final en = l10nFor();
    expect(dayLabel(DateTime(2026, 3, 29, 12), en, now: now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 3, 30, 0, 10), en, now: now), 'Today');
    expect(
      dayLabel(DateTime(2026, 3, 28, 12), en, now: now),
      'Saturday 28 March',
    );
  });

  test(
    'the new check asks by feed position, so a late article is counted',
    () async {
      final log = <Uri>[];
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final feed = FeedController(
        api: _api(
          {
            '': {
              'items': [
                _article('s2', DateTime.now(), feedSeq: 12),
                _article('s1', DateTime.now(), feedSeq: 11),
              ],
              'nextCursor': null,
              'top': [],
            },
          },
          log: log,
          // Published yesterday, appeared just now: the server returns it for after=12.
          since: {
            'items': [_article('late', yesterday, feedSeq: 13)],
            'nextCursor': null,
            'top': [],
          },
        ),
      );
      await feed.start();
      await feed.checkForNew();
      expect(log.last.queryParameters['after'], '12');
      expect(log.last.queryParameters.containsKey('since'), isFalse);
      expect(feed.newCount, 1);
    },
  );

  testWidgets(
    'lists articles in the order they appeared, with no day heading in between',
    (tester) async {
      final now = DateTime.now();
      await _pump(
        tester,
        FeedController(
          api: _api({
            '': {
              'items': [
                // Published three days ago, appeared just now: first.
                _article(
                  'late',
                  now.subtract(const Duration(days: 3)),
                  headline: 'Late but new',
                  feedSeq: 2,
                  addedAt: now,
                ),
                _article(
                  'older',
                  now.subtract(const Duration(days: 1)),
                  headline: 'Appeared yesterday',
                  feedSeq: 1,
                  addedAt: now.subtract(const Duration(days: 1)),
                ),
              ],
              'nextCursor': null,
              'top': [],
            },
          }),
        ),
      );
      expect(find.text('Latest'), findsOneWidget);
      expect(find.text('Yesterday'), findsNothing);
      final late = tester.getTopLeft(find.text('Late but new')).dy;
      final older = tester.getTopLeft(find.text('Appeared yesterday')).dy;
      expect(late, lessThan(older));
    },
  );

  testWidgets('a card shows when the article appeared, so times only go down', (
    tester,
  ) async {
    final now = DateTime.now();
    final dated = DateTime(now.year, now.month, now.day - 3, 12);
    await _pump(
      tester,
      FeedController(
        api: _api({
          '': {
            'items': [
              // Dated three days ago (no time), appeared just now: under "Latest".
              _article(
                'dated',
                dated,
                headline: 'Dated earlier',
                feedSeq: 2,
                addedAt: now,
                dateOnly: true,
              ),
              _article(
                'today',
                DateTime(now.year, now.month, now.day, 0, 30),
                headline: 'Dated today',
                feedSeq: 1,
                addedAt: now,
                dateOnly: true,
              ),
            ],
            'nextCursor': null,
            'top': [],
          },
        }),
      ),
    );
    expect(find.text('Latest'), findsOneWidget);
    // Both appeared just now: the cards say so, not the older publication day.
    expect(find.text(dayLabel(dated, l10nFor())), findsNothing);
    expect(find.text('Today'), findsNothing);
    expect(find.textContaining('m ago'), findsNWidgets(2));
  });

  group('language', () {
    final now = DateTime.now();
    final english = _page([
      _article('a1', now, headline: 'Cabinet approves budget', feedSeq: 7),
      _article('a2', now, headline: 'Law on water signed', feedSeq: 6),
    ]);
    final ukrainian = _page([
      _translated('a1', now, 'Кабінет схвалив бюджет', feedSeq: 2),
    ]);

    testWidgets(
      'the settings button is at the top right, with a VoiceOver label',
      (tester) async {
        _screen(tester, _phone);
        final semantics = tester.ensureSemantics();
        await _pump(
          tester,
          FeedController(
            api: _langApi({
              'en': {'': english},
            }),
          ),
        );
        expect(find.byIcon(CupertinoIcons.globe), findsNothing);
        final button = find.ancestor(
          of: find.byIcon(CupertinoIcons.gear_alt),
          matching: find.byType(CupertinoButton),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('Settings')),
          isSemantics(label: 'Settings'),
        );
        // At the right of the masthead, with at least the 44-pt target iOS asks for.
        final target = tester.getRect(button);
        expect(target.height, greaterThanOrEqualTo(44));
        expect(target.width, greaterThanOrEqualTo(44));
        expect(target.right, _phone.width - 20);
        expect(
          target.top,
          lessThan(tester.getRect(find.text('Official News')).bottom),
        );
        semantics.dispose();
      },
    );

    testWidgets('opens in the language saved on the phone', (tester) async {
      final semantics = tester.ensureSemantics();
      final log = <Uri>[];
      SharedPreferences.setMockInitialValues({'feed.lang': 'ru'});
      await _pump(
        tester,
        FeedController(
          api: _langApi({
            'ru': {
              '': _page([
                _translated('a1', now, 'Кабинет одобрил бюджет', lang: 'ru'),
              ]),
            },
          }, log: log),
        ),
      );
      expect(find.text('Кабинет одобрил бюджет'), findsOneWidget);
      expect(log.single.queryParameters['lang'], 'ru');
      semantics.dispose();
    });

    testWidgets(
      'choosing Українська saves it, asks for lang=uk and shows the translated feed',
      (tester) async {
        _screen(tester, _phone);
        final semantics = tester.ensureSemantics();
        final log = <Uri>[];
        final feed = await _pump(
          tester,
          FeedController(
            api: _langApi({
              'en': {'': english},
              'uk': {'': ukrainian},
            }, log: log),
          ),
        );
        await tester.tap(find.text('Law on water signed'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Settings shows the current language; opening it changes nothing.
        await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
        await tester.pumpAndSettle();
        expect(find.text('English'), findsOneWidget);
        await tester.tap(find.text('Language'));
        await tester.pumpAndSettle();
        expect(log, hasLength(1));
        for (final name in [
          'English',
          'Українська',
          'Русский',
          'Español',
          'Deutsch',
        ]) {
          expect(find.text(name), findsOneWidget);
        }
        // The checkmark is on the current language.
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text('English'),
              matching: find.byType(CupertinoListTile),
            ),
            matching: find.byIcon(CupertinoIcons.checkmark_alt),
          ),
          findsOneWidget,
        );
        expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
        // VoiceOver says which one is current.
        expect(
          tester.getSemantics(find.text('English')),
          isSemantics(label: 'English', isSelected: true),
        );
        expect(
          tester.getSemantics(find.text('Українська')),
          isSemantics(label: 'Українська', isSelected: false),
        );

        await tester.tap(find.text('Українська'));
        await tester.pumpAndSettle();
        // The checkmark moves at once, and Settings shows the new language.
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text('Українська'),
              matching: find.byType(CupertinoListTile),
            ),
            matching: find.byIcon(CupertinoIcons.checkmark_alt),
          ),
          findsOneWidget,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Українська'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(log.last.queryParameters['lang'], 'uk');
        expect(find.text('Кабінет схвалив бюджет'), findsOneWidget);
        expect(find.text('Cabinet approves budget'), findsNothing);
        expect(find.text('Law on water signed'), findsNothing);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('feed.lang'), 'uk');
        // One saved first page per language; English keeps its old key.
        expect(
          prefs.getString('feed.lastPage.uk'),
          contains('Кабінет схвалив бюджет'),
        );
        expect(
          prefs.getString('feed.lastPage'),
          contains('Cabinet approves budget'),
        );
        // Read state is per article, in every language.
        expect(feed.readIds, {'a2'});

        // The article opens as the feed shows it; the official link stays the original.
        await tester.tap(find.text('Кабінет схвалив бюджет'));
        await tester.pumpAndSettle();
        expect(find.text('Кабінет схвалив бюджет'), findsOneWidget);
        expect(
          // #36's article screen shows the official link as "site · original title".
          find.text('bundesregierung.de · Original a1'),
          findsOneWidget,
        );
        semantics.dispose();
      },
    );

    test('English requests carry no lang parameter, others always do', () async {
      final log = <Uri>[];
      final feed = FeedController(
        api: _langApi({
          'en': {
            '': _page([_article('e1', now, feedSeq: 9)], next: 'c2'),
            'c2': _page([_article('e2', now, feedSeq: 8)]),
          },
          'uk': {
            '': _page([
              _translated('e1', now, 'Рішення', feedSeq: 3),
            ], next: 'u2'),
            'u2': _page([_translated('e2', now, 'Ще рішення', feedSeq: 1)]),
          },
        }, log: log),
      );
      await feed.start();
      await feed.loadMore();
      await feed.checkForNew();
      expect(log, hasLength(3));
      expect(log.where((u) => u.queryParameters.containsKey('lang')), isEmpty);

      log.clear();
      await feed.setLanguage(FeedLanguage.uk);
      await feed.loadMore();
      await feed.checkForNew();
      expect(log.map((u) => u.queryParameters['lang']), ['uk', 'uk', 'uk']);
      expect(log[1].queryParameters['cursor'], 'u2');
      // Feed positions are per language: the check asks after the Ukrainian one.
      expect(log[2].queryParameters['after'], '3');
      expect(feed.items.map((a) => a.headline), ['Рішення', 'Ще рішення']);

      log.clear();
      await feed.setLanguage(FeedLanguage.en);
      expect(log.single.queryParameters.containsKey('lang'), isFalse);
      expect(log.single.hasQuery, isTrue); // only limit
    });

    test('a late page for the previous language is dropped', () async {
      final enFirst = Completer<http.Response>();
      final enAsked = Completer<void>();
      final feed = FeedController(
        api: ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient((request) async {
            if (request.url.queryParameters['lang'] == 'uk') {
              return _ok(ukrainian);
            }
            enAsked.complete();
            return enFirst.future;
          }),
        ),
      );
      final starting = feed.start();
      await enAsked.future;
      await feed.setLanguage(FeedLanguage.uk);
      expect(feed.items.map((a) => a.headline), ['Кабінет схвалив бюджет']);

      enFirst.complete(_ok(english));
      await starting;
      expect(feed.language, FeedLanguage.uk);
      expect(feed.items.map((a) => a.headline), ['Кабінет схвалив бюджет']);
      expect(feed.loading, isFalse);
      expect(feed.error, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('feed.lastPage'), isNull);
    });

    test(
      'a next page or new check for the previous language is dropped',
      () async {
        final enMore = Completer<http.Response>();
        final enNew = Completer<http.Response>();
        final feed = FeedController(
          api: ApiClient(
            baseUrl: 'https://api.test',
            client: MockClient((request) async {
              final query = request.url.queryParameters;
              if (query['lang'] == 'uk') {
                return _ok(ukrainian);
              }
              if (query['cursor'] == 'c2') return enMore.future;
              if (query.containsKey('after')) return enNew.future;
              return _ok(_page([_article('e1', now, feedSeq: 5)], next: 'c2'));
            }),
          ),
        );
        await feed.start();
        final loading = feed.loadMore();
        final checking = feed.checkForNew();
        await feed.setLanguage(FeedLanguage.uk);

        enMore.complete(_ok(_page([_article('old', now)])));
        enNew.complete(_ok(_page([_article('new', now)])));
        await loading;
        await checking;
        expect(feed.items.map((a) => a.id), ['a1']);
        expect(feed.newCount, 0);
        expect(feed.loadingMore, isFalse);
      },
    );

    testWidgets('each language opens from its own saved page', (tester) async {
      SharedPreferences.setMockInitialValues({
        'feed.lang': 'uk',
        'feed.lastPage': jsonEncode(
          _page([_article('s1', now, headline: 'Saved decision')]),
        ),
        'feed.lastPage.uk': jsonEncode(
          _page([_translated('s1', now, 'Збережене рішення')]),
        ),
      });
      // Offline: only the saved pages.
      final feed = await _pump(tester, FeedController(api: _langApi({})));
      expect(find.text('Збережене рішення'), findsOneWidget);
      expect(
        find.text("Couldn't refresh. Pull down to retry."),
        findsOneWidget,
      );

      unawaited(feed.setLanguage(FeedLanguage.en));
      await tester.pump();
      expect(find.text('Saved decision'), findsOneWidget);
      expect(find.text('Збережене рішення'), findsNothing);

      // Nothing saved for Russian: the English feed goes at once, loading, then the error.
      unawaited(feed.setLanguage(FeedLanguage.ru));
      expect(feed.items, isEmpty);
      expect(feed.loading, isTrue);
      await tester.pump();
      expect(find.text('Saved decision'), findsNothing);
      expect(
        find.text("Couldn't load the news. Pull down to retry."),
        findsOneWidget,
      );
    });

    testWidgets('a language with nothing translated yet says so calmly', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
      await _pump(
        tester,
        FeedController(
          api: _langApi({
            'uk': {'': _page([])},
          }),
        ),
      );
      expect(find.text('No translated decisions yet.'), findsOneWidget);
      expect(
        find.text('Translations appear here as they are ready.'),
        findsOneWidget,
      );
      expect(find.text('No decisions yet today.'), findsNothing);
    });

    test(
      'the article request asks in the language, English without it',
      () async {
        final log = <Uri>[];
        final api = ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient((request) async {
            log.add(request.url);
            return _ok(_translated('x', now, 'Рішення'));
          }),
        );
        await api.fetchArticle('x', lang: 'uk');
        await api.fetchArticle('x', lang: 'en');
        await api.fetchArticle('x');
        expect(log.map((u) => u.toString()), [
          'https://api.test/articles/x?lang=uk',
          'https://api.test/articles/x',
          'https://api.test/articles/x',
        ]);
      },
    );

    testWidgets(
      'a server that does not know lang shows no English under УКР and saves none',
      (tester) async {
        final log = <Uri>[];
        SharedPreferences.setMockInitialValues({
          'feed.lang': 'uk',
          // An English page saved under Ukrainian by a build that trusted any page.
          'feed.lastPage.uk': jsonEncode(english),
        });
        // The API before #49 ignores `lang` and sends the English feed.
        final api = ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient((request) async {
            log.add(request.url);
            return _ok({
              ...english,
              'nextCursor': 'c2',
              'top': english['items'],
            });
          }),
        );
        final feed = await _pump(tester, FeedController(api: api));
        expect(log.first.queryParameters['lang'], 'uk');
        expect(find.text('Cabinet approves budget'), findsNothing);
        expect(find.text('Law on water signed'), findsNothing);
        expect(find.text('No translated decisions yet.'), findsOneWidget);
        // Its cursor pages through the English feed: not followed.
        expect(feed.hasMore, isFalse);
        expect(
          log.where((u) => u.queryParameters.containsKey('cursor')),
          isEmpty,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('feed.lastPage.uk'),
          isNot(contains('Cabinet approves budget')),
        );
      },
    );

    test(
      'only articles in the chosen language are kept, on every request',
      () async {
        SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
        final feed = FeedController(
          api: ApiClient(
            baseUrl: 'https://api.test',
            client: MockClient((request) async {
              if (request.url.queryParameters.containsKey('after')) {
                return _ok(_page([_article('e9', now, feedSeq: 9)]));
              }
              // A page with an English article mixed in.
              return _ok({
                ..._page([
                  _translated('a1', now, 'Кабінет схвалив бюджет', feedSeq: 2),
                  _article(
                    'a2',
                    now,
                    headline: 'Law on water signed',
                    feedSeq: 6,
                  ),
                ], next: 'c2'),
                'top': [_article('a2', now, headline: 'Law on water signed')],
              });
            }),
          ),
        );
        await feed.start();
        expect(feed.items.map((a) => a.id), ['a1']);
        expect(feed.items.single.lang, 'uk');
        expect(feed.top, isEmpty);
        expect(feed.hasMore, isFalse);
        await feed.checkForNew();
        expect(feed.newCount, 0);
      },
    );

    test(
      'an article asked for in a language is never taken in another',
      () async {
        final api = ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient((request) async => _ok(_article('x', now))),
        );
        await expectLater(
          api.fetchArticle('x', lang: 'uk'),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
          ),
        );
        expect((await api.fetchArticle('x')).id, 'x');
      },
    );

    testWidgets(
      'an empty translated feed fills in at the next check, without a pull',
      (tester) async {
        SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
        var translated = false;
        final feed = await _pump(
          tester,
          FeedController(
            api: ApiClient(
              baseUrl: 'https://api.test',
              client: MockClient(
                (request) async => _ok(translated ? ukrainian : _page([])),
              ),
            ),
          ),
        );
        expect(find.text('No translated decisions yet.'), findsOneWidget);

        translated = true;
        await feed.checkForNew(); // what the screen's timer calls
        await tester.pump();
        expect(find.text('Кабінет схвалив бюджет'), findsOneWidget);
        expect(find.text('No translated decisions yet.'), findsNothing);
      },
    );

    test(
      'offline with nothing to show, the check retries and keeps the error meanwhile',
      () async {
        final second = Completer<http.Response>();
        var calls = 0;
        final feed = FeedController(
          api: ApiClient(
            baseUrl: 'https://api.test',
            client: MockClient((request) async {
              calls++;
              return calls == 1 ? http.Response('offline', 503) : second.future;
            }),
          ),
        );
        await feed.start();
        expect(feed.error, isNotNull);

        final checking = feed.checkForNew();
        await Future<void>.delayed(Duration.zero);
        expect(calls, 2);
        // "Couldn't load the news" stays while it asks, not "No decisions yet".
        expect(feed.error, isNotNull);

        second.complete(_ok(english));
        await checking;
        expect(feed.error, isNull);
        expect(feed.items.map((a) => a.id), ['a1', 'a2']);
      },
    );

    testWidgets(
      'at large text sizes the date keeps whole words and the settings button stays on screen',
      (tester) async {
        _screen(tester, _phone);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pump(
          tester,
          FeedController(
            api: _langApi({
              'en': {'': english},
            }),
          ),
        );
        final day = longDay(DateTime.now(), l10nFor());
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pump();
        final button = tester.getRect(
          find.ancestor(
            of: find.byIcon(CupertinoIcons.gear_alt),
            matching: find.byType(CupertinoButton),
          ),
        );
        expect(button.right, lessThanOrEqualTo(_phone.width));
        final paragraph = tester.renderObject<RenderParagraph>(find.text(day));
        var start = 0;
        for (final word in day.split(' ')) {
          final end = start + word.length;
          expect(
            paragraph.getBoxesForSelection(
              TextSelection(baseOffset: start, extentOffset: end),
            ),
            hasLength(1),
            reason: '"$word" is split over two lines',
          );
          start = end + 1;
        }
      },
    );

    testWidgets('choosing Español in Settings asks for lang=es', (
      tester,
    ) async {
      _screen(tester, _phone);
      final log = <Uri>[];
      await _pump(
        tester,
        FeedController(
          api: _langApi({
            'en': {'': english},
            'es': {
              '': {
                'items': <Map<String, dynamic>>[],
                'nextCursor': null,
                'top': <Map<String, dynamic>>[],
              },
            },
          }, log: log),
        ),
      );
      await _chooseLanguage(tester, 'Español');
      expect(log.last.queryParameters['lang'], 'es');
      expect(find.text('No translated decisions yet.'), findsOneWidget);
    });
  });
}
