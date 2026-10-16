import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_look_b_cards.dart';
import 'package:official_news/features/feed/feed_filters.dart';
import 'package:official_news/features/feed/feed_look.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:official_news/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// PROTOTYPE (#67, #68): the feed's chips after Yurii's review of 16 Oct.
/// Where is All countries, the groups (EU, G7, G20), then each country in the
/// feed; a chosen filter shows short (GB, G7, a topic's icon) in red on the
/// grey chip, VoiceOver hears it whole, and the "N new" pill never covers
/// the name or the chips.

Map<String, dynamic> _article(
  String id,
  String country, {
  List<String> topics = const ['economy'],
  int seq = 0,
  String? lang,
}) => {
  'id': id,
  'country': country,
  'source': {'id': 'src-$id', 'name': 'Ministry', 'url': 'https://gov.test'},
  'publishedAt': DateTime.now().toUtc().toIso8601String(),
  'dateOnly': false,
  'headline': 'Decision $id',
  'shortSummary': 'Short summary $id.',
  'summary': 'Summary $id',
  'decisionType': 'decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'en',
  'topics': topics,
  'tags': <String>[],
  'importance': 3,
  'imageUrl': null,
  'originalUrl': 'https://gov.test/$id',
  'feedSeq': seq,
  'lang': ?lang,
};

/// One decision from each of these, every one on economy, two also on health.
List<Map<String, dynamic>> _world({String? lang}) => [
  _article('gb', 'GB', seq: 9, lang: lang),
  _article('de', 'DE', seq: 8, topics: ['economy', 'health'], lang: lang),
  _article('pl', 'PL', seq: 7, lang: lang),
  _article('eu', 'EU', seq: 6, lang: lang),
  _article('us', 'US', seq: 5, topics: ['economy', 'health'], lang: lang),
  _article('ua', 'UA', seq: 4, lang: lang),
  _article('es', 'ES', seq: 3, lang: lang),
];

ApiClient _api(
  List<Map<String, dynamic>> items, {
  List<Map<String, dynamic>> newer = const [],
}) => ApiClient(
  baseUrl: 'https://api.test',
  client: MockClient((request) async {
    final query = request.url.queryParameters;
    final asksNewer = query.containsKey('after') || query.containsKey('since');
    return http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'items': asksNewer ? newer : items,
          'nextCursor': null,
          'top': <Object>[],
        }),
      ),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

Future<FeedController> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> items, {
  List<Map<String, dynamic>> newer = const [],
  FeedLanguage language = FeedLanguage.en,
  Brightness brightness = Brightness.light,
  Size screen = const Size(402, 874),
}) async {
  tester.view.physicalSize = screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final feed = FeedController(api: _api(items, newer: newer));
  // As testApp, in the app's theme for [brightness] (the phone's setting).
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(brightness),
      locale: language.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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

/// A phone as tall as the whole test feed (iPhone 17's width), so every card
/// is built and the headlines show what the filters let through.
const _tall = Size(402, 4000);

/// The chip that opens the Where menu, and the one for Topics: the ones on
/// screen (B also lays out copies of its masthead, to measure it).
final _where = find.byKey(const ValueKey('filter-where')).hitTestable();
final _topics = find.byKey(const ValueKey('filter-topic')).hitTestable();

/// What the open menu lists, top to bottom: each item's name, "—" for a
/// divider between groups.
List<String> _menu(WidgetTester tester) => [
  for (final entry in tester.widgetList(
    find.byWidgetPredicate(
      (w) => w is CupertinoMenuItem || w is CupertinoMenuDivider,
    ),
  ))
    if (entry is CupertinoMenuItem)
      ((entry.child as Semantics).child! as Text).data!
    else
      '—',
];

/// The leading icon of the open menu's item named [item], or null.
IconData? _menuIcon(WidgetTester tester, String item) {
  final entry = tester
      .widgetList<CupertinoMenuItem>(find.byType(CupertinoMenuItem))
      .singleWhere((e) => ((e.child as Semantics).child! as Text).data == item);
  return (entry.leading as Icon?)?.icon;
}

/// The Where chip's 44-pt target, wherever it is (above the screen once a
/// masthead that scrolls has gone). B and C also lay out copies of their
/// masthead to measure it, inside ExcludeSemantics, never painted.
Rect _whereTarget(WidgetTester tester) {
  final real = find
      .byKey(const ValueKey('filter-where'), skipOffstage: false)
      .evaluate()
      .where((e) {
        var copy = false;
        e.visitAncestorElements((a) {
          final w = a.widget;
          copy = w is ExcludeSemantics && w.excluding;
          return !copy;
        });
        return !copy;
      })
      .toList();
  expect(real, hasLength(1));
  RenderBox? button;
  void visit(Element e) {
    if (button != null) return;
    if (e.widget is CupertinoButton) {
      button = e.renderObject! as RenderBox;
      return;
    }
    e.visitChildren(visit);
  }

  visit(real.single);
  return button!.localToGlobal(Offset.zero) & button!.size;
}

Future<void> _choose(WidgetTester tester, Finder chip, String item) async {
  await tester.tap(chip);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(CupertinoMenuItem),
      matching: find.text(item),
    ),
  );
  await tester.pumpAndSettle();
}

/// The headlines in the feed now.
Set<String> _shown(WidgetTester tester) => {
  for (final id in ['gb', 'de', 'pl', 'eu', 'us', 'ua', 'es'])
    if (find.text('Decision $id').evaluate().isNotEmpty) id,
};

/// The colour of the chip's label (or its icon) and of its fill.
({Color label, Color fill}) _colours(WidgetTester tester, Finder chip) {
  final box = tester.widget<Container>(
    find.descendant(of: chip, matching: find.byType(Container)).first,
  );
  final rich = tester.widget<Text>(
    find.descendant(of: chip, matching: find.byType(Text)).first,
  );
  // Resolved dynamic colours compared by value.
  return (
    label: Color(rich.style!.color!.toARGB32()),
    fill: Color((box.decoration! as BoxDecoration).color!.toARGB32()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    feedDesign.value = FeedDesign.b;
  });
  tearDown(() => feedDesign.value = FeedDesign.now);

  testWidgets('Where lists All countries, the groups, then each country', (
    tester,
  ) async {
    await _pump(tester, _world(), screen: _tall);
    await tester.tap(_where);
    await tester.pumpAndSettle();
    // The EU's institutions are in the European Union group, not a country.
    expect(_menu(tester), [
      'All countries',
      '—',
      'European Union',
      'G7',
      'G20',
      '—',
      'Germany',
      'Poland',
      'Spain',
      'Ukraine',
      'United Kingdom',
      'United States',
    ]);
  });

  testWidgets('a country shows only its own decisions', (tester) async {
    await _pump(tester, _world(), screen: _tall);
    expect(_shown(tester), {'gb', 'de', 'pl', 'eu', 'us', 'ua', 'es'});
    await _choose(tester, _where, 'United Kingdom');
    expect(_shown(tester), {'gb'});
    await _choose(tester, _where, 'Poland');
    expect(_shown(tester), {'pl'});
    await _choose(tester, _where, 'All countries');
    expect(_shown(tester), {'gb', 'de', 'pl', 'eu', 'us', 'ua', 'es'});
  });

  testWidgets('a group shows its members\' decisions', (tester) async {
    await _pump(tester, _world(), screen: _tall);
    await _choose(tester, _where, 'European Union');
    expect(_shown(tester), {'eu', 'de', 'pl', 'es'});
    await _choose(tester, _where, 'G7');
    expect(_shown(tester), {'gb', 'de', 'eu', 'us'});
    await _choose(tester, _where, 'G20');
    expect(_shown(tester), {'gb', 'de', 'eu', 'us'});
    // With a topic too: both must hold.
    await _choose(tester, _topics, 'Health');
    expect(_shown(tester), {'de', 'us'});
  });

  testWidgets('a chosen filter shows short, in red on the same grey chip', (
    tester,
  ) async {
    await _pump(tester, _world(), screen: _tall);
    final grey = Color(CupertinoColors.tertiarySystemFill.color.toARGB32());
    final ink = Color(CupertinoColors.label.color.toARGB32());
    expect(_colours(tester, _where), (label: ink, fill: grey));
    expect(_colours(tester, _topics), (label: ink, fill: grey));

    // A country: its code.
    await _choose(tester, _where, 'United Kingdom');
    expect(find.descendant(of: _where, matching: find.text('GB')), findsOne);
    expect(find.text('United Kingdom'), findsNothing);
    // #C41230: at least 4.5:1 on the grey chip (#D1203A was 4.1:1 on B's).
    final red = Color(filterRed.color.toARGB32());
    expect(red, const Color(0xFFC41230));
    expect(_colours(tester, _where), (label: red, fill: grey));
    expect(
      find.descendant(
        of: _where,
        matching: find.byIcon(CupertinoIcons.chevron_down),
      ),
      findsOne,
    );

    // A group: its short name.
    await _choose(tester, _where, 'European Union');
    expect(find.descendant(of: _where, matching: find.text('EU')), findsOne);
    await _choose(tester, _where, 'G7');
    expect(find.descendant(of: _where, matching: find.text('G7')), findsOne);

    // A topic: its icon, no words.
    await _choose(tester, _topics, 'Economy');
    expect(
      find.descendant(
        of: _topics,
        matching: find.byIcon(CupertinoIcons.chart_bar_alt_fill),
      ),
      findsOne,
    );
    expect(
      find.descendant(of: _topics, matching: find.text('Economy')),
      findsNothing,
    );
    final icon = tester.widget<Icon>(
      find.descendant(
        of: _topics,
        matching: find.byIcon(CupertinoIcons.chart_bar_alt_fill),
      ),
    );
    expect(Color(icon.color!.toARGB32()), red);

    // The menu keeps the full names, each topic beside the icon its chip
    // shows, so the reader learns what the icon means.
    await tester.tap(_topics);
    await tester.pumpAndSettle();
    expect(_menu(tester), ['All topics', '—', 'Economy', 'Health']);
    expect(_menuIcon(tester, 'All topics'), isNull);
    expect(_menuIcon(tester, 'Economy'), CupertinoIcons.chart_bar_alt_fill);
    expect(_menuIcon(tester, 'Health'), CupertinoIcons.staroflife_fill);
    // The checkmark is the same red.
    final check = tester.widget<Icon>(
      find.byIcon(CupertinoIcons.checkmark_alt),
    );
    expect(Color(check.color!.toARGB32()), red);
  });

  testWidgets('the Topics menu shows each icon beside its name, in Ukrainian '
      'too', (tester) async {
    SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
    await _pump(
      tester,
      _world(lang: 'uk'),
      language: FeedLanguage.uk,
      screen: _tall,
    );
    await tester.tap(_topics);
    await tester.pumpAndSettle();
    final economy = find.ancestor(
      of: find.text('Економіка'),
      matching: find.byType(CupertinoMenuItem),
    );
    expect(
      find.descendant(
        of: economy,
        matching: find.byIcon(CupertinoIcons.chart_bar_alt_fill),
      ),
      findsOne,
    );
    // The icon comes first, on the same line as the name.
    final icon = tester.getRect(
      find.descendant(
        of: economy,
        matching: find.byIcon(CupertinoIcons.chart_bar_alt_fill),
      ),
    );
    final name = tester.getRect(find.text('Економіка'));
    expect(icon.right, lessThan(name.left));
    expect(icon.center.dy, closeTo(name.center.dy, 2));
  });

  testWidgets('in dark mode the chosen chip is a red that reads on the dark '
      'chip', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await _pump(tester, _world(), brightness: Brightness.dark, screen: _tall);
    await _choose(tester, _where, 'United Kingdom');
    final colours = _colours(tester, _where);
    // #FF3B55: 4.9:1 on the dark chip (the brand red #FA2D48 is 4.48:1).
    expect(colours.label, const Color(0xFFFF3B55));
    expect(
      colours.fill,
      Color(CupertinoColors.tertiarySystemFill.darkColor.toARGB32()),
    );
  });

  test('every topic has an icon and a name in every language', () {
    const ids = [
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
    ];
    expect(topicIcons.keys.toSet(), ids.toSet());
    expect(topicIcons.values.toSet(), hasLength(ids.length));
    for (final lang in FeedLanguage.values) {
      final l10n = l10nFor(lang);
      final names = {for (final id in ids) topicName(id, l10n)};
      expect(names, hasLength(ids.length), reason: lang.code);
      expect(names.any((n) => ids.contains(n)), isFalse, reason: lang.code);
    }
    expect(topicName('economy', l10nFor(FeedLanguage.uk)), 'Економіка');
    expect(topicName('economy', l10nFor(FeedLanguage.de)), 'Wirtschaft');
  });

  testWidgets('in Ukrainian the menus name topics and countries in Ukrainian', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
    await _pump(
      tester,
      _world(lang: 'uk'),
      language: FeedLanguage.uk,
      screen: _tall,
    );
    expect(find.text('Усі країни').hitTestable(), findsOne);
    expect(find.text('Усі теми').hitTestable(), findsOne);

    await tester.tap(_topics);
    await tester.pumpAndSettle();
    expect(_menu(tester), ['Усі теми', '—', 'Економіка', 'Здоров’я']);
    expect(find.text('Economy'), findsNothing);
    await tester.tap(_topics);
    await tester.pumpAndSettle();

    // Alphabetical as in Ukrainian: І comes after Г and before Н, not after Я.
    await tester.tap(_where);
    await tester.pumpAndSettle();
    final menu = _menu(tester);
    expect(menu.take(6), [
      'Усі країни',
      '—',
      'Європейський Союз',
      'G7',
      'G20',
      '—',
    ]);
    expect(menu.skip(6), [
      'Велика Британія',
      'Іспанія',
      'Німеччина',
      'Польща',
      'США',
      'Україна',
    ]);
    await tester.tap(_where);
    await tester.pumpAndSettle();

    // The European Union's chip is its Ukrainian abbreviation, not "EU";
    // G7 is written so in every language.
    await _choose(tester, _where, 'Європейський Союз');
    expect(find.descendant(of: _where, matching: find.text('ЄС')), findsOne);
    expect(
      find.descendant(of: _where, matching: find.text('EU')),
      findsNothing,
    );
    await _choose(tester, _where, 'G7');
    expect(find.descendant(of: _where, matching: find.text('G7')), findsOne);
  });

  test('the EU\'s abbreviation in each language', () {
    expect(
      {
        for (final l in FeedLanguage.values)
          l.code: groupShort('EU', l10nFor(l)),
      },
      {'en': 'EU', 'uk': 'ЄС', 'ru': 'ЕС', 'es': 'UE', 'de': 'EU'},
    );
    expect(groupShort('G20', l10nFor(FeedLanguage.uk)), 'G20');
  });

  testWidgets('B\'s cards name the chosen topic, not another of theirs', (
    tester,
  ) async {
    await _pump(tester, [
      _article('gb', 'GB', topics: ['technology', 'economy'], seq: 2),
      _article('de', 'DE', topics: ['health', 'economy'], seq: 1),
    ], screen: _tall);
    Finder footer(String id, String topic) => find.descendant(
      of: find.ancestor(
        of: find.text('Decision $id'),
        matching: find.byType(BCard),
      ),
      matching: find.textContaining(topic),
    );
    // No topic chosen: each card's main topic.
    expect(footer('gb', 'Technology'), findsOne);
    expect(footer('de', 'Health'), findsOne);
    await _choose(tester, _topics, 'Economy');
    expect(footer('gb', 'Economy'), findsOne);
    expect(footer('gb', 'Technology'), findsNothing);
    expect(footer('de', 'Economy'), findsOne);
    expect(footer('de', 'Health'), findsNothing);
  });

  testWidgets(
    'B\'s cards and the Topics menu name a topic alike in Ukrainian',
    (tester) async {
      SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
      await _pump(
        tester,
        [
          _article('de', 'DE', topics: ['health'], lang: 'uk'),
        ],
        language: FeedLanguage.uk,
        screen: _tall,
      );
      final card = find.ancestor(
        of: find.text('Decision de'),
        matching: find.byType(BCard),
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('Здоров’я')),
        findsOne,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('Охорона')),
        findsNothing,
      );
    },
  );

  testWidgets('VoiceOver hears the whole choice; targets are 44 pt', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _world(), screen: _tall);
    expect(find.bySemanticsLabel('All countries'), findsOne);
    expect(find.bySemanticsLabel('All topics'), findsOne);

    await _choose(tester, _where, 'United Kingdom');
    await _choose(tester, _topics, 'Economy');
    expect(
      tester.getSemantics(find.bySemanticsLabel('Country: United Kingdom')),
      isSemantics(
        label: 'Country: United Kingdom',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Topic: Economy')),
      isSemantics(label: 'Topic: Economy', isButton: true, hasTapAction: true),
    );
    // The short forms are not read on their own.
    expect(find.bySemanticsLabel('GB'), findsNothing);

    await _choose(tester, _where, 'G7');
    expect(find.bySemanticsLabel('Countries: G7'), findsOne);
    await _choose(tester, _where, 'European Union');
    expect(find.bySemanticsLabel('Countries: European Union'), findsOne);

    // Even the shortest chips are 44-pt targets.
    for (final chip in [_where, _topics]) {
      final target = tester.getRect(
        find.descendant(of: chip, matching: find.byType(CupertinoButton)),
      );
      expect(target.height, greaterThanOrEqualTo(44));
      expect(target.width, greaterThanOrEqualTo(44));
    }
    semantics.dispose();
  });

  testWidgets('a choice with nothing offers the way back', (tester) async {
    await _pump(tester, _world(), screen: _tall);
    await _choose(tester, _topics, 'Health');
    // Poland has nothing on health.
    await _choose(tester, _where, 'Poland');
    expect(_shown(tester), isEmpty);
    expect(find.text('No decisions here in the last 7 days.'), findsOne);
    await tester.tap(find.text('Show all topics'));
    await tester.pumpAndSettle();
    expect(_shown(tester), {'pl'});
  });

  test('a demo build names its filters', () {
    expect(demoFilters('GB:economy'), (
      place: const FeedPlace.country('GB'),
      topic: 'economy',
    ));
    expect(demoFilters('g7'), (
      place: const FeedPlace.group('G7'),
      topic: null,
    ));
    expect(demoFilters('EU'), (
      place: const FeedPlace.group('EU'),
      topic: null,
    ));
    expect(demoFilters(':health'), (place: FeedPlace.all, topic: 'health'));
    expect(demoFilters(''), (place: FeedPlace.all, topic: null));
  });

  test('names sort as readers expect', () {
    final uk = [
      'Японія',
      'Італія',
      'Індія',
      'Греція',
      'Ґамбія',
      'Єгипет',
      'Їжакія',
    ];
    expect(uk..sort(compareNames), [
      'Греція',
      'Ґамбія',
      'Єгипет',
      'Індія',
      'Італія',
      'Їжакія',
      'Японія',
    ]);
    final es = ['Reino Unido', 'Ñandú', 'Alemania', 'México', 'Árabe', 'Nueva'];
    expect(es..sort(compareNames), [
      'Alemania',
      'Árabe',
      'México',
      'Nueva',
      'Ñandú',
      'Reino Unido',
    ]);
    final de = ['Vereinigtes Königreich', 'Österreich', 'Polen', 'Ägypten'];
    expect(de..sort(compareNames), [
      'Ägypten',
      'Österreich',
      'Polen',
      'Vereinigtes Königreich',
    ]);
  });

  group('the "N new" pill never covers the name or the chips', () {
    for (final design in FeedDesign.values) {
      testWidgets('design ${design.name}', (tester) async {
        feedDesign.value = design;
        final feed = await _pump(
          tester,
          [for (var i = 30; i >= 1; i--) _article('n$i', 'DE', seq: i)],
          newer: [_article('new', 'DE', seq: 31)],
        );
        await feed.checkForNew();
        await tester.pump();
        await tester.pump();
        final pill = find.text('1 new decision');
        expect(pill, findsOne);
        Rect pillBox() => tester.getRect(pill);

        // At the top: under the name and the chips, close under them.
        // (C slides its chips sideways when they do not fit, and the test
        // font is wide: there "All topics" is off the screen to the right.)
        Rect? onScreen(String text) {
          final f = find.text(text).hitTestable();
          return f.evaluate().isEmpty ? null : tester.getRect(f.first);
        }

        final title = onScreen('Official News')!;
        final chips = [?onScreen('All countries'), ?onScreen('All topics')];
        expect(chips, isNotEmpty);
        for (final r in [title, ...chips]) {
          expect(pillBox().overlaps(r), isFalse);
          expect(pillBox().top, greaterThan(r.bottom));
        }
        // The chips' 44-pt targets, the look's own margin, 8 pt and the
        // pill's padding.
        final lowest = chips.map((r) => r.bottom).reduce(math.max);
        expect(pillBox().top - lowest, lessThanOrEqualTo(50));

        // Scrolled: near the top of the list, still clear of what stays.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
        await tester.pumpAndSettle();
        for (final f in [
          find.text('Official News'),
          find.text('All countries'),
          find.text('All topics'),
        ]) {
          for (final e in f.hitTestable().evaluate()) {
            final r = tester.getRect(find.byWidget(e.widget));
            expect(pillBox().overlaps(r), isFalse, reason: '$f');
          }
        }
        expect(pillBox().top, lessThan(150));
      });
    }
  });

  group('the "N new" pill stays clear of the chips in every frame of a '
      'scroll back to the top', () {
    for (final design in FeedDesign.values) {
      testWidgets('design ${design.name}', (tester) async {
        feedDesign.value = design;
        final feed = await _pump(
          tester,
          [for (var i = 30; i >= 1; i--) _article('n$i', 'DE', seq: i)],
          newer: [_article('new', 'DE', seq: 31)],
        );
        await feed.checkForNew();
        await tester.pump();
        await tester.pump();
        final pill = find.text('1 new decision');
        expect(pill, findsOne);

        // Down the list first, then a finger pulling it back fast: 40 pt a
        // frame (about 5,000 pt/s at 120 Hz), past the top.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        expect(scroll.pixels, greaterThan(500));
        final gesture = await tester.startGesture(const Offset(201, 600));
        var frames = 0;
        for (var i = 0; i < 18; i++) {
          await gesture.moveBy(const Offset(0, 40));
          await tester.pump(const Duration(milliseconds: 8));
          final where = _whereTarget(tester);
          final box = tester.getRect(pill);
          expect(
            box.overlaps(where),
            isFalse,
            reason: 'frame $i at ${scroll.pixels}: pill $box, Where $where',
          );
          if (where.bottom > 0) frames++;
        }
        await gesture.up();
        await tester.pumpAndSettle();
        // The chips were on screen for several of those frames.
        expect(frames, greaterThanOrEqualTo(5));
        expect(scroll.pixels, 0);
      });
    }
  });

  group('the gear is level with the chips', () {
    for (final design in [FeedDesign.b, FeedDesign.c]) {
      testWidgets('design ${design.name}', (tester) async {
        feedDesign.value = design;
        await _pump(tester, _world());
        final gear = tester.getRect(
          find.ancestor(
            of: find.byIcon(CupertinoIcons.gear_alt).hitTestable(),
            matching: find.byType(CupertinoButton),
          ),
        );
        expect(gear.center.dy, closeTo(_whereTarget(tester).center.dy, 0.5));
      });
    }
  });

  test('a place includes what it says', () {
    final gb = Article.fromJson(_article('gb', 'GB'));
    final eu = Article.fromJson(_article('eu', 'EU'));
    final pl = Article.fromJson(_article('pl', 'PL'));
    expect(FeedPlace.all.includes(pl), isTrue);
    expect(const FeedPlace.country('GB').includes(gb), isTrue);
    expect(const FeedPlace.country('GB').includes(eu), isFalse);
    expect(const FeedPlace.group('EU').includes(pl), isTrue);
    expect(const FeedPlace.group('G7').includes(eu), isTrue);
    expect(const FeedPlace.group('G7').includes(pl), isFalse);
    expect(const FeedPlace.group('G20').includes(gb), isTrue);
  });
}
