import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/core/push.dart';
import 'package:official_news/features/settings/info_pages.dart';
import 'package:official_news/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_messaging.dart';
import 'test_app.dart';

/// The countries a server with `GET /countries` lists, in English.
const _countries = [
  FeedCountry('DE', 'Germany'),
  FeedCountry('FR', 'France'),
  FeedCountry('US', 'United States'),
];

Future<ValueNotifier<FeedLanguage>> _pump(
  WidgetTester tester, {
  List<FeedLanguage>? chosen,
  FeedLanguage words = FeedLanguage.en,
  ValueNotifier<CountryMenu>? country,
  List<String>? countriesChosen,
  VoidCallback? loadCountries,
}) async {
  final language = ValueNotifier(FeedLanguage.en);
  final menu =
      country ??
      ValueNotifier(const CountryMenu(current: 'DE', countries: _countries));
  await tester.pumpWidget(
    testApp(
      language: words,
      home: SettingsScreen(
        language: language,
        onLanguage: (lang) {
          chosen?.add(lang);
          language.value = lang;
        },
        country: menu,
        onCountry: (code) {
          countriesChosen?.add(code);
          menu.value = CountryMenu(
            current: code,
            countries: menu.value.countries,
            region: menu.value.region,
          );
        },
        loadCountries: loadCountries ?? () {},
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
      'About Official News',
      'Privacy Policy',
      'Terms of Use',
      'Contact & Support',
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.text('English'), findsOneWidget);
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
            // No Country row: the chevrons counted are push's and the pages'.
            country: ValueNotifier(const CountryMenu(available: false)),
            onCountry: (_) {},
            loadCountries: () {},
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
      expect(find.byType(CupertinoListTileChevron), findsNWidgets(5));
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
      expect(find.byType(CupertinoListTileChevron), findsNWidgets(6));

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

  testWidgets('Country (#68): the Local country, chosen from the list', (
    tester,
  ) async {
    final chosen = <String>[];
    await _pump(tester, countriesChosen: chosen);
    expect(find.text('Country'), findsOneWidget);
    expect(find.text('Germany'), findsOneWidget);
    await tester.tap(find.text('Country'));
    await tester.pumpAndSettle();
    expect(find.text('France'), findsOneWidget);
    expect(find.text('United States'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
    await tester.tap(find.text('France'));
    await tester.pumpAndSettle();
    expect(chosen, ['FR']);
    expect(
      tester.getSemantics(find.text('France')),
      isSemantics(label: 'France', isSelected: true),
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('France'), findsOneWidget);
  });

  testWidgets('Country while the list loads, and when it could not', (
    tester,
  ) async {
    final menu = ValueNotifier(const CountryMenu(current: 'DE', loading: true));
    var asked = 0;
    await _pump(tester, country: menu, loadCountries: () => asked++);
    await tester.tap(find.text('Country'));
    // Not pumpAndSettle: the spinner turns for as long as it is shown.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(asked, 1); // the page asks when it opens
    menu.value = const CountryMenu(current: 'DE');
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    // The country shown now stays listed, checked.
    expect(find.text('Germany'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
    // The failure text asks again.
    await tester.tap(
      find.text("Couldn't load the list of countries. Tap to try again."),
    );
    expect(asked, 2);
    menu.value = const CountryMenu(current: 'DE', countries: _countries);
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't load"), findsNothing);
    expect(find.text('United States'), findsOneWidget);
  });

  testWidgets('Country: the phone region without sources is listed first', (
    tester,
  ) async {
    final chosen = <String>[];
    final menu = ValueNotifier(
      const CountryMenu(current: 'UA', region: 'UA', countries: _countries),
    );
    await _pump(tester, country: menu, countriesChosen: chosen);
    expect(find.text('Ukraine'), findsOneWidget); // the row's value
    await tester.tap(find.text('Country'));
    await tester.pumpAndSettle();
    List<String> names() => [
      for (final tile in tester.widgetList<CupertinoListTile>(
        find.byType(CupertinoListTile),
      ))
        ((tile.title as Semantics).child! as Text).data!,
    ];
    expect(names(), ['Ukraine', 'Germany', 'France', 'United States']);
    expect(
      tester.getSemantics(find.text('Ukraine')),
      isSemantics(label: 'Ukraine', isSelected: true),
    );
    // Another country: the phone's stays offered, to go back to.
    await tester.tap(find.text('Germany'));
    await tester.pumpAndSettle();
    expect(names(), ['Ukraine', 'Germany', 'France', 'United States']);
    await tester.tap(find.text('Ukraine'));
    await tester.pumpAndSettle();
    expect(chosen, ['DE', 'UA']);
  });

  testWidgets('no Country row for a server without countries', (tester) async {
    await _pump(
      tester,
      country: ValueNotifier(const CountryMenu(available: false)),
    );
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Country'), findsNothing);
  });

  for (final (row, title, line) in [
    ('About Official News', 'About', 'Official News is an independent app'),
    ('Privacy Policy', 'Privacy Policy', 'Official News has no accounts'),
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
    expect(find.text('Last updated 16 October 2026'), findsOneWidget);
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
    expect(find.text('Оновлено 16 жовтня 2026\u202Fр.'), findsOneWidget);
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
    expect(find.text('Stand: 16. Oktober 2026'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Verantwortlicher: RS Elite Pro s.r.o., Slowakei.'),
      200,
    );
    expect(find.textContaining('(siehe „Kontakt & Support“)'), findsOneWidget);
  });
}
