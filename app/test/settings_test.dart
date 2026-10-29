import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/push.dart';
import 'package:official_news/features/settings/info_pages.dart';
import 'package:official_news/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_messaging.dart';
import 'test_app.dart';

Future<ValueNotifier<FeedLanguage>> _pump(
  WidgetTester tester, {
  List<FeedLanguage>? chosen,
  FeedLanguage words = FeedLanguage.en,
}) async {
  // The test's screen, 100 pt taller: the prototype's rows (Design, Splash,
  // Play, Read, Topics) take the top of the list, the pages' rows under them.
  tester.view.physicalSize = const Size(800, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final language = ValueNotifier(FeedLanguage.en);
  await tester.pumpWidget(
    testApp(
      language: words,
      home: SettingsScreen(
        language: language,
        onLanguage: (lang) {
          chosen?.add(lang);
          language.value = lang;
        },
        openLink: (_) async {},
      ),
    ),
  );
  return language;
}

void main() {
  testWidgets('lists the language, notifications and the four pages', (
    tester,
  ) async {
    await _pump(tester);
    for (final row in [
      'Language',
      'Notifications',
      'About Outer News',
      'Privacy Policy',
      'Terms of Use',
      'Contact & Support',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.text('English'), findsOneWidget);
    // Below the prototype's rows, which push it off the test's screen.
    await tester.scrollUntilVisible(
      find.textContaining('not affiliated with any government'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('not affiliated with any government'),
      findsOneWidget,
    );
  });

  group('the Notifications row (#62)', () {
    final en = l10nFor();
    late List<(String, Map<String, Object>)> events;
    late int settingsAppOpened;

    setUp(() {
      events = [];
      settingsAppOpened = 0;
      analytics = Analytics(
        (name, parameters) async => events.add((name, parameters)),
      );
    });
    tearDown(() => analytics = Analytics());

    Iterable<Map<String, Object>> sent(String name) =>
        events.where((e) => e.$1 == name).map((e) => e.$2);

    /// Settings in [words], with push on [messaging], or off without one (a
    /// build without Firebase); the iOS Settings app only counted.
    Future<void> pumpWithPush(
      WidgetTester tester,
      FakeMessaging? messaging, {
      FeedLanguage words = FeedLanguage.en,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final push = Push();
      if (messaging != null) {
        await push.start(
          messaging,
          await SharedPreferences.getInstance(),
          language: FeedLanguage.en,
        );
        addTearDown(push.stop);
      }
      await tester.pumpWidget(
        testApp(
          language: words,
          home: SettingsScreen(
            language: ValueNotifier(FeedLanguage.en),
            onLanguage: (_) {},
            openLink: (_) async {},
            notifications: push,
            openSettingsApp: () async => settingsAppOpened++,
          ),
        ),
      );
    }

    /// The row's grey or accent text, [info], next to "Notifications".
    Finder row(String info) => find.descendant(
      of: find.ancestor(
        of: find.text(l10nFor().notifications),
        matching: find.byType(CupertinoListTile),
      ),
      matching: find.text(info),
    );

    /// Away to the iOS Settings app and back: iOS sends inactive, then resumed.
    Future<void> backFromSettingsApp(WidgetTester tester) async {
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    testWidgets('no push in this build: Unavailable, and a tap does nothing', (
      tester,
    ) async {
      await pumpWithPush(tester, null);
      expect(row(en.notificationsUnavailable), findsOneWidget);
      expect(find.byType(CupertinoListTileChevron), findsNWidgets(7));
      await tester.tap(find.text(en.notifications));
      await tester.pumpAndSettle();
      expect(settingsAppOpened, 0);
      expect(events, isEmpty);
      expect(find.text(en.settings), findsOneWidget);
    });

    testWidgets('not asked yet: Turn On; a tap is iOS\'s question, then On', (
      tester,
    ) async {
      final messaging = FakeMessaging();
      await pumpWithPush(tester, messaging);
      expect(row(en.notificationsTurnOn), findsOneWidget);
      expect(messaging.asked, 0);

      await tester.tap(find.text(en.notifications));
      await tester.pumpAndSettle();
      expect(messaging.asked, 1, reason: 'iOS asks, with no explanation first');
      expect(row(en.notificationsOn), findsOneWidget);
      expect(sent('push_permission').single, {
        'result': 'granted',
        'trigger': 'settings',
      });
      expect(messaging.calls, ['subscribe breaking_en']);
      expect(settingsAppOpened, 0);
    });

    testWidgets('a second tap before iOS answers asks nothing more', (
      tester,
    ) async {
      final messaging = FakeMessaging()..question = Completer<void>();
      await pumpWithPush(tester, messaging);
      await tester.tap(find.text(en.notifications));
      await tester.pump(const Duration(milliseconds: 300));
      // iOS's alert not up yet: the row still says Turn On.
      expect(row(en.notificationsTurnOn), findsOneWidget);
      await tester.tap(find.text(en.notifications));
      await tester.pump();

      messaging.question!.complete();
      await tester.pumpAndSettle();
      expect(messaging.asked, 1);
      expect(row(en.notificationsOn), findsOneWidget);
      expect(sent('push_permission').single, {
        'result': 'granted',
        'trigger': 'settings',
      });
      expect(messaging.calls, ['subscribe breaking_en']);
      expect(settingsAppOpened, 0);
    });

    testWidgets('"Don\'t Allow" to iOS: Off, and the next tap opens Settings', (
      tester,
    ) async {
      final messaging = FakeMessaging(answer: PushPermission.denied);
      await pumpWithPush(tester, messaging);
      await tester.tap(find.text(en.notifications));
      await tester.pumpAndSettle();
      expect(row(en.notificationsOff), findsOneWidget);
      expect(sent('push_permission').single, {
        'result': 'denied',
        'trigger': 'settings',
      });
      expect(settingsAppOpened, 0);

      // iOS never asks again: only its Settings app can turn them on.
      await tester.tap(find.text(en.notifications));
      await tester.pumpAndSettle();
      expect(settingsAppOpened, 1);
      expect(messaging.asked, 1);
      expect(sent('push_permission'), hasLength(1));
    });

    testWidgets('Off: a tap opens the iOS Settings app; on there, On here', (
      tester,
    ) async {
      final messaging = FakeMessaging(status: PushPermission.denied);
      await pumpWithPush(tester, messaging);
      expect(row(en.notificationsOff), findsOneWidget);
      expect(find.byType(CupertinoListTileChevron), findsNWidgets(8));

      await tester.tap(find.text(en.notifications));
      await tester.pumpAndSettle();
      expect(settingsAppOpened, 1);
      expect(messaging.asked, 0);

      messaging.status = PushPermission.granted;
      await backFromSettingsApp(tester);
      expect(row(en.notificationsOn), findsOneWidget);
      expect(messaging.calls, ['subscribe breaking_en']);
      expect(sent('push_permission'), isEmpty, reason: 'iOS did not ask');
    });

    testWidgets('On: a tap opens the iOS Settings app; off there, Off here', (
      tester,
    ) async {
      final messaging = FakeMessaging(status: PushPermission.granted);
      await pumpWithPush(tester, messaging);
      expect(row(en.notificationsOn), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.hint == en.notificationsOpensSettings,
        ),
        findsOneWidget,
      );

      await tester.tap(find.text(en.notifications));
      await tester.pumpAndSettle();
      expect(settingsAppOpened, 1);

      messaging.status = PushPermission.denied;
      await backFromSettingsApp(tester);
      expect(row(en.notificationsOff), findsOneWidget);
      expect(messaging.calls, [
        'subscribe breaking_en',
        'unsubscribe breaking_en',
      ]);
    });

    // Every language, on the narrowest iPhone (SE, 375 pt): a grey value too
    // long for the row fails the test with an overflow. The title is not
    // checked: CupertinoListTile cuts it to one line with an ellipsis, and
    // with the test font (every letter a square, far wider than iOS's) it is
    // cut in every language, so only a phone shows whether it fits.
    for (final lang in FeedLanguage.values) {
      testWidgets('each state in ${lang.nativeName}, on a small phone', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(375, 667) * 2;
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final l10n = l10nFor(lang);
        for (final (messaging, info) in [
          (null, l10n.notificationsUnavailable),
          (FakeMessaging(), l10n.notificationsTurnOn),
          (FakeMessaging(status: PushPermission.granted), l10n.notificationsOn),
          (FakeMessaging(status: PushPermission.denied), l10n.notificationsOff),
        ]) {
          await pumpWithPush(tester, messaging, words: lang);
          expect(find.text(l10n.notifications), findsOneWidget);
          expect(find.text(info), findsOneWidget, reason: info);
          // A new screen for the next state.
          await tester.pumpWidget(const SizedBox());
        }
      });
    }

    // As the iOS Settings app writes them on its Notifications screen
    // (NotificationsSettings.bundle, iOS 26.3): full words in Ukrainian,
    // short ones in Russian.
    test('the row\'s words, and a hint that names the app', () {
      for (final (lang, words) in [
        (FeedLanguage.uk, ['Увімкнути', 'Увімкнено', 'Вимкнено', 'Недоступно']),
        (FeedLanguage.ru, ['Включить', 'Вкл.', 'Выкл.', 'Недоступно']),
      ]) {
        final l10n = l10nFor(lang);
        expect([
          l10n.notificationsTurnOn,
          l10n.notificationsOn,
          l10n.notificationsOff,
          l10n.notificationsUnavailable,
        ], words);
      }
      // The app, not the Settings screen the row is on (same word).
      for (final (lang, hint) in [
        (FeedLanguage.uk, 'Відкриває застосунок «Параметри»'),
        (FeedLanguage.ru, 'Открывает приложение «Настройки»'),
        (FeedLanguage.de, 'Öffnet die App „Einstellungen“'),
        (FeedLanguage.es, 'Abre los ajustes de tu teléfono'),
      ]) {
        expect(l10nFor(lang).notificationsOpensSettings, hint);
      }
    });
  });

  testWidgets('a chosen language shows in Settings at once', (tester) async {
    final chosen = <FeedLanguage>[];
    await _pump(tester, chosen: chosen);
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español'));
    await tester.pumpAndSettle();
    expect(chosen, [FeedLanguage.es]);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Español'), findsOneWidget);
  });

  for (final (row, title, line) in [
    ('About Outer News', 'About', 'Outer News is an independent app'),
    ('Privacy Policy', 'Privacy Policy', 'Outer News has no accounts'),
    (
      'Terms of Use',
      'Terms of Use',
      'It is not legal, financial or professional advice.',
    ),
    ('Contact & Support', 'Contact & Support', 'We read every message.'),
  ]) {
    testWidgets('$row opens its page', (tester) async {
      await _pump(tester);
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.textContaining(line), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
    });
  }

  testWidgets('the policy pages say when they were last updated', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Privacy Policy'));
    await tester.pumpAndSettle();
    expect(find.text('Last updated 29 October 2026'), findsOneWidget);
    // The parts App Review and #34, #60 ask for.
    for (final heading in [
      'On your phone',
      'When the app loads news',
      'Analytics',
      'Your rights',
    ]) {
      await tester.scrollUntilVisible(find.text(heading), 200);
      expect(find.text(heading), findsOneWidget);
    }
    // Lazily built: each is checked when scrolled to.
    for (final line in [
      'loaded directly from the official website',
      'Google Analytics for Firebase',
      // For you's country (#170, Yurii on #170): where it comes from, and
      // that the server keeps nothing.
      "your phone's region, or from Settings → My country",
      'and does not save it',
      "Cloudflare's technical logs, which are deleted automatically within a "
          'week',
    ]) {
      await tester.scrollUntilVisible(find.textContaining(line), -200);
      expect(find.textContaining(line), findsOneWidget);
    }
  });

  // #52: every page in every language, the names that are never translated
  // kept as they are.
  for (final lang in FeedLanguage.values) {
    testWidgets('the pages read in ${lang.nativeName}', (tester) async {
      final l10n = l10nFor(lang);
      await _pump(tester, words: lang);
      expect(find.text(l10n.settings), findsOneWidget);
      expect(find.text(l10n.settingsReading.toUpperCase()), findsOneWidget);

      await tester.tap(find.text(l10n.privacyPolicy));
      await tester.pumpAndSettle();
      expect(find.text(l10n.privacyPolicy), findsOneWidget);
      expect(find.text(policyUpdatedLine(l10n)), findsOneWidget);
      // The back button: "< Settings" in the language, or the system's own
      // "Back" in it when the word is long ("Einstellungen" is "Zurück").
      final back = CupertinoLocalizations.of(
        tester.element(find.text(l10n.privacyPolicy)),
      ).backButtonLabel;
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && (w.data == l10n.settings || w.data == back),
        ),
        findsOneWidget,
      );
      for (final name in [
        'Google Analytics for Firebase',
        'Cloudflare Workers AI',
        'Groq',
        'RS Elite Pro s.r.o.',
      ]) {
        await tester.scrollUntilVisible(find.textContaining(name), 200);
        expect(find.textContaining(name), findsOneWidget, reason: name);
      }
      await tester.pageBack();
      await tester.pumpAndSettle();

      for (final (row, line) in [
        (l10n.aboutApp, l10n.aboutIntro),
        (l10n.termsOfUse, l10n.termsIntro1),
        (l10n.contactSupport, l10n.supportAppStore),
      ]) {
        await tester.tap(find.text(row));
        await tester.pumpAndSettle();
        expect(find.text(line), findsOneWidget, reason: row);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('the terms date and the publisher in Ukrainian', (tester) async {
    await _pump(tester, words: FeedLanguage.uk);
    await tester.tap(find.text('Умови використання'));
    await tester.pumpAndSettle();
    expect(find.text('Оновлено 29 жовтня 2026\u202Fр.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('RS Elite Pro s.r.o., Словаччина'),
      200,
    );
    expect(
      find.text(
        'Видавець: RS Elite Pro s.r.o., Словаччина. Якщо ці умови зміняться, '
        'нова версія з’явиться в застосунку з новою датою.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the policy date and the data controller in German', (
    tester,
  ) async {
    await _pump(tester, words: FeedLanguage.de);
    await tester.tap(find.text('Datenschutzerklärung'));
    await tester.pumpAndSettle();
    expect(find.text('Stand: 29. Oktober 2026'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Verantwortlicher: RS Elite Pro s.r.o., Slowakei.'),
      200,
    );
    expect(find.textContaining('(siehe „Kontakt & Support“)'), findsOneWidget);
  });
}
