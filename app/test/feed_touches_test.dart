import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/motion.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:official_news/features/feed/feed_touches.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

Map<String, dynamic> _article(String id, {DateTime? at}) => {
  'id': id,
  'country': 'DE',
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': (at ?? DateTime.now()).toUtc().toIso8601String(),
  'dateOnly': false,
  'headline': 'Decision $id',
  'shortSummary': 'What $id changes.',
  'summary': 'Summary $id',
  'decisionType': 'cabinet-decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'de',
  'topics': <String>[],
  'tags': <String>[],
  'importance': 3,
  'imageUrl': null,
  'originalUrl': 'https://www.bundesregierung.de/$id#stage-2',
};

/// A fake API: the first page is [items], or fails while [fail] says so.
ApiClient _api(List<Map<String, dynamic>> items, {bool Function()? fail}) =>
    ApiClient(
      baseUrl: 'https://api.test',
      client: MockClient((request) async {
        if (!request.url.path.startsWith('/articles')) {
          return http.Response('{"error":"Not found"}', 404);
        }
        if (fail?.call() ?? false) {
          return http.Response('{"error":"Internal error"}', 500);
        }
        final query = request.url.queryParameters;
        final newer = query.containsKey('since') || query.containsKey('after');
        return http.Response(
          jsonEncode({
            'items': newer ? <Object>[] : items,
            'nextCursor': null,
            'top': <Object>[],
          }),
          200,
        );
      }),
    );

Future<void> _pumpFeed(WidgetTester tester, ApiClient api) async {
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
}

/// What the app asked the platform for: haptics and the clipboard.
List<MethodCall> _recordPlatform(WidgetTester tester) {
  final calls = <MethodCall>[];
  Haptics.enabled = true;
  addTearDown(() => Haptics.enabled = false);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a long press on a card offers share, the official page and '
      'its link, without opening it', (tester) async {
    final calls = _recordPlatform(tester);
    await _pumpFeed(tester, _api([_article('a1')]));

    await tester.longPress(find.text('Decision a1'));
    await tester.pumpAndSettle();
    expect(
      calls.map((c) => c.arguments),
      contains('HapticFeedbackType.mediumImpact'),
    );
    expect(find.byType(CupertinoActionSheet), findsOneWidget);
    expect(find.text('What a1 changes.'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Read the official decision'), findsOneWidget);
    // Still the feed: the long press did not open the article.
    expect(find.text('Summary a1'), findsNothing);

    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    final copied = calls.firstWhere((c) => c.method == 'Clipboard.setData');
    // The official page, without the fetcher's #fragment.
    expect(
      (copied.arguments as Map)['text'],
      'https://www.bundesregierung.de/a1',
    );
    expect(find.byType(CupertinoActionSheet), findsNothing);
  });

  testWidgets('Cancel closes the menu', (tester) async {
    await _pumpFeed(tester, _api([_article('a1')]));
    await tester.longPress(find.text('Decision a1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActionSheet), findsNothing);
  });

  test('a decision is fresh for an hour after it came into the feed', () {
    final now = DateTime.utc(2026, 10, 22, 12);
    Article at(Duration ago) =>
        Article.fromJson(_article('x', at: now.subtract(ago)));
    expect(isFresh(at(const Duration(minutes: 5)), now: now), isTrue);
    expect(isFresh(at(const Duration(minutes: 59)), now: now), isTrue);
    expect(isFresh(at(const Duration(hours: 1)), now: now), isFalse);
    expect(isFresh(at(const Duration(minutes: -5)), now: now), isFalse);
  });

  testWidgets('the time of a fresh decision is red and pulses three times, '
      'then stays', (tester) async {
    await _pumpFeed(tester, _api([_article('a1')]));
    final time = find.byType(FreshTime);
    expect(time, findsOneWidget);
    expect(
      tester
          .widget<Text>(find.descendant(of: time, matching: find.byType(Text)))
          .style
          ?.color,
      AppColors.accent,
    );
    // Settles: the pulse is not endless.
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FadeTransition>(
            find.descendant(of: time, matching: find.byType(FadeTransition)),
          )
          .opacity
          .value,
      1,
    );
  });

  testWidgets('an older decision keeps the plain time', (tester) async {
    await _pumpFeed(
      tester,
      _api([
        _article('a1', at: DateTime.now().subtract(const Duration(hours: 3))),
      ]),
    );
    expect(find.byType(FreshTime), findsNothing);
  });

  testWidgets('when the news cannot load, "Try again" loads it again', (
    tester,
  ) async {
    var down = true;
    await _pumpFeed(tester, _api([_article('a1')], fail: () => down));
    expect(find.byIcon(CupertinoIcons.wifi_slash), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    down = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Decision a1'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });
}
