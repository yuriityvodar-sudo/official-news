import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/news_widgets.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _today = localDay(DateTime.now());

Map<String, dynamic> _article(
  String id,
  DateTime publishedAt, {
  String? headline,
  String? imageUrl,
  String country = 'DE',
}) => {
  'id': id,
  'country': country,
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': publishedAt.toUtc().toIso8601String(),
  'dateOnly': false,
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
    if (query.containsKey('since')) {
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

Future<FeedController> _pump(WidgetTester tester, FeedController feed) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows top stories, then the latest decisions grouped by day', (
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
    expect(find.text('Yesterday'), findsOneWidget);
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
    expect(dayLabel(DateTime(2026, 3, 29, 12), now: now), 'Yesterday');
    expect(dayLabel(DateTime(2026, 3, 30, 0, 10), now: now), 'Today');
    expect(dayLabel(DateTime(2026, 3, 28, 12), now: now), 'Saturday 28 March');
  });
}
