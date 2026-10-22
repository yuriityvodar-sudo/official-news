import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// The one list (Yurii, 16 Oct) on the live API's own answers, saved on
/// 16 Oct at 23:26 (Berlin) in `test/fixtures/`: `GET /articles` (page 1,
/// feedSeq 209 to 190, top stories 209, 181, 175, 173 and 171) and its next
/// page, `GET /articles?cursor=WzE5MF0` (feedSeq 189 to 170). Four of the
/// five top stories are on page 2; each must show once, in its place, and
/// page 2 must only add to the end of the list.

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

final _page1 = _fixture('live_2026-10-16_page1.json');
final _page2 = _fixture('live_2026-10-16_page2.json');

/// The live answers by cursor. Page 2's own next page was not saved: asking
/// for it fails, as offline, and the end of the list offers a retry.
ApiClient _liveApi(List<String> asked) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    final menu = fakeMenus(request);
    if (menu != null) return menu;
    final cursor = request.url.queryParameters['cursor'] ?? '';
    asked.add(cursor);
    final page = switch (cursor) {
      '' => _page1,
      'WzE5MF0' => _page2,
      _ => null,
    };
    return page == null
        ? http.Response('{"error":"Internal error"}', 500)
        : http.Response.bytes(
            utf8.encode(jsonEncode(page)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
  }),
);

List<int> _seqs(Map<String, dynamic> page, String key) => [
  for (final a in page[key] as List) (a as Map)['feedSeq'] as int,
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => feedDesign.value = FeedDesign.now);

  test('the saved pages are what the review saw', () {
    expect(_seqs(_page1, 'items'), [for (var s = 209; s >= 190; s--) s]);
    expect(_seqs(_page1, 'top'), [209, 181, 175, 173, 171]);
    expect(_page1['nextCursor'], 'WzE5MF0');
    expect(_seqs(_page2, 'items'), [for (var s = 189; s >= 170; s--) s]);
  });

  for (final design in FeedDesign.values) {
    testWidgets('design ${design.name}: the live pages make one list, '
        '209 down to 170, each top story once', (tester) async {
      feedDesign.value = design;
      tester.view.physicalSize = const Size(393, 852) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final asked = <String>[];
      final feed = FeedController(api: _liveApi(asked));
      await tester.pumpWidget(
        testApp(
          onGenerateRoute: onGenerateRoute,
          home: FeedScreen(
            controller: feed,
            newCheckEvery: const Duration(hours: 1),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Page 1: its own articles only; 181, 175, 173 and 171 wait for page 2.
      final first = [for (final a in feed.feed) a.feedSeq!];
      expect(first, [for (var s = 209; s >= 190; s--) s]);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(asked.take(2), ['', 'WzE5MF0']);
      final all = [for (final a in feed.feed) a.feedSeq!];
      expect(all, [for (var s = 209; s >= 170; s--) s]);
      expect(all.take(first.length), first, reason: 'page 2 only appends');
      for (final top in [209, 181, 175, 173, 171]) {
        expect(all.where((s) => s == top), hasLength(1), reason: '$top');
      }

      // On screen too: 181, a top story from page 2, between 182 and 180
      // (laid out, if just off the screen). Found by the headline's start:
      // A cuts a headline at a whole word, and 180's live headline came
      // already cut ("…Programa Nacional de…").
      String start(int seq) {
        final h = feed.feed.singleWhere((a) => a.feedSeq == seq).headline;
        return h.length > 40 ? h.substring(0, 40) : h;
      }

      Finder row(int seq) => find.textContaining(
        start(seq),
        findRichText: true,
        skipOffstage: false,
      );
      double y(int seq) => tester.getTopLeft(row(seq).first).dy;

      // From the top (a jump, not a pull: a pull would refresh to page 1).
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pump();
      final row181 = find.textContaining(start(181), findRichText: true);
      await tester.scrollUntilVisible(
        row181,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // In the middle of the screen, so the rows around it are laid out.
      await Scrollable.ensureVisible(
        tester.element(row181.first),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      expect(y(182), lessThan(y(181)));
      expect(y(181), lessThan(y(180)));
    });
  }
}
