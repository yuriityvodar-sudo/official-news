import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/story.dart';

import 'test_app.dart';

void main() {
  group('Story', () {
    test('reads each outlet\'s headline, link and time, and the headline '
        'the model wrote', () {
      final story = Story.fromJson(fakeStory());
      expect(story.title, 'Babiš names his government');
      expect(story.aiTitle, isTrue);
      expect(story.lastSeen, DateTime.utc(2026, 11, 2, 9, 30));
      expect(
        [for (final i in story.items) i.outlet],
        ['ČT24', 'Seznam Zprávy', 'iROZHLAS', 'Deník N'],
      );
      expect(story.items.first.url, 'https://example.test/0');
      expect(story.items.first.title, 'ČT24: headline 0');
    });

    test('leaves out an outlet\'s headline without a web link, and a story '
        'with none left', () {
      final json = fakeStory(outlets: const ['ČT24', 'Echo24']);
      (json['items'] as List)[1]['url'] = 'javascript:alert(1)';
      expect(Story.isValid(json), isTrue);
      expect(Story.fromJson(json).items.map((i) => i.outlet), ['ČT24']);

      (json['items'] as List)[0]['url'] = 'ftp://example.test/0';
      expect(Story.isValid(json), isFalse);
      expect(Story.isValid({...fakeStory(), 'lastSeen': 'soon'}), isFalse);
      expect(Story.isValid({...fakeStory(), 'title': null}), isFalse);
    });

    test('a headline the outlets wrote is not the model\'s', () {
      final json = fakeStory()..remove('aiTitle');
      expect(Story.fromJson(json).aiTitle, isFalse);
    });

    test('keeps what it read', () {
      final story = Story.fromJson(fakeStory());
      expect(Story.fromJson(story.toJson()).toJson(), story.toJson());
    });
  });

  test('outletInitials: two words\' first letters, or one word\'s first '
      'two, without a domain\'s ending', () {
    expect(outletInitials('ČT24'), 'ČT');
    expect(outletInitials('Seznam Zprávy'), 'SZ');
    expect(outletInitials('Novinky.cz'), 'NO');
    expect(outletInitials('Deník N'), 'DN');
    expect(outletInitials('iROZHLAS'), 'IR');
    expect(outletInitials('Українська правда'), 'УП');
  });

  test('storyMeta: the country, then the first two outlets and how many '
      'more', () {
    final en = l10nFor();
    final ru = l10nFor(FeedLanguage.ru);
    Story of(List<String> outlets) =>
        Story.fromJson(fakeStory(outlets: outlets));
    expect(storyMeta(of(['ČT24']), 'CZ', en), 'Czechia · ČT24');
    expect(
      storyMeta(of(['ČT24', 'Echo24']), 'CZ', en),
      'Czechia · ČT24, Echo24',
    );
    expect(
      storyMeta(of(['ČT24', 'Seznam Zprávy', 'iROZHLAS', 'Deník N']), 'CZ', en),
      'Czechia · ČT24, Seznam Zprávy and 2 more',
    );
    expect(
      storyMeta(of(['ČT24', 'Seznam Zprávy', 'iROZHLAS']), 'CZ', ru),
      'Чехия · ČT24, Seznam Zprávy и ещё 1',
    );
    expect(storyMeta(of(['ČT24', 'Echo24']), null, en), 'ČT24, Echo24');
  });

  group('ArticlesPage', () {
    test('reads For you\'s stories, leaves out a broken one, and keeps them '
        'on the phone', () {
      final page = ArticlesPage.fromJson({
        'items': <Object>[],
        'nextCursor': null,
        'top': <Object>[],
        'stories': [
          fakeStory(),
          {'id': 'broken'},
          fakeStory(id: 's2', outlets: const ['Echo24']),
        ],
      });
      expect(page.stories.map((s) => s.id), ['s1', 's2']);
      final saved = ArticlesPage.fromJson(page.toJson());
      expect(saved.stories.map((s) => s.toJson()), [
        for (final s in page.stories) s.toJson(),
      ]);
    });

    test('an older server sends no stories', () {
      final page = ArticlesPage.fromJson({
        'items': <Object>[],
        'nextCursor': null,
      });
      expect(page.stories, isEmpty);
    });
  });
}
