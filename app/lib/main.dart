import 'dart:async';

import 'package:flutter/material.dart';

import 'core/analytics.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/feed/feed_controller.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The language is read before the first frame (#52), so no word shows in
  // another language first; the launch screen stays up meanwhile.
  final feed = FeedController();
  await feed.open();
  // Not awaited: the feed shows at once; events before Firebase is up are not sent.
  // Its language is the feed's, so a first launch reports the phone's.
  unawaited(startAnalytics(language: feed.languageChanges));
  runApp(OfficialNewsApp(feed: feed));
}

/// The app. One language setting drives everything (#52): the feed's language
/// is also the language of every word the app shows, its dates and the system's
/// own words (the back button, VoiceOver hints), so changing it in Settings
/// redraws the whole app in it at once.
class OfficialNewsApp extends StatelessWidget {
  const OfficialNewsApp({super.key, required this.feed});

  /// The feed lives as long as the app: its language is the app's language.
  final FeedController feed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: feed.languageChanges,
      builder: (context, language, _) => MaterialApp(
        title: 'Official News',
        debugShowCheckedModeBanner: false,
        locale: language.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        onGenerateRoute: (settings) => onGenerateRoute(settings, feed: feed),
        navigatorObservers: [ScreenViews()],
        initialRoute: Routes.feed,
      ),
    );
  }
}
