import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/decision_types.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_filters.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:official_news/features/feed/feed_topic_tags.dart';
import 'package:official_news/features/settings/settings_screen.dart';
import 'package:official_news/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// PROTOTYPE (Yurii, 16 Oct): the cards show their topics, not their
/// decision type. In every look: no decision type on a card; up to three
/// topic tags, each with the Topics filter's icon and name; the filtered
/// topic first; no tag row without topics; VoiceOver hears "Topics: …"; the
/// article screen keeps the type. Tags fit, or wrap whole, at 375 pt in
/// Ukrainian and German, also at the largest text sizes.
///
/// Tests draw text in the FlutterTest font, every letter a square as wide as
/// the font size, so names here are much wider than in SF: tags that fit
/// here fit on the phone.

Map<String, dynamic> _article(
  String id, {
  List<String> topics = const ['economy'],
  String type = 'bill',
  int seq = 0,
  String? lang,
  String? imageUrl,
}) => {
  'id': id,
  'country': 'DE',
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': DateTime.now().toUtc().toIso8601String(),
  'dateOnly': false,
  // No decision type's word in it ("Decision" is one).
  'headline': 'Headline $id',
  'shortSummary': 'Short summary $id.',
  'summary': 'Summary $id',
  'decisionType': type,
  'originalTitle': 'Original $id',
  'originalLanguage': 'de',
  'topics': topics,
  'tags': <String>[],
  'importance': 3,
  'imageUrl': imageUrl,
  'originalUrl': 'https://www.bundesregierung.de/$id',
  'feedSeq': seq,
  'lang': ?lang,
};

ApiClient _api(List<Map<String, dynamic>> items) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    final query = request.url.queryParameters;
    final newer = query.containsKey('after') || query.containsKey('since');
    return http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'items': newer ? <Object>[] : items,
          'nextCursor': null,
          'top': <Object>[],
        }),
      ),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

/// The feed in [language] on a phone [width] pt wide and tall enough for
/// every card, at [textScale].
Future<void> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> items, {
  FeedLanguage language = FeedLanguage.en,
  double width = 402,
  double textScale = 1,
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({'feed.lang': language.code});
  tester.view.physicalSize = Size(width, 4000) * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      locale: language.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: onGenerateRoute,
      home: FeedScreen(
        controller: FeedController(api: _api(items)),
        newCheckEvery: const Duration(hours: 1),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// The card of article [id]: the nearest tap target around its headline, in
/// every look.
Finder _card(String id) => find
    .ancestor(
      of: find.text('Headline $id'),
      matching: find.byType(GestureDetector),
    )
    .first;

/// The topic tags on card [id], in the order shown.
List<TopicTag> _tags(WidgetTester tester, String id) => tester
    .widgetList<TopicTag>(
      find.descendant(of: _card(id), matching: find.byType(TopicTag)),
    )
    .toList();

/// The icons the tags on card [id] show, in order.
List<IconData?> _icons(WidgetTester tester, String id) => [
  for (final tag
      in find
          .descendant(of: _card(id), matching: find.byType(TopicTag))
          .evaluate())
    tester
        .widget<Icon>(
          find.descendant(
            of: find.byWidget(tag.widget),
            matching: find.byType(Icon),
          ),
        )
        .icon,
];

/// The paragraph that draws [tag]'s name (its icon is a paragraph too).
RenderParagraph _name(WidgetTester tester, TopicTag tag) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.descendant(
          of: find.byWidget(tag),
          matching: find.byType(Text),
        ),
        matching: find.byType(RichText),
      ),
    );

/// Every decision type's name in [language], in any case: none may be on a
/// card.
RegExp _decisionTypes(FeedLanguage language) => RegExp(
  [
    for (final id in decisionTypes)
      RegExp.escape(decisionTypeLabel(id, l10nFor(language))!),
  ].join('|'),
  caseSensitive: false,
  unicode: true,
);

/// The words of the text in [paragraph] that its lines break inside: each
/// one's letters do not all sit on one line.
List<String> _brokenWords(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  final broken = <String>[];
  for (final word in RegExp(r'[^\s]+').allMatches(text)) {
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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    feedDesign.value = FeedDesign.now;
    topicTagCount.value = maxCardTopics;
  });

  group('a card\'s topics', () {
    final article = Article.fromJson(
      _article('a1', topics: ['economy', 'trade', 'health']),
    );

    test('are the article\'s own, in its order, at most three', () {
      expect(cardTopics(article), ['economy', 'trade', 'health']);
      final four = Article.fromJson(
        _article('a2', topics: ['economy', 'trade', 'health', 'energy']),
      );
      expect(cardTopics(four), ['economy', 'trade', 'health']);
      expect(cardTopics(article, max: 1), ['economy']);
      expect(cardTopics(article, max: 2), ['economy', 'trade']);
    });

    test('start with the topic the feed is filtered by', () {
      expect(cardTopics(article, first: 'health'), [
        'health',
        'economy',
        'trade',
      ]);
      expect(cardTopics(article, first: 'health', max: 1), ['health']);
      // A topic the article does not have is not added.
      expect(cardTopics(article, first: 'energy'), [
        'economy',
        'trade',
        'health',
      ]);
    });

    test('are none for an article without topics; each shows once', () {
      expect(cardTopics(Article.fromJson(_article('a1', topics: []))), []);
      expect(
        cardTopics(
          Article.fromJson(_article('a1', topics: ['trade', 'trade', ''])),
        ),
        ['trade'],
      );
    });

    test('are said as "Topics: …" in every language', () {
      expect(
        spokenTopics(['economy', 'trade'], l10nFor()),
        'Topics: Economy, Trade',
      );
      expect(spokenTopics(['economy'], l10nFor()), 'Topic: Economy');
      expect(
        spokenTopics(['economy', 'trade'], l10nFor(FeedLanguage.uk)),
        'Теми: Економіка, Торгівля',
      );
      expect(
        spokenTopics(['health'], l10nFor(FeedLanguage.uk)),
        'Тема: Здоров’я',
      );
      expect(
        spokenTopics(['economy', 'trade'], l10nFor(FeedLanguage.ru)),
        startsWith('Темы: '),
      );
      expect(
        spokenTopics(['economy', 'trade'], l10nFor(FeedLanguage.es)),
        startsWith('Temas: '),
      );
      expect(
        spokenTopics(['economy', 'trade'], l10nFor(FeedLanguage.de)),
        'Themen: Wirtschaft, Handel',
      );
      expect(spokenTopics([], l10nFor()), isNull);
    });

    test('a build can start with 1, 2 or 3 tags', () {
      expect(topicTagCountNamed('1'), 1);
      expect(topicTagCountNamed(' 2 '), 2);
      expect(topicTagCountNamed('3'), 3);
      expect(topicTagCountNamed(''), 3);
      expect(topicTagCountNamed('0'), 3);
      expect(topicTagCountNamed('5'), 3);
    });
  });

  testWidgets('no topics: no tags, no room for them', (tester) async {
    await tester.pumpWidget(
      testApp(
        home: const Align(
          alignment: Alignment.topLeft,
          child: TopicTags([], color: Color(0xFF6C6C70)),
        ),
      ),
    );
    expect(tester.getSize(find.byType(TopicTags)), Size.zero);
  });

  for (final design in FeedDesign.values) {
    group('design ${design.name}', () {
      setUp(() => feedDesign.value = design);

      testWidgets('cards show no decision type, only up to three topics, '
          'with the filter\'s icons and names', (tester) async {
        await _pump(tester, [
          _article(
            'a1',
            topics: ['economy', 'trade', 'health', 'energy'],
            seq: 3,
          ),
          _article('a2', topics: ['security-defence'], type: 'law', seq: 2),
          _article('a3', topics: [], type: 'cabinet-decision', seq: 1),
        ]);
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining(
            _decisionTypes(FeedLanguage.en),
            findRichText: true,
          ),
          findsNothing,
        );

        expect(
          [for (final t in _tags(tester, 'a1')) t.name],
          ['Economy', 'Trade', 'Health'],
        );
        expect(_icons(tester, 'a1'), [
          topicIcons['economy'],
          topicIcons['trade'],
          topicIcons['health'],
        ]);
        expect(
          [for (final t in _tags(tester, 'a2')) t.name],
          ['Security and defence'],
        );
        expect(_icons(tester, 'a2'), [CupertinoIcons.shield_fill]);
        // Left to right on a line, the way they are read.
        final rects = [
          for (final e
              in find
                  .descendant(of: _card('a1'), matching: find.byType(TopicTag))
                  .evaluate())
            tester.getRect(find.byWidget(e.widget)),
        ];
        for (var i = 1; i < rects.length; i++) {
          final before = rects[i - 1], after = rects[i];
          expect(
            after.top > before.top + 1 || after.left > before.right,
            isTrue,
            reason: '$before, then $after',
          );
        }

        // No topics: no tags at all, so no row and no gap for them.
        expect(_tags(tester, 'a3'), isEmpty);
        expect(
          find.descendant(of: _card('a3'), matching: find.byType(TopicTags)),
          findsNothing,
        );

        // Grey, never red.
        final name = tester.widget<Text>(
          find.descendant(
            of: find.byWidget(_tags(tester, 'a1').first),
            matching: find.byType(Text),
          ),
        );
        final grey = Color(name.style!.color!.toARGB32());
        expect(grey, const Color(0xFF6C6C70));
      });

      testWidgets('the filtered topic comes first', (tester) async {
        // Wide enough for C's chips, which slide sideways in the test font.
        await _pump(tester, [
          _article('a1', topics: ['economy', 'trade', 'health'], seq: 2),
          _article('a2', topics: ['trade'], seq: 1),
        ], width: 700);
        await tester.tap(
          find.byKey(const ValueKey('filter-topic')).hitTestable(),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(CupertinoMenuItem),
            matching: find.text('Health'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          [for (final t in _tags(tester, 'a1')) t.name],
          ['Health', 'Economy', 'Trade'],
        );
        expect(find.text('Headline a2'), findsNothing);
      });

      testWidgets('one or two tags when the prototype says so', (tester) async {
        topicTagCount.value = 1;
        await _pump(tester, [
          _article('a1', topics: ['economy', 'trade', 'health']),
        ]);
        expect([for (final t in _tags(tester, 'a1')) t.name], ['Economy']);
        topicTagCount.value = 2;
        await tester.pump();
        expect(
          [for (final t in _tags(tester, 'a1')) t.name],
          ['Economy', 'Trade'],
        );
      });

      testWidgets('VoiceOver hears the topics on the card', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, [
          _article('a1', topics: ['economy', 'trade'], seq: 2),
          _article('a2', topics: [], seq: 1),
        ]);
        final card = tester.getSemantics(
          find.bySemanticsLabel(RegExp('Headline a1')),
        );
        expect(card.label, contains('Topics: Economy, Trade'));
        // Said once, not also tag by tag.
        expect(
          RegExp('Economy').allMatches(card.label).length,
          1,
          reason: card.label,
        );
        final bare = tester.getSemantics(
          find.bySemanticsLabel(RegExp('Headline a2')),
        );
        expect(bare.label, isNot(contains('Topic')));
        handle.dispose();
      });

      testWidgets('VoiceOver hears them in Ukrainian', (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, [
          _article('a1', topics: ['economy', 'trade'], lang: 'uk'),
        ], language: FeedLanguage.uk);
        expect(
          tester
              .getSemantics(find.bySemanticsLabel(RegExp('Headline a1')))
              .label,
          contains('Теми: Економіка, Торгівля'),
        );
        handle.dispose();
      });

      testWidgets('the article screen still shows the decision type', (
        tester,
      ) async {
        await _pump(tester, [
          _article('a1', topics: ['economy']),
        ]);
        expect(find.text('BILL'), findsNothing);
        await tester.tap(find.text('Headline a1'));
        await tester.pumpAndSettle();
        expect(find.text('BILL'), findsOneWidget);
      });

      testWidgets('in dark mode the tags are grey on a quiet fill', (
        tester,
      ) async {
        await _pump(tester, [
          _article('a1', topics: ['economy']),
        ], brightness: Brightness.dark);
        final text = tester.widget<Text>(
          find.descendant(
            of: find.byType(TopicTag),
            matching: find.byType(Text),
          ),
        );
        expect(Color(text.style!.color!.toARGB32()), const Color(0xFF98989F));
      });

      // 375 pt (iPhone SE, mini), at the normal size, the largest standard
      // one (XXXL) and the largest Accessibility size (AX5).
      for (final language in [FeedLanguage.uk, FeedLanguage.de]) {
        for (final scale in [1.0, 23 / 17, 53 / 17]) {
          testWidgets('tags fit or wrap whole at 375 pt in ${language.code} at '
              '${scale.toStringAsFixed(2)}x', (tester) async {
            await _pump(
              tester,
              [
                _article(
                  'a1',
                  topics: [
                    'security-defence',
                    'foreign-affairs',
                    'human-rights',
                  ],
                  lang: language.code,
                  seq: 2,
                ),
                _article(
                  'a2',
                  topics: ['technology', 'elections', 'migration'],
                  lang: language.code,
                  seq: 1,
                ),
              ],
              language: language,
              width: 375,
              textScale: scale,
            );
            expect(tester.takeException(), isNull);
            final l10n = l10nFor(language);
            for (final id in ['a1', 'a2']) {
              final tags = _tags(tester, id);
              expect(tags, hasLength(3));
              final row = tester.getRect(
                find.descendant(
                  of: _card(id),
                  matching: find.byType(TopicTags),
                ),
              );
              final shown = <Rect>[];
              for (final tag in tags) {
                expect(tag.name, topicName(tag.id, l10n));
                final box = tester.getRect(find.byWidget(tag));
                // Inside the row and the screen, over no other tag.
                expect(box.left, greaterThanOrEqualTo(row.left - 0.5));
                expect(box.right, lessThanOrEqualTo(row.right + 0.5));
                expect(box.right, lessThanOrEqualTo(375));
                for (final other in shown) {
                  expect(box.overlaps(other), isFalse, reason: tag.name);
                }
                shown.add(box);
                // The whole name, never cut and never broken in a word.
                final paragraph = _name(tester, tag);
                expect(paragraph.text.toPlainText(), tag.name);
                expect(paragraph.didExceedMaxLines, isFalse);
                expect(
                  _brokenWords(paragraph),
                  isEmpty,
                  reason: '${tag.name} at ${scale}x',
                );
                // Its text inside its fill.
                final text =
                    paragraph.localToGlobal(Offset.zero) & paragraph.size;
                expect(text.right, lessThanOrEqualTo(box.right + 0.5));
                expect(text.bottom, lessThanOrEqualTo(box.bottom + 0.5));
              }
            }
          });
        }
      }
    });
  }

  // Narrower than any tag row gets on a 375-pt phone (C's text column, the
  // narrowest, is 287 pt; Now and A give the tags the whole row, beside no
  // picture): the tags alone, with a time after them, still wrap whole.
  for (final language in [FeedLanguage.uk, FeedLanguage.de]) {
    for (final scale in [1.0, 23 / 17, 53 / 17]) {
      testWidgets('the longest names wrap whole in 237 pt in ${language.code} '
          'at ${scale.toStringAsFixed(2)}x', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final ids = ['security-defence', 'foreign-affairs', 'human-rights'];
        await tester.pumpWidget(
          testApp(
            language: language,
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 237,
                child: TopicTags(
                  ids,
                  color: const Color(0xFF6C6C70),
                  trailing: const Text('5 хв тому'),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        for (final e in find.byType(TopicTag).evaluate()) {
          final tag = e.widget as TopicTag;
          final box = tester.getRect(find.byWidget(tag));
          expect(box.right, lessThanOrEqualTo(237.5), reason: tag.name);
          final paragraph = _name(tester, tag);
          expect(_brokenWords(paragraph), isEmpty, reason: tag.name);
          expect(paragraph.text.toPlainText(), tag.name);
        }
      });
    }
  }

  testWidgets('the Topics row in Settings switches 1, 2 or 3 tags and goes '
      'back to the feed to show it', (tester) async {
    feedDesign.value = FeedDesign.b;
    await _pump(tester, [
      _article('a1', topics: ['economy', 'trade', 'health']),
    ]);
    expect(_tags(tester, 'a1'), hasLength(3));
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt).hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Topics'), findsOneWidget);
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    // Settings closes once the segment has slid over.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(topicTagCount.value, 1);
    expect(find.byType(SettingsScreen), findsNothing);
    expect([for (final t in _tags(tester, 'a1')) t.name], ['Economy']);
  });
}
