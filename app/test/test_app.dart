import 'package:flutter/material.dart';
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
