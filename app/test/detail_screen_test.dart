import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/features/detail/detail_screen.dart';

import 'test_app.dart';

Article _article({
  String? headline = 'Germany\'s cabinet approves the 2027 draft budget',
  String? summary =
      'The federal cabinet approved the draft budget for 2027.\n\nThe Bundestag now debates it.',
  String language = 'de',
  String? lang,
  bool dateOnly = false,
  String? imageUrl,
  String originalUrl =
      'https://www.bundesregierung.de/breg-de/aktuelles/haushalt-2027',
}) => Article.fromJson({
  'id': 'a1',
  'country': 'DE',
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': DateTime(2026, 10, 14, 11, 30).toUtc().toIso8601String(),
  'dateOnly': dateOnly,
  'headline': headline,
  'shortSummary': 'The cabinet approved the 2027 draft budget.',
  'summary': summary,
  'decisionType': 'cabinet-decision',
  'originalTitle': 'Kabinett beschließt Haushaltsentwurf 2027',
  'originalLanguage': language,
  'topics': ['economy'],
  'tags': ['Germany'],
  'importance': 4,
  'imageUrl': imageUrl,
  'originalUrl': originalUrl,
  'lang': lang,
});

Future<void> _pump(
  WidgetTester tester,
  Article article, {
  OpenLink? openLink,
  ShareArticle? share,
  FeedLanguage language = FeedLanguage.en,
}) async {
  await tester.pumpWidget(
    testApp(
      language: language,
      home: DetailScreen(
        article: article,
        openLink: openLink ?? (_) async {},
        share: share ?? (_, _, _) async {},
      ),
    ),
  );
}

void main() {
  testWidgets('the status bar has dark words on the page again once a sheet '
      'over the article has gone (the paywall leaves light ones)', (
    tester,
  ) async {
    await _pump(tester, _article());
    await tester.pump();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      CupertinoSheetRoute<void>(
        scrollableBuilder: (_, _) => const Text('Sheet'),
      ),
    );
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.dark);
  });

  testWidgets(
    'shows the ministry, decision, date, AI label and the summary paragraphs',
    (tester) async {
      await _pump(tester, _article());

      expect(find.text('Federal Government'), findsOneWidget);
      expect(find.text('Germany · '), findsOneWidget);
      expect(find.text('Official source'), findsOneWidget);
      expect(find.text('CABINET DECISION'), findsOneWidget);
      expect(
        find.text("Germany's cabinet approves the 2027 draft budget"),
        findsOneWidget,
      );
      expect(find.text('14 October 2026, 11:30'), findsOneWidget);
      expect(
        find.text('Summary by AI · translated from German'),
        findsOneWidget,
      );
      expect(
        find.text('The federal cabinet approved the draft budget for 2027.'),
        findsOneWidget,
      );
      expect(find.text('The Bundestag now debates it.'), findsOneWidget);
      expect(find.text('Read the official decision'), findsOneWidget);
      expect(
        find.text(
          'bundesregierung.de · Kabinett beschließt Haushaltsentwurf 2027',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'says "Summary by AI" without a translation note for English sources',
    (tester) async {
      await _pump(tester, _article(language: 'en'));
      expect(find.text('Summary by AI'), findsOneWidget);
    },
  );

  // The note is about the text the reader sees: in the Russian feed, a Russian
  // source has none, an English or German one says where it came from.
  testWidgets('in a translated feed, the note compares the source with it', (
    tester,
  ) async {
    for (final (source, label) in [
      ('ru', 'Краткое изложение от ИИ'),
      ('en', 'Краткое изложение от ИИ · перевод с английского'),
      ('de', 'Краткое изложение от ИИ · перевод с немецкого'),
    ]) {
      await _pump(
        tester,
        _article(language: source, lang: 'ru'),
        language: FeedLanguage.ru,
      );
      expect(find.text(label), findsOneWidget, reason: source);
    }
  });

  testWidgets('shows only the day when the source gave no time', (
    tester,
  ) async {
    await _pump(tester, _article(dateOnly: true));
    expect(find.text('14 October 2026'), findsOneWidget);
  });

  testWidgets(
    'before the AI step: the original title and a note instead of the summary',
    (tester) async {
      await _pump(tester, _article(headline: null, summary: null));

      expect(
        find.text('Kabinett beschließt Haushaltsentwurf 2027'),
        findsOneWidget,
      );
      expect(
        find.textContaining('The AI summary is on its way'),
        findsOneWidget,
      );
      expect(find.textContaining('Summary by AI'), findsNothing);
    },
  );

  testWidgets('shows the picture with where it comes from', (tester) async {
    await _pump(
      tester,
      _article(imageUrl: 'https://www.bundesregierung.de/image.jpg'),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Image: bundesregierung.de'), findsOneWidget);
  });

  testWidgets('opens the official page', (tester) async {
    final opened = <Uri>[];
    await _pump(tester, _article(), openLink: (uri) async => opened.add(uri));

    await tester.tap(find.text('Read the official decision'));
    expect(opened, [
      Uri.parse(
        'https://www.bundesregierung.de/breg-de/aktuelles/haushalt-2027',
      ),
    ]);
  });

  testWidgets('opens the page without the bill-stage fragment', (tester) async {
    final opened = <Uri>[];
    await _pump(
      tester,
      _article(
        originalUrl:
            'https://www.parl.ca/legisinfo/en/bill/45-1/C-37#2026-10-09',
      ),
      openLink: (uri) async => opened.add(uri),
    );

    await tester.tap(find.text('Read the official decision'));
    expect(opened, [
      Uri.parse('https://www.parl.ca/legisinfo/en/bill/45-1/C-37'),
    ]);
  });

  test('officialPage keeps only web pages and drops the fragment', () {
    expect(
      officialPage('https://sansad.in/ls/bill#Lok%20Sabha-153-Passed'),
      Uri.parse('https://sansad.in/ls/bill'),
    );
    expect(officialPage('javascript:alert(1)'), isNull);
    expect(officialPage('mailto:press@gov.example'), isNull);
  });

  testWidgets('never opens a link that is not a web page', (tester) async {
    final opened = <Uri>[];
    await _pump(
      tester,
      _article(originalUrl: 'javascript:alert(1)'),
      openLink: (uri) async => opened.add(uri),
    );

    await tester.tap(find.text('Read the official decision'));
    expect(opened, isEmpty);
  });

  testWidgets('shares the article', (tester) async {
    final shared = <(Article, String)>[];
    await _pump(
      tester,
      _article(),
      share: (article, text, _) async => shared.add((article, text)),
    );

    await tester.tap(find.byIcon(CupertinoIcons.share));
    expect(shared.single.$1.id, 'a1');
    expect(
      shared.single.$2,
      "Germany's cabinet approves the 2027 draft budget\n\n"
      'The cabinet approved the 2027 draft budget.\n\n'
      'Official source: '
      'https://www.bundesregierung.de/breg-de/aktuelles/haushalt-2027',
    );
  });

  // #52: the article screen in the app's language; the article's own text is
  // as the feed has it (here English, as the test article is).
  testWidgets('shows its labels, dates and country in Ukrainian', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final shared = <String>[];
    await _pump(
      tester,
      _article(imageUrl: 'https://www.bundesregierung.de/image.jpg'),
      language: FeedLanguage.uk,
      share: (_, text, _) async => shared.add(text),
    );

    expect(find.text('Німеччина · '), findsOneWidget);
    expect(find.text('Офіційне джерело'), findsOneWidget);
    expect(find.text('РІШЕННЯ УРЯДУ'), findsOneWidget);
    expect(find.text('14 жовтня 2026\u202Fр. о 11:30'), findsOneWidget);
    expect(find.text('Зображення: bundesregierung.de'), findsOneWidget);
    expect(find.bySemanticsLabel('Поширити'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.share));
    expect(
      shared.single,
      endsWith(
        '\n\nОфіційне джерело: '
        'https://www.bundesregierung.de/breg-de/aktuelles/haushalt-2027',
      ),
    );

    // Below the picture: built when scrolled to.
    final label = find.text('Стислий виклад від ШІ · переклад з німецької');
    await tester.scrollUntilVisible(label, 200);
    expect(label, findsOneWidget);
    final link = find.text('Читати офіційне рішення');
    await tester.scrollUntilVisible(link, 200);
    expect(link, findsOneWidget);
    expect(
      find.bySemanticsLabel('Читати офіційне рішення на bundesregierung.de'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('says where the summary was translated from in each language', (
    tester,
  ) async {
    for (final (language, label) in [
      (FeedLanguage.ru, 'Краткое изложение от ИИ · перевод с немецкого'),
      (FeedLanguage.es, 'Resumido por IA · traducido del alemán'),
      (FeedLanguage.de, 'KI-Zusammenfassung · aus dem Deutschen übersetzt'),
    ]) {
      await _pump(tester, _article(), language: language);
      expect(find.text(label), findsOneWidget, reason: language.code);
    }
    await _pump(tester, _article(dateOnly: true), language: FeedLanguage.de);
    expect(find.text('14. Oktober 2026'), findsOneWidget);
    await _pump(tester, _article(), language: FeedLanguage.es);
    expect(find.text('14 de octubre de 2026, 11:30'), findsOneWidget);
  });
}
