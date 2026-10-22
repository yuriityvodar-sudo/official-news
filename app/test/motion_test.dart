import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/motion.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:official_news/features/feed/feed_skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

Map<String, dynamic> _article(String id) => {
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
  'topics': <String>[],
  'tags': <String>[],
  'importance': 3,
  'imageUrl': null,
  'originalUrl': 'https://www.bundesregierung.de/$id',
};

/// A fake API whose first page comes when [page] completes; the menus and
/// the new check find nothing.
ApiClient _api(Future<List<Map<String, dynamic>>> page) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    if (!request.url.path.startsWith('/articles')) {
      return http.Response('{"error":"Not found"}', 404);
    }
    final query = request.url.queryParameters;
    final items = query.containsKey('since') || query.containsKey('after')
        ? <Map<String, dynamic>>[]
        : await page;
    return http.Response(
      jsonEncode({'items': items, 'nextCursor': null, 'top': <Object>[]}),
      200,
    );
  }),
);

Future<void> _pumpFeed(
  WidgetTester tester,
  Future<List<Map<String, dynamic>>> page,
) async {
  await tester.pumpWidget(
    testApp(
      onGenerateRoute: onGenerateRoute,
      home: FeedScreen(
        controller: FeedController(api: _api(page)),
        newCheckEvery: const Duration(hours: 1),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// What the app asked the taptic engine to play, by Flutter's names.
List<String> _recordHaptics(WidgetTester tester) {
  final played = <String>[];
  Haptics.enabled = true;
  addTearDown(() => Haptics.enabled = false);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        played.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return played;
}

double _scale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PressScale', () {
    Widget card(VoidCallback onTap, {bool reduced = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: PressScale(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: const SizedBox(width: 200, height: 80),
            ),
          ),
        ),
      ),
    );

    testWidgets('shrinks while held, springs back, and the row gets the tap', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(card(() => taps++));
      expect(_scale(tester), 1);

      final finger = await tester.startGesture(
        tester.getCenter(find.byType(SizedBox)),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(_scale(tester), Motion.pressedScale);

      await finger.up();
      await tester.pumpAndSettle();
      expect(_scale(tester), 1);
      expect(taps, 1);
    });

    testWidgets('a scroll that starts on it lets it go', (tester) async {
      await tester.pumpWidget(card(() {}));
      final finger = await tester.startGesture(
        tester.getCenter(find.byType(SizedBox)),
      );
      await tester.pump(const Duration(milliseconds: 150));
      await finger.moveBy(const Offset(0, 60));
      await tester.pumpAndSettle();
      expect(_scale(tester), 1);
      await finger.up();
    });

    testWidgets('does not move with Reduce Motion on', (tester) async {
      var taps = 0;
      await tester.pumpWidget(card(() => taps++, reduced: true));
      expect(find.byType(AnimatedScale), findsNothing);
      await tester.tap(find.byType(SizedBox));
      expect(taps, 1);
    });
  });

  group('Arrive', () {
    setUp(() => Arrive.enabled = true);
    tearDown(() => Arrive.enabled = false);

    double opacity(WidgetTester tester) =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

    testWidgets('fades in after its delay', (tester) async {
      await tester.pumpWidget(
        const Arrive(
          delay: Duration(milliseconds: 90),
          child: SizedBox(width: 10, height: 10),
        ),
      );
      expect(opacity(tester), 0);
      await tester.pump(const Duration(milliseconds: 90));
      expect(opacity(tester), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('is there at once when not animated', (tester) async {
      await tester.pumpWidget(
        const Arrive(animate: false, child: SizedBox(width: 10, height: 10)),
      );
      expect(opacity(tester), 1);
    });

    testWidgets('the first rows of a feed that has just loaded arrive one '
        'after another', (tester) async {
      await _pumpFeed(
        tester,
        Future.value([for (var i = 0; i < 3; i++) _article('a$i')]),
      );
      final arrivals = tester.widgetList<Arrive>(find.byType(Arrive)).toList();
      expect(arrivals, hasLength(3));
      expect(arrivals.every((a) => a.animate), isTrue);
      expect(arrivals.map((a) => a.delay.inMilliseconds), [0, 45, 90]);
      // VoiceOver hears them while they arrive.
      expect(find.bySemanticsLabel(RegExp('Decision a2')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .every((o) => o.opacity == 1),
        isTrue,
      );

      // Once they have arrived, rows built again (scrolled away and back)
      // come in still (Yurii's review of #142).
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        tester.widgetList<Arrive>(find.byType(Arrive)).every((a) => !a.animate),
        isTrue,
      );
    });
  });

  testWidgets('grey rows stand where the feed will be while it loads', (
    tester,
  ) async {
    final page = Completer<List<Map<String, dynamic>>>();
    await _pumpFeed(tester, page.future);
    expect(find.byType(FeedSkeleton), findsOneWidget);
    expect(find.bySemanticsLabel('Loading the news'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsNothing);

    page.complete([_article('a1')]);
    await tester.pump();
    await tester.pump();
    expect(find.byType(FeedSkeleton), findsNothing);
    expect(find.text('Decision a1'), findsOneWidget);
  });

  testWidgets(
    'taps back once when a card is opened, and once as the pull will refresh',
    (tester) async {
      final played = _recordHaptics(tester);
      await _pumpFeed(tester, Future.value([_article('a1')]));

      await tester.tap(find.text('Decision a1'));
      expect(played, ['HapticFeedbackType.lightImpact']);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      played.clear();
      final finger = await tester.startGesture(
        tester.getCenter(find.text('Decision a1')),
      );
      for (var i = 0; i < 8; i++) {
        await finger.moveBy(const Offset(0, 30));
        await tester.pump();
      }
      // Once, as the pull passes the point where letting go refreshes: the
      // refresh control's own, not a second one of ours.
      expect(played, ['HapticFeedbackType.mediumImpact']);
      await finger.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('plays nothing where haptics are off (Android, tests)', (
    tester,
  ) async {
    final played = _recordHaptics(tester);
    Haptics.enabled = false;
    Haptics.light();
    Haptics.selection();
    expect(played, isEmpty);
  });

  group('fadeInPicture', () {
    const picture = SizedBox(width: 10, height: 10);

    testWidgets('fades in a picture that has to load', (tester) async {
      await tester.pumpWidget(
        Builder(
          builder: (context) => fadeInPicture(context, picture, null, false),
        ),
      );
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
    });

    testWidgets('shows one already in memory at once', (tester) async {
      await tester.pumpWidget(
        Builder(builder: (context) => fadeInPicture(context, picture, 0, true)),
      );
      expect(find.byType(AnimatedOpacity), findsNothing);
    });
  });
}
