import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/glass.dart';
import 'package:official_news/features/detail/detail_screen.dart';

import 'test_app.dart';

Article _article({String? summary = 'First part.\n\nSecond part.'}) =>
    Article.fromJson({
      'id': 'a1',
      'country': 'DE',
      'source': {
        'id': 'de-gov',
        'name': 'Federal Government',
        'url': 'https://www.bundesregierung.de',
      },
      'publishedAt': DateTime(2026, 10, 14, 11, 30).toUtc().toIso8601String(),
      'dateOnly': false,
      'headline': 'Cabinet approves the 2027 draft budget',
      'shortSummary': 'The cabinet approved the draft budget.',
      'summary': summary,
      'decisionType': 'cabinet-decision',
      'originalTitle': 'Kabinett beschließt Haushaltsentwurf 2027',
      'originalLanguage': 'de',
      'topics': ['economy'],
      'tags': <String>[],
      'importance': 4,
      'imageUrl': 'https://www.bundesregierung.de/picture.jpg',
      'originalUrl': 'https://www.bundesregierung.de/budget',
    });

/// The article opened from a page under it, so it has a way back.
Future<void> _open(
  WidgetTester tester,
  Article article, {
  ShareArticle? share,
}) async {
  await tester.pumpWidget(
    testApp(
      home: Builder(
        builder: (context) => CupertinoButton(
          onPressed: () => Navigator.of(context).push(
            CupertinoPageRoute<void>(
              builder: (_) => DetailScreen(
                article: article,
                openLink: (_) async {},
                share: share ?? (_, _, _) async {},
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

double _scaleOf(WidgetTester tester, IconData icon) => tester
    .widget<AnimatedScale>(
      find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(AnimatedScale),
      ),
    )
    .scale;

void main() {
  testWidgets('back and share float on Liquid Glass over the text', (
    tester,
  ) async {
    var shared = 0;
    await _open(tester, _article(), share: (_, _, _) async => shared++);
    expect(find.byType(CupertinoNavigationBar), findsNothing);
    expect(
      find.ancestor(
        of: find.byIcon(CupertinoIcons.share),
        matching: find.byType(GlassCircle),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(CupertinoIcons.share));
    expect(shared, 1);

    // Named for VoiceOver, never shown.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('no back button when there is nothing to go back to', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(home: DetailScreen(article: _article())));
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byIcon(CupertinoIcons.share), findsOneWidget);
  });

  testWidgets('the buttons get smaller while scrolling down, back as it '
      'scrolls up', (tester) async {
    await _open(
      tester,
      _article(summary: List.filled(30, 'Long.').join('\n\n')),
    );
    expect(_scaleOf(tester, CupertinoIcons.share), 1);

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(_scaleOf(tester, CupertinoIcons.share), lessThan(1));

    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(_scaleOf(tester, CupertinoIcons.share), 1);
  });

  testWidgets('"Discuss with AI" says the chat is coming and counts the tap', (
    tester,
  ) async {
    final sent = <String>[];
    analytics = Analytics((name, _) async => sent.add(name));
    addTearDown(() => analytics = Analytics());

    await _open(tester, _article());
    await tester.scrollUntilVisible(find.text('Discuss with AI'), 100);
    expect(find.text('Beta'), findsOneWidget);
    await tester.tap(find.text('Discuss with AI'));
    await tester.pumpAndSettle();

    expect(sent, contains('discuss_ai_tap'));
    expect(find.text('Coming soon'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Coming soon'), findsNothing);
  });

  testWidgets('no "Discuss with AI" before the summary is written', (
    tester,
  ) async {
    await _open(tester, _article(summary: null));
    expect(find.text('Discuss with AI'), findsNothing);
  });
}
