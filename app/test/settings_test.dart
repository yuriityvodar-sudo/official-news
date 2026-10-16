import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/features/settings/info_pages.dart';
import 'package:official_news/features/settings/settings_screen.dart';

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
          menu.value = CountryMenu(current: code, countries: _countries);
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
    await _pump(tester, country: menu);
    await tester.tap(find.text('Country'));
    // Not pumpAndSettle: the spinner turns for as long as it is shown.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    menu.value = const CountryMenu(current: 'DE');
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoActivityIndicator), findsNothing);
    expect(find.text("Couldn't load the list of countries."), findsOneWidget);
    // The country shown now stays listed, checked.
    expect(find.text('Germany'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
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
