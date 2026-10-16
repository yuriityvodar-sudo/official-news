import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/read_mark.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:official_news/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// PROTOTYPE (Yurii, 16 Oct): Settings > Prototype > Read. Dim fades read
/// articles as before; Blue and Red leave them in their full colours and put
/// a dot on the unread ones instead of the official-source tick, in every
/// design, in Top stories and in Latest.

Map<String, dynamic> _article(String id, {String? imageUrl}) => {
  'id': id,
  'country': 'DE',
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': DateTime.now().toUtc().toIso8601String(),
  'dateOnly': false,
  'headline': 'Decision $id',
  'shortSummary': 'Short summary $id.',
  'summary': 'Summary $id',
  'decisionType': 'cabinet-decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'de',
  'topics': ['economy'],
  'tags': <String>[],
  'importance': 3,
  'imageUrl': imageUrl,
  'originalUrl': 'https://www.bundesregierung.de/$id',
};

/// Top stories t1 (with a picture) to t3, then Latest a1 and a2 (a1 with a
/// picture). t1 and a1 were opened before.
final _top = [
  _article('t1', imageUrl: 'https://example.test/t1.jpg'),
  _article('t2'),
  _article('t3'),
];
final _items = [
  ..._top,
  _article('a1', imageUrl: 'https://example.test/a1.jpg'),
  _article('a2'),
];
const _read = ['t1', 'a1'];
const _unread = ['t2', 't3', 'a2'];

ApiClient _api() => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    final query = request.url.queryParameters;
    final page = query.containsKey('since') || query.containsKey('after')
        ? {'items': <Object>[], 'nextCursor': null, 'top': <Object>[]}
        : {'items': _items, 'nextCursor': null, 'top': _top};
    return http.Response.bytes(
      utf8.encode(jsonEncode(page)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

/// A tall phone, so every article is built without scrolling.
Future<void> _pumpFeed(
  WidgetTester tester, {
  FeedLanguage language = FeedLanguage.en,
}) async {
  tester.view.physicalSize = const Size(390, 3000) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    testApp(
      language: language,
      onGenerateRoute: onGenerateRoute,
      home: FeedScreen(
        controller: FeedController(api: _api()),
        newCheckEvery: const Duration(hours: 1),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// The row or card of the article with [id]: the nearest tap target around
/// its headline, in every design.
Finder _row(String id) => find
    .ancestor(
      of: find.text('Decision $id'),
      matching: find.byType(GestureDetector),
    )
    .first;

/// The dots of [color] inside [of].
Finder _dots(Finder of, Color color) => find.descendant(
  of: of,
  matching: find.byWidgetPredicate(
    (w) =>
        w is DecoratedBox &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle &&
        (w.decoration as BoxDecoration).color?.toARGB32() == color.toARGB32(),
  ),
);

Color? _headlineColor(WidgetTester tester, String id) =>
    tester.widget<Text>(find.text('Decision $id')).style?.color;

/// Where the institution's name starts on the row of [id], from the row's
/// left: the words after the dot, which must not move when it goes.
double _sourceX(WidgetTester tester, String id) {
  final row = _row(id);
  final paragraph = tester
      .renderObjectList<RenderParagraph>(
        find.descendant(of: row, matching: find.byType(RichText)),
      )
      .firstWhere((p) => p.text.toPlainText().contains('Federal Government'));
  final at = paragraph.text.toPlainText().indexOf('Federal Government');
  final caret = paragraph.getOffsetForCaret(
    TextPosition(offset: at),
    Rect.zero,
  );
  return paragraph.localToGlobal(caret).dx - tester.getTopLeft(row).dx;
}

/// The semantics of the article [id]'s card: one VoiceOver stop with the
/// headline as a sentence (C starts a top story's with its number), or, in
/// today's rows, as a line of its own.
SemanticsNode _card(WidgetTester tester, String id) => tester.getSemantics(
  find.bySemanticsLabel(RegExp('(^|\\. |\\n)Decision $id(\\.|\\n)')),
);

/// The colour of the blue dot in the light theme tests use.
final _blue = CupertinoColors.systemBlue.color;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'feed.readIds': _read});
    analytics = Analytics((name, parameters) async {}, (name, value) async {});
  });
  tearDown(() {
    analytics = Analytics();
    feedDesign.value = FeedDesign.now;
    readStyle.value = ReadStyle.dim;
  });

  test('a build names its read style in any case; the preview starts with '
      'the blue dot', () {
    expect(readStyleNamed('dim'), ReadStyle.dim);
    expect(readStyleNamed(' Red '), ReadStyle.red);
    expect(readStyleNamed('blue'), ReadStyle.blue);
    expect(readStyleNamed(''), ReadStyle.blue);
    expect(readStyleNamed('grey'), ReadStyle.blue);
  });

  for (final design in FeedDesign.values) {
    group('design ${design.name}', () {
      setUp(() => feedDesign.value = design);

      for (final (style, color) in [
        (ReadStyle.blue, _blue),
        (ReadStyle.red, AppColors.accent),
      ]) {
        testWidgets('${style.name}: a dot on each unread article instead of '
            'the tick, and read ones in full colour', (tester) async {
          readStyle.value = style;
          await _pumpFeed(tester);
          for (final id in _unread) {
            expect(_dots(_row(id), color), findsOneWidget, reason: id);
          }
          for (final id in _read) {
            expect(_dots(_row(id), color), findsNothing, reason: id);
            // Its words where an unread article's in the same section are:
            // the dot's room is kept.
            final unread = id.startsWith('t') ? 't2' : 'a2';
            expect(_sourceX(tester, id), _sourceX(tester, unread), reason: id);
            // Not faded: the same colour as an unread headline.
            expect(
              _headlineColor(tester, id),
              _headlineColor(tester, 'a2'),
              reason: id,
            );
          }
          expect(find.byIcon(CupertinoIcons.checkmark_seal), findsNothing);
          // Pictures keep their colours too (the tests' pictures fail to
          // load, but the Image keeps the opacity it would draw with).
          for (final image in tester.widgetList<Image>(find.byType(Image))) {
            expect(image.opacity, isNull);
          }
        });
      }

      testWidgets('blue: the dot goes once the article is opened, and the '
          'line keeps its place', (tester) async {
        readStyle.value = ReadStyle.blue;
        await _pumpFeed(tester);
        expect(_dots(_row('a2'), _blue), findsOneWidget);
        final words = _sourceX(tester, 'a2');
        final headline = tester.getTopLeft(find.text('Decision a2'));
        await tester.tap(find.text('Decision a2'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(_dots(_row('a2'), _blue), findsNothing);
        expect(_dots(_row('t2'), _blue), findsOneWidget);
        expect(_sourceX(tester, 'a2'), words);
        expect(tester.getTopLeft(find.text('Decision a2')), headline);
      });

      testWidgets('dim: read articles fade as before, with no dot', (
        tester,
      ) async {
        readStyle.value = ReadStyle.dim;
        await _pumpFeed(tester);
        expect(_dots(find.byType(FeedScreen), _blue), findsNothing);
        expect(_dots(find.byType(FeedScreen), AppColors.accent), findsNothing);
        expect(
          _headlineColor(tester, 't2'),
          isNot(_headlineColor(tester, 't1')),
        );
        expect(
          _headlineColor(tester, 'a2'),
          isNot(_headlineColor(tester, 'a1')),
        );
        // Today's official-source tick, in the designs that have one.
        if (design == FeedDesign.now || design == FeedDesign.b) {
          expect(find.byIcon(CupertinoIcons.checkmark_seal), findsWidgets);
        }
      });
    });
  }

  group('VoiceOver hears "Unread" on articles not opened yet', () {
    for (final design in FeedDesign.values) {
      testWidgets('design ${design.name}', (tester) async {
        feedDesign.value = design;
        readStyle.value = ReadStyle.red;
        final handle = tester.ensureSemantics();
        await _pumpFeed(tester);
        // Today's rows say it after the publisher, where the dot is; the
        // designs' cards after the rest.
        for (final id in [..._read, ..._unread]) {
          final node = _card(tester, id);
          final said = '${node.label} ${node.value}';
          expect(
            said.contains('Unread'),
            _unread.contains(id),
            reason: '$id: $said',
          );
          // Read ones say nothing more: the dot style marks the unread.
          expect(said, isNot(contains('Opened')), reason: id);
          expect(node.value, isNot('Read'), reason: id);
        }
        handle.dispose();
      });
    }

    testWidgets('in Ukrainian', (tester) async {
      feedDesign.value = FeedDesign.b;
      readStyle.value = ReadStyle.blue;
      final handle = tester.ensureSemantics();
      await _pumpFeed(tester, language: FeedLanguage.uk);
      expect(_card(tester, 'a2').value, 'Непрочитане');
      expect(_card(tester, 'a1').value, isEmpty);
      handle.dispose();
    });

    test('the word in every language', () {
      expect(
        {
          for (final lang in FeedLanguage.values)
            lang: l10nFor(lang).feedUnread,
        },
        {
          FeedLanguage.en: 'Unread',
          FeedLanguage.uk: 'Непрочитане',
          FeedLanguage.ru: 'Непрочитанное',
          FeedLanguage.es: 'No leído',
          FeedLanguage.de: 'Ungelesen',
        },
      );
    });
  });

  testWidgets('the Read row in Settings switches the style and goes back to '
      'the feed to show it', (tester) async {
    await _pumpFeed(tester);
    expect(_dots(find.byType(FeedScreen), AppColors.accent), findsNothing);
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
    await tester.pumpAndSettle();
    expect(find.text('Read'), findsOneWidget);
    final control = tester.widget<CupertinoSlidingSegmentedControl<ReadStyle>>(
      find.byType(CupertinoSlidingSegmentedControl<ReadStyle>),
    );
    expect(control.groupValue, ReadStyle.dim);

    await tester.tap(find.text('Red'));
    await tester.pumpAndSettle();
    // Settings closes once the segment has slid over.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(readStyle.value, ReadStyle.red);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(_dots(_row('a2'), AppColors.accent), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dim'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(readStyle.value, ReadStyle.dim);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(_dots(find.byType(FeedScreen), AppColors.accent), findsNothing);
  });
}
