import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/settings/settings_screen.dart';

Future<ValueNotifier<FeedLanguage>> _pump(
  WidgetTester tester, {
  List<FeedLanguage>? chosen,
}) async {
  final language = ValueNotifier(FeedLanguage.en);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
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
}
