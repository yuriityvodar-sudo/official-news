import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/core/home_country.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:official_news/features/story/story_screen.dart';
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

/// The reader's country's stories in For you's Top stories block (#230, the
/// aggregator; Roman's variant B, 1 Nov): two stories, then a decision, and
/// again; a story opens its page.
void main() {
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

  /// For you in Czechia: three top decisions and five stories; the whole
  /// world's feed has no stories, as the server sends them.
  Future<FeedController> pumpFeed(WidgetTester tester) async {
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
        final forYou = request.url.queryParameters['for'] == 'CZ';
        return forYou
            ? fakeJson({
                ...page,
                'stories': [
                  for (var i = 0; i < 5; i++)
                    fakeStory(id: 's$i', title: 'Story $i'),
                ],
              })
            : fakeJson(page);
      }),
    );
    // Tall enough for the whole block.
    tester.view.physicalSize = const Size(393, 2600) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final feed = FeedController(api: api);
    await tester.pumpWidget(
      testApp(
        onGenerateRoute: onGenerateRoute,
        home: Theme(
          data: buildTheme(Brightness.light),
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

  double top(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('two stories, then a decision, and again; the rest after the '
      'last decision', (tester) async {
    final feed = await pumpFeed(tester);
    expect(feed.stories, hasLength(5));
    final order = [
      'Story 0',
      'Story 1',
      'Decision t1',
      'Story 2',
      'Story 3',
      'Decision t2',
      'Story 4',
      'Decision t3',
    ];
    final ys = [for (final t in order) top(tester, t)];
    expect(ys, [...ys]..sort(), reason: 'in that order, top to bottom');
    // The decisions under the block are the list's, not again.
    expect(find.text('Decision t1'), findsOneWidget);
  });

  testWidgets('a story\'s card: its country and outlets, its headline, and '
      '"Discuss with AI" by its time; no outlets\' tile, no topics', (
    tester,
  ) async {
    await pumpFeed(tester);
    expect(
      find.text('Czechia · ČT24, Seznam Zprávy and 2 more'),
      findsNWidgets(5),
    );
    expect(find.text('Discuss with AI'), findsNWidgets(5));
    // Not the count of outlets and their marks in the picture's place any
    // more (Roman, 3 Nov: a card like ours).
    expect(find.text('4'), findsNothing);
    expect(find.text('outlets'), findsNothing);
    expect(find.text('SZ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('where the chat is not open, as in tests, a story opens its '
      'page, and back', (tester) async {
    await pumpFeed(tester);
    await tester.tap(find.text('Story 3'));
    await tester.pumpAndSettle();
    expect(find.byType(StoryScreen), findsOneWidget);
    expect(find.text('CZECHIA · STORY'), findsOneWidget);
    expect(find.text('ČT24: headline 0'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(StoryScreen), findsNothing);
    expect(find.text('Story 3'), findsOneWidget);
  });

  testWidgets('the whole world\'s feed has no stories', (tester) async {
    final feed = await pumpFeed(tester);
    await feed.setFeed(FeedWhere.all);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Story '), findsNothing);
    expect(find.text('Decision t1'), findsOneWidget);
  });
}
