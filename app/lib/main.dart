import 'dart:async';

import 'package:flutter/material.dart';

import 'core/analytics.dart';
import 'core/push.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/feed/feed_controller.dart';
import 'features/splash/splash.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The language is read before the first frame (#52), so no word shows in
  // another language first; the launch screen stays up meanwhile.
  final feed = FeedController();
  await feed.open();
  // Not awaited: the feed shows at once; events before Firebase is up are not sent.
  unawaited(_startFirebase(feed));
  runApp(OfficialNewsApp(feed: feed));
}

/// Analytics, then push notifications, which need Firebase too (#62). Both
/// take the feed's language, so a first launch uses the phone's.
Future<void> _startFirebase(FeedController feed) async {
  if (await startAnalytics(language: feed.languageChanges)) {
    await startPush(language: feed.languageChanges);
  }
}

/// The app. One language setting drives everything (#52): the feed's language
/// is also the language of every word the app shows, its dates and the system's
/// own words (the back button, VoiceOver hints), so changing it in Settings
/// redraws the whole app in it at once.
class OfficialNewsApp extends StatelessWidget {
  OfficialNewsApp({super.key, required this.feed});

  /// The feed lives as long as the app: its language is the app's language.
  final FeedController feed;

  /// Made once, so a language change keeps the same observers (an offer
  /// waiting for the article to slide away is not lost).
  final navigatorObservers = <NavigatorObserver>[ScreenViews(), PushOffer()];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: feed.languageChanges,
      builder: (context, language, _) => ValueListenableBuilder(
        // The headline weight from Settings → Design (#66) is in the theme.
        valueListenable: headlineWeight,
        builder: (context, weight, _) => MaterialApp(
          title: 'Official News',
          debugShowCheckedModeBanner: false,
          locale: language.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(Brightness.light, headline: weight),
          darkTheme: buildTheme(Brightness.dark, headline: weight),
          themeMode: ThemeMode.system,
          onGenerateRoute: (settings) => onGenerateRoute(settings, feed: feed),
          navigatorKey: appNavigator,
          navigatorObservers: navigatorObservers,
          initialRoute: Routes.feed,
          // The splash over the feed at start (#66); the feed loads under it.
          builder: (context, app) => SplashHost(child: app!),
        ),
      ),
    );
  }
}
