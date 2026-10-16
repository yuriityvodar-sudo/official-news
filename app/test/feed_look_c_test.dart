import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// PROTOTYPE (#66): design option C, "Briefing". What it shows for each
/// decision, and where the "N new" pill goes.

Map<String, dynamic> _article(
  String id, {
  int importance = 3,
  String decisionType = 'proposal',
  int? feedSeq,
  DateTime? addedAt,
}) => {
  'id': id,
  'feedSeq': feedSeq,
  'country': 'DE',
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government (Bundesregierung)',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': DateTime.now().toUtc().toIso8601String(),
  'addedAt': (addedAt ?? DateTime.now()).toUtc().toIso8601String(),
  'dateOnly': false,
  'headline': 'Decision $id',
  'shortSummary': 'Short summary $id.',
  'summary': 'Summary $id',
  'decisionType': decisionType,
  'originalTitle': 'Original $id',
  'originalLanguage': 'de',
  'topics': ['economy'],
  'tags': <String>[],
  'importance': importance,
  'imageUrl': null,
  'originalUrl': 'https://www.bundesregierung.de/$id',
};

/// The feed, and on the new check the [newer] articles.
ApiClient _api(
  List<Map<String, dynamic>> items,
  List<Map<String, dynamic>> top, {
  List<Map<String, dynamic>> newer = const [],
}) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    final query = request.url.queryParameters;
    final isCheck = query.containsKey('after') || query.containsKey('since');
    return http.Response(
      jsonEncode({
        'items': isCheck ? newer : items,
        'nextCursor': null,
        'top': isCheck ? <Object>[] : top,
      }),
      200,
    );
  }),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    feedDesign.value = FeedDesign.c;
  });
  tearDown(() => feedDesign.value = FeedDesign.now);

  Future<FeedController> pumpFeed(
    WidgetTester tester,
    List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> top, {
    List<Map<String, dynamic>> newer = const [],
  }) async {
    tester.view.physicalSize = const Size(420, 912) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final feed = FeedController(api: _api(items, top, newer: newer));
    await tester.pumpWidget(
      testApp(
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

  testWidgets('VoiceOver hears the kind of act, importance and opened rows', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpFeed(tester, [
      _article('a1', importance: 5, decisionType: 'bill'),
      _article('a2'),
    ], []);

    final important = find.bySemanticsLabel(
      RegExp(r'^Important\. Decision a1\. Bill\. Germany, Federal Government'),
    );
    expect(important, findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Decision a2\. Proposal\. Germany')),
      findsOneWidget,
    );
    // The kind is on screen too, at the start of the summary.
    expect(
      find.textContaining('Proposal\u00A0· Short summary a2.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Decision a2'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp(r'^Decision a2\. .* Opened\.$')),
      findsOneWidget,
    );
    handle.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('an important row has a red rule beside its headline, on '
        'screen (text size x$scale)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpFeed(tester, [
        _article('i1', importance: 4),
        _article('i2', importance: 3),
      ], []);
      // Red boxes 3 pt wide (the feed's end mark is red too, and square).
      final rules = tester
          .widgetList(
            find.byWidgetPredicate(
              (w) => w is ColoredBox && w.color == AppColors.accent,
            ),
          )
          .map((w) => tester.getRect(find.byWidget(w)))
          .where((r) => r.width == 3)
          .toList();
      expect(rules, hasLength(1));
      final rule = rules.single;
      final headline = tester.getRect(find.text('Decision i1'));
      expect(rule.left, greaterThanOrEqualTo(4));
      expect(rule.right, lessThan(headline.left));
      expect(rule.top, greaterThanOrEqualTo(headline.top));
      expect(rule.bottom, lessThanOrEqualTo(headline.bottom));
    });
  }

  testWidgets('the left column logs when each decision appeared', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 0, 5);
    final earlier = today.subtract(const Duration(days: 2));
    final older = today.subtract(const Duration(days: 9));
    await pumpFeed(tester, [
      _article('d0', addedAt: today),
      _article('d2', addedAt: earlier),
      _article('d9', addedAt: older),
    ], []);
    String clock(DateTime d) => DateFormat.Hm('en_GB').format(d);
    expect(find.text(clock(today)), findsOneWidget);
    expect(
      find.text('${DateFormat.E('en_GB').format(earlier)}\n${clock(earlier)}'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Decision d9'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('${DateFormat.MMMd('en_GB').format(older)}\n${clock(older)}'),
      findsOneWidget,
    );
  });

  testWidgets('a row shades while it is pressed, and clears after the tap', (
    tester,
  ) async {
    await pumpFeed(tester, [_article('p1')], []);
    Iterable<Color> shades() => tester
        .widgetList<ColoredBox>(
          find.ancestor(
            of: find.text('Decision p1'),
            matching: find.byType(ColoredBox),
          ),
        )
        .map((box) => box.color)
        .where((c) => c.a > 0 && c.a < 0.5);

    expect(shades(), isEmpty);
    final press = await tester.startGesture(
      tester.getCenter(find.text('Decision p1')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(shades(), isNotEmpty);
    await press.cancel();
    await tester.pumpAndSettle();
    expect(shades(), isEmpty);
  });

  testWidgets(
    'the "N new" pill sits under the masthead, never on the filters',
    (tester) async {
      final feed = await pumpFeed(
        tester,
        [for (var i = 1; i <= 20; i++) _article('n$i', feedSeq: 100 - i)],
        [],
        newer: [_article('new1', feedSeq: 200)],
      );
      await feed.checkForNew();
      await tester.pump();
      await tester.pump();
      final pill = find.text('1 new decision');
      expect(pill, findsOneWidget);

      // At the top, with the whole masthead open.
      final chips = find.text('All topics').hitTestable();
      expect(
        tester.getTopLeft(pill).dy,
        greaterThan(tester.getBottomLeft(chips).dy + 8),
      );

      // Scrolled: the date and the name have gone, the bar is pinned, and the
      // pill has moved up with it, still under the filters.
      final atTop = tester.getTopLeft(pill).dy;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Official News').hitTestable(), findsNothing);
      expect(tester.getTopLeft(pill).dy, lessThan(atTop));
      expect(
        tester.getTopLeft(pill).dy,
        greaterThan(tester.getBottomLeft(chips).dy + 8),
      );
    },
  );
}
