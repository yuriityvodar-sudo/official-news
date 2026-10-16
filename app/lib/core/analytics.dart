import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

import 'article.dart';
import 'feed_language.dart';

/// Sends one event: its name and parameters (Google Analytics limits: names
/// up to 40 characters, text values up to 100).
typedef SendEvent =
    Future<void> Function(String name, Map<String, Object> parameters);

/// Product analytics (#60): Google Analytics through Firebase, project
/// `official-news-48e16`. Off until [startAnalytics] finds the Firebase values
/// the TestFlight build passes in (`--dart-define`, from the GitHub secret
/// GOOGLE_SERVICE_INFO_PLIST); tests and local runs have none, so they send
/// nothing. No advertising ID and no tracking prompt.
class Analytics {
  /// Off without [_send].
  Analytics([this._send]);

  final SendEvent? _send;

  /// Whether events go anywhere.
  bool get on => _send != null;

  Future<void> _event(String name, Map<String, Object> parameters) async {
    final send = _send;
    if (send == null) return;
    try {
      await send(name, parameters);
    } catch (error) {
      // Analytics never breaks the app.
      debugPrint('analytics: $name not sent: $error');
    }
  }

  /// A screen shown: `feed` or `article`.
  Future<void> screen(String name) =>
      _event('screen_view', {'screen_name': name, 'screen_class': name});

  /// The reader chose another language for the feed.
  Future<void> languageChosen(
    FeedLanguage chosen, {
    required FeedLanguage from,
  }) => _event('select_language', {
    'language': chosen.code,
    'previous_language': from.code,
  });

  /// An article opened from the feed: from `top` (Top stories) or `latest`.
  Future<void> articleOpened(
    Article article, {
    required String section,
    required int position,
  }) => _event('open_article', {
    ..._about(article),
    'section': section,
    'position': position,
  });

  /// The official page opened from an article.
  Future<void> officialLinkOpened(Article article) =>
      _event('open_official_link', _about(article));

  /// The share sheet opened for an article.
  Future<void> shared(Article article) => _event('share', {
    'content_type': 'article',
    'item_id': article.id,
    ..._about(article),
  });

  /// What an event says about its article: no text of it, only where it is from and what it is.
  static Map<String, Object> _about(Article a) => {
    'article_id': a.id,
    'country': a.country,
    'source_id': a.source.id,
    'decision_type': a.decisionType ?? 'none',
    'topic': a.topics.isEmpty ? 'none' : a.topics.first,
    'feed_language': a.lang ?? 'en',
  };
}

/// Sends a screen view for each screen shown: when it opens and when the
/// reader comes back to it. The screen is the route's name without its slash
/// (`/` is `feed`).
class ScreenViews extends NavigatorObserver {
  static String _name(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null) return '';
    return name == '/' ? 'feed' : name.replaceFirst('/', '');
  }

  void _shown(Route<dynamic>? route) {
    final name = _name(route);
    if (name.isNotEmpty) {
      analytics.screen(name);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _shown(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _shown(previousRoute);
}

/// The app's analytics; off until [startAnalytics] turns it on.
Analytics analytics = Analytics();

const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

/// Turns analytics on when the build has the Firebase values; otherwise it stays off.
Future<void> startAnalytics() async {
  if ([_apiKey, _appId, _senderId, _projectId].any((v) => v.isEmpty)) return;
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: _apiKey,
        appId: _appId,
        messagingSenderId: _senderId,
        projectId: _projectId,
        iosBundleId: 'com.officialnews.app',
      ),
    );
    final ga = FirebaseAnalytics.instance;
    await ga.setAnalyticsCollectionEnabled(true);
    analytics = Analytics(
      (name, parameters) => name == 'screen_view'
          ? ga.logScreenView(
              screenName: parameters['screen_name'] as String,
              screenClass: parameters['screen_class'] as String,
            )
          : ga.logEvent(name: name, parameters: parameters),
    );
  } catch (error) {
    debugPrint('analytics: off, Firebase did not start: $error');
  }
}
