import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/story.dart';
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
    test('its headline, also as its summary, its outlets as its source, '
        'their headlines as its media, and the world as its place', () {
      final l10n = l10nFor();
      final article = Tick.fromJson(fakeTick()).asArticle(l10n);
      expect(article.isTick, isTrue);
      expect(article.isEvent, isFalse);
      expect(article.id, 'w1');
      expect(article.headline, "US strikes Iran's Qeshm Island");
      expect(article.source.name, 'ABC News, BBC World and 1 more');
      expect(article.country, 'WW');
      // In the reader's language, as the paywall and the demo show it.
      expect(article.summary, "US strikes Iran's Qeshm Island");
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

    test('its card\'s first line: the world and how many countries, its '
        'own outlets counted as one', () {
      final l10n = l10nFor();
      expect(tickMeta(Tick.fromJson(fakeTick()), l10n), 'World · 2 countries');
      expect(
        tickMeta(Tick.fromJson(fakeTick()), l10nFor(FeedLanguage.ru)),
        'Мир · 2 страны',
      );
      expect(
        tickSpoken(Tick.fromJson(fakeTick()), l10n),
        startsWith("US strikes Iran's Qeshm Island. World, 2 countries. "),
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

  group('a story of a country\'s outlets as the chat takes it', () {
    test('its headline, also as its summary, its outlets as its source, '
        'their headlines as its media, and its country as its place', () {
      final l10n = l10nFor();
      final article = Story.fromJson(fakeStory()).asArticle(l10n, 'CZ');
      expect(article.isMediaStory, isTrue);
      expect(article.isMedia, isTrue);
      expect(article.isTick, isFalse);
      expect(article.isStory, isFalse);
      expect(article.id, 's1');
      expect(article.country, 'CZ');
      expect(article.headline, 'Babiš names his government');
      expect(article.summary, 'Babiš names his government');
      expect(article.source.name, 'ČT24, Seznam Zprávy and 2 more');
      expect(article.media.map((m) => m.outlet).first, 'ČT24');
      expect(Article.fromJson(article.toJson()).isMediaStory, isTrue);
      expect(Article.fromJson(article.toJson()).country, 'CZ');
      expect(suggestedQuestions(article, l10n), [
        'What is known?',
        'Why does it matter?',
        'What happens next?',
      ]);
    });
  });
}
