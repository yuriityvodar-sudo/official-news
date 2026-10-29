import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'article.dart';
import 'feed_design.dart';
import 'feed_language.dart';
import 'filters.dart';
import 'theme.dart' show HeadlineWeight;

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

  /// The reader changed what the feed shows (#170): `where` is `forYou` or
  /// `all` (the whole world), `topic` the topic's id, or `all`. Builds before
  /// For you also sent `group` or `country` as `where`, with `place` the
  /// group's id or the country's code (#68). Not `value`: Google Analytics
  /// keeps that name for an event's number, and drops a text in it
  /// (`firebase_error` 18).
  Future<void> filterChanged({required FeedWhere where, String? topic}) =>
      _event('filter_changed', {'where': where.name, 'topic': topic ?? 'all'});

  /// An article opened from the feed: [section] is `feed`, the one list
  /// (Yurii, 16 Oct; builds before it sent `top` or `latest`), and
  /// [position] its place in the list as shown, filters applied, from 0.
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

  /// "Discuss with AI" tapped under a summary (#141, #133): until the chat is
  /// built it opens a note about it, so the taps measure whether it is wanted.
  Future<void> discussAiTapped(Article article) =>
      _event('discuss_ai_tap', _about(article));

  /// "Tell me when it's ready" tapped in the AI chat's note (#160), once per
  /// phone: with the taps on "Discuss with AI", how many readers want the chat.
  Future<void> aiChatInterest() => _event('ai_chat_interest', const {});

  /// The AI chat's paywall shown over an article (#146).
  Future<void> paywallView(Article article) =>
      _event('paywall_view', _about(article));

  /// Subscribe tapped on the paywall, and how it ended: `purchased`,
  /// `cancelled`, `failed` or `pending` (Ask to Buy).
  Future<void> subscribeTap() => _event('subscribe_tap', const {});
  Future<void> subscribeResult(String result) =>
      _event('subscribe_result', {'result': result});

  /// Restore Purchases on the paywall: `restored`, `nothing` or `failed`.
  Future<void> restoreResult(String result) =>
      _event('restore_result', {'result': result});

  /// The top-up sheet shown, once the day's questions were used up (#146).
  Future<void> topUpView() => _event('topup_view', const {});

  /// How a pack's purchase ended: `credited`, `cancelled`, `failed` or
  /// `pending`, and which pack (`50` or `200` questions).
  Future<void> topUpResult(String result, {required int questions}) =>
      _event('topup_result', {'result': result, 'questions': questions});

  /// A question to the AI agent: the article and the question's number in the
  /// conversation, never its text (#146).
  Future<void> chatQuestion(Article article, int number) =>
      _event('chat_question', {'number': number, ..._about(article)});

  /// A look chosen in Settings → Design (Yurii, 28 Oct: which design options
  /// readers prefer), the look in the event's name (`design_garnet`), so it
  /// counts without a custom dimension. The look in use is the user property
  /// `feed_design` ([useAnalytics]).
  Future<void> designChosen(FeedDesign design) =>
      _event('design_${design.name}', const {});

  /// A headline weight chosen in Settings (`headline_bold`); the one in use is
  /// the user property `headline_weight`.
  Future<void> headlineWeightChosen(HeadlineWeight weight) =>
      _event('headline_${weight.name}', const {});

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

  /// The reader's own country for For you (#170), on their later events: two
  /// letters, or `none` while the app knows none. The country only, nothing
  /// else about the reader.
  Future<void> homeCountry(String? code) =>
      _user('home_country', code ?? 'none');

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

/// The feed depths [Analytics.feedDepth] reports, in rows of the feed.
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

/// Which build this is: `testflight` for the team's phones, `store` for the
/// build submitted to the App Store, `dev` for a local one; the TestFlight
/// workflow sets it from its `build` choice (#137). A user property, so the
/// team's use can be left out of every report.
const _build = String.fromEnvironment('APP_BUILD', defaultValue: 'dev');

/// Turns analytics on when the build has the Firebase values; otherwise it stays off.
/// [language] is the feed's ([FeedController.languageChanges]), so the user
/// property is the language the app is read in, the phone's on a first launch.
/// True when Firebase started, so push notifications can start too (#62).
Future<bool> startAnalytics({
  required ValueListenable<FeedLanguage> language,
  ValueListenable<FeedDesign>? design,
  ValueListenable<HeadlineWeight>? weight,
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
      design: design,
      weight: weight,
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
/// [Analytics.languageChosen] keeps it current from then on. With [design]
/// and [weight], also the look the feed is read in and the headlines' weight
/// (`feed_design`, `headline_weight`), kept current as they change, also when
/// the saved ones are restored at start, so every event can be split by them.
Future<void> useAnalytics(
  Analytics instance, {
  required ValueListenable<FeedLanguage> language,
  ValueListenable<FeedDesign>? design,
  ValueListenable<HeadlineWeight>? weight,
}) async {
  analytics = instance;
  await instance._user('build', _build);
  await instance.feedLanguage(language.value);
  if (design != null) {
    await instance._user('feed_design', design.value.name);
    design.addListener(
      () => unawaited(instance._user('feed_design', design.value.name)),
    );
  }
  if (weight != null) {
    await instance._user('headline_weight', weight.value.name);
    weight.addListener(
      () => unawaited(instance._user('headline_weight', weight.value.name)),
    );
  }
}
