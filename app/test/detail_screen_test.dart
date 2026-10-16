import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/detail/detail_screen.dart';

Article _article({
  String? headline = 'Germany\'s cabinet approves the 2027 draft budget',
  String? summary =
      'The federal cabinet approved the draft budget for 2027.\n\nThe Bundestag now debates it.',
  String language = 'de',
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
});

Future<void> _pump(
  WidgetTester tester,
  Article article, {
  OpenLink? openLink,
  ShareArticle? share,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: DetailScreen(
        article: article,
        openLink: openLink ?? (_) async {},
        share: share ?? (_, _) async {},
      ),
    ),
  );
}

void main() {
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
    final shared = <Article>[];
    await _pump(
      tester,
      _article(),
      share: (article, _) async => shared.add(article),
    );

    await tester.tap(find.byIcon(CupertinoIcons.share));
    expect(shared.single.id, 'a1');
  });
}
