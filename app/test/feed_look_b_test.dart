import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_look_b_cards.dart';
import 'package:official_news/features/feed/feed_look_b_words.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// PROTOTYPE (#66), design option B: what its cards promise at any text size.
/// Tests draw text in the FlutterTest font, where every letter is a square as
/// wide as the font size, so long words here are much wider than in Georgia:
/// the checks below hold for whatever font draws the words.

const _long = 'Bundesverfassungsgericht stoppt Verbraucherschutzgesetz';
const _summary =
    'The Chamber of Deputies proposed a bill to restrict government benefits '
    'during election years. It requires financial proof of compliance from '
    'every municipality before the vote.';

Map<String, dynamic> _article(
  String id, {
  String? headline,
  String? summary = _summary,
  String? imageUrl,
  String source = 'Federal Government (Bundesregierung)',
  String type = 'cabinet-decision',
}) => {
  'id': id,
  'country': 'DE',
  'source': {
    'id': 'de-gov',
    'name': source,
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': DateTime.now().toUtc().toIso8601String(),
  'dateOnly': false,
  'headline': headline ?? 'Decision $id',
  'shortSummary': summary,
  'summary': 'Summary $id',
  'decisionType': type,
  'originalTitle': 'Original $id',
  'originalLanguage': 'de',
  'topics': ['economy'],
  'tags': <String>[],
  'importance': 3,
  'imageUrl': imageUrl,
  'originalUrl': 'https://www.bundesregierung.de/$id',
};

ApiClient _api(
  List<Map<String, dynamic>> items, {
  List<Map<String, dynamic>> top = const [],
  List<Map<String, dynamic>> newer = const [],
}) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    final query = request.url.queryParameters;
    final page = query.containsKey('since') || query.containsKey('after')
        ? {'items': newer, 'nextCursor': null, 'top': <Object>[]}
        : {'items': items, 'nextCursor': null, 'top': top};
    return http.Response.bytes(
      utf8.encode(jsonEncode(page)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

/// The words of [finder]'s text that the line breaks inside: each one's
/// letters do not all sit on one line.
List<String> _brokenWords(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final text = paragraph.text.toPlainText();
  // Words of letters: an inline widget (U+FFFC, the seal) sits a little
  // higher than the letters, on the same line.
  final broken = <String>[];
  for (final word in RegExp(r'[^\s\-\uFFFC]+').allMatches(text)) {
    final tops = paragraph
        .getBoxesForSelection(
          TextSelection(baseOffset: word.start, extentOffset: word.end),
        )
        .map((box) => box.top);
    if (tops.reduce(math.max) - tops.reduce(math.min) > 4) {
      broken.add(word.group(0)!);
    }
  }
  return broken;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    analytics = Analytics((name, parameters) async {}, (name, value) async {});
    feedDesign.value = FeedDesign.b;
  });
  tearDown(() {
    analytics = Analytics();
    feedDesign.value = FeedDesign.now;
  });

  /// iPhone 17: 402 x 874 pt, with its notch and home indicator.
  Future<FeedController> pumpFeed(
    WidgetTester tester,
    List<Map<String, dynamic>> items, {
    List<Map<String, dynamic>> top = const [],
    List<Map<String, dynamic>> newer = const [],
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final feed = FeedController(
      api: _api(items, top: top, newer: newer),
    );
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
    return feed;
  }

  // Normal, XXXL (the largest standard size), AX1, AX3 and AX5.
  for (final scale in [1.0, 23 / 17, 28 / 17, 40 / 17, 53 / 17]) {
    final name = scale.toStringAsFixed(2);
    testWidgets('no word is broken between two letters at ${name}x', (
      tester,
    ) async {
      await pumpFeed(
        tester,
        [_article('t1', headline: _long), _article('a1', headline: _long)],
        top: [_article('t1', headline: _long)],
        textScale: scale,
      );
      expect(tester.takeException(), isNull);
      final headlines = find.text(_long);
      expect(headlines, findsWidgets);
      for (final element in headlines.evaluate()) {
        expect(
          _brokenWords(tester, find.byWidget(element.widget)),
          isEmpty,
          reason: 'headline at ${name}x',
        );
      }
      final place = find.textContaining(
        '(Bundesregierung)',
        findRichText: true,
      );
      expect(_brokenWords(tester, place.first), isEmpty, reason: 'ministry');
    });
  }

  testWidgets('the whole ministry shows, on two lines if need be', (
    tester,
  ) async {
    // Two lines in the test font (in SF it is one).
    await pumpFeed(tester, [_article('a1', source: 'Official Gazette (DOF)')]);
    final place = tester.renderObject<RenderParagraph>(
      find.textContaining('(DOF)', findRichText: true).first,
    );
    expect(place.didExceedMaxLines, isFalse);
    expect(place.size.height, greaterThan(13 * 1.3 * 1.5));
  });

  testWidgets('what it means is cut after a whole word, never inside one', (
    tester,
  ) async {
    await pumpFeed(tester, [_article('a1')]);
    final shown = find.textContaining('The Chamber of Deputies');
    expect(shown, findsOneWidget);
    final text = tester.widget<Text>(shown).data!;
    expect(text, isNot(_summary));
    final kept = text.endsWith('…') ? text.substring(0, text.length - 1) : text;
    expect(_summary.startsWith(kept), isTrue, reason: text);
    // The next letter of the summary starts a new word.
    expect(_summary[kept.length], anyOf(' ', ','), reason: text);
    expect(
      tester.renderObject<RenderParagraph>(shown).didExceedMaxLines,
      isFalse,
    );
  });

  test(
    'a cut that leaves a few words of a sentence ends at the one before',
    () {
      String? cut(String text, int lines) => bCutAtWord(
        text,
        style: const TextStyle(fontSize: 10),
        scaler: TextScaler.noScaling,
        maxLines: lines,
        width: 200,
        direction: TextDirection.ltr,
      );
      // 20 letters a line: "The cabinet approved" / "the plan. It also…"
      // would leave two words of the second sentence.
      const text =
          'The cabinet approved the plan. It also set out the next steps.';
      expect(cut(text, 2), 'The cabinet approved the plan.');
      // Cut in the middle of a sentence: after a whole word, with "…".
      expect(cut(text, 1), 'The cabinet…');
      expect(cut('Short.', 2), isNull);
    },
  );

  testWidgets(
    'the new-decisions pill sits under the pinned filters, clear of them',
    (tester) async {
      final feed = await pumpFeed(
        tester,
        [_article('a1')],
        newer: [_article('n1'), _article('n2')],
      );
      await feed.checkForNew();
      await tester.pump();
      await tester.pump();
      final pill = find.text('2 new decisions');
      expect(pill, findsOneWidget);
      final pillBox = tester.getRect(pill);
      // Under the chips, near them (the 44-pt pill's padding and 8 pt).
      final topics = find.text('All topics').hitTestable();
      final chips = tester.getRect(topics);
      expect(pillBox.overlaps(chips), isFalse);
      expect(pillBox.top, greaterThan(chips.bottom));
      expect(pillBox.top - chips.bottom, lessThan(40));

      // Taps elsewhere still reach the feed: the filter opens its menu, and
      // the new decisions still wait.
      await tester.tap(topics);
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoMenuItem), findsWidgets);
      expect(pill, findsOneWidget);
    },
  );

  testWidgets('the gear is level with the filters', (tester) async {
    await pumpFeed(tester, [_article('a1')]);
    final gear = tester.getCenter(
      find.byIcon(CupertinoIcons.gear_alt).hitTestable(),
    );
    final chip = tester.getCenter(find.text('All countries').hitTestable());
    expect((gear.dy - chip.dy).abs(), lessThan(1));
  });

  testWidgets('a card already read says so to VoiceOver', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpFeed(tester, [_article('a1'), _article('a2')]);
    await tester.tap(find.text('Decision a1'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Decision a1'))).value,
      'Read',
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Decision a2'))).value,
      '',
    );
    handle.dispose();
  });

  testWidgets('a picture that cannot be loaded keeps its place', (
    tester,
  ) async {
    // Tests have no pictures: every one fails, as a download can.
    await pumpFeed(tester, [
      _article('a1', imageUrl: 'https://example.test/a1.jpg'),
    ]);
    await tester.pumpAndSettle();
    final card = find.ancestor(
      of: find.text('Decision a1'),
      matching: find.byType(BCard),
    );
    final box = find.descendant(of: card, matching: find.byType(AspectRatio));
    expect(box, findsOneWidget);
    expect(tester.getSize(box).height, closeTo((402 - 32) / 2.4, 0.5));
  });

  test('topics are named in every language, and "read" too', () {
    final article = Article.fromJson(_article('a1'));
    expect(bTopicName(article, l10nFor()), 'Economy');
    expect(bTopicName(article, l10nFor(FeedLanguage.uk)), 'Економіка');
    expect(bTopicName(article, l10nFor(FeedLanguage.de)), 'Wirtschaft');
    for (final language in FeedLanguage.values) {
      for (final id in [
        'foreign-affairs',
        'economy',
        'security-defence',
        'health',
        'climate',
        'trade',
        'technology',
        'energy',
        'migration',
        'elections',
        'human-rights',
        'science',
      ]) {
        final named = Article.fromJson({
          ..._article('a1'),
          'topics': [id],
        });
        expect(bTopicName(named, l10nFor(language)), isNotNull);
      }
    }
    expect(bReadWord(l10nFor(FeedLanguage.uk)), 'Прочитано');
  });

  testWidgets('the large layout starts at the Accessibility sizes', (
    tester,
  ) async {
    bool? large;
    Future<bool> at(double scale) async {
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Builder(
            builder: (context) {
              large = bLargeText(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return large!;
    }

    expect(await at(23 / 17), isFalse, reason: 'XXXL');
    expect(await at(28 / 17), isTrue, reason: 'AX1');
  });
}
