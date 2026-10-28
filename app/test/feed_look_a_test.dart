import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// PROTOTYPE (#66): design option A's own behaviour: where its "N new" pill
/// floats, the masthead settling open or folded, a top story's one-sentence
/// summary and the "Read" VoiceOver users hear.

Map<String, dynamic> _article(String id, {int seq = 0}) => {
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
  'imageUrl': null,
  'originalUrl': 'https://www.bundesregierung.de/$id',
  'feedSeq': seq,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    feedDesign.value = FeedDesign.a;
  });
  tearDown(() => feedDesign.value = FeedDesign.now);

  /// A feed of 30 articles and 3 top stories; asking for newer ones finds 3.
  Future<FeedController> pumpFeed(WidgetTester tester) async {
    final items = [for (var i = 30; i >= 1; i--) _article('n$i', seq: i)];
    final tops = [_article('t1'), _article('t2'), _article('t3')];
    final controller = FeedController(
      api: ApiClient(
        baseUrl: 'https://api.test',
        client: MockClient((request) async {
    final menu = fakeMenus(request);
    if (menu != null) return menu;
          final newer = request.url.queryParameters.containsKey('after');
          return http.Response(
            jsonEncode({
              'items': newer
                  ? [for (var i = 33; i > 30; i--) _article('n$i', seq: i)]
                  : items,
              'nextCursor': null,
              'top': newer ? <Object>[] : tops,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      testApp(
        onGenerateRoute: onGenerateRoute,
        home: FeedScreen(
          controller: controller,
          newCheckEvery: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return controller;
  }

  double scrolled(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;

  testWidgets('the "N new" pill floats under the masthead, open or folded', (
    tester,
  ) async {
    final controller = await pumpFeed(tester);
    await controller.checkForNew();
    await tester.pumpAndSettle();
    final pill = find.text('3 new decisions');
    expect(pill, findsOneWidget);

    // Open: below the nameplate and the filters, not over them.
    final filters = tester.getRect(find.text('All countries'));
    expect(tester.getRect(pill).top, greaterThan(filters.bottom));

    // Folded: below the 44-pt bar and its title, not over them.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Outer News'), findsWidgets);
    final barTitle = tester.getRect(find.text('Outer News').last);
    expect(barTitle.bottom, lessThanOrEqualTo(44));
    expect(tester.getRect(pill).top, greaterThan(44));
    // And the space around it lets taps through to the feed.
    expect(
      tester.getRect(pill).top - 44,
      lessThan(30),
      reason: 'the pill stays near the top',
    );
  });

  testWidgets('a scroll that stops halfway settles the masthead', (
    tester,
  ) async {
    await pumpFeed(tester);
    // A short way in: it opens again.
    // A test drag spends its first 20 pt getting past the touch slop.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -40));
    await tester.pumpAndSettle();
    expect(scrolled(tester), 0);

    // Most of the way: it folds.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
    await tester.pumpAndSettle();
    final folded = scrolled(tester);

    expect(folded, greaterThan(80));

    // Past it, the list stays where the reader left it.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
    await tester.pumpAndSettle();
    expect(scrolled(tester), closeTo(folded + 300, 1));
  });

  testWidgets('VoiceOver hears a row once and "Read" once opened', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'feed.readIds': ['n29'],
    });
    final semantics = tester.ensureSemantics();
    await pumpFeed(tester);
    // Every row as the Latest rows were: no summary under the headline.
    final read = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'^Decision n29\. Germany, Federal')),
    );
    expect(read.value, 'Read');
    final unread = tester.getSemantics(
      find.bySemanticsLabel(RegExp(r'^Decision n28\. Germany, Federal')),
    );
    expect(unread.value, isEmpty);
    expect(find.textContaining('Short summary'), findsNothing);
    semantics.dispose();
  });
}
