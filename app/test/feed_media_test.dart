import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/core/home_country.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/chat/chat_screen.dart';
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

/// The media's news in For you's Top stories block (#230; Roman, 3 Nov:
/// «пусть будет просто в ленте как часть ленты», then pick 1 of
/// `handoff/ask-ai-button.html`): the world's ticks and the country's stories
/// in turn, two before each decision and the rest after the last, each a card
/// like a decision's with "Discuss with AI" beside its time; the card and
/// the button open the AI chat about it.
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
    ChatScreen.debugAvailable = null;
  });

  /// For you in Czechia: three top decisions, [stories] stories and [ticks]
  /// ticks; the whole world's feed has none of them, as the server sends
  /// them.
  Future<FeedController> pumpFeed(
    WidgetTester tester, {
    int ticks = 5,
    int stories = 5,
    bool aiTitles = true,
  }) async {
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
                  for (var i = 0; i < stories; i++)
                    fakeStory(
                      id: 's$i',
                      title: 'Story $i',
                      aiTitle: aiTitles,
                    ),
                ],
                'ticks': [
                  for (var i = 0; i < ticks; i++)
                    fakeTick(id: 'w$i', title: 'Tick $i'),
                ],
              })
            : fakeJson(page);
      }),
    );
    // Tall enough for the whole block.
    tester.view.physicalSize = const Size(393, 3200) * 3;
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
      tester.getTopLeft(find.textContaining(text).first).dy;

  testWidgets('a tick and a story in turn, two before each decision, the '
      'rest after the last', (tester) async {
    final feed = await pumpFeed(tester);
    expect(feed.ticks, hasLength(5));
    final order = [
      'Tick 0',
      'Story 0',
      'Decision t1',
      'Tick 1',
      'Story 1',
      'Decision t2',
      'Tick 2',
      'Story 2',
      'Decision t3',
      'Tick 3',
      'Story 3',
      'Tick 4',
      'Story 4',
    ];
    final ys = [for (final t in order) top(tester, t)];
    expect(ys, [...ys]..sort(), reason: 'in that order, top to bottom');
    expect(find.text('Discuss with AI'), findsNWidgets(10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a card: where it comes from, its headline, and "Discuss with '
      'AI" on its time\'s line at the right, read as one', (tester) async {
    await pumpFeed(tester, ticks: 1, stories: 1);
    expect(find.text('World · 2 countries'), findsOneWidget);
    expect(
      find.text('Czechia · ČT24, Seznam Zprávy and 2 more'),
      findsOneWidget,
    );
    for (final (headline, button) in [
      ('Tick 0', find.text('Discuss with AI').first),
      ('Story 0', find.text('Discuss with AI').last),
    ]) {
      final title = find.text(headline);
      expect(
        tester.getTopLeft(button).dy,
        greaterThan(tester.getBottomLeft(title).dy),
      );
      expect(tester.getTopRight(button).dx, greaterThan(393 / 2));
      // The card's last row: nothing under it but the card's edge.
      expect(
        tester.getBottomLeft(button).dy - tester.getBottomLeft(title).dy,
        lessThan(48),
      );
    }
    final label = tester.getSemantics(find.text('Tick 0')).label;
    expect(label, startsWith('Tick 0. World, 2 countries.'));
    expect(label, endsWith('Discuss with AI.'));
    expect(
      tester.getSemantics(find.text('Story 0')).label,
      endsWith('Discuss with AI.'),
    );
    // No outlets' tile: a card like a decision's.
    expect(find.text('4'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the AI\'s headlines carry ✦ by the time and VoiceOver says '
      'so; a story with its outlets\' own headline has none (AI Act, art. 50: '
      'L2 of the release audit, 4 Nov)', (tester) async {
    await pumpFeed(tester, ticks: 1, stories: 1);
    final marks = find.byKey(const ValueKey('by-ai'));
    Finder card(String headline) => find
        .ancestor(of: find.text(headline), matching: find.byType(Semantics))
        .first;
    for (final headline in ['Tick 0', 'Story 0']) {
      expect(find.descendant(of: card(headline), matching: marks), findsOne);
      expect(
        tester.getSemantics(find.text(headline)).label,
        endsWith('Headline by AI. Discuss with AI.'),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a story with its outlets\' own headline, the model\'s not yet '
      'written, has no ✦', (tester) async {
    await pumpFeed(tester, ticks: 0, stories: 1, aiTitles: false);
    final card = find
        .ancestor(of: find.text('Story 0'), matching: find.byType(Semantics))
        .first;
    expect(
      find.descendant(of: card, matching: find.byKey(const ValueKey('by-ai'))),
      findsNothing,
    );
    expect(
      tester.getSemantics(find.text('Story 0')).label,
      isNot(contains('Headline by AI')),
    );
  });

  testWidgets('where the chat is not open yet, the card or its button opens '
      'the page of its outlets\' headlines', (tester) async {
    ChatScreen.debugAvailable = false;
    await pumpFeed(tester, ticks: 1, stories: 1);
    await tester.tap(find.text('Tick 0'));
    await tester.pumpAndSettle();
    expect(find.byType(StoryScreen), findsOneWidget);
    expect(find.text('ABC News: headline 0'), findsOneWidget);
    expect(find.text('BBC World: headline 1'), findsOneWidget);
    Navigator.of(tester.element(find.byType(StoryScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discuss with AI').last);
    await tester.pumpAndSettle();
    expect(find.byType(StoryScreen), findsOneWidget);
    expect(find.text('ČT24: headline 0'), findsOneWidget);
  });

  testWidgets('the whole world\'s feed has none of them', (tester) async {
    final feed = await pumpFeed(tester);
    await feed.setFeed(FeedWhere.all);
    await tester.pump();
    await tester.pump();
    expect(find.text('Discuss with AI'), findsNothing);
    expect(find.text('Tick 0'), findsNothing);
    expect(find.text('Decision t1'), findsOneWidget);
  });
}
