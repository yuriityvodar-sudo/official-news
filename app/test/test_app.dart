import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:official_news/core/countries.dart';
import 'package:official_news/core/topics.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/l10n/app_localizations.dart';

/// A screen under test in a MaterialApp with the app's localizations (#52):
/// its words, dates and the system's own words, in English unless [language]
/// says otherwise.
Widget testApp({
  Widget? home,
  RouteFactory? onGenerateRoute,
  FeedLanguage language = FeedLanguage.en,
  List<NavigatorObserver> navigatorObservers = const [],
}) => MaterialApp(
  theme: buildTheme(Brightness.light),
  locale: language.locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  onGenerateRoute: onGenerateRoute,
  navigatorObservers: navigatorObservers,
  home: home,
);

/// The app's words in [language], for texts checked outside a screen.
AppLocalizations l10nFor([FeedLanguage language = FeedLanguage.en]) =>
    lookupAppLocalizations(language.locale);

/// What a fake server answers for the real filter bar's menus (#67, #68):
/// a few countries and groups, and every topic the app knows, named in the
/// request's language. Null for any other request, which the fake answers
/// itself. Without this, the bar reads an articles page as a menu, gives up
/// and hides its chips.
http.Response? fakeMenus(http.Request request) {
  final lang = FeedLanguage.fromCode(request.url.queryParameters['lang'] ?? 'en');
  final l10n = l10nFor(lang);
  return switch (request.url.path) {
    '/countries' => fakeJson({
      'groups': [
        {'id': 'eu', 'name': 'EU', 'members': ['DE', 'PL', 'EU']},
        {'id': 'g7', 'name': 'G7', 'members': ['DE', 'GB', 'US']},
      ],
      'countries': [
        for (final code in ['DE', 'GB', 'PL', 'US'])
          {'code': code, 'name': countryName(code, l10n)},
      ],
    }),
    '/topics' => fakeJson({
      'topics': [
        for (final id in topicIds) {'id': id, 'name': topicLabel(id, l10n) ?? id},
      ],
    }),
    _ => null,
  };
}

http.Response fakeJson(Object body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// [items] as the server narrows them by `topic=`, `country=` and `group=`
/// (the groups of [fakeMenus]).
List<Map<String, dynamic>> fakeFiltered(
  List<Map<String, dynamic>> items,
  Map<String, String> q,
) {
  const groups = {
    'eu': ['DE', 'PL', 'EU'],
    'g7': ['DE', 'GB', 'US'],
  };
  final topic = q['topic'];
  final country = q['country'];
  final group = q['group'];
  return [
    for (final a in items)
      if ((topic == null || (a['topics'] as List? ?? const []).contains(topic)) &&
          (country == null || a['country'] == country) &&
          (group == null || (groups[group] ?? const []).contains(a['country'])))
        a,
  ];
}

/// A page's `items` and `top` narrowed by [q] ([fakeFiltered]); null stays null.
Map<String, dynamic>? fakePage(Map<String, dynamic>? page, Map<String, String> q) =>
    page == null
    ? null
    : {
        ...page,
        'items': fakeFiltered((page['items'] as List).cast<Map<String, dynamic>>(), q),
        'top': fakeFiltered((page['top'] as List? ?? const []).cast<Map<String, dynamic>>(), q),
      };
