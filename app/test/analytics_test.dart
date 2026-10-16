import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/features/detail/detail_screen.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

Map<String, dynamic> _article(
  String id, {
  List<String> topics = const ['economy'],
}) => {
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
  'shortSummary': null,
  'summary': 'Summary $id',
  'decisionType': 'cabinet-decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'de',
  'topics': topics,
  'tags': <String>[],
  'importance': 3,
  'imageUrl': null,
  'originalUrl': 'https://www.bundesregierung.de/$id',
};

ApiClient _api() => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient(
    (request) async => http.Response(
      jsonEncode({
        'items': [_article('a1'), _article('a2', topics: const [])],
        'nextCursor': null,
        'top': [_article('t1')],
      }),
      200,
    ),
  ),
);

void main() {
  late List<(String, Map<String, Object>)> events;
  late Map<String, String> userProperties;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    events = [];
    userProperties = {};
    analytics = Analytics(
      (name, parameters) async => events.add((name, parameters)),
      (name, value) async => userProperties[name] = value,
    );
  });
  tearDown(() => analytics = Analytics());

  Future<void> pumpFeed(WidgetTester tester, {bool screens = true}) async {
    await tester.pumpWidget(
      testApp(
        onGenerateRoute: onGenerateRoute,
        navigatorObservers: [if (screens) ScreenViews()],
        home: FeedScreen(
          controller: FeedController(api: _api()),
          newCheckEvery: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('off by default: no sender, nothing sent', (tester) async {
    analytics = Analytics();
    expect(analytics.on, isFalse);
    await analytics.screen('feed');
    expect(events, isEmpty);
  });

  testWidgets('a sender that fails never breaks the app', (tester) async {
    analytics = Analytics((_, _) async => throw StateError('offline'));
    await analytics.screen('feed');
  });

  testWidgets(
    'sends the feed screen, an opened article with its section and place, and the article screen',
    (tester) async {
      await pumpFeed(tester);
      expect(events.first.$1, 'screen_view');
      expect(events.first.$2, {'screen_name': 'feed', 'screen_class': 'feed'});

      await tester.tap(find.text('Decision a2'));
      await tester.pumpAndSettle();
      final opened = events.firstWhere((e) => e.$1 == 'open_article').$2;
      expect(opened, {
        'article_id': 'a2',
        'country': 'DE',
        'source_id': 'de-gov',
        'decision_type': 'cabinet-decision',
        'topic': 'none',
        'feed_language': 'en',
        'section': 'latest',
        'position': 1,
      });
      expect(events.last.$1, 'screen_view');
      expect(events.last.$2, {
        'screen_name': 'article',
        'screen_class': 'article',
      });

      // Back to the feed counts as the feed shown again.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(events.last.$2['screen_name'], 'feed');

      await tester.tap(find.text('Decision t1'));
      await tester.pumpAndSettle();
      final top = events.lastWhere((e) => e.$1 == 'open_article').$2;
      expect(
        (top['section'], top['position'], top['topic']),
        ('top', 0, 'economy'),
      );
    },
  );

  testWidgets('sends the chosen language with the one before', (tester) async {
    await pumpFeed(tester, screens: false);
    // The language is chosen in Settings (#64).
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Українська'));
    await tester.pumpAndSettle();
    expect(events.where((e) => e.$1 == 'select_language').single.$2, {
      'language': 'uk',
      'previous_language': 'en',
    });
    expect(userProperties, {'feed_language': 'uk'});
  });

  test(
    'on a first launch, feed_language is the phone language the feed uses',
    () async {
      // Nothing saved: the app follows the phone (#52), and the property with it.
      final feed = FeedController(
        api: _api(),
        phoneLanguages: () => const [Locale('uk', 'UA')],
      );
      await feed.open();
      await useAnalytics(
        Analytics(null, (name, value) async => userProperties[name] = value),
        language: feed.languageChanges,
      );
      expect(userProperties, {'build': 'dev', 'feed_language': 'uk'});
    },
  );

  testWidgets('sends an opened official link and a share, with the article', (
    tester,
  ) async {
    final article = Article.fromJson(_article('a1'));
    await tester.pumpWidget(
      testApp(
        home: DetailScreen(
          article: article,
          openLink: (_) async {},
          share: (_, _, _) async {},
        ),
      ),
    );
    await tester.tap(find.text('Read the official decision'));
    await tester.tap(find.byIcon(CupertinoIcons.share));
    expect(events.map((e) => e.$1), ['open_official_link', 'share']);
    expect(events.last.$2, containsPair('item_id', 'a1'));
    expect(events.last.$2, containsPair('content_type', 'article'));
  });

  testWidgets(
    'counts an article read after 15 seconds open, not while the app is away',
    (tester) async {
      final article = Article.fromJson(_article('a1'));
      await tester.pumpWidget(testApp(home: DetailScreen(article: article)));
      await tester.pump(const Duration(seconds: 10));
      // Away for a while: the wait starts again when the app is back.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(minutes: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 10));
      expect(events.where((e) => e.$1 == 'article_read'), isEmpty);
      await tester.pump(const Duration(seconds: 6));
      expect(
        events.where((e) => e.$1 == 'article_read').single.$2['article_id'],
        'a1',
      );
      await tester.pump(const Duration(minutes: 1));
      expect(events.where((e) => e.$1 == 'article_read'), hasLength(1));
    },
  );

  testWidgets('no read when the article closes before 15 seconds', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(home: DetailScreen(article: Article.fromJson(_article('a1')))),
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    expect(events.where((e) => e.$1 == 'article_read'), isEmpty);
  });

  testWidgets('sends each feed depth once, as the reader scrolls down', (
    tester,
  ) async {
    final items = [for (var i = 1; i <= 30; i++) _article('n$i')];
    final api = ApiClient(
      baseUrl: 'https://api.test',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'items': items, 'nextCursor': null, 'top': []}),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      testApp(
        onGenerateRoute: onGenerateRoute,
        home: FeedScreen(
          controller: FeedController(api: api),
          newCheckEvery: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    Iterable<String> depths() =>
        events.map((e) => e.$1).where((n) => n.startsWith('feed_scroll_'));
    expect(depths(), isEmpty);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 6000));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(depths(), ['feed_scroll_10', 'feed_scroll_25']);
  });

  testWidgets('sends a failed first page once, not on every redraw', (
    tester,
  ) async {
    final api = ApiClient(
      baseUrl: 'https://api.test',
      client: MockClient((_) async => http.Response('{"error":"down"}', 500)),
    );
    final feed = FeedController(api: api);
    await tester.pumpWidget(
      testApp(
        home: FeedScreen(
          controller: feed,
          newCheckEvery: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(events.where((e) => e.$1 == 'feed_load_failed'), hasLength(1));
  });
}
