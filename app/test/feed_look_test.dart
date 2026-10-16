import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:official_news/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// PROTOTYPE (#66): every look keeps what the feed does. Whatever a design
/// option draws, opening an article and scrolling must still reach analytics
/// with the same section, position and depth as today's feed.

Map<String, dynamic> _article(String id, {String? imageUrl}) => {
  'id': id,
  'country': 'DE',
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
) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient(
    (request) async => http.Response(
      jsonEncode({'items': items, 'nextCursor': null, 'top': top}),
      200,
    ),
  ),
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

  Future<void> pumpFeed(
    WidgetTester tester,
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> top,
  ) async {
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        onGenerateRoute: onGenerateRoute,
        home: FeedScreen(
          controller: FeedController(api: _api(items, top)),
          newCheckEvery: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
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

      testWidgets(
        'opens top stories and latest articles with their section and place',
        (tester) async {
          final top = [
            _article('t1', imageUrl: 'https://example.test/t1.jpg'),
            _article('t2'),
          ];
          await pumpFeed(tester, [...top, _article('a1'), _article('a2')], top);
          expect(find.text('Official News'), findsOneWidget);

          await tester.tap(find.text('Decision t2'));
          await tester.pumpAndSettle();
          expect(
            (lastOpened()['section'], lastOpened()['position']),
            ('top', 1),
          );
          await tester.pageBack();
          await tester.pumpAndSettle();

          await tester.scrollUntilVisible(
            find.text('Decision a2'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Decision a2'));
          await tester.pumpAndSettle();
          expect(
            (lastOpened()['section'], lastOpened()['position']),
            ('latest', 1),
          );
        },
      );

      testWidgets('sends each feed depth once, as the reader scrolls down', (
        tester,
      ) async {
        await pumpFeed(tester, [
          for (var i = 1; i <= 30; i++) _article('n$i'),
        ], []);
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
    await tester.pumpWidget(
      testApp(
        home: SettingsScreen(
          language: ValueNotifier(FeedLanguage.en),
          onLanguage: (_) {},
        ),
      ),
    );
    expect(find.text('Design'), findsOneWidget);
    await tester.tap(find.text('B'));
    await tester.pumpAndSettle();
    expect(feedDesign.value, FeedDesign.b);
    await tester.tap(find.text('Now'));
    await tester.pumpAndSettle();
    expect(feedDesign.value, FeedDesign.now);
  });
}
