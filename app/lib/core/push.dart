import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics.dart';
import 'api_client.dart';
import 'article.dart';
import 'feed_language.dart';
import 'router.dart';

/// Whether this phone gets notifications of breaking decisions (#62).
enum PushPermission {
  /// Push is off in this build: no Firebase values (tests, local runs), or
  /// Firebase did not start.
  unavailable,

  /// iOS has not asked yet.
  notAsked,

  /// Notifications allowed.
  granted,

  /// Not allowed: "Don't Allow" to iOS, or turned off in the iOS Settings app.
  /// iOS never asks again; only the Settings app can turn them on.
  denied,
}

/// What a notification carries besides its text (docs/contract.md, Push
/// notifications in the app): the article to open and its language.
class PushTap {
  const PushTap({this.articleId, this.lang});

  factory PushTap.fromData(Map<String, dynamic> data) =>
      PushTap(articleId: _text(data['articleId']), lang: _text(data['lang']));

  final String? articleId;
  final String? lang;

  static String? _text(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

/// The part of Firebase Cloud Messaging the app uses, so tests never touch
/// Firebase: they pass their own.
abstract class Messaging {
  /// The current answer, without asking.
  Future<PushPermission> permission();

  /// Asks iOS (alert, badge, sound): its question shows only while
  /// [PushPermission.notAsked]; otherwise the answer comes back at once.
  Future<PushPermission> requestPermission();

  /// Lets Firebase register this phone with FCM (`FirebaseMessagingAutoInitEnabled`
  /// is off in Info.plist, so a phone that never allowed notifications gets no
  /// FCM token). Kept by Firebase across launches.
  Future<void> allowToken();

  /// Whether topics can be changed now. On iOS that needs the phone's APNs
  /// token: an FCM token made without it never reaches the phone.
  Future<bool> ready();

  Future<void> subscribe(String topic);

  Future<void> unsubscribe(String topic);

  /// Shows a notification that arrives while the app is open as a banner.
  Future<void> showInForeground();

  /// The notification whose tap started the app, if one did.
  Future<PushTap?> initialTap();

  /// Taps on a notification while the app runs, in the background or open.
  Stream<PushTap> get taps;

  /// A new FCM token: its topics are subscribed again.
  Stream<void> get tokenChanges;
}

/// [Messaging] through the `firebase_messaging` plugin. Only used once
/// Firebase has started.
class FirebaseMessagingLayer implements Messaging {
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  static PushPermission _permission(NotificationSettings settings) =>
      switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.notDetermined => PushPermission.notAsked,
        AuthorizationStatus.denied ||
        AuthorizationStatus.deniedPermanently => PushPermission.denied,
      };

  @override
  Future<PushPermission> permission() async =>
      _permission(await _fcm.getNotificationSettings());

  @override
  Future<PushPermission> requestPermission() async => _permission(
    await _fcm.requestPermission(alert: true, badge: true, sound: true),
  );

  @override
  Future<void> allowToken() => _fcm.setAutoInitEnabled(true);

  /// Waits until Apple has given the APNs token, checking once a second for up
  /// to 10 seconds (on the iOS Simulator it came about a second after Allow,
  /// 16 Oct). When it is still missing, [tokenChanges] (the FCM token follows
  /// the APNs one), the next return to the app or the next start tries again.
  @override
  Future<bool> ready() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return true;
    for (var i = 0; i < 10; i++) {
      if (await _fcm.getAPNSToken() != null) return true;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  @override
  Future<void> subscribe(String topic) => _fcm.subscribeToTopic(topic);

  @override
  Future<void> unsubscribe(String topic) => _fcm.unsubscribeFromTopic(topic);

  @override
  Future<void> showInForeground() =>
      _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

  @override
  Future<PushTap?> initialTap() async {
    final message = await _fcm.getInitialMessage();
    return message == null ? null : PushTap.fromData(message.data);
  }

  @override
  Stream<PushTap> get taps =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => PushTap.fromData(m.data));

  /// The FCM token's own event: `onRegistered` replaces it only for apps that
  /// turn on `FirebaseMessagingInstallationIdEnabled`, which this one does not.
  @override
  // ignore: deprecated_member_use
  Stream<void> get tokenChanges => _fcm.onTokenRefresh;
}

/// The app's words for the question before iOS asks; kept together for the
/// translations of the app's own words (#52).
abstract final class PushTexts {
  static const title = 'Breaking decisions';
  static const body =
      'Get the most important official decisions as a notification: '
      'at most 2 a day, none at night.';
  static const notNow = 'Not Now';
  static const turnOn = 'Turn On';
}

/// Push notifications (#62): the server sends breaking official decisions, at
/// most 2 a day per language, to one Firebase Cloud Messaging topic per feed
/// language (docs/contract.md, Push notifications in the app).
///
/// - Off until [start] (from [startPush], only once Firebase has started): in
///   tests and local runs every method does nothing.
/// - Asks once, at a calm moment: back on the feed after the third article
///   read ([PushOffer]), with the app's short explanation first; iOS asks only
///   after "Turn On". Whatever the answer, it never asks by itself again.
/// - Allowed: subscribed to `breaking_<feed language>`, moved with the
///   language; the topic is saved, so a start corrects it.
/// - A tap opens the article in the notification's language, or the feed.
///
/// For the Settings row: [permission] says what to show, [enable] asks.
class Push with WidgetsBindingObserver {
  Push({this._api, GlobalKey<NavigatorState>? navigator})
    : _navigator = navigator ?? appNavigator;

  /// Articles read before the app offers notifications.
  static const readsBeforeOffer = 3;

  static const _readsKey = 'push.readIds';
  static const _offeredKey = 'push.offered';
  static const _topicKey = 'push.topic';

  /// How long the app waits for a topic change; then it is tried again at the
  /// next trigger. Firebase may still carry it out later: on iOS a change that
  /// meets no network waits in Firebase's own queue, kept across launches, and
  /// is sent once the phone is back online (Firebase iOS SDK 13,
  /// `FIRMessagingPendingTopicsList`). So the saved topic is the one that may
  /// be subscribed, not only the one Firebase confirmed.
  static const _timeout = Duration(seconds: 30);

  /// Article ids are ULIDs; anything else in a notification is not opened.
  static final _articleId = RegExp(r'^[0-9A-Za-z_-]{1,64}$');

  ApiClient? _api;
  final GlobalKey<NavigatorState> _navigator;
  final _permission = ValueNotifier(PushPermission.unavailable);
  final _subscriptions = <StreamSubscription<Object?>>[];

  Messaging? _messaging;
  SharedPreferences? _prefs;
  FeedLanguage _language = FeedLanguage.en;

  /// The topic Firebase confirmed during this run, so a start (or a new FCM
  /// token) subscribes again once: that repairs a subscription Firebase lost.
  /// Null from the moment a change is sent until Firebase answers it, so a
  /// change without an answer is sent again at the next trigger.
  String? _confirmed;
  Future<void> _syncing = Future.value();

  /// The topic of a feed language: `breaking_uk`.
  static String topicFor(FeedLanguage language) => 'breaking_${language.code}';

  /// What the phone allows; [PushPermission.unavailable] while push is off.
  ValueListenable<PushPermission> get permission => _permission;

  /// Asks iOS for notifications, then subscribes to the feed language's topic.
  /// After a "Don't Allow", iOS does not ask again and this returns
  /// [PushPermission.denied] at once: the Settings row should then open the
  /// iOS Settings app. [trigger] is for analytics: `reads` or `settings`.
  Future<PushPermission> enable({String trigger = 'settings'}) async {
    final messaging = _messaging;
    if (messaging == null) return PushPermission.unavailable;
    final before = _permission.value;
    final now = await _try('permission request', messaging.requestPermission);
    if (now == null) return _permission.value;
    // Only when iOS really asked: the funnel of answers to its question.
    if (before == PushPermission.notAsked && now != PushPermission.notAsked) {
      unawaited(
        analytics.pushPermission(
          now == PushPermission.granted ? 'granted' : 'denied',
          trigger: trigger,
        ),
      );
    }
    await _apply(now);
    return now;
  }

  /// Turns push on; [startPush] calls it once Firebase has started. [language]
  /// is the feed's now ([FeedController.language]): the one chosen in
  /// Settings or, with none chosen, the phone's (#52); [setLanguage] follows it.
  Future<void> start(
    Messaging messaging,
    SharedPreferences prefs, {
    required FeedLanguage language,
  }) async {
    if (_messaging != null) return;
    _messaging = messaging;
    _prefs = prefs;
    _language = language;
    WidgetsBinding.instance.addObserver(this);
    _subscriptions
      ..add(messaging.taps.listen((tap) => unawaited(open(tap))))
      ..add(
        messaging.tokenChanges.listen((_) {
          _confirmed = null;
          unawaited(_sync());
        }),
      );
    final initial = await _try('first notification', messaging.initialTap);
    if (initial != null) unawaited(open(initial));
    await _try('banner setting', messaging.showInForeground);
    final now = await _try('permission', messaging.permission);
    if (now != null) await _apply(now);
  }

  /// Turns push off again (tests), forgetting this run as an app quit would:
  /// a [start] after it is the next launch.
  @visibleForTesting
  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _messaging = null;
    _prefs = null;
    _confirmed = null;
    // A new chain: the old one may belong to an earlier test's fake clock.
    _syncing = Future.value();
    _permission.value = PushPermission.unavailable;
  }

  /// An article read ([ArticleReadTimer]): the third different one makes the
  /// offer due.
  Future<void> articleRead(String id) async {
    final prefs = _prefs;
    if (prefs == null || prefs.getBool(_offeredKey) == true) return;
    final ids = prefs.getStringList(_readsKey) ?? const <String>[];
    if (ids.length >= readsBeforeOffer || ids.contains(id)) return;
    await prefs.setStringList(_readsKey, [...ids, id]);
  }

  /// Whether to offer notifications now: push on, iOS never asked, three
  /// articles read, and never offered before.
  bool get offerDue {
    final prefs = _prefs;
    return prefs != null &&
        _permission.value == PushPermission.notAsked &&
        prefs.getBool(_offeredKey) != true &&
        (prefs.getStringList(_readsKey)?.length ?? 0) >= readsBeforeOffer;
  }

  /// The app's short explanation; "Turn On" goes on to iOS's question. Shown
  /// once, whatever the answer (also when the app is closed meanwhile).
  Future<void> offer(BuildContext context) async {
    if (!offerDue) return;
    final answer = showCupertinoDialog<bool>(
      context: context,
      builder: (_) => const _PushOfferDialog(),
    );
    await _prefs?.setBool(_offeredKey, true);
    if (await answer == true) {
      await enable(trigger: 'reads');
    } else {
      unawaited(analytics.pushPermission('not_now', trigger: 'reads'));
    }
  }

  /// The feed's language changed: the topic moves with it.
  Future<void> setLanguage(FeedLanguage language) async {
    if (language == _language) return;
    _language = language;
    await _sync();
  }

  /// Opens a tapped notification's article over the feed, in the
  /// notification's language; the feed alone when it cannot be loaded.
  Future<void> open(PushTap tap) async {
    final given = tap.articleId;
    final id = given != null && _articleId.hasMatch(given) ? given : null;
    final lang = FeedLanguage.fromCode(tap.lang);
    unawaited(analytics.pushOpened(articleId: id ?? 'none', lang: lang.code));
    Article? article;
    if (id != null) {
      try {
        article = await (_api ??= ApiClient()).fetchArticle(
          id,
          lang: lang.code,
        );
      } catch (error) {
        debugPrint('push: article $id not loaded: $error');
      }
    }
    final navigator = await _navigatorReady();
    navigator.popUntil((route) => route.isFirst);
    if (article != null) {
      unawaited(navigator.pushNamed(Routes.detail, arguments: article));
    }
  }

  /// Back in the app: notifications may have been turned on or off in the iOS
  /// Settings app, and a failed topic change is tried again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final messaging = _messaging;
    if (messaging == null) return;
    final now = await _try('permission', messaging.permission);
    if (now != null && now != _permission.value) {
      await _apply(now);
    } else {
      await _sync();
    }
  }

  Future<void> _apply(PushPermission now) async {
    _permission.value = now;
    unawaited(
      analytics.pushState(switch (now) {
        PushPermission.granted => 'on',
        PushPermission.denied => 'off',
        _ => 'not_asked',
      }),
    );
    final messaging = _messaging;
    if (now == PushPermission.granted && messaging != null) {
      await _try('token', messaging.allowToken);
    }
    await _sync();
  }

  /// One topic change at a time, in order; a failure waits for the next
  /// trigger (a language change, the app coming back, a new token, a start).
  Future<void> _sync() {
    _syncing = _syncing
        .then((_) => _syncNow())
        .catchError((Object error) => debugPrint('push: topic: $error'));
    return _syncing;
  }

  Future<void> _syncNow() async {
    final messaging = _messaging;
    final prefs = _prefs;
    if (messaging == null || prefs == null) return;
    final state = _permission.value;
    if (state == PushPermission.unavailable) return;
    final want = state == PushPermission.granted ? topicFor(_language) : null;
    final have = prefs.getString(_topicKey);
    if (want == have && (want == null || want == _confirmed)) return;
    if (!await messaging.ready()) return;
    // Unknown until Firebase answers: a change without an answer may still be
    // carried out, so the next trigger sends the wanted topic again.
    _confirmed = null;
    // The old topic first: never two languages at once. It stays saved until
    // Firebase confirms it is gone.
    if (have != null && have != want) {
      await messaging.unsubscribe(have).timeout(_timeout);
      if (want == null) await prefs.remove(_topicKey);
    }
    if (want != null) {
      // Saved before it is sent, so a later change unsubscribes it even when
      // this subscribe gets no answer and Firebase carries it out later.
      await prefs.setString(_topicKey, want);
      await messaging.subscribe(want).timeout(_timeout);
      _confirmed = want;
    }
  }

  Future<NavigatorState> _navigatorReady() async {
    // A tap that started the app can come before the first frame.
    while (_navigator.currentState == null) {
      await WidgetsBinding.instance.endOfFrame;
    }
    return _navigator.currentState!;
  }

  static Future<T?> _try<T>(String what, Future<T> Function() call) async {
    try {
      return await call();
    } catch (error) {
      // Push never breaks the app.
      debugPrint('push: $what failed: $error');
      return null;
    }
  }
}

/// The app's push notifications; off until [startPush].
final push = Push();

/// Starts push notifications; call only once Firebase has started
/// ([startAnalytics] returned true). [language] is the feed's
/// ([FeedController.languageChanges]), read when push starts, so a language
/// chosen while Firebase was starting counts too.
Future<void> startPush({
  required ValueListenable<FeedLanguage> language,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await push.start(FirebaseMessagingLayer(), prefs, language: language.value);
  } catch (error) {
    debugPrint('push: off: $error');
  }
}

/// Offers notifications at a calm moment: back on the feed after an article,
/// once [Push.offerDue], after the article has slid away.
class PushOffer extends NavigatorObserver {
  PushOffer([this._push]);

  final Push? _push;

  Push get _target => _push ?? push;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null ||
        previousRoute.settings.name != Routes.feed ||
        !_target.offerDue) {
      return;
    }
    unawaited(_offerOnFeed(route, previousRoute));
  }

  Future<void> _offerOnFeed(Route<dynamic> closed, Route<dynamic> feed) async {
    if (closed is TransitionRoute) await closed.completed;
    final navigator = this.navigator;
    // Another screen opened meanwhile: the next return to the feed offers it.
    if (navigator == null || !navigator.mounted || !feed.isCurrent) return;
    await _target.offer(navigator.context);
  }
}

class _PushOfferDialog extends StatelessWidget {
  const _PushOfferDialog();

  @override
  Widget build(BuildContext context) => CupertinoAlertDialog(
    title: const Text(PushTexts.title),
    content: const Text(PushTexts.body),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text(PushTexts.notNow),
      ),
      CupertinoDialogAction(
        isDefaultAction: true,
        onPressed: () => Navigator.of(context).pop(true),
        child: const Text(PushTexts.turnOn),
      ),
    ],
  );
}
