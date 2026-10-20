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
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// PROTOTYPE (Yurii, 16 Oct): Settings > Prototype > Read. Dim fades read
/// articles as before; Blue and Red leave them in their full colours and put
/// a dot on the unread ones instead of the official-source tick, in every
/// design, on every row of the one list (the server's top stories too).

Map<String, dynamic> _article(
  String id, {
  String? imageUrl,
  String source = 'Federal Government',
  int importance = 3,
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
  'headline': 'Decision $id',
  'shortSummary': 'Short summary $id.',
  'summary': 'Summary $id',
  'decisionType': 'cabinet-decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'de',
  'topics': ['economy'],
  'tags': <String>[],
  'importance': importance,
  'imageUrl': imageUrl,
  'originalUrl': 'https://www.bundesregierung.de/$id',
};

/// t1 (with a picture) to t3 are the server's top stories, in the items too;
/// a1 (with a picture) and a2 follow, all in one list. t1 and a1 were opened
/// before. a1 and a2 are important (C's red rule), and a2's institution has a
/// long name, cut with "…" in today's rows.
final _top = [
  _article('t1', imageUrl: 'https://example.test/t1.jpg'),
  _article('t2'),
  _article('t3'),
];
final _items = [
  ..._top,
  _article('a1', imageUrl: 'https://example.test/a1.jpg', importance: 4),
  _article(
    'a2',
    source:
        'Federal Government Press and Information Office of the Federal '
        'Republic',
    importance: 4,
  ),
];
const _read = ['t1', 'a1'];
const _unread = ['t2', 't3', 'a2'];

ApiClient _api() => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    final menu = fakeMenus(request);
    if (menu != null) return menu;
    final query = request.url.queryParameters;
    final page = query.containsKey('since') || query.containsKey('after')
        ? {'items': <Object>[], 'nextCursor': null, 'top': <Object>[]}
        : fakePage({'items': _items, 'nextCursor': null, 'top': _top}, query);
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

/// Today's rows (Now): the unread dot's room after "Source · Country".
Size _dotRoom(WidgetTester tester, String id) => tester.getSize(
  find.descendant(of: _row(id), matching: find.byType(UnreadDot)),
);

/// Today's rows (Now): the "Source · Country" text of the row of [id].
Finder _publisher(String id) => find.descendant(
  of: _row(id),
  matching: find.byWidgetPredicate(
    (w) => w is Text && (w.data?.contains(' · Germany') ?? false),
  ),
);

/// C's importance rule beside the headline of [id]: its colour.
Color _rule(WidgetTester tester, String id) => tester
    .widget<ColoredBox>(
      find.descendant(
        of: find.descendant(
          of: _row(id),
          matching: find.byWidgetPredicate(
            (w) => w is Positioned && w.width == 3,
          ),
        ),
        matching: find.byType(ColoredBox),
      ),
    )
    .color;

/// The semantics of the article [id]'s card: one VoiceOver stop with the
/// headline as a sentence (C starts a top story's with its number), or, in
/// today's rows, as a line of its own.
SemanticsNode _card(WidgetTester tester, String id) => tester.getSemantics(
  find.bySemanticsLabel(RegExp('(^|\\. |\\n)Decision $id(\\.|\\n)')),
);

/// The colour of the blue dot in the light theme tests use.
final _blue = CupertinoColors.systemBlue.color;

/// The grey of secondary text in the light theme: a read row's " · ".
const _grey = Color(0xFF6C6C70);

/// The red dot in the light theme: B's own deeper red there, the app's red
/// in the other designs.
Color _red(FeedDesign design) =>
    design == FeedDesign.b ? AppColors.deepRed : AppColors.accent;

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
    expect(readStyleNamed(''), ReadStyle.none);
    expect(readStyleNamed('grey'), ReadStyle.none);
    expect(readStyleNamed('none'), ReadStyle.none);
  });

  for (final design in FeedDesign.values) {
    group('design ${design.name}', () {
      setUp(() => feedDesign.value = design);

      for (final (style, color) in [
        (ReadStyle.blue, _blue),
        (ReadStyle.red, _red(design)),
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
            // Its words where an unread article's are (t2's for t1, a2's for
            // a1): the dot's room is kept.
            final unread = id.startsWith('t') ? 't2' : 'a2';
            expect(_sourceX(tester, id), _sourceX(tester, unread), reason: id);
            // The designs show a small grey " · " in the dot's room, between
            // the country and the institution; today's rows nothing.
            expect(
              _dots(_row(id), _grey),
              design == FeedDesign.now ? findsNothing : findsOneWidget,
              reason: id,
            );
            // Today's rows keep the dot's room at the line's end, the size
            // of the dot and its gap.
            if (design == FeedDesign.now) {
              expect(
                _dotRoom(tester, id),
                _dotRoom(tester, unread),
                reason: id,
              );
            }
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
        // Today's rows: a2's long "Source · Country" is cut with "…"; it
        // would show more of it if the dot's room went with the dot.
        final now = design == FeedDesign.now;
        RenderParagraph cut() => tester.renderObject(
          find.descendant(
            of: _publisher('a2'),
            matching: find.byType(RichText),
          ),
        );
        final width = now ? tester.getSize(_publisher('a2')).width : null;
        if (now) expect(cut().didExceedMaxLines, isTrue);
        await tester.tap(find.text('Decision a2'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(_dots(_row('a2'), _blue), findsNothing);
        expect(_dots(_row('t2'), _blue), findsOneWidget);
        expect(_sourceX(tester, 'a2'), words);
        expect(tester.getTopLeft(find.text('Decision a2')), headline);
        if (now) {
          expect(tester.getSize(_publisher('a2')).width, width);
          expect(cut().didExceedMaxLines, isTrue);
        }
      });

      if (design == FeedDesign.c) {
        for (final (style, grey) in [
          (ReadStyle.dim, true),
          (ReadStyle.blue, false),
          (ReadStyle.red, true),
        ]) {
          testWidgets('${style.name}: the importance rule of a read article '
              '${grey ? 'turns grey' : 'stays red'}', (tester) async {
            readStyle.value = style;
            await _pumpFeed(tester);
            expect(_rule(tester, 'a2'), AppColors.accent);
            expect(_rule(tester, 'a1'), grey ? _grey : AppColors.accent);
          });
        }
      }

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
        // After the rest of the row or card, in every design.
        for (final id in [..._read, ..._unread]) {
          final node = _card(tester, id);
          final said = '${node.label} ${node.value}';
          expect(
            said.contains('Unread'),
            _unread.contains(id),
            reason: '$id: $said',
          );
          if (_unread.contains(id)) {
            // C says it as a sentence of its label: "… 1m ago. Unread."
            expect(
              said.trim(),
              matches(RegExp(r'Unread\.?$')),
              reason: '$id: $said',
            );
          }
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

  group("today's dot grows with the reader's text, up to 1.4x", () {
    for (final (scale, size) in [(1.0, 8.0), (1.2, 9.6), (2.0, 11.2)]) {
      testWidgets('at ${scale}x', (tester) async {
        readStyle.value = ReadStyle.red;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pumpFeed(tester);
        final dot = find.descendant(
          of: _row('t2'),
          matching: find.byWidgetPredicate((w) => w is DecoratedBox),
        );
        expect(tester.getSize(dot.last).width, closeTo(size, 0.01));
        // The room of a read row's dot grows with it.
        expect(_dotRoom(tester, 't1'), _dotRoom(tester, 't2'));
        expect(_dotRoom(tester, 't2').height, closeTo(size, 0.01));
      });
    }
  });

}
