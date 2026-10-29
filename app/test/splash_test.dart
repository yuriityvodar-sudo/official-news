import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/splash/splash.dart';
import 'package:official_news/l10n/app_localizations.dart';
import 'package:official_news/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'test_app.dart';

/// PROTOTYPE (Yurii, 16 Oct): the splash at start, its three styles and
/// Settings → Play.

/// [app] under a [SplashHost], as `MaterialApp.builder` puts it.
Widget _host({
  Widget app = const Text('the app'),
  bool onStart = true,
  String locale = 'en',
  Listenable? endOn,
}) => MaterialApp(
  theme: buildTheme(Brightness.light),
  darkTheme: buildTheme(Brightness.dark),
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) =>
      SplashHost(onStart: onStart, endOn: endOn, child: child!),
  home: app,
);

/// Frame by frame, as a phone draws: the splash's clock moves on by at most
/// 50 ms a frame, so one long pump would not play it through.
Future<void> _play(WidgetTester tester, Duration time) async {
  const frame = Duration(milliseconds: 16);
  for (var t = Duration.zero; t < time; t += frame) {
    await tester.pump(frame);
  }
}

/// The time a splash shows, fade included.
Duration _total(SplashStyle style) => splashLength(style) + splashFade;

/// The opacities the splash's words are drawn with (its own fades left out).
List<double> _wordOpacities(WidgetTester tester) => tester
    .widgetList<Opacity>(
      find.descendant(of: find.byType(Splash), matching: find.byType(Opacity)),
    )
    .map((o) => o.opacity)
    .toList();

Map<String, dynamic> _article(String id, String headline) => {
  'feedSeq': 1,
  'addedAt': DateTime.now().toUtc().toIso8601String(),
  'id': id,
  'country': 'DE',
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': DateTime.now().toUtc().toIso8601String(),
  'dateOnly': false,
  'headline': headline,
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => splashStyle.value = SplashStyle.riseUp);

  test('a build picks the style by name or number; riseUp otherwise', () {
    expect(splashNamed('sweep'), SplashStyle.sweep);
    expect(splashNamed(' FILL '), SplashStyle.fill);
    expect(splashNamed('1'), SplashStyle.rise);
    expect(splashNamed('1b'), SplashStyle.riseUp);
    expect(splashNamed('riseup'), SplashStyle.riseUp);
    expect(splashNamed('RiseUp'), SplashStyle.riseUp);
    expect(splashNamed('2'), SplashStyle.sweep);
    expect(splashNamed('3'), SplashStyle.fill);
    expect(splashNamed(''), SplashStyle.riseUp);
    expect(splashNamed('wave'), SplashStyle.riseUp);
  });

  test('the two words, in one place, as written', () {
    expect(splashLines, ['Outer', 'News']);
  });

  testWidgets(
    'the app starts with the splash over a feed that is already loading, '
    'then shows the feed',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final asked = <Uri>[];
      final top = _article('t1', 'Cabinet approves budget');
      final feed = FeedController(
        api: ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient((request) async {
            final menu = fakeMenus(request);
            if (menu != null) return menu;
            asked.add(request.url);
            final q = request.url.queryParameters;
            final body = q.containsKey('after') || q.containsKey('since')
                ? {'items': [], 'nextCursor': null, 'top': []}
                : {
                    'items': [top],
                    'nextCursor': null,
                    'top': [top],
                  };
            return http.Response.bytes(
              utf8.encode(jsonEncode(body)),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
        phoneLanguages: () => const [Locale('en', 'US')],
      );
      await feed.open();
      await tester.pumpWidget(OfficialNewsApp(feed: feed));
      await tester.pump();

      expect(find.byType(Splash), findsOneWidget);
      for (final word in splashLines) {
        expect(find.text(word), findsOneWidget, reason: word);
      }
      // The feed is built and asked for its news from the first frame...
      expect(asked, isNotEmpty);
      await tester.pump();
      expect(find.text('Cabinet approves budget'), findsOneWidget);
      // ...but under the splash, which takes the taps.
      expect(find.text('Cabinet approves budget').hitTestable(), findsNothing);

      await _play(tester, _total(SplashStyle.rise));
      expect(find.byType(Splash), findsNothing);
      expect(
        find.text('Cabinet approves budget').hitTestable(),
        findsOneWidget,
      );
    },
  );

  for (final style in SplashStyle.values) {
    testWidgets('${style.name}: starts on the plain page, plays about two '
        'seconds, then fades out by itself', (tester) async {
      splashStyle.value = style;
      await tester.pumpWidget(_host());
      // The first frame is only the page, as the launch screen: no words yet.
      expect(_wordOpacities(tester), everyElement(0));
      final page = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(Splash),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(page.color, Colors.white);

      expect(splashLength(style), greaterThanOrEqualTo(seconds(1.8)));
      expect(_total(style), lessThanOrEqualTo(seconds(2.3)));
      await _play(tester, splashLength(style) - seconds(0.1));
      expect(find.byType(Splash), findsOneWidget);
      // At rest before the fade: every word fully drawn.
      expect(_wordOpacities(tester), everyElement(1));
      await _play(tester, seconds(0.1) + splashFade + seconds(0.05));
      expect(find.byType(Splash), findsNothing);
      expect(find.text('the app').hitTestable(), findsOneWidget);
    });
  }

  /// How far [word] still is under its place (rise).
  double drop(WidgetTester tester, String word) => tester
      .widget<Transform>(
        find
            .ancestor(of: find.text(word), matching: find.byType(Transform))
            .first,
      )
      .transform
      .getTranslation()
      .y;

  testWidgets('1 rise brings "Outer" up first; 1b, "News" first', (
    tester,
  ) async {
    splashStyle.value = SplashStyle.rise;
    await tester.pumpWidget(_host());
    await _play(tester, seconds(0.4));
    expect(drop(tester, 'Outer'), lessThan(drop(tester, 'News')));
    await _play(tester, _total(SplashStyle.rise));

    splashStyle.value = SplashStyle.riseUp;
    await tester.pumpWidget(KeyedSubtree(key: UniqueKey(), child: _host()));
    await _play(tester, seconds(0.4));
    expect(drop(tester, 'News'), lessThan(drop(tester, 'Outer')));
    await _play(tester, _total(SplashStyle.riseUp));
  });

  test('3 fill: "News" fills first, and from the first fill to the last, '
      'some line is always filling (no stop between the lines)', () {
    // In the order of the words: Outer, News.
    final early = splashFillLevels(300);
    expect(early[1], greaterThan(early[0]));
    for (var ms = 200.0; ms <= 1500; ms += 8) {
      expect(
        splashFillLevels(ms).any((level) => level > 0.02 && level < 0.98),
        isTrue,
        reason: 'at $ms ms',
      );
    }
    // Full before the hold, so the splash ends at rest.
    final end = splashLength(SplashStyle.fill).inMilliseconds - 200.0;
    expect(splashFillLevels(end), everyElement(1));
  });

  testWidgets('a slow frame (the app starting) slows it down, never skips it', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 16));
    // One frame that took a second: the splash moves on by 50 ms only.
    await tester.pump(const Duration(seconds: 1));
    expect(_wordOpacities(tester), everyElement(lessThan(0.5)));
    await _play(tester, _total(SplashStyle.rise) + seconds(0.1));
    expect(find.byType(Splash), findsNothing);
  });

  testWidgets('in dark mode the page is black and the words white', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(_host());
    final page = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(Splash),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(page.color, Colors.black);
    final word = tester.widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('Outer'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    expect(word.style.color, Colors.white);
    await _play(tester, _total(SplashStyle.rise));
  });

  testWidgets('a large text size does not grow the words past the screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host());
    final normal = tester.getSize(find.text('Outer'));
    // On the screen, after the fit that keeps a long word on it.
    final shown = tester.getRect(find.text('Outer'));
    await _play(tester, _total(SplashStyle.rise));

    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // A new start of the app, with the large text size.
    await tester.pumpWidget(KeyedSubtree(key: UniqueKey(), child: _host()));
    expect(tester.getSize(find.text('Outer')), normal);
    expect(tester.getRect(find.text('Outer')), shown);
    expect(shown.width, lessThan(390));
    await _play(tester, _total(SplashStyle.rise));
  });

  testWidgets('the words are the app\'s name in every language (Yurii, 28 Oct)', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    for (final locale in ['uk', 'de']) {
      await tester.pumpWidget(
        KeyedSubtree(
          key: UniqueKey(),
          child: _host(locale: locale),
        ),
      );
      for (final word in splashLines) {
        expect(find.text(word), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Outer News'), findsOneWidget);
      await _play(tester, _total(SplashStyle.riseUp));
    }
    semantics.dispose();
  });

  testWidgets('a notification that started the app ends it at once, with '
      'its fade', (tester) async {
    final opened = ValueNotifier(0);
    addTearDown(opened.dispose);
    await tester.pumpWidget(_host(endOn: opened));
    await _play(tester, seconds(0.3));
    expect(find.byType(Splash), findsOneWidget);
    opened.value++;
    await _play(tester, splashFade + seconds(0.05));
    expect(find.byType(Splash), findsNothing);
    expect(find.text('the app').hitTestable(), findsOneWidget);
  });

  testWidgets('a tap skips it: it fades out at once', (tester) async {
    await tester.pumpWidget(_host());
    await _play(tester, seconds(0.3));
    await tester.tap(find.byType(Splash));
    await _play(tester, splashFade + seconds(0.05));
    expect(find.byType(Splash), findsNothing);
    expect(find.text('the app').hitTestable(), findsOneWidget);
  });

  testWidgets('a scroll skips it too, from the first touch', (tester) async {
    await tester.pumpWidget(_host());
    await _play(tester, seconds(0.3));
    final gesture = await tester.startGesture(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    // Fading already, with the finger still down.
    expect(
      tester
          .widget<FadeTransition>(
            find
                .descendant(
                  of: find.byType(Splash),
                  matching: find.byType(FadeTransition),
                )
                .last,
          )
          .opacity
          .value,
      lessThan(1),
    );
    await gesture.moveBy(const Offset(0, -200));
    await gesture.up();
    await _play(tester, splashFade + seconds(0.05));
    expect(find.byType(Splash), findsNothing);
  });

  testWidgets('while it fades, the app under it already takes taps', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        app: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    await _play(tester, seconds(0.3));
    await tester.tapAt(const Offset(400, 300)); // skips the splash
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tapAt(const Offset(400, 300)); // reaches the app
    expect(taps, 1);
    await _play(tester, splashFade);
  });

  for (final (name, features) in [
    ('Reduce Motion', const FakeAccessibilityFeatures(reduceMotion: true)),
    (
      'animations off',
      const FakeAccessibilityFeatures(disableAnimations: true),
    ),
  ]) {
    for (final style in SplashStyle.values) {
      testWidgets('$name, ${style.name}: the words fade in without moving, '
          'stand still about 0.6 s, then fade', (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue = features;
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        splashStyle.value = style;
        await tester.pumpWidget(_host());
        void atRest() => expect(
          tester.widgetList<Transform>(
            find.descendant(
              of: find.byType(Splash),
              matching: find.byType(Transform),
            ),
          ),
          everyElement(
            isA<Transform>().having(
              (t) => t.transform.getTranslation().y,
              'moved down by',
              0,
            ),
          ),
        );
        // The first frame is the plain page (no hard cut to the words); the
        // words are already in place, at rest.
        expect(_wordOpacities(tester).first, 0);
        expect(_wordOpacities(tester).skip(1), everyElement(1));
        atRest();
        await _play(tester, seconds(0.25));
        expect(_wordOpacities(tester), everyElement(1));
        atRest();
        await _play(tester, splashStill - seconds(0.35));
        expect(find.byType(Splash), findsOneWidget);
        await _play(tester, seconds(0.1) + splashFade + seconds(0.05));
        expect(find.byType(Splash), findsNothing);
      });
    }
  }

  testWidgets('VoiceOver reads the name while it shows', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host());
    expect(find.bySemanticsLabel('Outer News'), findsOneWidget);
    expect(find.bySemanticsLabel('the app'), findsNothing);
    await _play(tester, _total(SplashStyle.rise));
    expect(find.bySemanticsLabel('Outer News'), findsNothing);
    expect(find.bySemanticsLabel('the app'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('it shows once: not again when the app comes back', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await _play(tester, _total(SplashStyle.rise));
    expect(find.byType(Splash), findsNothing);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(find.byType(Splash), findsNothing);
  });

  testWidgets('leaving the app while it plays ends it: coming back, the app '
      'is there, not the rest of the splash', (tester) async {
    await tester.pumpWidget(_host());
    await _play(tester, seconds(0.5));
    expect(find.byType(Splash), findsOneWidget);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(find.byType(Splash), findsNothing);
    expect(find.text('the app').hitTestable(), findsOneWidget);
  });

  testWidgets('a glance away (Control Centre: inactive only) lets it play on', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await _play(tester, seconds(0.5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.byType(Splash), findsOneWidget);
    await _play(tester, _total(SplashStyle.rise));
    expect(find.byType(Splash), findsNothing);
  });
}

Duration seconds(double s) => Duration(milliseconds: (s * 1000).round());
