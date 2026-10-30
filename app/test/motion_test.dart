import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
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

/// A fake API whose first page is what [items] gives at each request, and
/// whose new check finds what [newer] gives.
ApiClient _liveApi(
  List<Map<String, dynamic>> Function() items, {
  List<Map<String, dynamic>> Function()? newer,
}) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    if (!request.url.path.startsWith('/articles')) {
      return http.Response('{"error":"Not found"}', 404);
    }
    final query = request.url.queryParameters;
    final list = query.containsKey('since') || query.containsKey('after')
        ? newer?.call() ?? <Map<String, dynamic>>[]
        : items();
    return http.Response(
      jsonEncode({'items': list, 'nextCursor': null, 'top': <Object>[]}),
      200,
    );
  }),
);

/// The feed screen over [controller].
Future<void> _pumpScreen(WidgetTester tester, FeedController controller) async {
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
  // The first rows have arrived (#141).
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// The app's name as the folded title shows it, small.
final _smallTitle = find.byWidgetPredicate(
  (w) => w is Text && w.data == 'Outer News' && w.style?.fontSize == 17,
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

  group('decisions that have just come in', () {
    setUp(() => Arrive.enabled = true);
    tearDown(() => Arrive.enabled = false);

    double top(WidgetTester tester, String id) =>
        tester.getTopLeft(find.text('Decision $id')).dy;

    testWidgets('spring in at the top and push the others down', (
      tester,
    ) async {
      var items = [_article('a1'), _article('a2')];
      final controller = FeedController(api: _liveApi(() => items));
      await _pumpScreen(tester, controller);
      final before = top(tester, 'a1');

      items = [_article('n1'), _article('n2'), ...items];
      await controller.refresh();
      await tester.pump();
      // The new ones start with no height: the others have not moved yet.
      expect(top(tester, 'a1'), moreOrLessEquals(before, epsilon: 0.5));
      // Two rows and the lines under them; with no height, not on screen.
      expect(
        tester
            .widgetList<GrowIn>(find.byType(GrowIn, skipOffstage: false))
            .where((g) => g.animate)
            .length,
        4,
      );

      // The first one starts at the next frames, and is on its way.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 100));
      final early = top(tester, 'a1');
      expect(early, greaterThan(before + 1));
      await tester.pumpAndSettle();
      expect(top(tester, 'a1'), greaterThan(early));
      expect(top(tester, 'n1'), lessThan(top(tester, 'n2')));
    });

    testWidgets('are cut to their height only while they grow, so a card '
        'keeps its whole shadow', (tester) async {
      var items = [_article('a1')];
      final controller = FeedController(api: _liveApi(() => items));
      await _pumpScreen(tester, controller);
      // How each row's growing box clips: a clip left on cut the card's
      // shadow to the card's box (Roman, build 54, 30 Oct).
      List<Clip> clips() => [
        for (final grow in find.byType(GrowIn, skipOffstage: false).evaluate())
          (grow.renderObject! as RenderClipRect).clipBehavior,
      ];
      expect(clips(), everyElement(Clip.none));

      items = [_article('n1'), ...items];
      await controller.refresh();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(clips(), contains(Clip.hardEdge));
      await tester.pumpAndSettle();
      expect(clips(), everyElement(Clip.none));
    });

    testWidgets('with Reduce Motion on, are there at once, fading in', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      var items = [_article('a1')];
      final controller = FeedController(api: _liveApi(() => items));
      await _pumpScreen(tester, controller);

      items = [_article('n1'), ...items];
      await controller.refresh();
      await tester.pump();
      final now = top(tester, 'a1');
      await tester.pumpAndSettle();
      expect(top(tester, 'a1'), now);
    });
  });

  group('the folded title', () {
    testWidgets('the name folds into a small title as the masthead scrolls '
        'away; a tap on it goes back to the top', (tester) async {
      final controller = FeedController(
        api: _liveApi(() => [for (var i = 0; i < 20; i++) _article('a$i')]),
      );
      await _pumpScreen(tester, controller);
      expect(_smallTitle, findsNothing);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(_smallTitle, findsOneWidget);

      await tester.tap(_smallTitle);
      await tester.pumpAndSettle();
      final list = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(list.position.pixels, 0);
      expect(_smallTitle, findsNothing);
    });

    testWidgets('the "N new" pill floats under it', (tester) async {
      final controller = FeedController(
        api: _liveApi(
          () => [for (var i = 0; i < 20; i++) _article('a$i')],
          newer: () => [_article('n1')],
        ),
      );
      await _pumpScreen(tester, controller);
      await controller.checkForNew();
      await tester.pump();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();

      final pill = find.text('1 new decision');
      expect(pill, findsOneWidget);
      expect(
        tester.getTopLeft(pill).dy,
        greaterThan(tester.getBottomLeft(_smallTitle).dy),
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
