import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yurii, 16 Oct: the feed is one list. The server still sends its top
/// stories; the app puts them among the rest, each article once, in the order
/// the articles arrived in the feed ([oneFeed], [FeedController.feed]).

final _now = DateTime.utc(2026, 10, 16, 12);

Map<String, dynamic> _json(String id, {int? feedSeq, DateTime? addedAt}) => {
  'id': id,
  'feedSeq': feedSeq,
  'addedAt': addedAt?.toIso8601String(),
  'country': 'DE',
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': _now.toIso8601String(),
  'dateOnly': false,
  'headline': 'Decision $id',
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
};

Article _a(String id, {int? feedSeq, DateTime? addedAt}) =>
    Article.fromJson(_json(id, feedSeq: feedSeq, addedAt: addedAt));

List<String> _ids(List<Article> articles) => [for (final a in articles) a.id];

void main() {
  group('oneFeed', () {
    test('an article in both the top stories and the items is there once', () {
      final feed = oneFeed(
        top: [_a('t1', feedSeq: 4), _a('t2', feedSeq: 2)],
        items: [
          _a('a1', feedSeq: 5),
          _a('t1', feedSeq: 4),
          _a('a2', feedSeq: 3),
          _a('t2', feedSeq: 2),
        ],
        complete: true,
      );
      expect(_ids(feed), ['a1', 't1', 'a2', 't2']);
    });

    test('ordered by feedSeq, newest first, however the lists come', () {
      final feed = oneFeed(
        top: [_a('t9', feedSeq: 9), _a('t3', feedSeq: 3)],
        items: [
          _a('a2', feedSeq: 2),
          _a('a7', feedSeq: 7),
          _a('t3', feedSeq: 3),
          _a('a10', feedSeq: 10),
        ],
        complete: true,
      );
      expect(_ids(feed), ['a10', 't9', 'a7', 't3', 'a2']);
    });

    test('articles without a feedSeq come after, by addedAt, newest first; '
        'without either, as the server listed them', () {
      final feed = oneFeed(
        top: [_a('top-old', addedAt: _now.subtract(const Duration(days: 2)))],
        items: [
          _a('plain1'),
          _a('added-old', addedAt: _now.subtract(const Duration(days: 1))),
          _a('seq1', feedSeq: 1),
          _a('plain2'),
          _a('added-new', addedAt: _now),
        ],
        complete: true,
      );
      expect(_ids(feed), [
        'seq1',
        'added-new',
        'added-old',
        'top-old',
        'plain1',
        'plain2',
      ]);
    });

    test('while more pages are to come, a top story older than the last '
        'article loaded waits for its page', () {
      final top = [_a('t8', feedSeq: 8), _a('t2', feedSeq: 2)];
      final page1 = [
        _a('a9', feedSeq: 9),
        _a('t8', feedSeq: 8),
        _a('a5', feedSeq: 5),
      ];
      expect(_ids(oneFeed(top: top, items: page1, complete: false)), [
        'a9',
        't8',
        'a5',
      ]);
      // The last page: nothing more to wait for.
      expect(_ids(oneFeed(top: top, items: page1, complete: true)), [
        'a9',
        't8',
        'a5',
        't2',
      ]);
    });

    test('a top story not in the items yet but newer than the last one '
        'loaded is shown at once, in its place', () {
      final feed = oneFeed(
        top: [_a('t6', feedSeq: 6)],
        items: [_a('a9', feedSeq: 9), _a('a5', feedSeq: 5)],
        complete: false,
      );
      expect(_ids(feed), ['a9', 't6', 'a5']);
    });

    test('empty lists make an empty feed', () {
      expect(oneFeed(top: const [], items: const [], complete: true), isEmpty);
      expect(_ids(oneFeed(top: [_a('t1')], items: const [], complete: false)), [
        't1',
      ]);
    });
  });

  group('FeedController.feed', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    /// Page 1 (a40 to a21) with its top stories a30 and a15, page 2 (a20 to
    /// a1). Once [newest] is 42, the new check finds a42 and a41, and the
    /// first page starts with them.
    var newest = 40;
    setUp(() => newest = 40);
    FeedController controller() => FeedController(
      api: ApiClient(
        baseUrl: 'https://api.test',
        client: MockClient((request) async {
          final query = request.url.queryParameters;
          Map<String, dynamic> page(int from, int to, String? next) => {
            'items': [
              for (var i = from; i >= to; i--) _json('a$i', feedSeq: i),
            ],
            'nextCursor': next,
            'top': query.containsKey('cursor') || query.containsKey('after')
                ? []
                : [_json('a30', feedSeq: 30), _json('a15', feedSeq: 15)],
          };
          final body = query.containsKey('after')
              ? page(newest, int.parse(query['after']!) + 1, null)
              : query['cursor'] == 'c2'
              ? page(20, 1, null)
              : page(newest, 21, 'c2');
          return http.Response(jsonEncode(body), 200);
        }),
      ),
    );

    test('loading more only adds to the end, each article once', () async {
      final feed = controller();
      await feed.start();
      final first = _ids(feed.feed);
      expect(first, [for (var i = 40; i >= 21; i--) 'a$i']);
      await feed.loadMore();
      expect(_ids(feed.feed).take(first.length), first);
      expect(_ids(feed.feed), [for (var i = 40; i >= 1; i--) 'a$i']);
    });

    test('the new check counts only what arrived after the newest shown, '
        'and a refresh puts it at the top', () async {
      final feed = controller();
      await feed.start();
      await feed.checkForNew();
      expect(feed.newCount, 0);
      newest = 42;
      await feed.checkForNew();
      expect(feed.newCount, 2);
      await feed.refresh();
      expect(feed.newCount, 0);
      expect(_ids(feed.feed).take(3), ['a42', 'a41', 'a40']);
      expect(_ids(feed.feed).where((id) => id == 'a30'), hasLength(1));
    });
  });
}
