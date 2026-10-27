import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/feed_store.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:official_news/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// PROTOTYPE (#66): every look keeps what the feed does. Whatever a design
/// option draws, opening an article and scrolling must still reach analytics
/// with the same section, position and depth as today's feed.
///
/// And every look draws the Top stories block (#164, Yurii 26 Oct): a heading
/// and the top stories in the look's own rows, then one list of the rest,
/// each decision once, in the order they arrived, with no other section
/// title.

Map<String, dynamic> _article(
  String id, {
  String? imageUrl,
  int? feedSeq,
  String country = 'DE',
}) => {
  'id': id,
  'feedSeq': feedSeq,
  'country': country,
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': DateTime.now().toUtc().toIso8601String(),
  'dateOnly': false,
  'headline': 'Decision $id',
  'shortSummary': 'Short summary $id.',
  'summary': 'Summary $id',
  'decisionType': 'cabinet-decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'de',
  'topics': ['economy'],
  'tags': <String>[],
  'importance': 3,
  'imageUrl': imageUrl,
  'originalUrl': 'https://www.bundesregierung.de/$id',
};

ApiClient _api(
  List<Map<String, dynamic>> items,
  List<Map<String, dynamic>> top,
) => _pagedApi({
  '': {'items': items, 'nextCursor': null, 'top': top},
});

/// A fake API: the pages by cursor ('' for the first), and for the new check
/// whatever [newer] returns then.
ApiClient _pagedApi(
  Map<String, Map<String, dynamic>> pages, {
  List<Map<String, dynamic>> Function()? newer,
}) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    final menu = fakeMenus(request);
    if (menu != null) return menu;
    final query = request.url.queryParameters;
    final page = query.containsKey('after') || query.containsKey('since')
        ? {'items': newer?.call() ?? [], 'nextCursor': null, 'top': []}
        : fakePage(pages[query['cursor'] ?? ''], query);
    return page == null
        ? http.Response('{"error":"Internal error"}', 500)
        : http.Response.bytes(
            utf8.encode(jsonEncode(page)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
  }),
);

/// The top stories t1 (with a picture) and t2, among four more, as the server
/// sends them: the items newest in the feed first, the top stories in them
/// too.
final _top = [
  _article('t1', imageUrl: 'https://example.test/t1.jpg', feedSeq: 5),
  _article('t2', feedSeq: 2),
];
final _items = [
  _article('a1', feedSeq: 6),
  _top[0],
  _article('a2', imageUrl: 'https://example.test/a2.jpg', feedSeq: 4),
  _article('a3', feedSeq: 3),
  _top[1],
  _article('a4', feedSeq: 1),
];

/// The block's two, then the list without them.
const _order = ['t1', 't2', 'a1', 'a2', 'a3', 'a4'];

/// Any section title, in English or Ukrainian, in any case (C drew them in
/// capitals).
final _sectionTitle = RegExp(
  r'top stories|latest|головне|останнє',
  caseSensitive: false,
  unicode: true,
);

/// A title other than the Top stories heading.
final _otherTitle = RegExp(
  r'latest|останнє',
  caseSensitive: false,
  unicode: true,
);

void main() {
  late List<(String, Map<String, Object>)> events;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    events = [];
    analytics = Analytics(
      (name, parameters) async => events.add((name, parameters)),
      (name, value) async {},
    );
  });
  tearDown(() {
    analytics = Analytics();
    feedDesign.value = FeedDesign.now;
  });

  Future<FeedController> pumpFeed(
    WidgetTester tester,
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> top, {
    ApiClient? api,
    FeedLanguage language = FeedLanguage.en,
    double height = 852,
  }) async {
    tester.view.physicalSize = Size(393, height) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final feed = FeedController(api: api ?? _api(items, top));
    await tester.pumpWidget(
      testApp(
        language: language,
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

  /// The headlines on screen, top to bottom.
  List<String> shownOrder(WidgetTester tester) {
    final rows = find.textContaining(RegExp(r'^Decision \w+$'));
    final found = [
      for (final e in rows.evaluate())
        (
          (e.widget as Text).data!.substring('Decision '.length),
          tester.getTopLeft(find.byWidget(e.widget)).dy,
        ),
    ]..sort((x, y) => x.$2.compareTo(y.$2));
    return [for (final f in found) f.$1];
  }

  Map<String, Object> lastOpened() =>
      events.lastWhere((e) => e.$1 == 'open_article').$2;

  test('a build names its design in any case; anything else is today\'s', () {
    expect(designNamed('a'), FeedDesign.a);
    expect(designNamed(' B '), FeedDesign.b);
    expect(designNamed('now'), FeedDesign.now);
    expect(designNamed(''), FeedDesign.now);
    expect(designNamed('z'), FeedDesign.now);
  });

  for (final design in FeedDesign.values) {
    group('design ${design.name}', () {
      setUp(() => feedDesign.value = design);

      for (final language in [FeedLanguage.en, FeedLanguage.uk]) {
        testWidgets('Top stories, then one list in ${language.code}: every '
            'article once, no other section title, every row alike', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          // Tall enough to build every row.
          await pumpFeed(
            tester,
            _items,
            _top,
            language: language,
            height: 3000,
          );
          expect(find.text('Official News'), findsOneWidget);
          for (final id in _order) {
            expect(find.text('Decision $id'), findsOneWidget, reason: id);
          }
          expect(shownOrder(tester), _order);
          final heading = language == FeedLanguage.en
              ? 'Top stories'
              : 'Головне';
          expect(find.text(heading), findsOneWidget);
          expect(
            find.textContaining(_sectionTitle, findRichText: true),
            findsOneWidget,
          );
          expect(find.textContaining(_otherTitle), findsNothing);
          expect(
            find.bySemanticsLabel(_sectionTitle),
            findsOneWidget,
            reason: 'VoiceOver hears the one heading',
          );
          // No lead card and no bigger top-story card: every headline is
          // drawn in the same size, the first top story's too.
          final sizes = {
            for (final id in _order)
              tester
                  .renderObject<RenderParagraph>(find.text('Decision $id'))
                  .text
                  .style
                  ?.fontSize,
          };
          expect(sizes, hasLength(1), reason: '$sizes');
          // No numbered top block (C numbered its top stories 1 to 5).
          for (final n in ['1', '2']) {
            expect(find.text(n), findsNothing);
          }
          semantics.dispose();
        });
      }

      testWidgets('opens a top story with section "top" and its place in the '
          'block, the rest with "feed" and theirs in the list', (tester) async {
        await pumpFeed(tester, _items, _top);

        await tester.tap(find.text('Decision t2'));
        await tester.pumpAndSettle();
        expect((lastOpened()['section'], lastOpened()['position']), ('top', 1));
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Decision a3'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // Wholly on screen: scrolling may stop with only its top in view.
        await tester.ensureVisible(find.text('Decision a3'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Decision a3'));
        await tester.pumpAndSettle();
        expect(
          (lastOpened()['section'], lastOpened()['position']),
          ('feed', 2),
        );
      });

      testWidgets('with a filter, the place is in the list as shown', (
        tester,
      ) async {
        // a1 is French: with Germany chosen, the list is a2, a3 and a4.
        final items = [
          for (final a in _items)
            a['id'] == 'a1' ? _article('a1', feedSeq: 6, country: 'FR') : a,
        ];
        final feed = await pumpFeed(tester, items, _top);
        final where = find.byKey(const ValueKey('filter-where')).hitTestable();
        if (where.evaluate().isEmpty) {
          // Garnet and Seal show no country to choose (Roman, 26 Oct).
          await feed.setWhere(const FeedWhere.country('DE'));
        } else {
          await tester.tap(where);
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(CupertinoMenuItem),
              matching: find.text('Germany'),
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(find.text('Decision a1'), findsNothing);

        await tester.scrollUntilVisible(
          find.text('Decision a3'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // Wholly on screen, clear of a pinned masthead.
        await Scrollable.ensureVisible(
          tester.element(find.text('Decision a3')),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Decision a3'));
        await tester.pumpAndSettle();
        expect(
          (lastOpened()['section'], lastOpened()['position']),
          ('feed', 1),
        );
      });

      testWidgets('new arrivals: the pill counts them, and a tap shows them '
          'at the top of the same list', (tester) async {
        var newest = 20;
        Map<String, dynamic> firstPage() => {
          'items': [
            for (var i = newest; i >= 1; i--) _article('n$i', feedSeq: i),
          ],
          'nextCursor': null,
          'top': [_article('n3', feedSeq: 3)],
        };
        final api = ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient((request) async {
            final menu = fakeMenus(request);
            if (menu != null) return menu;
            final query = request.url.queryParameters;
            final after = int.tryParse(query['after'] ?? '');
            final page = after == null
                ? firstPage()
                : {
                    'items': [
                      for (var i = 22; i > after; i--)
                        _article('n$i', feedSeq: i),
                    ],
                    'nextCursor': null,
                    'top': [],
                  };
            return http.Response(jsonEncode(page), 200);
          }),
        );
        final feed = await pumpFeed(tester, const [], const [], api: api);
        expect(shownOrder(tester).first, 'n20');
        // Read a little way down, then two decisions arrive.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
        await tester.pumpAndSettle();
        newest = 22;
        await feed.checkForNew();
        await tester.pump();
        expect(feed.newCount, 2);
        final pill = find.text('2 new decisions');
        expect(pill, findsOneWidget);

        await tester.tap(pill);
        await tester.pumpAndSettle();
        expect(pill, findsNothing);
        expect(
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .pixels,
          0,
        );
        expect(shownOrder(tester).take(3), ['n22', 'n21', 'n20']);
        expect(feed.feed.map((a) => a.id).take(3), ['n22', 'n21', 'n20']);
        expect(feed.feed.where((a) => a.id == 'n3'), hasLength(1));
        expect(find.textContaining(_sectionTitle), findsNothing);
      });

      testWidgets('loading more adds to the end of the list; a lone top story '
          '(no block) on a later page waits for it', (tester) async {
        final api = _pagedApi({
          '': {
            'items': [
              for (var i = 40; i > 20; i--) _article('p$i', feedSeq: i),
            ],
            'nextCursor': 'c2',
            // p15 is only on the next page.
            'top': [_article('p15', feedSeq: 15)],
          },
          'c2': {
            'items': [
              for (var i = 20; i >= 1; i--) _article('p$i', feedSeq: i),
            ],
            'nextCursor': null,
            'top': [],
          },
        });
        final feed = await pumpFeed(tester, const [], const [], api: api);
        final first = feed.feed.map((a) => a.id).toList();
        expect(first, [for (var i = 40; i > 20; i--) 'p$i']);

        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -20000),
        );
        await tester.pumpAndSettle();
        expect(feed.hasMore, isFalse);
        final all = feed.feed.map((a) => a.id).toList();
        expect(all, [for (var i = 40; i >= 1; i--) 'p$i']);
        expect(all.take(first.length), first);
        await tester.scrollUntilVisible(
          find.text('Decision p15'),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Decision p15'), findsOneWidget);
      });

      testWidgets('sends each feed depth once, as the reader scrolls down, '
          'the top stories\' rows counted too', (tester) async {
        // 27 rows, 3 of them in the Top stories block: the list alone has 24,
        // short of 25.
        final items = [
          for (var i = 27; i >= 1; i--) _article('n$i', feedSeq: i),
        ];
        final feed = await pumpFeed(tester, items, [
          for (final i in [26, 20, 14, 8, 2]) items[27 - i],
        ]);
        expect(feed.topStories, hasLength(3));
        expect(feed.feed, hasLength(24));
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -20000),
        );
        await tester.pumpAndSettle();
        expect(
          events.map((e) => e.$1).where((n) => n.startsWith('feed_scroll_')),
          ['feed_scroll_10', 'feed_scroll_25'],
        );
      });
    });
  }

  testWidgets('the Design row in Settings switches the feed\'s look', (
    tester,
  ) async {
    FeedDesign? saved;
    await tester.pumpWidget(
      testApp(
        home: SettingsScreen(
          language: ValueNotifier(FeedLanguage.en),
          onLanguage: (_) {},
          saveDesign: (d) => saved = d,
        ),
      ),
    );
    // The row shows the name of the look that is on; the sheet offers every
    // look by its icon and name, no letters.
    final semantics = tester.ensureSemantics();
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('Classic'), findsOneWidget);
    // VoiceOver hears the look's name with the row's title.
    expect(find.bySemanticsLabel(RegExp(r'\bClassic\b')), findsOneWidget);
    await tester.tap(find.text('Design'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    for (final (icon, name) in [
      (CupertinoIcons.square_list, 'Classic'),
      (CupertinoIcons.news, 'Magazine'),
      (CupertinoIcons.rectangle_grid_1x2, 'Cards'),
      (CupertinoIcons.text_alignleft, 'Briefing'),
      (CupertinoIcons.rectangle_stack, 'Garnet'),
      (CupertinoIcons.checkmark_seal, 'Seal'),
    ]) {
      expect(find.byIcon(icon), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CupertinoActionSheet),
          matching: find.text(name),
        ),
        findsOneWidget,
      );
    }
    for (final letter in ['A', 'B', 'C']) {
      expect(find.text(letter), findsNothing);
    }
    // The look that is on has the check mark.
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.rectangle_grid_1x2));
    await tester.pumpAndSettle();
    expect(feedDesign.value, FeedDesign.b);
    expect(saved, FeedDesign.b);
    expect(find.text('Cards'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'\bCards\b')), findsOneWidget);
    semantics.dispose();
    feedDesign.value = FeedDesign.now;
  });

  test('the look and the headline weight are kept on the phone, today\'s '
      'look and bold too, so a choice wins over a build\'s start', () async {
    SharedPreferences.setMockInitialValues({});
    final store = FeedStore(await SharedPreferences.getInstance());
    expect(store.design(), isNull);
    expect(store.headlineWeight(), isNull);
    await store.saveDesign(FeedDesign.b);
    await store.saveHeadlineWeight(HeadlineWeight.light);
    expect(store.design(), FeedDesign.b);
    expect(store.headlineWeight(), HeadlineWeight.light);
    await store.saveDesign(FeedDesign.now);
    await store.saveHeadlineWeight(HeadlineWeight.bold);
    final again = FeedStore(await SharedPreferences.getInstance());
    expect(again.design(), FeedDesign.now);
    expect(again.headlineWeight(), HeadlineWeight.bold);
  });

  for (final design in [FeedDesign.garnet, FeedDesign.seal]) {
    group('design ${design.name}', () {
      setUp(() => feedDesign.value = design);

      testWidgets('the topic pills stay at the top as glass while the rows '
          'pass under them; nothing fades over them', (tester) async {
        await pumpFeed(
          tester,
          [for (var i = 0; i < 12; i++) _article('r$i', feedSeq: 20 - i)],
          const [],
          height: 700,
        );
        final pills = find.byType(TopicPills);
        final before = tester.getTopLeft(pills).dy;
        expect(before, greaterThan(60));
        await tester.drag(find.text('Decision r3'), const Offset(0, -500));
        await tester.pumpAndSettle();
        // Pinned at the top of the safe area, rows scrolled under it.
        expect(tester.getTopLeft(pills).dy, 0);
        expect(find.text('All topics'), findsOneWidget);
        expect(
          find.descendant(of: pills, matching: find.byType(BackdropFilter)),
          findsWidgets,
        );
      });

      testWidgets('pulled down, the title and the date grow from their left '
          'edge, grey words in the gap say to pull, and no glow rises', (
        tester,
      ) async {
        await pumpFeed(tester, [_article('r0', feedSeq: 1)], const []);
        final title = find.text('Official News');
        final rest = tester.getRect(title);
        final pull = await tester.startGesture(
          tester.getCenter(find.text('Decision r0')),
        );
        await pull.moveBy(const Offset(0, 60));
        await pull.moveBy(const Offset(0, 60));
        await tester.pump();
        expect(find.text('Pull to refresh'), findsOneWidget);
        expect(find.byType(ImageFiltered), findsNothing);
        final pulled = tester.getRect(title);
        final grown = pulled.width / rest.width;
        expect(grown, greaterThan(1.02));
        // From the left edge of the masthead's text, 16 points in: the
        // name, after the seal, moves right only as much as the seal grows.
        expect(
          pulled.left - rest.left,
          moreOrLessEquals((rest.left - 16) * (grown - 1), epsilon: 0.01),
        );
        await pull.up();
        await tester.pumpAndSettle();
        // Sprung back with the feed.
        expect(tester.getRect(title), rest);
        expect(find.text('Pull to refresh'), findsNothing);
      });

      /// A server whose first page has one decision, and [fresh] more on
      /// top of it once it is asked again.
      ApiClient refreshingApi(List<Map<String, dynamic>> fresh) {
        var pages = 0;
        return ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient((request) async {
            final menu = fakeMenus(request);
            if (menu != null) return menu;
            final query = request.url.queryParameters;
            final newCheck =
                query.containsKey('after') || query.containsKey('since');
            if (!newCheck) pages++;
            return fakeJson({
              'items': [
                if (!newCheck && pages > 1) ...fresh,
                if (!newCheck) _article('r0', feedSeq: 1),
              ],
              'nextCursor': null,
              'top': [],
            });
          }),
        );
      }

      /// Pulls the feed down past the point where it refreshes, holding it.
      Future<TestGesture> pullFar(WidgetTester tester) async {
        final pull = await tester.startGesture(
          tester.getCenter(find.text('Decision r0')),
        );
        for (var i = 0; i < 8; i++) {
          await pull.moveBy(const Offset(0, 50));
          await tester.pump();
        }
        return pull;
      }

      testWidgets('pulled far enough it says to let go; once refreshed it '
          'says how many decisions are new, then the gap closes', (
        tester,
      ) async {
        await pumpFeed(
          tester,
          const [],
          const [],
          api: refreshingApi([
            _article('n1', feedSeq: 3),
            _article('n2', feedSeq: 2),
          ]),
        );
        final title = find.text('Official News');
        final rest = tester.getRect(title);
        final pull = await pullFar(tester);
        expect(find.text('Release to refresh'), findsOneWidget);
        expect(tester.getRect(title).width, greaterThan(rest.width * 1.05));
        await pull.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('2 new decisions'), findsOneWidget);
        expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOne);
        expect(find.text('Decision n1'), findsOneWidget);

        // Held about a second, then gone with the gap; the title is its own
        // size again while the gap stays open.
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('2 new decisions'), findsOneWidget);
        expect(tester.getRect(title).width, moreOrLessEquals(rest.width));
        expect(tester.getRect(title).top, greaterThan(rest.top + 40));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(find.text('2 new decisions'), findsNothing);
      });

      testWidgets('a top story that comes in counts as new; one that moves '
          'into the Top stories block does not', (tester) async {
        var pages = 0;
        final api = ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient((request) async {
            final menu = fakeMenus(request);
            if (menu != null) return menu;
            final query = request.url.queryParameters;
            if (query.containsKey('after') || query.containsKey('since')) {
              return fakeJson({'items': [], 'nextCursor': null, 'top': []});
            }
            final r0 = _article('r0', feedSeq: 1);
            final r1 = _article('r1', feedSeq: 2);
            final n1 = _article('n1', feedSeq: 3);
            return fakeJson(
              ++pages == 1
                  ? {
                      'items': [r1, r0],
                      'nextCursor': null,
                      'top': [],
                    }
                  : {
                      'items': [n1, r1, r0],
                      'nextCursor': null,
                      'top': [n1, r1],
                    },
            );
          }),
        );
        await pumpFeed(tester, const [], const [], api: api);
        final pull = await pullFar(tester);
        await pull.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('1 new decision'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
      });

      testWidgets('a refresh that brings nothing new says so', (tester) async {
        await pumpFeed(tester, const [], const [], api: refreshingApi([]));
        final pull = await pullFar(tester);
        await pull.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('No new decisions'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text('No new decisions'), findsNothing);
      });

      testWidgets('while the feed loads, the words pulse softly', (
        tester,
      ) async {
        final answer = Completer<http.Response>();
        var pages = 0;
        final api = ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient((request) async {
            final menu = fakeMenus(request);
            if (menu != null) return menu;
            if (++pages > 1) return answer.future;
            return fakeJson({
              'items': [_article('r0', feedSeq: 1)],
              'nextCursor': null,
              'top': [],
            });
          }),
        );
        await pumpFeed(tester, const [], const [], api: api);
        final pull = await pullFar(tester);
        await pull.up();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Refreshing the news…'), findsOneWidget);
        double opacity() => tester
            .widget<Opacity>(
              find
                  .ancestor(
                    of: find.text('Refreshing the news…'),
                    matching: find.byType(Opacity),
                  )
                  .first,
            )
            .opacity;
        final first = opacity();
        await tester.pump(const Duration(milliseconds: 350));
        expect(opacity(), isNot(moreOrLessEquals(first)));

        answer.complete(
          fakeJson({
            'items': [_article('r0', feedSeq: 1)],
            'nextCursor': null,
            'top': [],
          }),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
      });
    });
  }
}
