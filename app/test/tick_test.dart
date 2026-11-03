import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/tick.dart';
import 'package:official_news/features/chat/chat_questions.dart';

import 'test_app.dart';

/// The world's stories as ticks (#230 step 4): read from For you's first
/// page, kept with it, and taken by the chat as what it is about.
void main() {
  group('Tick', () {
    test('reads the model\'s headline, its countries, how many outlets and '
        'their latest headlines', () {
      final tick = Tick.fromJson(fakeTick());
      expect(tick.id, 'w1');
      expect(tick.title, "US strikes Iran's Qeshm Island");
      expect(tick.countries, ['US', 'WW']);
      expect(tick.outlets, 3);
      expect(tick.lastSeen, DateTime.utc(2026, 11, 3, 10));
      expect([for (final i in tick.items) i.outlet], ['ABC News', 'BBC World']);
      expect(tick.items.first.url, 'https://example.test/t0');
    });

    test('leaves out a tick with no outlet\'s headline it can show', () {
      final json = fakeTick(outlets: const ['ABC News']);
      expect(Tick.isValid(json), isTrue);
      (json['items'] as List)[0]['url'] = 'javascript:alert(1)';
      expect(Tick.isValid(json), isFalse);
      expect(Tick.isValid({...fakeTick(), 'lastSeen': 'soon'}), isFalse);
      expect(Tick.isValid({...fakeTick(), 'title': null}), isFalse);
    });

    test('keeps what it read', () {
      final tick = Tick.fromJson(fakeTick());
      expect(Tick.fromJson(tick.toJson()).toJson(), tick.toJson());
    });

    test('For you\'s first page brings its ticks, a broken one left out, '
        'and keeps them on the phone', () {
      final page = ArticlesPage.fromJson({
        'items': [],
        'nextCursor': null,
        'top': [],
        'ticks': [
          fakeTick(),
          {...fakeTick(id: 'w2'), 'items': []},
        ],
      });
      expect([for (final t in page.ticks) t.id], ['w1']);
      expect(
        ArticlesPage.fromJson(page.toJson()).ticks.single.toJson(),
        page.ticks.single.toJson(),
      );
      expect(ArticlesPage.fromJson({'items': [], 'top': []}).ticks, isEmpty);
    });
  });

  group('a tick as the chat takes it', () {
    test('its headline, its outlets as its source, their headlines as its '
        'summary and media, and the world as its place', () {
      final l10n = l10nFor();
      final article = Tick.fromJson(fakeTick()).asArticle(l10n);
      expect(article.isTick, isTrue);
      expect(article.isEvent, isFalse);
      expect(article.id, 'w1');
      expect(article.headline, "US strikes Iran's Qeshm Island");
      expect(article.source.name, 'ABC News, BBC World and 1 more');
      expect(article.country, 'WW');
      expect(
        article.summary,
        'ABC News: ABC News: headline 0\nBBC World: BBC World: headline 1',
      );
      expect(article.media.map((m) => m.outlet), ['ABC News', 'BBC World']);
      // Kept with a conversation and read back as a tick.
      expect(Article.fromJson(article.toJson()).isTick, isTrue);
      expect(suggestedQuestions(article, l10n), [
        'What is known?',
        'Why does it matter?',
        'What happens next?',
      ]);
      expect(
        firstQuestionOf(article, l10nFor(FeedLanguage.ru)),
        'Что известно?',
      );
    });

    test('a story\'s page shows its outlets\' headlines where there is no '
        'chat', () {
      final story = Tick.fromJson(fakeTick()).asStory();
      expect(story.aiTitle, isTrue);
      expect(story.items.map((i) => i.title), [
        'ABC News: headline 0',
        'BBC World: headline 1',
      ]);
    });
  });
}
