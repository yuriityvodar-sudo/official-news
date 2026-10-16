import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/push.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/features/detail/detail_screen.dart';
import 'package:official_news/features/feed/feed_controller.dart';
import 'package:official_news/l10n/app_localizations.dart';
import 'package:official_news/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_messaging.dart';
import 'test_app.dart';

/// Topic changes as the Firebase iOS SDK (13) makes them: one that meets no
/// network gets no answer, waits in Firebase's own queue (kept across
/// launches) and is carried out, in order, once the phone is back online,
/// even after the app stopped waiting for it.
class QueuedMessaging extends FakeMessaging {
  QueuedMessaging() : super(status: PushPermission.granted);

  /// The topics FCM has for this phone.
  final topics = <String>{};
  bool online = true;

  /// The network drops just before this call (`subscribe breaking_de`).
  String? dropBefore;
  final _queue = <(String, bool, Completer<void>)>[];

  @override
  Future<void> subscribe(String topic) => _send('subscribe', topic, true);

  @override
  Future<void> unsubscribe(String topic) => _send('unsubscribe', topic, false);

  Future<void> _send(String call, String topic, bool add) {
    calls.add('$call $topic');
    if (dropBefore == '$call $topic') online = false;
    final done = Completer<void>();
    _queue.add((topic, add, done));
    if (online) _deliver();
    return done.future;
  }

  /// Back online: Firebase sends what waited.
  void reconnect() {
    online = true;
    _deliver();
  }

  void _deliver() {
    for (final (topic, add, done) in _queue) {
      add ? topics.add(topic) : topics.remove(topic);
      done.complete();
    }
    _queue.clear();
  }
}

Map<String, dynamic> _article(String id, {String? lang}) => {
  'id': id,
  'country': 'DE',
  'source': {
    'id': 'de-gov',
    'name': 'Federal Government',
    'url': 'https://www.bundesregierung.de',
  },
  'publishedAt': '2026-10-16T09:00:00Z',
  'dateOnly': false,
  'headline': lang == null ? 'Decision $id' : 'Decision $id ($lang)',
  'shortSummary': null,
  'summary': 'Summary $id',
  'decisionType': 'cabinet-decision',
  'originalTitle': 'Original $id',
  'originalLanguage': 'de',
  'topics': ['economy'],
  'tags': <String>[],
  'importance': 5,
  'imageUrl': null,
  'originalUrl': 'https://www.bundesregierung.de/$id',
  'lang': ?lang,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The app's words in English, the tests' app language unless one says otherwise.
  final en = l10nFor();

  late List<(String, Map<String, Object>)> events;
  late Map<String, String> userProperties;
  late List<Uri> requests;
  late int articleStatus;

  /// The phone's saved values, as [started] opened them.
  late SharedPreferences prefs;

  final api = ApiClient(
    baseUrl: 'https://api.test',
    client: MockClient((request) async {
      requests.add(request.url);
      if (articleStatus != 200) return http.Response('{"error":"x"}', 404);
      final id = request.url.pathSegments.last;
      final lang = request.url.queryParameters['lang'];
      return http.Response.bytes(
        utf8.encode(jsonEncode(_article(id, lang: lang))),
        200,
      );
    }),
  );

  setUp(() {
    events = [];
    userProperties = {};
    requests = [];
    articleStatus = 200;
    analytics = Analytics(
      (name, parameters) async => events.add((name, parameters)),
      (name, value) async => userProperties[name] = value,
    );
  });
  tearDown(() => analytics = Analytics());

  Iterable<Map<String, Object>> sent(String name) =>
      events.where((e) => e.$1 == name).map((e) => e.$2);

  /// Push turned on with [messaging], on a phone holding [saved], the feed
  /// read in [language].
  Future<Push> started(
    FakeMessaging messaging, {
    Map<String, Object> saved = const {},
    FeedLanguage language = FeedLanguage.en,
    GlobalKey<NavigatorState>? navigator,
  }) async {
    SharedPreferences.setMockInitialValues(saved);
    prefs = await SharedPreferences.getInstance();
    final push = Push(api: api, navigator: navigator);
    await push.start(messaging, prefs, language: language);
    addTearDown(push.stop);
    return push;
  }

  /// A feed and an article screen, as the app's routes are named, with the
  /// app's words in [language].
  Widget app(
    GlobalKey<NavigatorState> navigator,
    Push push, {
    FeedLanguage language = FeedLanguage.en,
  }) => MaterialApp(
    navigatorKey: navigator,
    navigatorObservers: [PushOffer(push)],
    locale: language.locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    onGenerateRoute: (settings) => CupertinoPageRoute(
      settings: settings,
      builder: (_) => Scaffold(
        body: Text(
          settings.name == Routes.detail
              ? 'article ${(settings.arguments! as Article).headline}'
              : 'feed',
        ),
      ),
    ),
  );

  /// Opens an article from the feed and goes back to it.
  Future<void> readAndReturn(
    WidgetTester tester,
    GlobalKey<NavigatorState> navigator,
  ) async {
    unawaited(
      navigator.currentState!.pushNamed(
        Routes.detail,
        arguments: Article.fromJson(_article('x')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
  }

  group('asking for notifications', () {
    testWidgets('not before the third different article read', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final push = await started(FakeMessaging(), navigator: navigator);
      await tester.pumpWidget(app(navigator, push));
      await push.articleRead('a1');
      await push.articleRead('a2');
      await push.articleRead('a2'); // the same article read again
      await readAndReturn(tester, navigator);
      expect(find.text(en.pushOfferTitle), findsNothing);
      expect(push.offerDue, isFalse);
    });

    testWidgets(
      'after the third read, back on the feed: the app explains, then iOS asks',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        final messaging = FakeMessaging();
        final push = await started(messaging, navigator: navigator);
        await tester.pumpWidget(app(navigator, push));
        for (final id in ['a1', 'a2', 'a3']) {
          await push.articleRead(id);
        }
        // Not over the article: only once the reader is back on the feed.
        expect(find.text(en.pushOfferTitle), findsNothing);
        expect(messaging.asked, 0);

        await readAndReturn(tester, navigator);
        expect(find.text(en.pushOfferTitle), findsOneWidget);
        expect(find.text(en.pushOfferBody), findsOneWidget);
        expect(messaging.asked, 0, reason: 'iOS asks only after Turn On');

        await tester.tap(find.text(en.pushOfferTurnOn));
        await tester.pumpAndSettle();
        expect(messaging.asked, 1);
        expect(push.permission.value, PushPermission.granted);
        expect(messaging.tokenAllowed, isTrue);
        expect(messaging.calls, ['subscribe breaking_en']);
        expect(sent('push_permission').single, {
          'result': 'granted',
          'trigger': 'reads',
        });
        expect(userProperties['notifications'], 'on');
      },
    );

    // #52: the explanation is in the app's language, like every other word.
    for (final (language, title, body, notNow, turnOn) in [
      (
        FeedLanguage.uk,
        'Важливі рішення',
        'Отримуйте найважливіші офіційні рішення у сповіщеннях: '
            'не більше 2 на день, уночі — жодних.',
        'Не зараз',
        'Увімкнути',
      ),
      (
        FeedLanguage.ru,
        'Важные решения',
        'Получайте самые важные официальные решения в уведомлениях: '
            'не больше 2 в день, ночью — ни одного.',
        'Не сейчас',
        'Включить',
      ),
    ]) {
      testWidgets('the explanation in ${language.nativeName}', (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        final messaging = FakeMessaging();
        final push = await started(
          messaging,
          language: language,
          navigator: navigator,
        );
        await tester.pumpWidget(app(navigator, push, language: language));
        for (final id in ['a1', 'a2', 'a3']) {
          await push.articleRead(id);
        }
        await readAndReturn(tester, navigator);
        expect(find.text(title), findsOneWidget);
        expect(find.text(body), findsOneWidget);
        expect(find.text(notNow), findsOneWidget);
        expect(find.text(en.pushOfferTitle), findsNothing);

        await tester.tap(find.text(turnOn));
        await tester.pumpAndSettle();
        expect(messaging.asked, 1);
        expect(messaging.calls, ['subscribe breaking_${language.code}']);
      });
    }

    testWidgets('asks once: not on the next return, nor after a restart', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      final messaging = FakeMessaging(answer: PushPermission.denied);
      final push = await started(messaging, navigator: navigator);
      await tester.pumpWidget(app(navigator, push));
      for (final id in ['a1', 'a2', 'a3']) {
        await push.articleRead(id);
      }
      await readAndReturn(tester, navigator);
      await tester.tap(find.text(en.pushOfferTurnOn));
      await tester.pumpAndSettle();
      expect(push.permission.value, PushPermission.denied);
      expect(sent('push_permission').single['result'], 'denied');
      expect(messaging.calls, isEmpty, reason: 'no topic without permission');

      await push.articleRead('a4');
      await readAndReturn(tester, navigator);
      expect(find.text(en.pushOfferTitle), findsNothing);
      expect(messaging.asked, 1);

      // A later launch: iOS says denied, and the app has asked before.
      push.stop();
      await push.start(messaging, prefs, language: FeedLanguage.en);
      expect(push.offerDue, isFalse);
    });

    testWidgets('"Not Now": iOS never asks, and the app never asks again', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      final messaging = FakeMessaging();
      final push = await started(messaging, navigator: navigator);
      await tester.pumpWidget(app(navigator, push));
      for (final id in ['a1', 'a2', 'a3']) {
        await push.articleRead(id);
      }
      await readAndReturn(tester, navigator);
      await tester.tap(find.text(en.pushOfferNotNow));
      await tester.pumpAndSettle();
      expect(messaging.asked, 0);
      expect(push.permission.value, PushPermission.notAsked);
      expect(sent('push_permission').single, {
        'result': 'not_now',
        'trigger': 'reads',
      });

      await readAndReturn(tester, navigator);
      expect(find.text(en.pushOfferTitle), findsNothing);

      // After a restart iOS still has not asked, but the app does not offer again.
      push.stop();
      await push.start(messaging, prefs, language: FeedLanguage.en);
      expect(push.permission.value, PushPermission.notAsked);
      expect(push.offerDue, isFalse);

      // The Settings screen can still turn them on.
      expect(await push.enable(), PushPermission.granted);
      expect(sent('push_permission').last, {
        'result': 'granted',
        'trigger': 'settings',
      });
      expect(messaging.calls, ['subscribe breaking_en']);
    });

    testWidgets('not when iOS was already answered (from Settings)', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      final push = await started(
        FakeMessaging(status: PushPermission.granted),
        navigator: navigator,
      );
      await tester.pumpWidget(app(navigator, push));
      for (final id in ['a1', 'a2', 'a3']) {
        await push.articleRead(id);
      }
      await readAndReturn(tester, navigator);
      expect(find.text(en.pushOfferTitle), findsNothing);
    });

    testWidgets('off without Firebase: no question, no counting', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final navigator = GlobalKey<NavigatorState>();
      final push = Push(api: api, navigator: navigator);
      await tester.pumpWidget(app(navigator, push));
      for (final id in ['a1', 'a2', 'a3']) {
        await push.articleRead(id);
      }
      await readAndReturn(tester, navigator);
      expect(push.permission.value, PushPermission.unavailable);
      expect(find.text(en.pushOfferTitle), findsNothing);
      expect(await push.enable(), PushPermission.unavailable);
      expect(prefs.getKeys(), isEmpty);
    });
  });

  group('topic per feed language', () {
    test(
      'allowed: subscribes to the feed language and saves the topic',
      () async {
        final messaging = FakeMessaging(status: PushPermission.granted);
        await started(messaging, language: FeedLanguage.uk);
        expect(messaging.calls, ['subscribe breaking_uk']);
        expect(messaging.banners, isTrue);
        expect(prefs.getString('push.topic'), 'breaking_uk');
      },
    );

    test('a language change moves it: the old topic off first', () async {
      final messaging = FakeMessaging(status: PushPermission.granted);
      final push = await started(messaging, language: FeedLanguage.uk);
      await push.setLanguage(FeedLanguage.ru);
      await push.setLanguage(FeedLanguage.ru);
      expect(messaging.calls, [
        'subscribe breaking_uk',
        'unsubscribe breaking_uk',
        'subscribe breaking_ru',
      ]);
      expect(prefs.getString('push.topic'), 'breaking_ru');
    });

    test('a start corrects a topic saved for another language', () async {
      final messaging = FakeMessaging(status: PushPermission.granted);
      await started(
        messaging,
        language: FeedLanguage.es,
        saved: {'push.topic': 'breaking_en'},
      );
      expect(messaging.calls, [
        'unsubscribe breaking_en',
        'subscribe breaking_es',
      ]);
    });

    test('a failed change is tried again when the app comes back', () async {
      final messaging = FakeMessaging(status: PushPermission.granted);
      final push = await started(messaging, language: FeedLanguage.uk);
      messaging.failTopics = StateError('offline');
      await push.setLanguage(FeedLanguage.de);
      expect(prefs.getString('push.topic'), 'breaking_uk');

      messaging
        ..failTopics = null
        ..calls.clear();
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(messaging.calls, [
        'unsubscribe breaking_uk',
        'subscribe breaking_de',
      ]);
      expect(prefs.getString('push.topic'), 'breaking_de');
    });

    group('a change Firebase queues while offline', () {
      /// [change] gets no answer: the app stops waiting after 30 seconds.
      Future<void> unanswered(
        WidgetTester tester,
        Future<void> Function() change,
      ) async {
        final done = change();
        await tester.pump(const Duration(seconds: 61));
        await done;
      }

      Future<void> backInFront(WidgetTester tester) async {
        tester.binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
      }

      testWidgets('a subscribe the app gave up on is still undone later', (
        tester,
      ) async {
        final messaging = QueuedMessaging();
        final push = await started(messaging, language: FeedLanguage.uk);
        expect(messaging.topics, {'breaking_uk'});

        // The old topic goes, then the network drops before the new one.
        messaging.dropBefore = 'subscribe breaking_de';
        await unanswered(tester, () => push.setLanguage(FeedLanguage.de));
        await unanswered(tester, () => push.setLanguage(FeedLanguage.ru));

        messaging.reconnect();
        await backInFront(tester);
        expect(messaging.topics, {'breaking_ru'});
        expect(prefs.getString('push.topic'), 'breaking_ru');
      });

      testWidgets('back to the first language offline: still subscribed', (
        tester,
      ) async {
        final messaging = QueuedMessaging();
        final push = await started(messaging);
        expect(messaging.topics, {'breaking_en'});

        messaging.online = false;
        await unanswered(tester, () => push.setLanguage(FeedLanguage.de));
        await unanswered(tester, () => push.setLanguage(FeedLanguage.en));

        messaging.reconnect();
        await backInFront(tester);
        expect(messaging.topics, {'breaking_en'});
        expect(prefs.getString('push.topic'), 'breaking_en');
      });

      testWidgets('a restart while still offline', (tester) async {
        final messaging = QueuedMessaging();
        final push = await started(messaging, language: FeedLanguage.es);
        messaging.dropBefore = 'subscribe breaking_uk';
        await unanswered(tester, () => push.setLanguage(FeedLanguage.uk));

        // Firebase keeps its queue across launches; the feed reads Ukrainian.
        push.stop();
        await unanswered(
          tester,
          () => push.start(messaging, prefs, language: FeedLanguage.uk),
        );
        await unanswered(tester, () => push.setLanguage(FeedLanguage.de));

        messaging.reconnect();
        await backInFront(tester);
        expect(messaging.topics, {'breaking_de'});
        expect(prefs.getString('push.topic'), 'breaking_de');
      });
    });

    test(
      'waits for the APNs token; the FCM token that follows subscribes',
      () async {
        final messaging = FakeMessaging(status: PushPermission.granted)
          ..apnsToken = false;
        await started(messaging);
        expect(messaging.calls, isEmpty);

        messaging.apnsToken = true;
        messaging.tokenEvents.add(null);
        await pumpEventQueue();
        expect(messaging.calls, ['subscribe breaking_en']);

        // Another new token: subscribed again, in case Firebase lost it.
        messaging.tokenEvents.add(null);
        await pumpEventQueue();
        expect(messaging.calls, [
          'subscribe breaking_en',
          'subscribe breaking_en',
        ]);
      },
    );

    test('turned off in the iOS Settings app: the topic is dropped', () async {
      final messaging = FakeMessaging(status: PushPermission.granted);
      await started(messaging, language: FeedLanguage.ru);
      messaging.status = PushPermission.denied;
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(messaging.calls, [
        'subscribe breaking_ru',
        'unsubscribe breaking_ru',
      ]);
      expect(prefs.getString('push.topic'), isNull);
      expect(userProperties['notifications'], 'off');
    });

    test('not allowed: no topic at all', () async {
      final messaging = FakeMessaging();
      final push = await started(messaging);
      await push.setLanguage(FeedLanguage.uk);
      expect(messaging.calls, isEmpty);
    });
  });

  group('a tapped notification', () {
    testWidgets('opens its article in its language, over the feed', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      final messaging = FakeMessaging(status: PushPermission.granted);
      final push = await started(messaging, navigator: navigator);
      await tester.pumpWidget(app(navigator, push));
      // The reader was in another article.
      unawaited(
        navigator.currentState!.pushNamed(
          Routes.detail,
          arguments: Article.fromJson(_article('other')),
        ),
      );
      await tester.pumpAndSettle();

      messaging.tapEvents.add(const PushTap(articleId: 'a1', lang: 'uk'));
      await tester.pumpAndSettle();
      expect(
        requests.single.toString(),
        'https://api.test/articles/a1?lang=uk',
      );
      expect(find.text('article Decision a1 (uk)'), findsOneWidget);
      expect(find.text('article Decision other'), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('feed'), findsOneWidget);
      expect(sent('push_open').single, {'article_id': 'a1', 'lang': 'uk'});
    });

    testWidgets('the tap that started the app opens its article', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(app(navigator, Push()));
      await started(
        FakeMessaging(
          status: PushPermission.granted,
          initial: const PushTap(articleId: 'a1', lang: 'en'),
        ),
        navigator: navigator,
      );
      await tester.pumpAndSettle();
      // English is the API without `lang`.
      expect(requests.single.toString(), 'https://api.test/articles/a1');
      expect(find.text('article Decision a1'), findsOneWidget);
    });

    testWidgets('an article that does not load: the feed', (tester) async {
      articleStatus = 404;
      final navigator = GlobalKey<NavigatorState>();
      final messaging = FakeMessaging(status: PushPermission.granted);
      final push = await started(messaging, navigator: navigator);
      await tester.pumpWidget(app(navigator, push));
      unawaited(
        navigator.currentState!.pushNamed(
          Routes.detail,
          arguments: Article.fromJson(_article('other')),
        ),
      );
      await tester.pumpAndSettle();

      messaging.tapEvents.add(const PushTap(articleId: 'gone', lang: 'ru'));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));
      expect(find.text('feed'), findsOneWidget);
      expect(find.textContaining('article'), findsNothing);
    });

    testWidgets('no usable article id: the feed, without asking the API', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      final messaging = FakeMessaging(status: PushPermission.granted);
      final push = await started(messaging, navigator: navigator);
      await tester.pumpWidget(app(navigator, push));
      messaging.tapEvents.add(PushTap.fromData({'articleId': '../health'}));
      messaging.tapEvents.add(PushTap.fromData({'lang': 'uk'}));
      await tester.pumpAndSettle();
      expect(requests, isEmpty);
      expect(find.text('feed'), findsOneWidget);
      expect(sent('push_open').first, {'article_id': 'none', 'lang': 'en'});
    });
  });

  group('wired into the app', () {
    /// The app's own [push], turned on with [messaging].
    Future<void> appPushStarted(FakeMessaging messaging) async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      await push.start(messaging, prefs, language: FeedLanguage.en);
      addTearDown(push.stop);
    }

    testWidgets('an article open 15 seconds counts towards the offer', (
      tester,
    ) async {
      await appPushStarted(FakeMessaging());
      await tester.pumpWidget(
        testApp(home: DetailScreen(article: Article.fromJson(_article('a1')))),
      );
      await tester.pump(const Duration(seconds: 14));
      expect(prefs.getStringList('push.readIds'), isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(prefs.getStringList('push.readIds'), ['a1']);
    });

    test('the feed\'s language change moves the topic', () async {
      final messaging = FakeMessaging(status: PushPermission.granted);
      await appPushStarted(messaging);
      final feed = FeedController(
        api: ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient(
            (_) async =>
                http.Response('{"items":[],"nextCursor":null,"top":[]}', 200),
          ),
        ),
      );
      addTearDown(feed.dispose);
      await feed.setLanguage(FeedLanguage.uk);
      await pumpEventQueue();
      expect(messaging.calls, [
        'subscribe breaking_en',
        'unsubscribe breaking_en',
        'subscribe breaking_uk',
      ]);
    });

    testWidgets('the app offers on its navigator, and taps open on it', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final feed = FeedController(
        api: ApiClient(
          baseUrl: 'https://api.test',
          client: MockClient(
            (_) async =>
                http.Response('{"items":[],"nextCursor":null,"top":[]}', 200),
          ),
        ),
        phoneLanguages: () => const [Locale('en')],
      );
      await feed.open();
      await tester.pumpWidget(OfficialNewsApp(feed: feed));
      await tester.pump();
      MaterialApp app() => tester.widget(find.byType(MaterialApp));
      final observers = app().navigatorObservers;
      expect(observers, contains(isA<PushOffer>()));
      expect(app().navigatorKey, same(appNavigator));

      // A language change redraws the app (#52) with the same observers, so
      // an offer waiting for an article to slide away is not lost.
      await feed.setLanguage(FeedLanguage.uk);
      await tester.pump();
      expect(app().locale, const Locale('uk'));
      expect(app().navigatorObservers, same(observers));
    });

    test('the Settings row opens this app\'s page in the iOS Settings app', () {
      // The value of UIApplication.openSettingsURLString; launchUrl opens it
      // with UIApplication.open, which needs no LSApplicationQueriesSchemes.
      expect(appSettingsPage.toString(), 'app-settings:');
    });
  });
}
