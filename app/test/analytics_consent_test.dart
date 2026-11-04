import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/analytics_consent.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// L1 of the release audit (4 Nov): usage statistics only once the reader
/// allows them.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    analyticsConsent.value = AnalyticsConsent.unknown;
    analyticsAvailable.value = false;
  });
  tearDown(() {
    analyticsConsent.value = AnalyticsConsent.unknown;
    analyticsAvailable.value = false;
  });

  test('unknown until answered; the answer is kept on the phone', () async {
    await loadAnalyticsConsent();
    expect(analyticsConsent.value, AnalyticsConsent.unknown);
    await setAnalyticsConsent(AnalyticsConsent.granted);
    analyticsConsent.value = AnalyticsConsent.unknown;
    await loadAnalyticsConsent();
    expect(analyticsConsent.value, AnalyticsConsent.granted);
    await setAnalyticsConsent(AnalyticsConsent.denied);
    await loadAnalyticsConsent();
    expect(analyticsConsent.value, AnalyticsConsent.denied);
  });

  /// An app that asks, as the splash's end does.
  Future<BuildContext> pumpApp(
    WidgetTester tester, {
    FeedLanguage language = FeedLanguage.en,
  }) async {
    late BuildContext shown;
    await tester.pumpWidget(
      testApp(
        language: language,
        home: Builder(
          builder: (context) {
            shown = context;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    return shown;
  }

  testWidgets('asks once, with two answers that weigh the same; Allow turns '
      'it on and is kept', (tester) async {
    analyticsAvailable.value = true;
    final context = await pumpApp(tester);
    final asked = askAnalyticsConsent(() => context);
    await tester.pumpAndSettle();
    expect(find.text('Help improve Outer News?'), findsOneWidget);
    expect(find.textContaining('Google Analytics for Firebase'), findsOneWidget);
    final actions = tester
        .widgetList<CupertinoDialogAction>(find.byType(CupertinoDialogAction))
        .toList();
    expect(actions, hasLength(2));
    expect(actions.every((a) => !a.isDefaultAction), isTrue);
    expect(actions.every((a) => !a.isDestructiveAction), isTrue);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    await asked;
    expect(analyticsConsent.value, AnalyticsConsent.granted);
    expect(
      (await SharedPreferences.getInstance()).getString('analytics.consent'),
      'granted',
    );
    // Answered: not asked again.
    unawaited(askAnalyticsConsent(() => context));
    await tester.pumpAndSettle();
    expect(find.text('Help improve Outer News?'), findsNothing);
  });

  testWidgets("Don't Allow keeps it off, and is kept", (tester) async {
    analyticsAvailable.value = true;
    final context = await pumpApp(tester);
    unawaited(askAnalyticsConsent(() => context));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Don't Allow"));
    await tester.pumpAndSettle();
    expect(analyticsConsent.value, AnalyticsConsent.denied);
    expect(find.text('Help improve Outer News?'), findsNothing);
  });

  testWidgets('a build without analytics never asks; one whose Firebase is '
      'still starting asks once it has', (tester) async {
    final context = await pumpApp(tester);
    unawaited(askAnalyticsConsent(() => context));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsNothing);
    analyticsAvailable.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
  });

  testWidgets('in the reader\'s language', (tester) async {
    analyticsAvailable.value = true;
    final context = await pumpApp(tester, language: FeedLanguage.ru);
    unawaited(askAnalyticsConsent(() => context));
    await tester.pumpAndSettle();
    expect(find.text('Помочь улучшить Outer News?'), findsOneWidget);
    expect(find.text('Не разрешать'), findsOneWidget);
    expect(find.text('Разрешить'), findsOneWidget);
    await tester.tap(find.text('Не разрешать'));
    await tester.pumpAndSettle();
  });

  group('Settings', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      final language = ValueNotifier(FeedLanguage.en);
      await tester.pumpWidget(
        testApp(
          home: SettingsScreen(language: language, onLanguage: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a switch turns usage statistics on and off at any time', (
      tester,
    ) async {
      analyticsAvailable.value = true;
      analyticsConsent.value = AnalyticsConsent.denied;
      await pumpSettings(tester);
      expect(find.text('Usage statistics'), findsOneWidget);
      final toggle = find.byType(CupertinoSwitch);
      expect(tester.widget<CupertinoSwitch>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(analyticsConsent.value, AnalyticsConsent.granted);
      expect(tester.widget<CupertinoSwitch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(analyticsConsent.value, AnalyticsConsent.denied);
    });

    testWidgets('no switch in a build without analytics', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Usage statistics'), findsNothing);
    });
  });
}
