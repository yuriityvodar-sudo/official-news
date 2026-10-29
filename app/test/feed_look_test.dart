import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Theme;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/feed_store.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/core/glass.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/core/topics.dart';
import 'package:official_news/features/chat/chat_style.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_pills.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:official_news/features/feed/feed_touches.dart';
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
    double width = 393,
    double height = 852,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, height) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final feed = FeedController(api: api ?? _api(items, top));
    await tester.pumpWidget(
      testApp(
        language: language,
        onGenerateRoute: onGenerateRoute,
        home: Theme(
          data: buildTheme(brightness),
          child: FeedScreen(
            controller: feed,
            newCheckEvery: const Duration(hours: 1),
          ),
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

  test('a build names its design in any case; anything else, and a new '
      'reader, gets Garnet', () {
    expect(designNamed('a'), FeedDesign.a);
    expect(designNamed(' B '), FeedDesign.b);
    expect(designNamed('now'), FeedDesign.now);
    expect(designNamed('Seal'), FeedDesign.seal);
    // Yurii, 28 Oct (#176, #195): Garnet is what a new reader sees first.
    expect(defaultDesign, FeedDesign.garnet);
    expect(designNamed(''), FeedDesign.garnet);
    expect(designNamed('z'), FeedDesign.garnet);
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
          expect(find.text('Outer News'), findsOneWidget);
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
        // a1 is about health: with Economy chosen, the list is a2, a3 and a4.
        final items = [
          for (final a in _items)
            a['id'] == 'a1'
                ? {
                    ..._article('a1', feedSeq: 6),
                    'topics': ['health'],
                  }
                : a,
        ];
        await pumpFeed(tester, items, _top);
        final pill = find.byKey(const ValueKey('pill-topic-economy'));
        if (pill.evaluate().isNotEmpty) {
          // Garnet and Seal: the topics are pills, along the row.
          await tester.ensureVisible(pill);
          await tester.pumpAndSettle();
          await tester.tap(pill);
        } else {
          await tester.tap(
            find.byKey(const ValueKey('filter-topic')).hitTestable(),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(CupertinoMenuItem),
              matching: find.text('Economy'),
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

      /// The look's colour: Garnet's red or Seal's green.
      final accent = design == FeedDesign.seal
          ? const Color(0xFF0E7A5E)
          : const Color(0xFFC41230);

      testWidgets('the logo before the app\'s name, the date, '
          'the filters, and every decision on a white card', (tester) async {
        await pumpFeed(tester, _items, _top);
        final logo = find.byKey(const ValueKey('masthead-logo'));
        expect(logo, findsOneWidget);
        expect(
          tester.getCenter(logo).dx,
          lessThan(tester.getTopLeft(find.text('Outer News')).dx),
        );
        // What the feed shows as pills under the date, not the other looks'
        // menu (#170).
        expect(find.byType(FeedPills), findsOneWidget);
        expect(find.byKey(const ValueKey('filter-topic')), findsNothing);
        final card = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.text('Decision a1'),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final box = card.decoration as BoxDecoration;
        expect(box.color, const Color(0xFFFFFFFF));
        expect(box.borderRadius, BorderRadius.circular(24));
        // A soft shadow in a tint of the colour.
        expect(box.boxShadow!.last.color.withValues(alpha: 1), accent);
        // The time of a decision from the last hour in the colour too, not
        // the app's pink (Yurii, #196).
        final fresh = tester.widgetList<FreshTime>(find.byType(FreshTime));
        expect(fresh, isNotEmpty);
        for (final time in fresh) {
          expect(time.color, accent);
        }
      });

      testWidgets('the AI chat takes the look\'s colour', (tester) async {
        late ChatStyle chat;
        await tester.pumpWidget(
          CupertinoApp(
            home: Builder(
              builder: (context) {
                chat = ChatStyle.of(context);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(chat.fill, accent);
      });
    });
  }

  for (final design in [FeedDesign.garnet, FeedDesign.seal]) {
    group('design ${design.name}: the tint and the pull', () {
      setUp(() => feedDesign.value = design);

      /// The look's colour: Garnet's red or Seal's green.
      final accent = design == FeedDesign.seal
          ? const Color(0xFF0E7A5E)
          : const Color(0xFFC41230);

      testWidgets("the page's top takes a tint of the colour, one piece with "
          "the status bar's", (tester) async {
        await pumpFeed(tester, _items, _top);
        final tint = Color.alphaBlend(
          accent.withValues(alpha: 0.1),
          const Color(0xFFF2F2F7),
        );
        final backdrop = tester
            .widgetList<DecoratedBox>(find.byType(DecoratedBox))
            .map((box) => box.decoration)
            .whereType<BoxDecoration>()
            .map((decoration) => decoration.gradient)
            .whereType<LinearGradient>()
            .firstWhere((gradient) => gradient.colors.length == 2);
        expect(backdrop.colors, [tint, const Color(0xFFF2F2F7)]);
        expect(backdrop.stops, [0, 0.32]);
      });

      testWidgets('pulled down, the title and the date grow from their left '
          'edge, grey words in the gap say to pull, and no glow rises', (
        tester,
      ) async {
        await pumpFeed(tester, [_article('r0', feedSeq: 1)], const []);
        final title = find.text('Outer News');
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

      /// Lets the pull go and draws the next [time] frame by frame, as the
      /// gap springs back to where it rests and the feed is asked again.
      Future<void> letGo(
        WidgetTester tester,
        TestGesture pull, [
        Duration time = const Duration(milliseconds: 300),
      ]) async {
        const frame = Duration(milliseconds: 50);
        await pull.up();
        for (var t = Duration.zero; t < time; t += frame) {
          await tester.pump(frame);
        }
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
        final title = find.text('Outer News');
        final rest = tester.getRect(title);
        final pull = await pullFar(tester);
        expect(find.text('Release to refresh'), findsOneWidget);
        expect(tester.getRect(title).width, greaterThan(rest.width * 1.05));
        // Held there, it waits to be let go, as it says (Yurii, #208): the
        // feed is not asked again yet.
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Release to refresh'), findsOneWidget);
        expect(find.text('Decision n1'), findsNothing);
        await letGo(tester, pull);
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
        await letGo(tester, pull);
        expect(find.text('1 new decision'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
      });

      testWidgets('a feed that another replaces while the gap is open says '
          'nothing about new decisions', (tester) async {
        final answer = Completer<http.Response>();
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
            // The pull's own answer waits; the whole world's comes at once,
            // with w1 in it.
            final r0 = _article('r0', feedSeq: 1);
            return switch (++pages) {
              2 => answer.future,
              1 => fakeJson({
                'items': [r0],
                'nextCursor': null,
                'top': [],
              }),
              _ => fakeJson({
                'items': [_article('w1', feedSeq: 2), r0],
                'nextCursor': null,
                'top': [],
              }),
            };
          }),
        );
        final feed = await pumpFeed(tester, const [], const [], api: api);
        final pull = await pullFar(tester);
        await letGo(tester, pull);
        expect(pages, 2);
        // Yurii's case: For you's feed replaced by the whole world's.
        unawaited(feed.setFeed(FeedWhere.all));
        await tester.pump();
        expect(find.text('Decision w1'), findsOneWidget);
        answer.complete(
          fakeJson({
            'items': [_article('r0', feedSeq: 1)],
            'nextCursor': null,
            'top': [],
          }),
        );
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.textContaining('new decision'), findsNothing);
          expect(find.text('News updated'), findsNothing);
        }
        await tester.pumpAndSettle();
      });

      testWidgets('a refresh that brings nothing new says so', (tester) async {
        await pumpFeed(tester, const [], const [], api: refreshingApi([]));
        final pull = await pullFar(tester);
        await letGo(tester, pull);
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
        await letGo(tester, pull, const Duration(milliseconds: 400));
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

  for (final design in [FeedDesign.garnet, FeedDesign.seal]) {
    group('design ${design.name}: the pills', () {
      setUp(() => feedDesign.value = design);

      /// The look's colour in light mode: Garnet's red or Seal's green.
      final accent = design == FeedDesign.seal
          ? const Color(0xFF0E7A5E)
          : const Color(0xFFC41230);

      final rows = [
        for (var i = 0; i < 12; i++) _article('r$i', feedSeq: 20 - i),
      ];

      /// The pills from left to right, by key.
      List<String> pills(WidgetTester tester) => [
        for (final pill in tester.widgetList(
          find.descendant(
            of: find.byType(FeedPills),
            matching: find.byWidgetPredicate(
              (w) => switch (w.key) {
                ValueKey<String>(:final value) => value.startsWith('pill-'),
                _ => false,
              },
            ),
          ),
        ))
          (pill.key! as ValueKey<String>).value,
      ];

      /// The glass of the pill [key]: the chosen one is filled with the
      /// colour's gradient, the others with a tint of the card.
      BoxDecoration glass(WidgetTester tester, String key) =>
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byKey(ValueKey(key)),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;

      testWidgets('For you first, then the whole world, then the topics '
          'busiest first, as the menu has them; a tap shows each', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final feed = await pumpFeed(tester, rows, const [], width: 2400);
        await tester.pumpAndSettle();
        expect(pills(tester), [
          'pill-for-you',
          'pill-world',
          for (final id in topicIds) 'pill-topic-$id',
        ]);
        expect(find.byKey(const ValueKey('filter-topic')), findsNothing);
        expect(
          tester.getSemantics(find.byKey(const ValueKey('pill-for-you'))),
          isSemantics(label: 'For you', isButton: true, isSelected: true),
        );
        expect(glass(tester, 'pill-for-you').gradient, isNotNull);
        expect(glass(tester, 'pill-world').gradient, isNull);

        await tester.tap(find.byKey(const ValueKey('pill-world')));
        await tester.pumpAndSettle();
        expect((feed.where, feed.topic), (FeedWhere.all, null));
        expect(
          tester.getSemantics(find.byKey(const ValueKey('pill-world'))),
          isSemantics(label: 'The whole world', isSelected: true),
        );
        expect(
          tester.getSemantics(find.byKey(const ValueKey('pill-for-you'))),
          isSemantics(isSelected: false),
        );

        // A topic is the whole world's (#170).
        await tester.tap(find.byKey(const ValueKey('pill-topic-health')));
        await tester.pumpAndSettle();
        expect((feed.where, feed.topic), (FeedWhere.all, 'health'));
        expect(glass(tester, 'pill-topic-health').gradient, isNotNull);
        expect(glass(tester, 'pill-world').gradient, isNull);

        await tester.tap(find.byKey(const ValueKey('pill-for-you')));
        await tester.pumpAndSettle();
        expect((feed.where, feed.topic), (FeedWhere.forYou, null));
        semantics.dispose();
      });

      for (final brightness in Brightness.values) {
        testWidgets('the chosen pill is the colour deepening, its white words '
            'at least 4.5:1 in ${brightness.name} mode (Yurii, #210)', (
          tester,
        ) async {
          await pumpFeed(tester, rows, const [], brightness: brightness);
          final colors =
              (glass(tester, 'pill-for-you').gradient! as LinearGradient)
                  .colors;
          for (final colour in colors) {
            final opaque = colour.withValues(alpha: 1);
            expect(
              1.05 / (opaque.computeLuminance() + 0.05),
              greaterThanOrEqualTo(4.5),
              reason: '$opaque',
            );
          }
          // The same deep colour in both themes, the look's own first.
          expect(colors.first.withValues(alpha: 1), accent);
          expect(
            tester.widget<Text>(find.text('For you')).style!.color,
            const Color(0xFFFFFFFF),
          );
        });
      }

      testWidgets('the pills stay at the top as glass while the rows pass '
          'under them; nothing fades over them', (tester) async {
        await pumpFeed(tester, rows, const [], height: 700);
        final row = find.byType(FeedPills);
        expect(tester.getTopLeft(row).dy, greaterThan(60));
        await tester.drag(find.text('Decision r3'), const Offset(0, -500));
        await tester.pumpAndSettle();
        // Pinned at the top of the safe area, rows scrolled under it.
        expect(tester.getTopLeft(row).dy, 0);
        expect(find.text('For you'), findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.byType(BackdropFilter)),
          findsWidgets,
        );
        expect(find.byType(ScrollEdgeFade), findsNothing);
        // The chosen pill's glow reaches over the rows, not cut where the
        // pinned header ends (Yurii, #210).
        final header = tester.widget<Stack>(
          find.ancestor(of: row, matching: find.byType(Stack)).first,
        );
        expect(header.clipBehavior, Clip.none);
      });

      testWidgets('at a large text size the pills grow with their words: '
          'none is cut (Yurii, #210)', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpFeed(tester, rows, const [], height: 700);
        await tester.pumpAndSettle();
        for (final name in ['For you', 'The whole world']) {
          final words = tester.renderObject<RenderParagraph>(find.text(name));
          expect(
            words.size.height,
            greaterThanOrEqualTo(
              words.getMaxIntrinsicHeight(words.size.width) - 0.01,
            ),
            reason: name,
          );
        }
      });

      testWidgets('a chosen topic that moves along the row as the fresh '
          'topics come in is brought into view again (Yurii, #210)', (
        tester,
      ) async {
        // Kept from last time: Justice first among the topics; the server
        // now lists it last, once the row is on screen.
        SharedPreferences.setMockInitialValues({
          'feed.topic': 'justice',
          'feed.topics.en': jsonEncode([
            {'id': 'justice', 'name': 'Justice'},
            for (final id in topicIds)
              if (id != 'justice') {'id': id, 'name': id},
          ]),
        });
        final topics = Completer<http.Response>();
        final api = ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient((request) async {
            if (request.url.path == '/topics') return topics.future;
            final menu = fakeMenus(request);
            if (menu != null) return menu;
            return fakeJson({'items': rows, 'nextCursor': null, 'top': []});
          }),
        );
        await pumpFeed(tester, const [], const [], api: api);
        await tester.pumpAndSettle();
        expect(pills(tester)[2], 'pill-topic-justice');

        topics.complete(
          fakeMenus(http.Request('GET', Uri.parse('https://api.test/topics'))),
        );
        await tester.pumpAndSettle();
        expect(pills(tester).last, 'pill-topic-justice');
        final pill = find.byKey(const ValueKey('pill-topic-justice'));
        expect(tester.getRect(pill).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(pill).right, lessThanOrEqualTo(393));
      });

      testWidgets('swiped sideways, the pills stay where they are as the '
          'title scrolls away and back: the same row, not a new one', (
        tester,
      ) async {
        await pumpFeed(tester, rows, const [], height: 700);
        await tester.pumpAndSettle();
        final row = find.byType(FeedPills);
        final forYou = find.text('For you');
        await tester.drag(forYou, const Offset(-120, 0));
        await tester.pumpAndSettle();
        final swiped = tester.getTopLeft(forYou).dx;
        expect(swiped, lessThan(0));

        await tester.drag(find.text('Decision r3'), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(row).dy, 0);
        expect(tester.getTopLeft(forYou).dx, swiped);

        await tester.drag(find.text('Decision r5'), const Offset(0, 500));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(row).dy, greaterThan(60));
        expect(tester.getTopLeft(forYou).dx, swiped);
      });

      testWidgets('a topic chosen before the app was closed shows chosen, '
          'brought into view along the row', (tester) async {
        SharedPreferences.setMockInitialValues({'feed.topic': 'justice'});
        final feed = await pumpFeed(tester, rows, const []);
        await tester.pumpAndSettle();
        expect((feed.where, feed.topic), (FeedWhere.all, 'justice'));
        final pill = find.byKey(const ValueKey('pill-topic-justice'));
        expect(glass(tester, 'pill-topic-justice').gradient, isNotNull);
        expect(tester.getRect(pill).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(pill).right, lessThanOrEqualTo(393));
      });

      testWidgets('a pill chosen in view leaves the row where it is; one '
          'partly out of view glides to the middle', (tester) async {
        await pumpFeed(tester, rows, const [], width: 1000);
        await tester.pumpAndSettle();
        final scroll = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(FeedPills),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('pill-topic-economy')));
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, 0);

        // Its end is out of view: tapped by its start.
        final next = find.byKey(const ValueKey('pill-topic-security-defence'));
        final start = tester.getRect(next);
        expect(start.right, greaterThan(1000));
        await tester.tapAt(start.centerLeft + const Offset(20, 0));
        // The new choice drawn, then the glide's first frame and 100 ms.
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final gliding = scroll.position.pixels;
        await tester.pumpAndSettle();
        expect(gliding, greaterThan(0));
        expect(gliding, lessThan(scroll.position.pixels));
        expect(tester.getCenter(next).dx, moreOrLessEquals(500, epsilon: 1));
      });
    });
  }
}
