import 'package:flutter/cupertino.dart';
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
import 'package:official_news/features/feed/tick_capsule.dart';
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

/// The world's ticks in For you's Top stories block (#230 step 4; Roman's
/// variant 1 of `handoff/tick-strip.html`, 3 Nov): two, one and two of them
/// open the groups before the decisions, a light capsule each, and a tap
/// opens the AI chat about one.
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

  /// For you in Czechia: three top decisions, five stories and five ticks;
  /// the whole world's feed has none of them, as the server sends them.
  Future<FeedController> pumpFeed(WidgetTester tester, {int ticks = 5}) async {
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

  testWidgets('two, one and two ticks open the groups before the decisions, '
      'the stories after them', (tester) async {
    final feed = await pumpFeed(tester);
    expect(feed.ticks, hasLength(5));
    final order = [
      'Tick 0',
      'Tick 1',
      'Story 0',
      'Story 1',
      'Decision t1',
      'Tick 2',
      'Story 2',
      'Story 3',
      'Decision t2',
      'Tick 3',
      'Tick 4',
      'Story 4',
      'Decision t3',
    ];
    final ys = [for (final t in order) top(tester, t)];
    expect(ys, [...ys]..sort(), reason: 'in that order, top to bottom');
    expect(find.byType(TickCapsule), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tick: its headline and the AI\'s mark, nothing else: no '
      'time, no outlets, no caption', (tester) async {
    await pumpFeed(tester, ticks: 1);
    final capsule = find.byType(TickCapsule);
    final texts = tester.widgetList<Text>(
      find.descendant(of: capsule, matching: find.byType(Text)),
    );
    expect([for (final t in texts) t.data], ['Tick 0']);
    expect(
      find.descendant(
        of: capsule,
        matching: find.byIcon(CupertinoIcons.sparkles),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(capsule).height, TickCapsule.height);
    expect(
      tester.getSemantics(capsule),
      matchesSemantics(
        label: 'Tick 0. Discuss with AI',
        isButton: true,
        hasTapAction: true,
      ),
    );
  });

  testWidgets('where the chat is not open yet, a tick opens the page of its '
      'outlets\' headlines', (tester) async {
    ChatScreen.debugAvailable = false;
    await pumpFeed(tester, ticks: 1);
    await tester.tap(find.byType(TickCapsule));
    await tester.pumpAndSettle();
    expect(find.byType(StoryScreen), findsOneWidget);
    expect(find.text('ABC News: headline 0'), findsOneWidget);
    expect(find.text('BBC World: headline 1'), findsOneWidget);
  });

  testWidgets('the whole world\'s feed has no ticks', (tester) async {
    final feed = await pumpFeed(tester);
    await feed.setFeed(FeedWhere.all);
    await tester.pump();
    await tester.pump();
    expect(find.byType(TickCapsule), findsNothing);
    expect(find.text('Decision t1'), findsOneWidget);
  });
}
