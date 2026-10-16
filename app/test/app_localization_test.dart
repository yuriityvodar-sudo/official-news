import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/countries.dart';
import 'package:official_news/core/decision_types.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/languages.dart';
import 'package:official_news/core/news_widgets.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// The app's words in every language (#52): the ARB files are complete, the
/// plurals are right, the first launch follows the phone, and one change in
/// Settings redraws the whole app in the chosen language.

Map<String, dynamic> _article(
  String id, {
  required String headline,
  String? lang,
  int? feedSeq,
}) => {
  'feedSeq': feedSeq,
  'addedAt': DateTime.now()
      .subtract(const Duration(minutes: 5))
      .toUtc()
      .toIso8601String(),
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
  'lang': ?lang,
};

/// One top story and one more decision in each language: `lang=uk` answers in
/// Ukrainian, no `lang` in English.
ApiClient _api({List<Uri>? log}) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    log?.add(request.url);
    final query = request.url.queryParameters;
    if (query.containsKey('after') || query.containsKey('since')) {
      return _ok({'items': [], 'nextCursor': null, 'top': []});
    }
    final lang = query['lang'];
    final top = _article(
      't1',
      headline: lang == null ? 'Cabinet approves budget' : 'Бюджет $lang',
      lang: lang,
      feedSeq: 2,
    );
    final other = _article(
      'a1',
      headline: lang == null ? 'Law on water signed' : 'Закон $lang',
      lang: lang,
      feedSeq: 1,
    );
    return _ok({
      'items': [top, other],
      'nextCursor': null,
      'top': [top],
    });
  }),
);

http.Response _ok(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// The whole app, as `main` starts it: the language is read before the first frame.
Future<FeedController> _launch(
  WidgetTester tester, {
  List<Locale> phone = const [Locale('en', 'US')],
  List<Uri>? log,
}) async {
  // A phone-sized screen (iPhone 15, 393 x 852 pt): longer words must fit.
  tester.view.physicalSize = const Size(393, 852) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final feed = FeedController(
    api: _api(log: log),
    phoneLanguages: () => phone,
  );
  await feed.open();
  await tester.pumpWidget(OfficialNewsApp(feed: feed));
  await tester.pump();
  await tester.pump();
  return feed;
}

/// Through the gear, Language and the language, leaving Settings open.
Future<void> _chooseInSettings(
  WidgetTester tester,
  String language,
  String languageRow,
) async {
  await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
  await tester.pumpAndSettle();
  await tester.tap(find.text(languageRow));
  await tester.pumpAndSettle();
  await tester.tap(find.text(language));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _arb(String code) =>
    jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync())
        as Map<String, dynamic>;

/// The placeholders a message uses: `{name}`, or `{name, plural, …}`.
Set<String> _placeholders(String message) => RegExp(
  r'\{(\w+)\s*[},]',
).allMatches(message).map((m) => m.group(1)!).toSet();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ARB files', () {
    final template = _arb('en');
    final keys = template.keys.where((k) => !k.startsWith('@')).toSet();

    test('there is one for each language in the picker, and only those', () {
      final codes = Directory('lib/l10n')
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .map((name) => RegExp(r'^app_(\w+)\.arb$').firstMatch(name)?[1])
          .whereType<String>()
          .toSet();
      expect(codes, FeedLanguage.values.map((l) => l.code).toSet());
    });

    test('every message of the template has a description', () {
      for (final key in keys) {
        final meta = template['@$key'] as Map<String, dynamic>?;
        expect(meta?['description'], isA<String>(), reason: key);
      }
    });

    for (final lang in FeedLanguage.values.where((l) => l != FeedLanguage.en)) {
      test('app_${lang.code}.arb has every message of app_en.arb', () {
        final arb = _arb(lang.code);
        expect(arb['@@locale'], lang.code);
        final translated = arb.keys.where((k) => !k.startsWith('@')).toSet();
        expect(keys.difference(translated), isEmpty, reason: 'missing');
        expect(translated.difference(keys), isEmpty, reason: 'not in app_en');
        for (final key in keys) {
          final message = arb[key] as String;
          expect(message.trim(), isNotEmpty, reason: key);
          // The same placeholders: a translation never drops a name or a number.
          expect(
            _placeholders(message),
            _placeholders(template[key] as String),
            reason: key,
          );
        }
      });
    }

    test('iOS lists the same languages (CFBundleLocalizations)', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final list = RegExp(
        r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
        dotAll: true,
      ).firstMatch(plist)?[1];
      expect(list, isNotNull);
      expect(
        RegExp(r'<string>(\w+)</string>').allMatches(list!).map((m) => m[1]),
        FeedLanguage.values.map((l) => l.code),
      );
    });

    test('every decision type, country and source language has its words', () {
      for (final lang in FeedLanguage.values) {
        final l10n = l10nFor(lang);
        for (final type in decisionTypes) {
          expect(decisionTypeLabel(type, l10n), isNotNull, reason: type);
        }
        expect(countryName('DE', l10n), isNot('DE'));
        expect(languageName('de', l10n), isNot('DE'));
        // Unknown codes are shown as they are.
        expect(countryName('XX', l10n), 'XX');
        expect(languageName('xx', l10n), 'XX');
      }
    });
  });

  group('plurals', () {
    test('"N new decisions" in Ukrainian: one, few, many', () {
      final uk = l10nFor(FeedLanguage.uk);
      expect(uk.newDecisions(1), '1 нове рішення');
      expect(uk.newDecisions(2), '2 нові рішення');
      expect(uk.newDecisions(5), '5 нових рішень');
      expect(uk.newDecisions(11), '11 нових рішень');
      expect(uk.newDecisions(21), '21 нове рішення');
      expect(uk.newDecisions(22), '22 нові рішення');
    });

    test('"N new decisions" in Russian, English, Spanish and German', () {
      final ru = l10nFor(FeedLanguage.ru);
      expect(ru.newDecisions(1), '1 новое решение');
      expect(ru.newDecisions(3), '3 новых решения');
      expect(ru.newDecisions(5), '5 новых решений');
      expect(ru.newDecisions(21), '21 новое решение');
      expect(l10nFor().newDecisions(1), '1 new decision');
      expect(l10nFor().newDecisions(2), '2 new decisions');
      expect(l10nFor(FeedLanguage.es).newDecisions(1), '1 decisión nueva');
      expect(l10nFor(FeedLanguage.es).newDecisions(4), '4 decisiones nuevas');
      expect(l10nFor(FeedLanguage.de).newDecisions(1), '1 neue Entscheidung');
      expect(l10nFor(FeedLanguage.de).newDecisions(7), '7 neue Entscheidungen');
    });

    test('card times: minutes, hours and days ago', () {
      final now = DateTime(2026, 10, 16, 12);
      String ago(FeedLanguage lang, Duration d) =>
          timeAgo(now.subtract(d), l10nFor(lang), now: now);
      expect(ago(FeedLanguage.en, const Duration(minutes: 3)), '3m ago');
      expect(ago(FeedLanguage.en, const Duration(days: 2)), '2d ago');
      expect(ago(FeedLanguage.uk, const Duration(minutes: 3)), '3 хв тому');
      expect(ago(FeedLanguage.uk, const Duration(hours: 2)), '2 год тому');
      expect(ago(FeedLanguage.uk, const Duration(days: 1)), '1 день тому');
      expect(ago(FeedLanguage.uk, const Duration(days: 3)), '3 дні тому');
      expect(ago(FeedLanguage.uk, const Duration(days: 5)), '5 днів тому');
      expect(ago(FeedLanguage.ru, const Duration(days: 5)), '5 дней назад');
      expect(ago(FeedLanguage.es, const Duration(hours: 4)), 'hace 4 h');
      expect(ago(FeedLanguage.de, const Duration(days: 2)), 'vor 2 Tagen');
    });

    test('dates in each language', () {
      final day = DateTime(2026, 10, 16, 9);
      expect(longDay(day, l10nFor()), 'Friday, 16 October');
      expect(longDay(day, l10nFor(FeedLanguage.uk)), 'Пʼятниця, 16 жовтня');
      expect(longDay(day, l10nFor(FeedLanguage.ru)), 'Пятница, 16 октября');
      expect(longDay(day, l10nFor(FeedLanguage.es)), 'Viernes, 16 de octubre');
      expect(longDay(day, l10nFor(FeedLanguage.de)), 'Freitag, 16. Oktober');
      expect(fullDate(day, l10nFor()), '16 October 2026');
      // A narrow no-break space keeps "р." / "г." (year) with the year.
      expect(fullDate(day, l10nFor(FeedLanguage.uk)), '16 жовтня 2026\u202Fр.');
      expect(
        fullDate(day, l10nFor(FeedLanguage.ru)),
        '16 октября 2026\u202Fг.',
      );
      expect(fullDate(day, l10nFor(FeedLanguage.de)), '16. Oktober 2026');
      expect(clockTime(day, l10nFor(FeedLanguage.uk)), '09:00');
      final now = DateTime(2026, 10, 16, 12);
      expect(
        dayLabel(DateTime(2026, 10, 15), l10nFor(FeedLanguage.uk), now: now),
        'Учора',
      );
      expect(
        dayLabel(DateTime(2026, 10, 12), l10nFor(FeedLanguage.uk), now: now),
        'Понеділок, 12 жовтня',
      );
    });
  });

  group('first launch', () {
    test('a phone language the app has is used, and not saved', () {
      expect(
        FeedLanguage.forPhone(const [Locale('uk', 'UA')]),
        FeedLanguage.uk,
      );
      expect(
        FeedLanguage.forPhone(const [Locale('de', 'AT')]),
        FeedLanguage.de,
      );
      // The first of the phone's languages that the app has, as iOS picks one.
      expect(
        FeedLanguage.forPhone(const [Locale('cs', 'CZ'), Locale('ru')]),
        FeedLanguage.ru,
      );
      expect(
        FeedLanguage.forPhone(const [Locale('cs', 'CZ')]),
        FeedLanguage.en,
      );
      expect(FeedLanguage.forPhone(const []), FeedLanguage.en);
    });

    test('nothing saved: the feed opens in the phone language', () async {
      final log = <Uri>[];
      final feed = FeedController(
        api: _api(log: log),
        phoneLanguages: () => const [Locale('uk', 'UA'), Locale('en', 'US')],
      );
      await feed.start();
      expect(feed.language, FeedLanguage.uk);
      expect(log.first.queryParameters['lang'], 'uk');
      // Not saved: it follows the phone until a language is chosen in Settings.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('feed.lang'), isNull);
    });

    test('a phone language the app does not have opens in English', () async {
      final log = <Uri>[];
      final feed = FeedController(
        api: _api(log: log),
        phoneLanguages: () => const [Locale('fr', 'FR')],
      );
      await feed.start();
      expect(feed.language, FeedLanguage.en);
      expect(log.first.queryParameters.containsKey('lang'), isFalse);
    });

    test('a language chosen before wins over the phone', () async {
      SharedPreferences.setMockInitialValues({'feed.lang': 'ru'});
      final feed = FeedController(
        api: _api(),
        phoneLanguages: () => const [Locale('uk', 'UA')],
      );
      await feed.start();
      expect(feed.language, FeedLanguage.ru);
    });

    testWidgets('the app opens in the phone language, words and dates', (
      tester,
    ) async {
      await _launch(tester, phone: const [Locale('uk', 'UA')]);
      expect(find.text('Головне'), findsOneWidget);
      expect(find.text('Останнє'), findsOneWidget);
      expect(
        find.text(longDay(DateTime.now(), l10nFor(FeedLanguage.uk))),
        findsOneWidget,
      );
      expect(find.text('Top stories'), findsNothing);
    });

    testWidgets('choosing the language it already shows saves it', (
      tester,
    ) async {
      final log = <Uri>[];
      final feed = await _launch(
        tester,
        phone: const [Locale('uk', 'UA')],
        log: log,
      );
      final asked = log.length;
      await _chooseInSettings(tester, 'Українська', 'Мова');
      // A choice made in Settings: the app no longer follows the phone.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('feed.lang'), 'uk');
      expect(feed.language, FeedLanguage.uk);
      // The same feed, so nothing loads again.
      expect(log, hasLength(asked));
    });

    testWidgets('a phone in another language opens the app in English', (
      tester,
    ) async {
      await _launch(tester, phone: const [Locale('fr', 'FR')]);
      expect(find.text('Top stories'), findsOneWidget);
      expect(find.text('Latest'), findsOneWidget);
    });
  });

  testWidgets(
    'choosing Українська in Settings redraws the whole app in Ukrainian at once',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final log = <Uri>[];
      await _launch(tester, log: log);
      expect(find.text('Top stories'), findsOneWidget);
      expect(find.text('CABINET DECISION'), findsNWidgets(2));
      expect(find.text(longDay(DateTime.now(), l10nFor())), findsOneWidget);

      await _chooseInSettings(tester, 'Українська', 'Language');
      // The language page itself changes at once, the system's words too.
      expect(find.text('Мова'), findsOneWidget);
      expect(
        find.text('Новини й застосунок показуються цією мовою.'),
        findsOneWidget,
      );
      final page = tester.element(find.text('Мова'));
      expect(CupertinoLocalizations.of(page).backButtonLabel, 'Назад');
      expect(MaterialLocalizations.of(page).backButtonTooltip, 'Назад');

      await tester.pageBack();
      await tester.pumpAndSettle();
      // The large title, and the small one the bar shows when scrolled.
      expect(find.text('Параметри'), findsWidgets);
      for (final word in [
        'ЧИТАННЯ',
        'Мова',
        'Українська',
        'Сповіщення',
        'Незабаром',
        'ІНФОРМАЦІЯ',
        'Про Official News',
        'Політика конфіденційності',
        'Умови використання',
        'Контакти й підтримка',
      ]) {
        expect(find.text(word), findsOneWidget, reason: word);
      }
      expect(find.textContaining('Версія 0.1.0'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(log.last.queryParameters['lang'], 'uk');
      expect(find.text('Головне'), findsOneWidget);
      expect(find.text('Останнє'), findsOneWidget);
      expect(find.text('Top stories'), findsNothing);
      expect(
        find.text(longDay(DateTime.now(), l10nFor(FeedLanguage.uk))),
        findsOneWidget,
      );
      expect(find.text('РІШЕННЯ УРЯДУ'), findsNWidgets(2));
      expect(find.text('Federal Government · Німеччина'), findsNWidgets(2));
      expect(find.text('5 хв тому'), findsNWidgets(2));
      expect(find.bySemanticsLabel('Параметри'), findsOneWidget);

      // An article opened now has "< Сьогодні" as its back button.
      await tester.tap(find.text('Закон uk'));
      await tester.pumpAndSettle();
      expect(find.text('Сьогодні'), findsOneWidget);
      expect(find.text('Офіційне джерело'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('feed.lang'), 'uk');

      // And back to English, from the Ukrainian Settings.
      await _chooseInSettings(tester, 'English', 'Мова');
      expect(find.text('Language'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Top stories'), findsOneWidget);
      expect(find.text('Головне'), findsNothing);
      semantics.dispose();
    },
  );

  // Every screen on a phone in every language: a longer word that does not fit
  // (a row that overflows) fails the test.
  for (final lang in FeedLanguage.values) {
    testWidgets('every screen fits on a phone in ${lang.nativeName}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'feed.lang': lang.code});
      final l10n = l10nFor(lang);
      await _launch(tester);
      expect(find.text(l10n.topStories), findsOneWidget);
      await tester.tap(
        find.textContaining(lang == FeedLanguage.en ? 'Law' : 'Закон'),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.today), findsOneWidget); // the back button
      expect(find.text(l10n.officialSource), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
      await tester.pumpAndSettle();
      for (final row in [
        l10n.language,
        l10n.aboutApp,
        l10n.privacyPolicy,
        l10n.termsOfUse,
        l10n.contactSupport,
      ]) {
        await tester.tap(find.text(row));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(find.text(l10n.settings), findsWidgets);
    });
  }
}
