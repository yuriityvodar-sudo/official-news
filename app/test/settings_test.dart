import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/features/settings/info_pages.dart';
import 'package:official_news/features/settings/settings_screen.dart';

import 'test_app.dart';

Future<ValueNotifier<FeedLanguage>> _pump(
  WidgetTester tester, {
  List<FeedLanguage>? chosen,
  FeedLanguage words = FeedLanguage.en,
}) async {
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
      'About Official News',
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
