import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/news_widgets.dart';
import 'package:official_news/core/story.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/story/story_screen.dart';

import 'test_app.dart';

/// A story's page (#230; Roman's variant B, 1 Nov): its country and
/// headline, then each outlet's own headline, which opens the outlet's page,
/// and nothing said about them.
void main() {
  Future<List<Uri>> pumpStory(
    WidgetTester tester, {
    bool aiTitle = true,
    FeedLanguage language = FeedLanguage.ru,
    Brightness brightness = Brightness.light,
  }) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      testApp(
        language: language,
        home: Theme(
          data: buildTheme(brightness),
          child: StoryScreen(
            story: Story.fromJson(
              fakeStory(
                title: 'Бабиш назвал своё правительство',
                aiTitle: aiTitle,
              ),
            ),
            country: 'CZ',
            look: lookFor(FeedDesign.garnet),
            openLink: (uri) async => opened.add(uri),
          ),
        ),
      ),
    );
    return opened;
  }

  testWidgets('the country and the kind, the headline, the AI label, then '
      'one card per outlet with its own headline', (tester) async {
    await pumpStory(tester);
    expect(find.text('ЧЕХИЯ · СЮЖЕТ'), findsOneWidget);
    expect(find.text('Бабиш назвал своё правительство'), findsOneWidget);
    expect(find.text('Заголовок от ИИ'), findsOneWidget);
    for (final (i, outlet) in [
      'ČT24',
      'Seznam Zprávy',
      'iROZHLAS',
      'Deník N',
    ].indexed) {
      await tester.scrollUntilVisible(
        find.text('$outlet: headline $i'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(outlet.toUpperCase()), findsOneWidget);
      expect(find.text('Читать на $outlet'), findsOneWidget);
    }
    // Nothing about the outlets: no "4 outlets on this", no footnote.
    expect(find.textContaining('СМИ'), findsNothing);
  });

  testWidgets('no AI label when the headline is an outlet\'s own', (
    tester,
  ) async {
    await pumpStory(tester, aiTitle: false, language: FeedLanguage.en);
    expect(find.text('CZECHIA · STORY'), findsOneWidget);
    expect(find.text('Headline by AI'), findsNothing);
  });

  testWidgets('an outlet\'s card opens its page', (tester) async {
    final opened = await pumpStory(tester);
    await tester.tap(find.text('ČT24: headline 0'));
    await tester.scrollUntilVisible(
      find.text('Seznam Zprávy: headline 1'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Seznam Zprávy: headline 1'));
    expect(opened, [
      Uri.parse('https://example.test/0'),
      Uri.parse('https://example.test/1'),
    ]);
  });

  testWidgets('VoiceOver reads an outlet\'s card once, as a button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpStory(tester, language: FeedLanguage.en);
    final time = timeAgo(DateTime.utc(2026, 11, 2, 9, 30), l10nFor());
    expect(
      tester.getSemantics(find.text('ČT24: headline 0')),
      matchesSemantics(
        label: 'ČT24: headline 0. ČT24, $time. Read on ČT24',
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('dark, in the look\'s page colour', (tester) async {
    await pumpStory(tester, brightness: Brightness.dark);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFF000000));
    expect(tester.takeException(), isNull);
  });
}
