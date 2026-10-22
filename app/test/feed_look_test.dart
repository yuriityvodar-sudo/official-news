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
/// And every look draws the feed as one list (Yurii, 16 Oct): the top stories
/// among the rest, each once, in the order they arrived, with no section
/// titles and no block of its own for the first articles.

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

/// The top stories t1 (with a picture, as a lead card had) and t2, among four
/// more, as the server sends them: newest in the feed first, the top stories
/// in the items too.
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
const _order = ['a1', 't1', 'a2', 'a3', 't2', 'a4'];

/// Any section title, in English or Ukrainian, in any case (C drew them in
/// capitals).
final _sectionTitle = RegExp(
  r'top stories|latest|головне|останнє',
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
        testWidgets('one list in ${language.code}: every article once, newest '
            'first, no section titles, every row alike', (tester) async {
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
          expect(find.textContaining(_sectionTitle), findsNothing);
          expect(
            find.textContaining(_sectionTitle, findRichText: true),
            findsNothing,
          );
          expect(
            find.bySemanticsLabel(_sectionTitle),
            findsNothing,
            reason: 'no title for VoiceOver either',
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

      testWidgets('opens each article with section "feed" and its place in '
          'the one list', (tester) async {
        await pumpFeed(tester, _items, _top);

        await tester.tap(find.text('Decision t1'));
        await tester.pumpAndSettle();
        expect(
          (lastOpened()['section'], lastOpened()['position']),
          ('feed', 1),
        );
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Decision t2'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // Wholly on screen: scrolling may stop with only its top in view.
        await tester.ensureVisible(find.text('Decision t2'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Decision t2'));
        await tester.pumpAndSettle();
        expect(
          (lastOpened()['section'], lastOpened()['position']),
          ('feed', 4),
        );
      });

      testWidgets('with a filter, the place is in the list as shown', (
        tester,
      ) async {
        // a1 is French: with Germany chosen, t1 is first and t2 fourth.
        final items = [
          for (final a in _items)
            a['id'] == 'a1' ? _article('a1', feedSeq: 6, country: 'FR') : a,
        ];
        await pumpFeed(tester, items, _top);
        await tester.tap(
          find.byKey(const ValueKey('filter-where')).hitTestable(),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(CupertinoMenuItem),
            matching: find.text('Germany'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Decision a1'), findsNothing);

        await tester.scrollUntilVisible(
          find.text('Decision t2'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // Wholly on screen, clear of a pinned masthead.
        await Scrollable.ensureVisible(
          tester.element(find.text('Decision t2')),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Decision t2'));
        await tester.pumpAndSettle();
        expect(
          (lastOpened()['section'], lastOpened()['position']),
          ('feed', 3),
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

      testWidgets('loading more adds to the end of the list; a top story on '
          'a later page waits for it', (tester) async {
        final api = _pagedApi({
          '': {
            'items': [
              for (var i = 40; i > 20; i--) _article('p$i', feedSeq: i),
            ],
            'nextCursor': 'c2',
            // p30 is on this page; p15 only on the next one.
            'top': [_article('p30', feedSeq: 30), _article('p15', feedSeq: 15)],
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
        // 27 rows, 5 of them top stories: Latest alone had 22, short of 25.
        final items = [
          for (var i = 27; i >= 1; i--) _article('n$i', feedSeq: i),
        ];
        final feed = await pumpFeed(tester, items, [
          for (final i in [26, 20, 14, 8, 2]) items[27 - i],
        ]);
        expect(feed.feed, hasLength(27));
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
    // The row shows the icon of the look that is on; the sheet offers the
    // four icons, no letters.
    final semantics = tester.ensureSemantics();
    expect(find.text('Design'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.square_list), findsOneWidget);
    // VoiceOver hears the look's name with the row's title.
    expect(find.bySemanticsLabel(RegExp(r'\bNow\b')), findsOneWidget);
    await tester.tap(find.text('Design'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    for (final icon in [
      CupertinoIcons.news,
      CupertinoIcons.rectangle_grid_1x2,
      CupertinoIcons.text_alignleft,
    ]) {
      expect(find.byIcon(icon), findsOneWidget);
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
    expect(find.byIcon(CupertinoIcons.rectangle_grid_1x2), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'\bDesign B\b')), findsOneWidget);
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
}
