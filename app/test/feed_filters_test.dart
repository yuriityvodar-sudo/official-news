import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/filters.dart';
import 'package:official_news/core/news_widgets.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/topics.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/features/feed/feed_filters.dart';
import 'package:official_news/features/feed/feed_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_app.dart';

/// The feed's filters (#67, #68): the Where chip (all countries, a group of
/// countries, or one country alone) and the Topics chip under the date, the
/// requests they make, the compact chips, the choices saved on the phone, the
/// empty filtered feed, and servers without the groups or the new endpoints.

Map<String, dynamic> _article(
  String id, {
  required String country,
  List<String> topics = const [],
  required int feedSeq,
  String? lang,
}) => {
  'feedSeq': feedSeq,
  'addedAt': DateTime.now()
      .subtract(Duration(minutes: 100 - feedSeq))
      .toUtc()
      .toIso8601String(),
  'id': id,
  'country': country,
  'source': {
    'id': '${country.toLowerCase()}-gov',
    'name': 'Government $country',
    'url': 'https://gov.test/$country',
  },
  'publishedAt': DateTime.now().toUtc().toIso8601String(),
  'dateOnly': false,
  'headline': lang == null ? 'Decision $id' : 'Рішення $id',
  'shortSummary': null,
  'summary': 'Summary $id',
  'decisionType': 'decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'en',
  'topics': topics,
  'tags': <String>[],
  'importance': 3,
  'imageUrl': null,
  'originalUrl': 'https://gov.test/$id',
  'lang': ?lang,
};

/// The week's feed, newest first: Germany, the US, the EU institutions, the
/// UK, Japan and Türkiye. Economy is the busiest topic, then health.
final _week = [
  _article('de1', country: 'DE', topics: ['economy'], feedSeq: 10),
  _article('us1', country: 'US', topics: ['economy', 'health'], feedSeq: 9),
  _article('eu1', country: 'EU', topics: ['trade'], feedSeq: 8),
  _article('gb1', country: 'GB', topics: ['economy'], feedSeq: 7),
  _article('de2', country: 'DE', topics: ['health'], feedSeq: 6),
  _article('jp1', country: 'JP', topics: ['security-defence'], feedSeq: 5),
  _article('us2', country: 'US', topics: ['economy'], feedSeq: 4),
  _article('tr1', country: 'TR', topics: ['health'], feedSeq: 3),
];

/// The groups as the server defines them (`GROUPS`), with the members these
/// tests have articles for; `EU` is the EU institutions.
const _groups = {
  'eu': {'DE', 'FR', 'EU'},
  'g7': {'DE', 'FR', 'GB', 'JP', 'US', 'EU'},
  'g20': {'DE', 'FR', 'GB', 'JP', 'TR', 'US', 'EU'},
  'nato': {'DE', 'FR', 'GB', 'TR', 'US'},
};

const _groupNames = {
  'en': {'eu': 'European Union', 'g7': 'G7', 'g20': 'G20', 'nato': 'NATO'},
  'uk': {'eu': 'Європейський Союз', 'g7': 'G7', 'g20': 'G20', 'nato': 'НАТО'},
  'de': {'eu': 'Europäische Union', 'g7': 'G7', 'g20': 'G20', 'nato': 'NATO'},
};

const _topicNames = {
  'en': {
    'economy': 'Economy',
    'health': 'Health',
    'trade': 'Trade',
    'security-defence': 'Security and defence',
    'education': 'Education',
  },
  'uk': {
    'economy': 'Економіка',
    'health': 'Здоров’я',
    'trade': 'Торгівля',
    'security-defence': 'Безпека та оборона',
    'education': 'Освіта',
  },
};

const _countryNames = {
  'en': {
    'DE': 'Germany',
    'GB': 'United Kingdom',
    'JP': 'Japan',
    'TR': 'Türkiye',
    'US': 'United States',
    'NZ': 'New Zealand',
  },
  'uk': {
    'DE': 'Німеччина',
    'GB': 'Велика Британія',
    'JP': 'Японія',
    'TR': 'Туреччина',
    'US': 'США',
    'NZ': 'Нова Зеландія',
  },
};

http.Response _ok(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _bad(String message) => http.Response.bytes(
  utf8.encode(jsonEncode({'error': message})),
  400,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// A server that follows the contract for the filters: `country=` (only that
/// country), `group=` (its members, refused when unknown, never with
/// `country=`) and `topic=` on every article request, `GET /topics` busiest
/// first under them, `GET /countries` with its groups (fixed order) and the
/// countries with sources (by name). With [groups] false, the server of the
/// first filters build: `/countries` without `groups`, and `group=` ignored.
/// Without [menus], a server from before them: both menus answer 404 and every
/// filter is ignored. Pages of [pageSize]; the cursor is the next offset.
class _Server {
  _Server({
    List<Map<String, dynamic>>? articles,
    this.countries = const ['DE', 'GB', 'JP', 'TR', 'US'],
    this.groupIds = const ['eu', 'g7', 'g20', 'nato'],
    this.menus = true,
    this.groups = true,
    this.extraTopics = const [],
    this.pageSize = 20,
  }) : articles = articles ?? _week;

  List<Map<String, dynamic>> articles;
  final List<String> countries;
  final List<String> groupIds;
  final bool menus;
  final bool groups;
  final List<String> extraTopics;
  final int pageSize;
  final log = <Uri>[];
  bool offline = false;

  /// The article requests only.
  List<Uri> get feedRequests =>
      log.where((u) => u.path == '/articles').toList();

  List<Uri> get topicRequests => log.where((u) => u.path == '/topics').toList();

  ApiClient get api => ApiClient(
    baseUrl: 'https://api.test',
    client: MockClient((request) async {
      log.add(request.url);
      if (offline) return http.Response('offline', 503);
      final q = request.url.queryParameters;
      final lang = q['lang'] ?? 'en';
      if (!menus && request.url.path != '/articles') {
        return http.Response('{"error":"Not found"}', 404);
      }
      final error = _check(q);
      if (error != null) return _bad(error);
      switch (request.url.path) {
        case '/countries':
          final names = _countryNames[lang]!;
          return _ok({
            if (groups)
              'groups': [
                for (final id in groupIds)
                  {
                    'id': id,
                    'name': _groupNames[lang]?[id] ?? id.toUpperCase(),
                    'members': [...?_groups[id]],
                  },
              ],
            'countries': [
              for (final c in countries) {'code': c, 'name': names[c]!},
            ]..sort((a, b) => a['name']!.compareTo(b['name']!)),
          });
        case '/topics':
          final counts = <String, int>{};
          for (final a in _matching(q, topic: false)) {
            for (final t in a['topics'] as List) {
              counts[t as String] = (counts[t] ?? 0) + 1;
            }
          }
          final ids = counts.keys.toList()
            ..sort((x, y) => counts[y]!.compareTo(counts[x]!));
          return _ok({
            'topics': [
              for (final id in [...ids, ...extraTopics])
                {'id': id, 'name': _topicNames[lang]![id]},
            ],
          });
        case '/articles':
          var shown = _matching(q);
          if (lang != 'en') {
            shown = [for (final a in shown) _translated(a, lang)];
          }
          final after = int.tryParse(q['after'] ?? '');
          if (after != null) {
            return _ok({
              'items': shown
                  .where((a) => (a['feedSeq'] as int) > after)
                  .toList(),
              'nextCursor': null,
              'top': [],
            });
          }
          final from = int.tryParse(q['cursor'] ?? '') ?? 0;
          final page = shown.skip(from).take(pageSize).toList();
          final next = from + pageSize;
          return _ok({
            'items': page,
            'nextCursor': next < shown.length ? '$next' : null,
            'top': [],
          });
      }
      return http.Response('{"error":"Not found"}', 404);
    }),
  );

  /// The server's 400s for the Where filter.
  String? _check(Map<String, String> q) {
    if (!menus || !groups) return null;
    if (q.containsKey('country') && q.containsKey('group')) {
      return 'country and group cannot be used together: send one of them';
    }
    final group = q['group'];
    if (group != null && !groupIds.contains(group)) {
      return 'group must be one of: ${groupIds.join(', ')}';
    }
    return null;
  }

  List<Map<String, dynamic>> _matching(
    Map<String, String> q, {
    bool topic = true,
  }) {
    if (!menus) return articles;
    final country = q['country'];
    final group = groups ? _groups[q['group']] : null;
    final id = topic ? q['topic'] : null;
    return [
      for (final a in articles)
        if ((country == null || a['country'] == country) &&
            (group == null || group.contains(a['country'])) &&
            (id == null || (a['topics'] as List).contains(id)))
          a,
    ];
  }

  static Map<String, dynamic> _translated(
    Map<String, dynamic> a,
    String lang,
  ) => {...a, 'lang': lang, 'headline': 'Рішення ${a['id']}'};
}

/// Lets the menus' requests, which the feed does not wait for, finish.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A phone-wide screen (iPhone 15, 393 pt), tall enough for the whole week.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(393, 1600) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<FeedController> _pump(
  WidgetTester tester,
  _Server server, {
  FeedLanguage words = FeedLanguage.en,
}) async {
  _phone(tester);
  final feed = FeedController(api: server.api);
  await tester.pumpWidget(
    testApp(
      language: words,
      onGenerateRoute: onGenerateRoute,
      home: FeedScreen(
        controller: feed,
        newCheckEvery: const Duration(hours: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return feed;
}

const _where = ValueKey('filter-where');
const _topics = ValueKey('filter-topic');

/// Opens a chip's pull-down and picks [item].
Future<void> _pick(WidgetTester tester, Key chip, String item) async {
  await tester.tap(find.byKey(chip));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(CupertinoMenuItem),
      matching: find.text(item),
    ),
  );
  await tester.pumpAndSettle();
}

/// Closes an open menu without picking.
Future<void> _close(WidgetTester tester) async {
  await tester.tapAt(const Offset(20, 20));
  await tester.pumpAndSettle();
}

/// The chip's line: its label and icon, the chevron after them.
Text _line(WidgetTester tester, Key chip) => tester.widget<Text>(
  find.descendant(of: find.byKey(chip), matching: find.byType(Text)).first,
);

/// What the chip shows as text; empty when it shows an icon.
String _label(WidgetTester tester, Key chip) {
  final span = _line(tester, chip).textSpan!;
  return span is TextSpan ? span.toPlainText() : '';
}

/// The chip's icon in place of a label, or null.
IconData? _icon(WidgetTester tester, Key chip) {
  final span = _line(tester, chip).textSpan;
  return span is WidgetSpan ? (span.child as Icon).icon : null;
}

/// The colour of the chip's label (or icon), and of its chevron, as ARGB.
int _ink(WidgetTester tester, Key chip) =>
    _line(tester, chip).style!.color!.toARGB32();

int _chevron(WidgetTester tester, Key chip) => tester
    .widget<Icon>(
      find.descendant(
        of: find.byKey(chip),
        matching: find.byIcon(CupertinoIcons.chevron_down),
      ),
    )
    .color!
    .toARGB32();

Finder _box(Key chip) => find
    .descendant(of: find.byKey(chip), matching: find.byType(Container))
    .first;

/// The chip's grey, as ARGB.
int _fill(WidgetTester tester, Key chip) =>
    (tester.widget<Container>(_box(chip)).decoration! as BoxDecoration).color!
        .toARGB32();

/// What VoiceOver says for the chip.
String _spoken(WidgetTester tester, Key chip) =>
    tester.getSemantics(_box(chip)).label;

Iterable<String> _shown(WidgetTester tester) => {
  for (final t in tester.widgetList<Text>(find.textContaining('Decision ')))
    t.data!.replaceFirst('Decision ', ''),
};

/// The open menu's items, top to bottom.
List<String> _menu(WidgetTester tester) => [
  for (final item in tester.widgetList<CupertinoMenuItem>(
    find.byType(CupertinoMenuItem),
  ))
    ((item.child as Semantics).child! as Text).data!,
];

/// The icon before [title] in the open menu, or null.
IconData? _menuIcon(WidgetTester tester, String title) {
  final item = tester
      .widgetList<CupertinoMenuItem>(find.byType(CupertinoMenuItem))
      .singleWhere(
        (i) => ((i.child as Semantics).child! as Text).data == title,
      );
  return (item.leading as Icon?)?.icon;
}

/// The colour of the open menu's checkmark, as ARGB.
int _checkmark(WidgetTester tester) => tester
    .widget<Icon>(find.byIcon(CupertinoIcons.checkmark_alt))
    .color!
    .toARGB32();

/// The WCAG contrast of [fg] on [bg] (both opaque).
double _contrast(Color fg, Color bg) {
  final a = fg.computeLuminance(), b = bg.computeLuminance();
  return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
}

/// The checked item of the open menu.
String _checked(WidgetTester tester) => [
  for (final item in tester.widgetList<CupertinoMenuItem>(
    find.byType(CupertinoMenuItem),
  ))
    if (item.trailing != null) ((item.child as Semantics).child! as Text).data!,
].single;

const _black = 0xFF000000;
const _lightRed = 0xFFC41230;
const _darkRed = 0xFFFF3B55;

void main() {
  late List<(String, Map<String, Object>)> events;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    events = [];
    analytics = Analytics((name, parameters) async {
      events.add((name, parameters));
    });
  });
  tearDown(() => analytics = Analytics());

  List<Map<String, Object>> filterEvents() => [
    for (final e in events)
      if (e.$1 == 'filter_changed') e.$2,
  ];

  testWidgets('a new reader sees All countries and All topics, in grey', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);
    expect(_label(tester, _where), 'All countries');
    expect(_label(tester, _topics), 'All topics');
    for (final chip in [_where, _topics]) {
      expect(_ink(tester, chip), _black, reason: '$chip');
      expect(_chevron(tester, chip), _black, reason: '$chip');
      expect(_icon(tester, chip), isNull, reason: '$chip');
    }
    expect(_spoken(tester, _where), 'All countries');
    expect(_spoken(tester, _topics), 'All topics');
    expect(_shown(tester), [
      'de1',
      'us1',
      'eu1',
      'gb1',
      'de2',
      'jp1',
      'us2',
      'tr1',
    ]);
    final first = server.feedRequests.single.queryParameters;
    for (final param in ['country', 'group', 'topic']) {
      expect(first.containsKey(param), isFalse, reason: param);
    }
    // Under the date.
    expect(
      tester.getRect(find.byKey(_where)).top,
      greaterThan(
        tester.getRect(find.text(longDay(DateTime.now(), l10nFor()))).bottom -
            4,
      ),
    );
  });

  testWidgets(
    'the Where menu: All countries, then the groups, then each country',
    (tester) async {
      await _pump(tester, _Server());
      await tester.tap(find.byKey(_where));
      await tester.pumpAndSettle();
      expect(_menu(tester), [
        'All countries',
        'European Union',
        'G7',
        'G20',
        'NATO',
        'Germany',
        'Japan',
        'Türkiye',
        'United Kingdom',
        'United States',
      ]);
      // A divider between the three parts.
      expect(find.byType(CupertinoMenuDivider), findsNWidgets(2));
      // The checkmark is on the current choice, and VoiceOver says so.
      expect(_checked(tester), 'All countries');
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);
      expect(
        tester.getSemantics(find.text('All countries').last),
        isSemantics(label: 'All countries', isSelected: true),
      );
    },
  );

  testWidgets('the long Where menu stays below the status bar', (tester) async {
    _phone(tester);
    // An iPhone's status bar and home indicator, on a screen shorter than
    // the menu.
    tester.view.physicalSize = const Size(393, 420) * 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    final feed = FeedController(api: _Server().api);
    await tester.pumpWidget(
      testApp(
        home: FeedScreen(
          controller: feed,
          newCheckEvery: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_where));
    await tester.pumpAndSettle();
    // Taller than the screen: it starts just under the status bar (it
    // started at 8 pt, over the clock, before), and scrolls.
    final first = tester.getRect(find.byType(CupertinoMenuItem).first);
    expect(first.top, greaterThanOrEqualTo(62 + 8));
  });

  testWidgets('one country: only its own, the chip its code in red', (
    tester,
  ) async {
    final server = _Server();
    final feed = await _pump(tester, server);
    final grey = _fill(tester, _where);
    await _pick(tester, _where, 'United Kingdom');
    expect(feed.where, const FeedWhere.country('GB'));
    final asked = server.feedRequests.last.queryParameters;
    expect(asked['country'], 'GB');
    expect(asked.containsKey('group'), isFalse);
    expect(_shown(tester), ['gb1']);
    // Short and red on the same grey chip; VoiceOver hears the full name.
    expect(_label(tester, _where), 'GB');
    expect(_ink(tester, _where), _lightRed);
    expect(_chevron(tester, _where), _lightRed);
    expect(_fill(tester, _where), grey);
    expect(_spoken(tester, _where), 'Country: United Kingdom');
    // The menu keeps the full names, the checkmark on the country.
    await tester.tap(find.byKey(_where));
    await tester.pumpAndSettle();
    expect(_checked(tester), 'United Kingdom');
  });

  testWidgets("a country alone never has the EU institutions' decisions", (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);
    await _pick(tester, _where, 'Germany');
    expect(server.feedRequests.last.queryParameters['country'], 'DE');
    expect(_shown(tester), ['de1', 'de2']);
  });

  testWidgets('a group: its countries together, the chip its short name', (
    tester,
  ) async {
    final server = _Server();
    final feed = await _pump(tester, server);
    await _pick(tester, _where, 'G7');
    expect(feed.where, const FeedWhere.group('g7'));
    final asked = server.feedRequests.last.queryParameters;
    expect(asked['group'], 'g7');
    expect(asked.containsKey('country'), isFalse);
    expect(_shown(tester), ['de1', 'us1', 'eu1', 'gb1', 'de2', 'jp1', 'us2']);
    expect(_label(tester, _where), 'G7');
    expect(_ink(tester, _where), _lightRed);
    expect(_spoken(tester, _where), 'Countries: G7');

    await _pick(tester, _where, 'European Union');
    expect(server.feedRequests.last.queryParameters['group'], 'eu');
    expect(_label(tester, _where), 'EU');
    expect(_spoken(tester, _where), 'Countries: European Union');
    expect(_shown(tester), ['de1', 'eu1', 'de2']);

    await _pick(tester, _where, 'NATO');
    expect(server.feedRequests.last.queryParameters['group'], 'nato');
    expect(_label(tester, _where), 'NATO');
    expect(_spoken(tester, _where), 'Countries: NATO');
    expect(_shown(tester), ['de1', 'us1', 'gb1', 'de2', 'us2', 'tr1']);

    await _pick(tester, _where, 'All countries');
    expect(feed.where, FeedWhere.all);
    expect(_label(tester, _where), 'All countries');
    expect(_ink(tester, _where), _black);
    final last = server.feedRequests.last.queryParameters;
    expect(last.containsKey('group'), isFalse);
    expect(last.containsKey('country'), isFalse);
  });

  testWidgets('in dark mode a chosen chip is the filter red, the rest white', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        home: CupertinoTheme(
          data: const CupertinoThemeData(brightness: Brightness.dark),
          child: Center(
            child: FeedFilterBar(
              where: const FeedWhere.group('g20'),
              whereMenu: const WhereMenu(groups: [FeedGroup('g20', 'G20')]),
              topic: 'health',
              topics: const [FeedTopic('health', 'Health')],
              onWhere: (_) {},
              onTopic: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(_label(tester, _where), 'G20');
    expect(_ink(tester, _where), _darkRed);
    expect(_chevron(tester, _topics), _darkRed);
    expect(filterRed.darkColor.toARGB32(), _darkRed);
    // The menu's checkmark is the same red.
    await tester.tap(find.byKey(_topics));
    await tester.pumpAndSettle();
    expect(_checkmark(tester), _darkRed);
    await _close(tester);
    await tester.pumpWidget(
      testApp(
        home: CupertinoTheme(
          data: const CupertinoThemeData(brightness: Brightness.dark),
          child: Center(
            child: FeedFilterBar(
              where: FeedWhere.all,
              whereMenu: const WhereMenu(),
              topic: null,
              topics: const [],
              onWhere: (_) {},
              onTopic: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(_ink(tester, _where), 0xFFFFFFFF);
    expect(_ink(tester, _topics), 0xFFFFFFFF);
  });

  test('the filter red is at least 4.5:1 on the grey chip, light and dark', () {
    // The chip's grey over the feed's white or black page, as it is drawn.
    Color chip(Color fill, Color page) => Color.alphaBlend(fill, page);
    final light = chip(
      CupertinoColors.tertiarySystemFill.color,
      const Color(0xFFFFFFFF),
    );
    final dark = chip(
      CupertinoColors.tertiarySystemFill.darkColor,
      const Color(0xFF000000),
    );
    expect(filterRed.color.toARGB32(), _lightRed);
    expect(_contrast(filterRed.color, light), greaterThanOrEqualTo(4.5));
    expect(_contrast(filterRed.darkColor, dark), greaterThanOrEqualTo(4.5));
    // The brand red is not, in dark mode: why the filters have their own.
    expect(_contrast(const Color(0xFFFA2D48), dark), lessThan(4.5));
  });

  testWidgets(
    'the Topics menu: All topics, then the busiest first, no counts',
    (tester) async {
      await _pump(tester, _Server());
      await tester.tap(find.byKey(_topics));
      await tester.pumpAndSettle();
      expect(_menu(tester), [
        'All topics',
        'Economy',
        'Health',
        'Trade',
        'Security and defence',
      ]);
      expect(find.byType(CupertinoMenuDivider), findsOneWidget);
      // Names only: no counts, no second line.
      expect(
        tester
            .widgetList<CupertinoMenuItem>(find.byType(CupertinoMenuItem))
            .map((i) => i.subtitle),
        everyElement(isNull),
      );
      // Each topic after the icon its chip shows, so the reader learns what
      // the chip's icon means; All topics has none.
      expect(_menuIcon(tester, 'All topics'), isNull);
      for (final (name, id) in [
        ('Economy', 'economy'),
        ('Health', 'health'),
        ('Trade', 'trade'),
        ('Security and defence', 'security-defence'),
      ]) {
        expect(_menuIcon(tester, name), topicIcons[id], reason: name);
      }
      // The checkmark is the filters' red.
      expect(_checked(tester), 'All topics');
      expect(_checkmark(tester), _lightRed);

      // Once chosen, the chip shows the same icon as the menu item.
      await tester.tap(find.text('Health'));
      await tester.pumpAndSettle();
      expect(_icon(tester, _topics), CupertinoIcons.staroflife_fill);
      await tester.tap(find.byKey(_topics));
      await tester.pumpAndSettle();
      expect(_menuIcon(tester, 'Health'), _icon(tester, _topics));
      expect(_checked(tester), 'Health');
    },
  );

  testWidgets('one topic at a time: the chip shows its icon in red', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server);
    await _pick(tester, _topics, 'Health');
    expect(server.feedRequests.last.queryParameters['topic'], 'health');
    expect(_shown(tester), ['us1', 'de2', 'tr1']);
    expect(_icon(tester, _topics), CupertinoIcons.staroflife_fill);
    expect(_label(tester, _topics), '');
    expect(
      find.descendant(of: find.byKey(_topics), matching: find.text('Health')),
      findsNothing,
    );
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(_topics),
        matching: find.byIcon(CupertinoIcons.staroflife_fill),
      ),
    );
    expect(icon.color!.toARGB32(), _lightRed);
    expect(_chevron(tester, _topics), _lightRed);
    expect(_spoken(tester, _topics), 'Topic: Health');

    await _pick(tester, _topics, 'Trade');
    expect(server.feedRequests.last.queryParameters['topic'], 'trade');
    expect(_icon(tester, _topics), CupertinoIcons.arrow_right_arrow_left);
    expect(_shown(tester), ['eu1']);

    await _pick(tester, _topics, 'All topics');
    expect(_label(tester, _topics), 'All topics');
    expect(_icon(tester, _topics), isNull);
    expect(
      server.feedRequests.last.queryParameters.containsKey('topic'),
      isFalse,
    );
    expect(_shown(tester), hasLength(8));
  });

  test('every topic of the fixed list has its own icon', () {
    expect(topicIcons.keys.toSet(), topicIds.toSet());
    expect(topicIcons.values.toSet(), hasLength(topicIds.length));
    expect(topicIcons.values, isNot(contains(otherTopicIcon)));
    // No icon that means something else in an app (Yurii's review, 16 Oct):
    // a heart reads as a favourite, a ticked box as chosen.
    for (final other in [
      CupertinoIcons.heart_fill,
      CupertinoIcons.checkmark_square_fill,
      CupertinoIcons.cloud_sun_fill,
    ]) {
      expect(topicIcons.values, isNot(contains(other)));
    }
  });

  test("a group's chip is its short name in the app's language", () {
    const expected = {
      FeedLanguage.en: ['EU', 'G7', 'G20', 'NATO'],
      FeedLanguage.uk: ['ЄС', 'G7', 'G20', 'НАТО'],
      FeedLanguage.ru: ['ЕС', 'G7', 'G20', 'НАТО'],
      FeedLanguage.es: ['UE', 'G7', 'G20', 'OTAN'],
      FeedLanguage.de: ['EU', 'G7', 'G20', 'NATO'],
    };
    expect(expected.keys.toSet(), FeedLanguage.values.toSet());
    for (final MapEntry(key: lang, value: short) in expected.entries) {
      final l10n = l10nFor(lang);
      expect(
        [for (final id in groupIds) groupShortName(id, l10n)],
        short,
        reason: lang.code,
      );
    }
    // A group the app does not know: its id in capitals.
    expect(groupShortName('brics', l10nFor()), 'BRICS');
  });

  testWidgets('the topics follow the Where choice', (tester) async {
    final server = _Server();
    await _pump(tester, server);
    await _pick(tester, _where, 'G7');
    expect(server.topicRequests.last.queryParameters['group'], 'g7');
    await tester.tap(find.byKey(_topics));
    await tester.pumpAndSettle();
    // No Türkiye: health is under economy now.
    expect(_menu(tester), [
      'All topics',
      'Economy',
      'Health',
      'Trade',
      'Security and defence',
    ]);
    await _close(tester);
    await _pick(tester, _where, 'Japan');
    final asked = server.topicRequests.last.queryParameters;
    expect(asked['country'], 'JP');
    expect(asked.containsKey('group'), isFalse);
    await tester.tap(find.byKey(_topics));
    await tester.pumpAndSettle();
    expect(_menu(tester), ['All topics', 'Security and defence']);
  });

  test('every request of a filtered feed carries its filters', () async {
    final server = _Server(pageSize: 1);
    final feed = FeedController(api: server.api);
    await feed.start();
    await feed.setWhere(const FeedWhere.group('nato'));
    await feed.setTopic('health');
    await _settle();
    // us1, de2, tr1: a page each.
    expect(feed.items.map((a) => a.id), ['us1']);
    await feed.loadMore();
    await feed.loadMore();
    await feed.checkForNew();
    await _settle();
    final asked = server.feedRequests.skip(2).toList();
    expect(asked, hasLength(4));
    for (final request in asked) {
      final q = request.queryParameters;
      expect(q['group'], 'nato', reason: '$request');
      expect(q['topic'], 'health', reason: '$request');
      expect(q.containsKey('country'), isFalse, reason: '$request');
    }
    expect(asked[1].queryParameters['cursor'], '1');
    expect(asked[2].queryParameters['cursor'], '2');
    expect(asked[3].queryParameters['after'], isNotNull);
    expect(feed.items.map((a) => a.id), ['us1', 'de2', 'tr1']);

    server.log.clear();
    await feed.setWhere(const FeedWhere.country('US'));
    await _settle();
    await feed.checkForNew();
    expect(
      server.feedRequests.map(
        (u) => (u.queryParameters['country'], u.queryParameters['group']),
      ),
      [('US', null), ('US', null)],
    );
    // A new Where asks for its topics once; the new check asks for no menu.
    expect(server.topicRequests, hasLength(1));
    expect(server.log.where((u) => u.path == '/countries'), isEmpty);
  });

  testWidgets('an empty group says so, and is still offered', (tester) async {
    // Nothing from the EU or its members this week.
    final server = _Server(
      articles: [
        for (final a in _week)
          if (!{'DE', 'EU'}.contains(a['country'])) a,
      ],
    );
    await _pump(tester, server);
    await _pick(tester, _topics, 'Health');
    expect(_shown(tester), ['us1', 'tr1']);
    await _pick(tester, _where, 'European Union');
    expect(_label(tester, _where), 'EU');
    expect(_shown(tester), isEmpty);
    expect(find.text('No decisions here in the last 7 days.'), findsOneWidget);
    expect(find.text('Show all countries'), findsOneWidget);
    expect(find.text('Show all topics'), findsOneWidget);
    expect(find.text('No decisions yet today.'), findsNothing);
    // Its topics are none, and the chosen one stays, checked.
    await tester.tap(find.byKey(_topics));
    await tester.pumpAndSettle();
    expect(_menu(tester), ['All topics', 'Health']);
    expect(_checked(tester), 'Health');
    await _close(tester);

    await tester.tap(find.text('Show all topics'));
    await tester.pumpAndSettle();
    expect(_label(tester, _topics), 'All topics');
    expect(find.text('No decisions here in the last 7 days.'), findsOneWidget);
    expect(find.text('Show all topics'), findsNothing);

    await tester.tap(find.text('Show all countries'));
    await tester.pumpAndSettle();
    expect(_label(tester, _where), 'All countries');
    expect(_shown(tester), ['us1', 'gb1', 'jp1', 'us2', 'tr1']);
    expect(find.text('No decisions here in the last 7 days.'), findsNothing);
  });

  testWidgets(
    'the choices are saved; the next launch opens with them, not the saved feed',
    (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _pick(tester, _where, 'G7');
      await _pick(tester, _topics, 'Economy');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('feed.where'), 'group:g7');
      expect(prefs.getString('feed.topic'), 'economy');
      // The first page kept on the phone is still the unfiltered one.
      expect(prefs.getString('feed.lastPage'), contains('"tr1"'));

      // The next launch, offline: the filtered feed is not saved, so it says
      // it could not load, rather than showing other countries' news.
      final next = _Server()..offline = true;
      await tester.pumpWidget(const SizedBox());
      final feed = await _pump(tester, next);
      expect(feed.where, const FeedWhere.group('g7'));
      expect(feed.topic, 'economy');
      expect(_label(tester, _where), 'G7');
      expect(_icon(tester, _topics), CupertinoIcons.chart_bar_alt_fill);
      expect(_spoken(tester, _topics), 'Topic: Economy');
      expect(_shown(tester), isEmpty);
      expect(
        find.text("Couldn't load the news. Pull down to retry."),
        findsOneWidget,
      );
      expect(next.feedRequests.first.queryParameters['group'], 'g7');
      expect(next.feedRequests.first.queryParameters['topic'], 'economy');
      // The saved menu, offline.
      await tester.tap(find.byKey(_where));
      await tester.pumpAndSettle();
      expect(_menu(tester), hasLength(10));
      expect(_checked(tester), 'G7');
      await _close(tester);

      // All countries and all topics open from the saved page at once.
      await _pick(tester, _where, 'All countries');
      await _pick(tester, _topics, 'All topics');
      expect(_shown(tester), hasLength(8));
      expect(prefs.getString('feed.where'), isNull);
      expect(prefs.getString('feed.topic'), isNull);
    },
  );

  test('one country is saved and asked again after a restart', () async {
    final server = _Server();
    final feed = FeedController(api: server.api);
    await feed.start();
    await feed.setWhere(const FeedWhere.country('JP'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('feed.where'), 'country:JP');
    server.log.clear();
    final next = FeedController(api: server.api);
    await next.start();
    await _settle();
    expect(next.where, const FeedWhere.country('JP'));
    expect(server.feedRequests.map((u) => u.queryParameters['country']), [
      'JP',
    ]);
  });

  test(
    'a Local saved by the first filters build opens on every country',
    () async {
      SharedPreferences.setMockInitialValues({
        'feed.scope': 'local',
        'feed.country': 'DE',
        'feed.countries.en': '[{"code":"DE","name":"Germany"}]',
        'feed.topic': 'health',
      });
      final server = _Server();
      final feed = FeedController(api: server.api);
      await feed.start();
      await _settle();
      expect(feed.where, FeedWhere.all);
      final asked = server.feedRequests.single.queryParameters;
      expect(asked.containsKey('country'), isFalse);
      expect(asked.containsKey('group'), isFalse);
      // The topic was its own choice and stays.
      expect(asked['topic'], 'health');
      final prefs = await SharedPreferences.getInstance();
      for (final key in ['feed.scope', 'feed.country', 'feed.countries.en']) {
        expect(prefs.containsKey(key), isFalse, reason: key);
      }
      expect(prefs.getString('feed.topic'), 'health');
    },
  );

  test('a saved value it cannot read is every country', () {
    for (final saved in [null, '', 'local', 'global', 'country:', 'x:y']) {
      expect(FeedWhere.fromSaved(saved), FeedWhere.all, reason: saved);
    }
    for (final where in const [
      FeedWhere.all,
      FeedWhere.group('g20'),
      FeedWhere.country('GB'),
    ]) {
      expect(FeedWhere.fromSaved(where.saved), where);
    }
  });

  testWidgets('the analytics event says what the filters are now', (
    tester,
  ) async {
    await _pump(tester, _Server());
    await _pick(tester, _where, 'G7');
    await _pick(tester, _topics, 'Health');
    await _pick(tester, _topics, 'Health'); // no change: no event
    await _pick(tester, _where, 'United Kingdom');
    await _pick(tester, _where, 'All countries');
    expect(filterEvents(), [
      {'where': 'group', 'place': 'g7', 'topic': 'all'},
      {'where': 'group', 'place': 'g7', 'topic': 'health'},
      {'where': 'country', 'place': 'GB', 'topic': 'health'},
      {'where': 'all', 'place': 'all', 'topic': 'health'},
    ]);
    // Never `value`: Google Analytics keeps it for a number and drops a text.
    for (final e in filterEvents()) {
      expect(e.containsKey('value'), isFalse);
    }
  });

  testWidgets('a chosen country the menu does not list stays in it, checked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'feed.where': 'country:CA'});
    final server = _Server();
    await _pump(tester, server);
    expect(server.feedRequests.single.queryParameters['country'], 'CA');
    expect(_label(tester, _where), 'CA');
    expect(_spoken(tester, _where), 'Country: Canada');
    expect(_shown(tester), isEmpty);
    expect(find.text('Show all countries'), findsOneWidget);
    // The button that undoes a filter is the filters' red.
    expect(
      tester
          .widget<Text>(find.text('Show all countries'))
          .style!
          .color!
          .toARGB32(),
      _lightRed,
    );
    await tester.tap(find.byKey(_where));
    await tester.pumpAndSettle();
    expect(_menu(tester).sublist(5, 7), ['Canada', 'Germany']);
    expect(_checked(tester), 'Canada');
  });

  testWidgets("a group or country the app does not know: the server's name", (
    tester,
  ) async {
    final server = _Server(
      groupIds: const ['eu', 'g7', 'g20', 'nato', 'brics'],
      countries: const ['DE', 'NZ'],
    );
    await _pump(tester, server);
    await tester.tap(find.byKey(_where));
    await tester.pumpAndSettle();
    expect(_menu(tester).sublist(4), [
      'NATO',
      'BRICS',
      'Germany',
      'New Zealand',
    ]);
    await tester.tap(find.text('BRICS'));
    await tester.pumpAndSettle();
    expect(server.feedRequests.last.queryParameters['group'], 'brics');
    expect(_label(tester, _where), 'BRICS');
    expect(_spoken(tester, _where), 'Countries: BRICS');
    await _pick(tester, _where, 'New Zealand');
    expect(_label(tester, _where), 'NZ');
    expect(_spoken(tester, _where), 'Country: New Zealand');
  });

  testWidgets("a topic the app does not know yet: the server's name", (
    tester,
  ) async {
    final server = _Server(extraTopics: const ['education']);
    await _pump(tester, server);
    await _pick(tester, _topics, 'Education');
    expect(server.feedRequests.last.queryParameters['topic'], 'education');
    expect(_icon(tester, _topics), otherTopicIcon);
    expect(_spoken(tester, _topics), 'Topic: Education');
  });

  group('a server from before the groups', () {
    testWidgets('the menu has every country and the countries, no crash', (
      tester,
    ) async {
      final server = _Server(groups: false);
      final feed = await _pump(tester, server);
      expect(feed.whereMenu!.groups, isNull);
      await tester.tap(find.byKey(_where));
      await tester.pumpAndSettle();
      expect(_menu(tester), [
        'All countries',
        'Germany',
        'Japan',
        'Türkiye',
        'United Kingdom',
        'United States',
      ]);
      expect(find.byType(CupertinoMenuDivider), findsOneWidget);
      await tester.tap(find.text('Japan'));
      await tester.pumpAndSettle();
      expect(server.feedRequests.last.queryParameters['country'], 'JP');
      expect(_label(tester, _where), 'JP');
    });

    test(
      'a saved group shows every country, and comes back with them',
      () async {
        SharedPreferences.setMockInitialValues({'feed.where': 'group:g7'});
        final old = _Server(groups: false);
        final feed = FeedController(api: old.api);
        await feed.start();
        await _settle();
        // G7 before the menu, every country once it says there are no groups.
        expect(old.feedRequests.map((u) => u.queryParameters['group']), [
          'g7',
          null,
        ]);
        expect(feed.where, FeedWhere.all);
        expect(feed.filtered, isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('feed.where'), 'group:g7'); // kept

        // The next launch knows the menu at once: no G7 request at all.
        old.log.clear();
        final next = FeedController(api: old.api);
        await next.start();
        await _settle();
        expect(old.feedRequests.map((u) => u.queryParameters['group']), [null]);

        // A server with the groups: G7 again, as it was chosen.
        final updated = _Server();
        final later = FeedController(api: updated.api);
        await later.start();
        await _settle();
        expect(updated.feedRequests.map((u) => u.queryParameters['group']), [
          null,
          'g7',
        ]);
        expect(later.where, const FeedWhere.group('g7'));
      },
    );

    test('All countries chosen then is saved, and nothing reloads', () async {
      SharedPreferences.setMockInitialValues({'feed.where': 'group:g7'});
      final old = _Server(groups: false);
      final feed = FeedController(api: old.api);
      await feed.start();
      await _settle();
      old.log.clear();
      await feed.setWhere(FeedWhere.all);
      expect(old.feedRequests, isEmpty);
      expect(filterEvents(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('feed.where'), isNull);
    });
  });

  test('a group the server no longer lists is never asked for', () async {
    SharedPreferences.setMockInitialValues({'feed.where': 'group:brics'});
    final server = _Server();
    final feed = FeedController(api: server.api);
    await feed.start();
    await _settle();
    // Asked before the menu said (a 400), then every country.
    expect(server.feedRequests.map((u) => u.queryParameters['group']), [
      'brics',
      null,
    ]);
    expect(feed.where, FeedWhere.all);
    expect(feed.error, isNull);
    expect(feed.items, hasLength(8));
  });

  group('a server without /topics and /countries', () {
    testWidgets('no Where or Topics chip', (tester) async {
      final server = _Server(menus: false);
      final feed = await _pump(tester, server);
      expect(find.byKey(_topics), findsNothing);
      expect(feed.topics, isNull);
      // Such a server ignores country= and group=.
      expect(find.byKey(_where), findsNothing);
      expect(feed.whereMenu, isNull);
      expect(
        server.feedRequests.where(
          (u) =>
              u.queryParameters.containsKey('country') ||
              u.queryParameters.containsKey('group'),
        ),
        isEmpty,
      );
    });

    test(
      'a chosen country shows every country, and the next launch starts so',
      () async {
        SharedPreferences.setMockInitialValues({'feed.where': 'country:DE'});
        final server = _Server(menus: false);
        final feed = FeedController(api: server.api);
        await feed.start();
        await _settle();
        // DE before the answer, every country after it.
        expect(server.feedRequests.map((u) => u.queryParameters['country']), [
          'DE',
          null,
        ]);
        expect(feed.where, FeedWhere.all);

        server.log.clear();
        final next = FeedController(api: server.api);
        await next.start();
        await _settle();
        expect(server.feedRequests.map((u) => u.queryParameters['country']), [
          null,
        ]);

        // A server with the filters again: the country is back, as chosen.
        final updated = _Server();
        final later = FeedController(api: updated.api);
        await later.start();
        await _settle();
        expect(updated.feedRequests.map((u) => u.queryParameters['country']), [
          null,
          'DE',
        ]);
        expect(later.where, const FeedWhere.country('DE'));
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('feed.noCountries'), isNull);
      },
    );

    testWidgets('a topic chosen before stays, so it can be cleared', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'feed.topic': 'health'});
      final server = _Server(menus: false);
      await _pump(tester, server);
      expect(_spoken(tester, _topics), 'Topic: Health'); // the app's own name
      await _pick(tester, _topics, 'All topics');
      expect(find.byKey(_topics), findsNothing);
    });
  });

  testWidgets('Settings has no Country any more', (tester) async {
    await _pump(tester, _Server());
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Country'), findsNothing);
  });

  group("names in the app's language", () {
    testWidgets('the menus and chips, in Ukrainian', (tester) async {
      SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
      final server = _Server();
      await _pump(tester, server, words: FeedLanguage.uk);
      expect(server.topicRequests.single.queryParameters['lang'], 'uk');
      expect(
        server.log
            .where((u) => u.path == '/countries')
            .single
            .queryParameters['lang'],
        'uk',
      );
      expect(_label(tester, _where), 'Усі країни');
      expect(_label(tester, _topics), 'Усі теми');
      await tester.tap(find.byKey(_where));
      await tester.pumpAndSettle();
      expect(_menu(tester), [
        'Усі країни',
        'Європейський Союз',
        'G7',
        'G20',
        'НАТО',
        'Велика Британія',
        'Німеччина',
        'США',
        'Туреччина',
        'Японія',
      ]);
      await tester.tap(find.text('Велика Британія'));
      await tester.pumpAndSettle();
      // The code stays the ISO code, in Latin letters.
      expect(_label(tester, _where), 'GB');
      expect(_spoken(tester, _where), 'Країна: Велика Британія');
      // A group's chip is its short name in the language, as the menu
      // writes it: НАТО, ЄС; G7 and G20 as everywhere.
      await _pick(tester, _where, 'НАТО');
      expect(_label(tester, _where), 'НАТО');
      expect(_spoken(tester, _where), 'Країни: НАТО');
      await _pick(tester, _where, 'Європейський Союз');
      expect(_label(tester, _where), 'ЄС');
      expect(_spoken(tester, _where), 'Країни: Європейський Союз');
      await _pick(tester, _where, 'G7');
      expect(_label(tester, _where), 'G7');
      await _pick(tester, _topics, 'Економіка');
      expect(_spoken(tester, _topics), 'Тема: Економіка');
      // The Topics menu in Ukrainian has the same icons.
      await tester.tap(find.byKey(_topics));
      await tester.pumpAndSettle();
      expect(_menuIcon(tester, 'Економіка'), topicIcons['economy']);
      expect(_menuIcon(tester, 'Усі теми'), isNull);
    });

    test('another language, offline: names in it, not the old one', () async {
      SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
      final server = _Server();
      final feed = FeedController(api: server.api);
      await feed.start();
      await _settle();
      await feed.setTopic('economy');
      await feed.setWhere(const FeedWhere.group('nato'));
      await _settle();
      server.offline = true;
      await feed.setLanguage(FeedLanguage.de);
      await _settle();
      final de = l10nFor(FeedLanguage.de);
      final menu = feed.whereMenu;
      expect(topicName('economy', feed.topics, de), 'Wirtschaft');
      expect(
        [for (final g in menu!.groups!) groupName(g.id, menu, de)],
        ['Europäische Union', 'G7', 'G20', 'NATO'],
      );
      expect(
        [for (final c in menu.countries) whereCountryName(c.code, menu, de)],
        [
          'Vereinigtes Königreich',
          'Deutschland',
          'Vereinigte Staaten',
          'Türkei',
          'Japan',
        ],
      );
    });

    testWidgets('a topic not in the menu, also after a restart', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'feed.lang': 'uk'});
      await _pump(tester, _Server(), words: FeedLanguage.uk);
      await _pick(tester, _topics, 'Торгівля');
      // Japan has no trade decisions: its menu has none.
      await _pick(tester, _where, 'Японія');
      expect(_spoken(tester, _topics), 'Тема: Торгівля');
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, _Server()..offline = true, words: FeedLanguage.uk);
      expect(_spoken(tester, _topics), 'Тема: Торгівля');
      expect(_spoken(tester, _where), 'Країна: Японія');
    });
  });
}
