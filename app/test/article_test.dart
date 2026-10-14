import 'package:flutter_test/flutter_test.dart';
import 'package:official_news/core/article.dart';

void main() {
  final full = {
    'id': '01JA2B3C4D5E6F7G8H9J',
    'country': 'PL',
    'source': {
      'id': 'pl-mfa',
      'name': 'Ministry of Foreign Affairs',
      'url': 'https://www.gov.pl/web/dyplomacja',
    },
    'publishedAt': '2026-10-11T14:05:00Z',
    'dateOnly': false,
    'headline': 'Poland condemns attack on Riyadh airport',
    'shortSummary': 'Poland condemned the attack.',
    'summary': 'Poland condemned the attack.',
    'decisionType': 'decision',
    'originalTitle': 'Oświadczenie MSZ ws. ataku w Rijadzie',
    'originalLanguage': 'pl',
    'topics': ['foreign-affairs', 'security-defence'],
    'tags': ['Saudi Arabia'],
    'importance': 4,
    'imageUrl': null,
    'originalUrl':
        'https://www.gov.pl/web/dyplomacja/oswiadczenie-msz-ws-ataku-w-rijadzie',
  };

  test('parses the contract example', () {
    final article = Article.fromJson(full);
    expect(article.headline, 'Poland condemns attack on Riyadh airport');
    expect(article.topics, ['foreign-affairs', 'security-defence']);
    expect(article.decisionType, 'decision');
    expect(article.publishedAt.isUtc, isTrue);
  });

  test('before the AI step, the headline falls back to the original title', () {
    final article = Article.fromJson({
      ...full,
      'headline': null,
      'shortSummary': null,
      'summary': null,
      'decisionType': null,
      'topics': null,
    });
    expect(article.headline, 'Oświadczenie MSZ ws. ataku w Rijadzie');
    expect(article.summary, isNull);
    expect(article.decisionType, isNull);
    expect(article.topics, isEmpty);
  });

  test('a page without top still parses', () {
    final page = ArticlesPage.fromJson({
      'items': [full],
      'nextCursor': null,
    });
    expect(page.items, hasLength(1));
    expect(page.top, isEmpty);
  });
}
