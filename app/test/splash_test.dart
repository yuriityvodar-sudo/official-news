import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/settings/settings_screen.dart';
import 'package:official_news/features/splash/splash.dart';
import 'package:official_news/l10n/app_localizations.dart';
import 'package:official_news/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PROTOTYPE (Yurii, 16 Oct): the splash at start, its three styles and
/// Settings → Play.

/// [app] under a [SplashHost], as `MaterialApp.builder` puts it.
Widget _host({Widget app = const Text('the app'), bool onStart = true}) =>
    MaterialApp(
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => SplashHost(onStart: onStart, child: child!),
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
  tearDown(() => splashStyle.value = SplashStyle.rise);

  test('a build picks the style by name or number; rise otherwise', () {
    expect(splashNamed('sweep'), SplashStyle.sweep);
    expect(splashNamed(' FILL '), SplashStyle.fill);
    expect(splashNamed('1'), SplashStyle.rise);
    expect(splashNamed('2'), SplashStyle.sweep);
    expect(splashNamed('3'), SplashStyle.fill);
    expect(splashNamed(''), SplashStyle.rise);
    expect(splashNamed('wave'), SplashStyle.rise);
  });

  test('the three words, in one place, lower case as written', () {
    expect(splashLines, ['only', 'official', 'news']);
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
            of: find.text('only'),
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
    final normal = tester.getSize(find.text('official'));
    await _play(tester, _total(SplashStyle.rise));

    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // A new start of the app, with the large text size.
    await tester.pumpWidget(KeyedSubtree(key: UniqueKey(), child: _host()));
    expect(tester.getSize(find.text('official')), normal);
    expect(normal.width, lessThan(390));
    await _play(tester, _total(SplashStyle.rise));
  });

  testWidgets('a tap skips it: it fades out at once', (tester) async {
    await tester.pumpWidget(_host());
    await _play(tester, seconds(0.3));
    await tester.tap(find.byType(Splash));
    await _play(tester, splashFade + seconds(0.05));
    expect(find.byType(Splash), findsNothing);
    expect(find.text('the app').hitTestable(), findsOneWidget);
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
      testWidgets('$name, ${style.name}: the words stand still for 0.6 s, '
          'then fade', (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue = features;
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        splashStyle.value = style;
        await tester.pumpWidget(_host());
        // At rest from the first frame.
        expect(_wordOpacities(tester), everyElement(1));
        expect(
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
        await _play(tester, splashStill - seconds(0.1));
        expect(find.byType(Splash), findsOneWidget);
        await _play(tester, seconds(0.1) + splashFade + seconds(0.05));
        expect(find.byType(Splash), findsNothing);
      });
    }
  }

  testWidgets('VoiceOver reads the three words while it shows', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host());
    expect(find.bySemanticsLabel('only official news'), findsOneWidget);
    expect(find.bySemanticsLabel('the app'), findsNothing);
    await _play(tester, _total(SplashStyle.rise));
    expect(find.bySemanticsLabel('only official news'), findsNothing);
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

  group('Settings → Prototype → Splash', () {
    Future<void> openSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          onStart: false,
          app: SettingsScreen(
            language: ValueNotifier(FeedLanguage.en),
            onLanguage: (_) {},
            openLink: (_) async {},
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('lists the three styles, rise chosen', (tester) async {
      await openSettings(tester);
      expect(find.text('Splash'), findsOneWidget);
      expect(find.text('1 rise · 2 sweep · 3 fill'), findsOneWidget);
      final control = tester
          .widget<CupertinoSlidingSegmentedControl<SplashStyle>>(
            find.byType(CupertinoSlidingSegmentedControl<SplashStyle>),
          );
      expect(control.groupValue, SplashStyle.rise);
      expect(find.byType(Splash), findsNothing);
    });

    for (final (segment, style) in [
      ('1', SplashStyle.rise),
      ('2', SplashStyle.sweep),
      ('3', SplashStyle.fill),
    ]) {
      testWidgets('$segment, then Play, shows ${style.name} over Settings', (
        tester,
      ) async {
        await openSettings(tester);
        await tester.tap(find.text(segment));
        await tester.pumpAndSettle();
        expect(splashStyle.value, style);

        await tester.tap(find.text('Play'));
        await tester.pump();
        expect(tester.widget<Splash>(find.byType(Splash)).style, style);
        expect(find.text('Splash').hitTestable(), findsNothing);

        await _play(tester, _total(style));
        expect(find.byType(Splash), findsNothing);
        // Back on Settings, as it was.
        expect(find.text('Splash').hitTestable(), findsOneWidget);
      });
    }

    testWidgets('Play again after it ends shows it again', (tester) async {
      await openSettings(tester);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Play'));
        await tester.pump();
        expect(find.byType(Splash), findsOneWidget);
        await _play(tester, _total(SplashStyle.rise));
        expect(find.byType(Splash), findsNothing);
      }
    });
  });
}

Duration seconds(double s) => Duration(milliseconds: (s * 1000).round());
