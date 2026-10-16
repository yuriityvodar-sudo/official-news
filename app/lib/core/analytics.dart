import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'article.dart';
import 'feed_language.dart';
import 'filters.dart';

/// Sends one event: its name and parameters (Google Analytics limits: names
/// up to 40 characters, text values up to 100).
typedef SendEvent =
    Future<void> Function(String name, Map<String, Object> parameters);

/// Sets a user property. It marks this phone's later events only (Google
/// Analytics never applies one backwards), so each is set from the first build.
typedef SetUserProperty = Future<void> Function(String name, String value);

/// Product analytics (#60): Google Analytics through Firebase, project
/// `official-news-48e16`. Off until [startAnalytics] finds the Firebase values
/// the TestFlight build passes in (`--dart-define`, from the GitHub secret
/// GOOGLE_SERVICE_INFO_PLIST); tests and local runs have none, so they send
/// nothing. No advertising ID and no tracking prompt.
///
/// From LyFi's lessons (docs in ~/Documents/lyfi): a read is attention, not a
/// screen opened ([articleRead]); the feed's depth is a value in the event name
/// ([feedDepth]), so it counts without a custom dimension; the team's phones
/// are told apart from day one (user property `build`).
class Analytics {
  /// Off without [_send].
  Analytics([this._send, this._setUser]);

  final SendEvent? _send;
  final SetUserProperty? _setUser;

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

  Future<void> _user(String name, String value) async {
    final set = _setUser;
    if (set == null) return;
    try {
      await set(name, value);
    } catch (error) {
      debugPrint('analytics: user property $name not set: $error');
    }
  }

  /// A screen shown: `feed` or `article`.
  Future<void> screen(String name) =>
      _event('screen_view', {'screen_name': name, 'screen_class': name});

  /// The language the feed is read in, on this phone's later events.
  Future<void> feedLanguage(FeedLanguage language) =>
      _user('feed_language', language.code);

  /// The reader chose another language for the feed.
  Future<void> languageChosen(
    FeedLanguage chosen, {
    required FeedLanguage from,
  }) async {
    await _event('select_language', {
      'language': chosen.code,
      'previous_language': from.code,
    });
    await feedLanguage(chosen);
  }

  /// The reader changed a filter (#67, #68), from the chips or the Country in
  /// Settings: the filters as they are now. `scope` is `global` or `local`;
  /// `country` is Local's country (also while Global is shown), `none` when
  /// there is none; `topic` is the topic's id or `all`.
  Future<void> filterChanged({
    required FeedScope scope,
    String? country,
    String? topic,
  }) => _event('filter_changed', {
    'scope': scope.name,
    'country': country ?? 'none',
    'topic': topic ?? 'all',
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

  /// An article read: its screen stayed open, with the app in front, for
  /// [ArticleReadTimer.after]. Opened against read is the number that says
  /// whether the summaries are worth it.
  Future<void> articleRead(Article article) =>
      _event('article_read', _about(article));

  /// The official page opened from an article.
  Future<void> officialLinkOpened(Article article) =>
      _event('open_official_link', _about(article));

  /// The share sheet opened for an article.
  Future<void> shared(Article article) => _event('share', {
    'content_type': 'article',
    'item_id': article.id,
    ..._about(article),
  });

  /// How far down the feed the reader came this visit: the first time a row
  /// of [feedDepths] is shown, `feed_scroll_10`, `feed_scroll_25` and so on.
  Future<void> feedDepth(int rows) => _event('feed_scroll_$rows', const {});

  /// The feed's first page did not load (offline, or the server failed).
  Future<void> feedFailed() => _event('feed_load_failed', const {});

  /// The answer about notifications (#62): `granted` or `denied` to the iOS
  /// question, `not_now` to the app's own explanation before it. [trigger] is
  /// what asked: `reads` (after the third article read) or `settings`.
  Future<void> pushPermission(String result, {required String trigger}) =>
      _event('push_permission', {'result': result, 'trigger': trigger});

  /// A notification tapped: the article it opens, in its language.
  Future<void> pushOpened({required String articleId, required String lang}) =>
      _event('push_open', {'article_id': articleId, 'lang': lang});

  /// Whether this phone gets notifications, on its later events: `on`, `off`
  /// or `not_asked`, so returns can be compared with and without them.
  Future<void> pushState(String state) => _user('notifications', state);

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

/// The feed depths [Analytics.feedDepth] reports, in rows of the Latest list.
const feedDepths = [10, 25, 50, 100];

/// The app's analytics; off until [startAnalytics] turns it on.
Analytics analytics = Analytics();

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

/// Calls [onRead] once the article has been open for [after] with the app in
/// front: time in the background does not count, and coming back starts the
/// wait again. Nothing when the screen closes first.
class ArticleReadTimer with WidgetsBindingObserver {
  ArticleReadTimer(this.onRead, {this.after = const Duration(seconds: 15)}) {
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  final VoidCallback onRead;
  final Duration after;
  Timer? _timer;
  bool _done = false;

  void _start() {
    if (_done) return;
    _timer?.cancel();
    _timer = Timer(after, () {
      _done = true;
      onRead();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
    }
  }

  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _appId = String.fromEnvironment('FIREBASE_APP_ID');
const _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

/// Which build this is: `testflight` (only the team's phones so far), later
/// `store`; set by the workflow that builds it. A user property, so the team's
/// use can be left out of every report.
const _build = String.fromEnvironment('APP_BUILD', defaultValue: 'dev');

/// Turns analytics on when the build has the Firebase values; otherwise it stays off.
/// [language] is the feed's ([FeedController.languageChanges]), so the user
/// property is the language the app is read in, the phone's on a first launch.
/// True when Firebase started, so push notifications can start too (#62).
Future<bool> startAnalytics({
  required ValueListenable<FeedLanguage> language,
}) async {
  if ([_apiKey, _appId, _senderId, _projectId].any((v) => v.isEmpty)) {
    return false;
  }
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
  } catch (error) {
    debugPrint('analytics: off, Firebase did not start: $error');
    return false;
  }
  try {
    final ga = FirebaseAnalytics.instance;
    await ga.setAnalyticsCollectionEnabled(true);
    await useAnalytics(
      Analytics(
        (name, parameters) => name == 'screen_view'
            ? ga.logScreenView(
                screenName: parameters['screen_name'] as String,
                screenClass: parameters['screen_class'] as String,
              )
            : ga.logEvent(name: name, parameters: parameters),
        (name, value) => ga.setUserProperty(name: name, value: value),
      ),
      language: language,
    );
  } catch (error) {
    debugPrint('analytics: not fully started: $error');
  }
  return true;
}

/// Makes [instance] the app's analytics and sets this phone's user properties:
/// the build, and the language the feed is read in now. That is the feed's own
/// value, not the saved one: with nothing saved the app follows the phone (#52),
/// and a language chosen while Firebase was starting is counted too.
/// [Analytics.languageChosen] keeps it current from then on.
Future<void> useAnalytics(
  Analytics instance, {
  required ValueListenable<FeedLanguage> language,
}) async {
  analytics = instance;
  await instance._user('build', _build);
  await instance.feedLanguage(language.value);
}
