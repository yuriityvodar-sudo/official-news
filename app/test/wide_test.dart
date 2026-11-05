import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/home_country.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/core/wide.dart';
import 'package:official_news/features/detail/detail_screen.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

Map<String, dynamic> _decision(String id, int feedSeq) => {
  'id': id,
  'feedSeq': feedSeq,
  'country': 'CZ',
  'source': {
    'id': 'cz-gov',
    'name': 'Government of the Czech Republic',
    'url': 'https://vlada.gov.cz',
  },
  'publishedAt': DateTime.now().toUtc().toIso8601String(),
  'dateOnly': false,
  'headline': 'Decision $id',
  'shortSummary': 'Short summary $id.',
  'summary': 'Summary $id',
  'decisionType': 'cabinet-decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'cs',
  'topics': ['economy'],
  'tags': <String>[],
  'importance': 3,
  'imageUrl': null,
  'originalUrl': 'https://vlada.gov.cz/$id',
};

/// The iPad and other wide windows (#137; Roman's pick A of
/// `handoff/ipad-layout.html`, 5 Nov: like Apple News): the feed in two or
/// three columns, the first of the Top stories wider and larger, the rest in
/// a column in the middle. A phone keeps its one column (the other tests).
void main() {
  test('the columns follow the window, never the device', () {
    expect(feedColumns(393), 1);
    expect(feedColumns(699), 1);
    expect(feedColumns(700), 2);
    expect(feedColumns(1032), 2);
    expect(feedColumns(1099), 2);
    expect(feedColumns(1100), 3);
    expect(feedColumns(1376), 3);
    expect(sideMargin(393), 0);
    expect(sideMargin(1032), (1032 - readableWidth) / 2);
    expect(sideMargin(1032, maxWidth: chatWidth), (1032 - chatWidth) / 2);
  });

  testWidgets('a row of cards: each as wide as its columns, all as tall as '
      'the tallest', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 312,
            // Not const: the row checks its spans against its cards.
            child: CardRow(
              columns: 3,
              spans: const [2, 1],
              children: const [
                SizedBox(key: Key('wide'), height: 40),
                SizedBox(key: Key('one'), height: 90),
              ],
            ),
          ),
        ),
      ),
    );
    // (312 - 2 gaps of 12) / 3 = 96 a column.
    expect(
      tester.getRect(find.byKey(const Key('wide'))),
      const Rect.fromLTWH(0, 0, 204, 90),
    );
    expect(
      tester.getRect(find.byKey(const Key('one'))),
      const Rect.fromLTWH(216, 0, 96, 90),
    );
  });

  group("the News looks' feed", () {
    late Future<String?> Function() region;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      feedDesign.value = FeedDesign.garnet;
      region = readPhoneRegion;
      readPhoneRegion = () async => 'CZ';
    });
    tearDown(() {
      feedDesign.value = FeedDesign.now;
      readPhoneRegion = region;
    });

    /// For you in Czechia in a window [width] wide: three top decisions, two
    /// ticks and two stories, and six decisions in the list.
    Future<void> pumpFeed(WidgetTester tester, double width) async {
      final top = [_decision('t1', 9), _decision('t2', 8), _decision('t3', 7)];
      final page = {
        'items': [...top, for (var i = 6; i > 0; i--) _decision('a$i', i)],
        'nextCursor': null,
        'top': top,
      };
      final api = ApiClient(
        baseUrl: 'https://api.test',
        client: MockClient((request) async {
          final menu = fakeMenus(request);
          if (menu != null) return menu;
          return request.url.queryParameters['for'] == 'CZ'
              ? fakeJson({
                  ...page,
                  'stories': [
                    for (var i = 0; i < 2; i++)
                      fakeStory(id: 's$i', title: 'Story $i'),
                  ],
                  'ticks': [
                    for (var i = 0; i < 2; i++)
                      fakeTick(id: 'w$i', title: 'Tick $i'),
                  ],
                })
              : fakeJson(page);
        }),
      );
      // Tall enough for the whole feed.
      tester.view.physicalSize = Size(width, 4000) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        testApp(
          onGenerateRoute: onGenerateRoute,
          home: Theme(
            data: buildTheme(Brightness.light),
            child: FeedScreen(
              controller: FeedController(api: api),
              newCheckEvery: const Duration(hours: 1),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    /// The card a headline stands in: its background.
    Rect card(WidgetTester tester, String headline) => tester.getRect(
      find
          .ancestor(
            of: find.text(headline),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );

    testWidgets('on an iPad held upright, two columns: the first of the Top '
        'stories across both, in larger type; then two cards a row, as tall '
        'as each other', (tester) async {
      await pumpFeed(tester, 1032);
      const content = 1032 - 2 * 16.0;
      const column = (content - 12) / 2;
      // The block's order as on a phone: two of the media's news before each decision.
      final lead = card(tester, 'Tick 0');
      expect(lead.left, 16);
      expect(lead.width, content);
      expect(tester.widget<Text>(find.text('Tick 0')).style!.fontSize, 26);
      expect(tester.widget<Text>(find.text('Story 0')).style!.fontSize, 18);

      final story = card(tester, 'Story 0');
      final decision = card(tester, 'Decision t1');
      expect(story.top, greaterThan(lead.bottom));
      expect(story.left, 16);
      expect(story.width, column);
      expect(decision.top, story.top);
      expect(decision.left, 16 + column + 12);
      expect(decision.height, story.height);

      // The list under the block, two a row.
      final a6 = card(tester, 'Decision a6');
      final a5 = card(tester, 'Decision a5');
      expect(a5.top, a6.top);
      expect(a5.left, a6.right + 12);
      expect(card(tester, 'Decision a4').top, greaterThan(a6.bottom));
    });

    testWidgets('on an iPad held sideways, three columns: the first of the '
        'Top stories across two, one card beside it', (tester) async {
      await pumpFeed(tester, 1376);
      const column = (1376 - 2 * 16.0 - 2 * 12) / 3;
      final lead = card(tester, 'Tick 0');
      expect(lead.width, 2 * column + 12);
      final story = card(tester, 'Story 0');
      expect(story.top, lead.top);
      expect(story.height, lead.height);
      expect(story.width, column);
      // Then three a row.
      final t1 = card(tester, 'Decision t1');
      expect(card(tester, 'Tick 1').top, t1.top);
      expect(card(tester, 'Story 1').top, t1.top);
      expect(card(tester, 'Decision a5').top, card(tester, 'Decision a6').top);
      expect(card(tester, 'Decision a4').top, card(tester, 'Decision a6').top);
    });

    testWidgets('in a narrow iPad window, one column, as on a phone', (
      tester,
    ) async {
      await pumpFeed(tester, 600);
      expect(card(tester, 'Tick 0').width, 600 - 2 * 16.0);
      expect(
        card(tester, 'Story 0').top,
        greaterThan(card(tester, 'Tick 0').bottom),
      );
      expect(tester.widget<Text>(find.text('Tick 0')).style!.fontSize, 18);
    });
  });

  testWidgets('an article on an iPad stands in a column in the middle; its '
      "bar's buttons stay at the screen's edges", (tester) async {
    tester.view.physicalSize = const Size(1032, 1376) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final article = Article.fromJson(_decision('a1', 1));
    await tester.pumpWidget(
      testApp(
        home: DetailScreen(
          article: article,
          openLink: (_) async {},
          share: (_, _, _) async {},
        ),
      ),
    );
    await tester.pump();
    const side = (1032 - readableWidth) / 2;
    final summary = tester.getRect(find.text('Summary a1'));
    expect(summary.left, side + 20);
    expect(summary.right, lessThanOrEqualTo(1032 - side - 20));
    expect(tester.getTopLeft(find.text('Decision a1')).dx, side + 20);
  });
}
