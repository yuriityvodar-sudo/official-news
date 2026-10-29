import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/feed_language.dart';
import 'package:official_news/core/news_widgets.dart';
import 'package:official_news/core/push.dart';
import 'package:official_news/core/router.dart';
import 'package:official_news/core/support.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/features/settings/info_pages.dart';
import 'package:official_news/features/settings/settings_screen.dart';
import 'package:official_news/features/settings/support_screen.dart';
import 'package:official_news/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_messaging.dart';
import 'test_app.dart';

/// The server of #220 as the contract describes it: one conversation, which
/// [thread] holds, and what each request was.
class FakeSupportServer {
  Map<String, dynamic>? thread;

  /// Answers the next POST with this status and body instead.
  (int, Map<String, dynamic>)? postAnswer;

  /// The next GETs fail as on a phone with no network.
  int failGets = 0;
  bool failPost = false;
  final requests = <http.Request>[];

  int get gets => requests.where((r) => r.method == 'GET').length;
  Map<String, dynamic> get lastBody =>
      jsonDecode(requests.lastWhere((r) => r.method == 'POST').body)
          as Map<String, dynamic>;

  late final api = ApiClient(
    baseUrl: 'https://api.test',
    client: MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET' && request.url.path == '/v1/support/thread') {
        if (failGets > 0) {
          failGets--;
          throw http.ClientException('offline');
        }
        return fakeJson({'thread': thread});
      }
      if (request.method == 'POST' &&
          request.url.path == '/v1/support/messages') {
        if (failPost) throw http.ClientException('offline');
        final answer = postAnswer;
        if (answer != null) {
          postAnswer = null;
          return http.Response(jsonEncode(answer.$2), answer.$1);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        thread = waiting(body['text'] as String);
        return fakeJson({'thread': thread});
      }
      return http.Response('{"error":"not found"}', 404);
    }),
  );
}

final _sentAt = DateTime.utc(2026, 10, 29, 9, 30);
final _writeAfter = DateTime.utc(2026, 11, 5, 9, 30);

Map<String, dynamic> waiting(String text) => {
  'status': 'waiting',
  'messages': [
    {'from': 'reader', 'text': text, 'at': _sentAt.toIso8601String()},
  ],
  'canWrite': false,
  'writeAfter': _writeAfter.toIso8601String(),
};

Map<String, dynamic> answered() => {
  'status': 'answered',
  'messages': [
    {'from': 'reader', 'text': 'A broken source', 'at': '2026-10-29T09:30:00Z'},
    {'from': 'team', 'text': 'Fixed, thank you!', 'at': '2026-10-30T10:00:00Z'},
  ],
  'canWrite': true,
  'writeAfter': null,
};

void main() {
  final en = l10nFor();
  late FakeSupportServer server;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = FakeSupportServer();
  });

  Future<void> pump(
    WidgetTester tester, {
    Future<String?> Function()? token,
    Brightness brightness = Brightness.light,
    FeedLanguage language = FeedLanguage.en,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(brightness),
        locale: language.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SupportScreen(
          api: server.api,
          pushToken: token ?? () async => 'fcm-token',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder sendButton() => find.ancestor(
    of: find.text(en.supportSend),
    matching: find.byType(CupertinoButton),
  );

  bool sendEnabled(WidgetTester tester) =>
      tester.widget<CupertinoButton>(sendButton()).onPressed != null;

  group('the phone\'s anonymous id', () {
    test('made once: 32 random bytes, base64url without padding', () async {
      final prefs = await SharedPreferences.getInstance();
      final id = await supportDevice(prefs);
      expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(prefs.getString('support.device'), id);
      expect(await supportDevice(prefs), id);
      expect(await supportDevice(), id, reason: 'the same phone, the same id');
    });

    test('a saved one is kept', () async {
      final saved = 'a' * 43;
      SharedPreferences.setMockInitialValues({'support.device': saved});
      expect(await supportDevice(), saved);
    });

    test('two phones get different ids', () async {
      final one = await supportDevice();
      SharedPreferences.setMockInitialValues({});
      expect(await supportDevice(), isNot(one));
    });
  });

  group(
    'the API (docs: POST /v1/support/messages, GET /v1/support/thread)',
    () {
      test(
        'GET sends the device in X-Support-Device, never in the address',
        () async {
          expect(await server.api.supportThread('dev1'), isNull);
          final request = server.requests.single;
          expect(request.url.toString(), 'https://api.test/v1/support/thread');
          expect(request.headers['x-support-device'], 'dev1');
        },
      );

      test('GET reads the conversation', () async {
        server.thread = answered();
        final thread = (await server.api.supportThread('dev1'))!;
        expect(thread.status, 'answered');
        expect(thread.canWrite, isTrue);
        expect(thread.writeAfter, isNull);
        expect(thread.messages.map((m) => (m.fromTeam, m.text)), [
          (false, 'A broken source'),
          (true, 'Fixed, thank you!'),
        ]);
      });

      test('POST sends device, text, lang, app and push as JSON', () async {
        final thread = await server.api.sendSupport(
          device: 'dev1',
          text: 'Hello',
          lang: 'uk',
          app: '1.0.0 (48)',
          push: 'tok',
        );
        final request = server.requests.single;
        expect(request.url.toString(), 'https://api.test/v1/support/messages');
        expect(request.headers['content-type'], startsWith('application/json'));
        expect(jsonDecode(request.body), {
          'device': 'dev1',
          'text': 'Hello',
          'lang': 'uk',
          'app': '1.0.0 (48)',
          'push': 'tok',
        });
        expect(thread.waiting, isTrue);
        expect(thread.writeAfter, _writeAfter);
      });

      test('POST without a token leaves push out', () async {
        await server.api.sendSupport(
          device: 'dev1',
          text: 'Hello',
          lang: 'en',
          app: '1.0.0',
        );
        expect(server.lastBody.containsKey('push'), isFalse);
      });

      test('409, 429 and 400 become their errors', () async {
        Future<void> send() => server.api.sendSupport(
          device: 'd',
          text: 't',
          lang: 'en',
          app: '1',
        );
        server.postAnswer = (
          409,
          {'error': 'waiting', 'writeAfter': '2026-11-05T09:30:00Z'},
        );
        await expectLater(
          send(),
          throwsA(
            isA<SupportWaiting>().having(
              (e) => e.writeAfter,
              'writeAfter',
              _writeAfter,
            ),
          ),
        );
        server.postAnswer = (
          429,
          {'error': 'limit', 'resetsAt': '2026-10-30T00:00:00Z'},
        );
        await expectLater(
          send(),
          throwsA(
            isA<SupportLimit>().having(
              (e) => e.resetsAt,
              'resetsAt',
              DateTime.utc(2026, 10, 30),
            ),
          ),
        );
        server.postAnswer = (400, {'error': 'text'});
        await expectLater(
          send(),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 400),
          ),
        );
      });
    },
  );

  group('the messages screen', () {
    testWidgets('empty, then sent: the message and "we\'ll reply here"', (
      tester,
    ) async {
      await pump(tester);
      expect(server.gets, 1);
      final device = server.requests.single.headers['x-support-device'];
      expect(device, hasLength(43));
      expect(find.text(en.supportIntro), findsOneWidget);
      expect(sendEnabled(tester), isFalse, reason: 'nothing written');

      await tester.enterText(find.byType(CupertinoTextField), '   ');
      await tester.pump();
      expect(sendEnabled(tester), isFalse, reason: 'only spaces');

      await tester.enterText(
        find.byType(CupertinoTextField),
        '  The Czech source is broken  ',
      );
      await tester.pump();
      expect(sendEnabled(tester), isTrue);
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(server.lastBody, {
        'device': device,
        'text': 'The Czech source is broken',
        'lang': 'en',
        'app': appVersion,
        'push': 'fcm-token',
      });
      expect(find.text('The Czech source is broken'), findsOneWidget);
      expect(find.text(en.supportReceived), findsOneWidget);
      expect(
        find.text(en.supportWriteAgainAfter(fullDate(_writeAfter, en))),
        findsOneWidget,
      );
      // Locked until we reply.
      expect(find.byType(CupertinoTextField), findsNothing);
      expect(find.text(en.supportIntro), findsNothing);
    });

    testWidgets('no token: the message goes without push, at once', (
      tester,
    ) async {
      await pump(tester, token: () async => null);
      await tester.enterText(find.byType(CupertinoTextField), 'Hi');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(server.lastBody.containsKey('push'), isFalse);
    });

    testWidgets('a token that never comes does not hold the message', (
      tester,
    ) async {
      await pump(tester, token: () => Completer<String?>().future);
      await tester.enterText(find.byType(CupertinoTextField), 'Hi');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(server.lastBody['text'], 'Hi');
      expect(server.lastBody.containsKey('push'), isFalse);
    });

    testWidgets('the app\'s language goes with the message', (tester) async {
      await pump(tester, language: FeedLanguage.uk);
      await tester.enterText(find.byType(CupertinoTextField), 'Привіт');
      await tester.pump();
      await tester.tap(find.text(l10nFor(FeedLanguage.uk).supportSend));
      await tester.pumpAndSettle();
      expect(server.lastBody['lang'], 'uk');
    });

    testWidgets('answered: our reply, in the serif, and the field again', (
      tester,
    ) async {
      server.thread = answered();
      await pump(tester);
      expect(find.text('A broken source'), findsOneWidget);
      expect(find.text('Outer News'), findsOneWidget);
      final reply = tester.widget<Text>(find.text('Fixed, thank you!'));
      expect(reply.style?.fontFamily, 'Georgia');
      final mine = tester.widget<Text>(find.text('A broken source'));
      expect(mine.style?.fontFamily, isNull, reason: 'the reader\'s in sans');
      expect(find.text(en.supportReceived), findsNothing);
      expect(find.byType(CupertinoTextField), findsOneWidget);
      // VoiceOver: who wrote it, and when.
      expect(find.bySemanticsLabel(RegExp('^Outer News, ')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^You, ')), findsOneWidget);
    });

    testWidgets('409: when the reader can write again', (tester) async {
      server.thread = answered();
      await pump(tester);
      server.postAnswer = (
        409,
        {'error': 'waiting', 'writeAfter': _writeAfter.toIso8601String()},
      );
      await tester.enterText(find.byType(CupertinoTextField), 'Again');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(
        find.text(en.supportWriteAgainAfter(fullDate(_writeAfter, en))),
        findsOneWidget,
      );
      expect(server.gets, 2, reason: 'the conversation read again');
    });

    testWidgets('429: when more can be sent', (tester) async {
      await pump(tester);
      final resets = DateTime.utc(2026, 10, 30);
      server.postAnswer = (
        429,
        {'error': 'limit', 'resetsAt': resets.toIso8601String()},
      );
      await tester.enterText(find.byType(CupertinoTextField), 'More');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(
        find.text(en.supportTooMany(clockTime(resets, en))),
        findsOneWidget,
      );
      expect(find.text('More'), findsOneWidget, reason: 'kept in the field');
    });

    testWidgets('offline: the load fails, Try again loads it', (tester) async {
      server
        ..failGets = 1
        ..thread = answered();
      await pump(tester);
      expect(find.text(en.supportLoadError), findsOneWidget);
      expect(find.byType(CupertinoTextField), findsNothing);
      await tester.tap(find.text(en.tryAgain));
      await tester.pumpAndSettle();
      expect(find.text(en.supportLoadError), findsNothing);
      expect(find.text('Fixed, thank you!'), findsOneWidget);
    });

    testWidgets('offline: a send fails and the text stays', (tester) async {
      await pump(tester);
      server.failPost = true;
      await tester.enterText(find.byType(CupertinoTextField), 'Lost?');
      await tester.pump();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();
      expect(find.text(en.supportSendError), findsOneWidget);
      expect(find.text('Lost?'), findsOneWidget);
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('a counter near the 2,000-character limit, no more taken', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(find.byType(CupertinoTextField), 'a' * 1700);
      await tester.pump();
      expect(find.textContaining('characters left'), findsNothing);
      await tester.enterText(find.byType(CupertinoTextField), 'a' * 1900);
      await tester.pump();
      expect(find.text(en.supportCharsLeft(100)), findsOneWidget);
      await tester.enterText(find.byType(CupertinoTextField), 'a' * 2100);
      await tester.pump();
      expect(find.text(en.supportCharsLeft(0)), findsOneWidget);
    });

    testWidgets('back in the app, the reply is read again', (tester) async {
      server.thread = waiting('Hello');
      await pump(tester);
      expect(find.text('Fixed, thank you!'), findsNothing);
      server.thread = answered();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(server.gets, 2);
      expect(find.text('Fixed, thank you!'), findsOneWidget);
      expect(find.byType(CupertinoTextField), findsOneWidget);
    });

    testWidgets('dark mode: the text in dark mode\'s colours', (tester) async {
      server.thread = answered();
      await pump(tester, brightness: Brightness.dark);
      final reply = tester.widget<Text>(find.text('Fixed, thank you!'));
      expect(
        reply.style!.color!.toARGB32(),
        CupertinoColors.label.darkColor.toARGB32(),
      );
      final page = tester.widget<CupertinoPageScaffold>(
        find.byType(CupertinoPageScaffold),
      );
      expect(
        page.backgroundColor!.toARGB32(),
        CupertinoColors.systemGroupedBackground.darkColor.toARGB32(),
      );
    });
  });

  group('Contact & Support', () {
    testWidgets(
      '"Write to us" opens the messages screen, the e-mail under it',
      (tester) async {
        tester.view.physicalSize = const Size(800, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          testApp(
            home: SettingsScreen(
              language: ValueNotifier(FeedLanguage.en),
              onLanguage: (_) {},
              supportApi: server.api,
            ),
          ),
        );
        await tester.tap(find.text(en.contactSupport));
        await tester.pumpAndSettle();
        expect(find.text(en.supportOrEmail(supportEmail)), findsOneWidget);
        await tester.tap(find.text(en.supportWrite));
        await tester.pumpAndSettle();
        expect(find.byType(SupportScreen), findsOneWidget);
        expect(find.text(en.supportIntro), findsOneWidget);
        expect(server.requests.single.url.path, '/v1/support/thread');
      },
    );

    test('no mailto link is left in the app', () {
      for (final file in [
        'lib/features/settings/info_pages.dart',
        'lib/features/settings/settings_screen.dart',
      ]) {
        expect(
          File(file).readAsStringSync(),
          isNot(contains("scheme: 'mailto'")),
          reason: file,
        );
      }
    });
  });

  group('the notification of our reply', () {
    test('type support is read from its data', () {
      expect(PushTap.fromData({'type': 'support'}).support, isTrue);
      expect(PushTap.fromData({'articleId': 'a1'}).support, isFalse);
    });

    testWidgets('a tap opens the messages screen over the feed', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      final push = Push(api: server.api, navigator: navigator);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          onGenerateRoute: (settings) => CupertinoPageRoute(
            settings: settings,
            builder: (_) => Text('${settings.name}'),
          ),
        ),
      );
      unawaited(navigator.currentState!.pushNamed('/article'));
      await tester.pumpAndSettle();
      await push.open(PushTap.fromData({'type': 'support'}));
      await tester.pumpAndSettle();
      expect(find.text(Routes.support), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(
        find.text(Routes.feed),
        findsOneWidget,
        reason: 'the feed under it',
      );
      expect(server.requests, isEmpty, reason: 'no article loaded');
    });

    testWidgets('the app\'s route for it is the messages screen', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final route =
          onGenerateRoute(const RouteSettings(name: Routes.support))
              as CupertinoPageRoute;
      expect(route.settings.name, '/support');
      expect(
        route.builder(tester.element(find.byType(SizedBox))),
        isA<SupportScreen>(),
      );
    });

    testWidgets('the token only while notifications are allowed', (
      tester,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final messaging = FakeMessaging(status: PushPermission.denied);
      final push = Push(api: server.api);
      expect(await push.token(), isNull, reason: 'push off');
      await push.start(messaging, prefs, language: FeedLanguage.en);
      addTearDown(push.stop);
      expect(await push.token(), isNull, reason: 'not allowed');
      messaging.status = PushPermission.granted;
      await push.enable();
      expect(await push.token(), 'fcm-token');
      messaging.fcmToken = null;
      expect(await push.token(), isNull, reason: 'none yet');
    });
  });

  group('the words', () {
    const keys = [
      'supportWrite',
      'supportOrEmail',
      'supportIntro',
      'supportPlaceholder',
      'supportSend',
      'supportYou',
      'supportReceived',
      'supportWriteAgainAfter',
      'supportTooMany',
      'supportSendError',
      'supportLoadError',
      'supportCharsLeft',
      'privacySupportHeading',
      'privacySupport',
    ];
    for (final lang in FeedLanguage.values) {
      test('app_${lang.code}.arb has the messages screen\'s words', () {
        final arb =
            jsonDecode(File('lib/l10n/app_${lang.code}.arb').readAsStringSync())
                as Map<String, dynamic>;
        for (final key in keys) {
          expect(
            arb[key],
            isA<String>().having((s) => s, 'text', isNotEmpty),
            reason: key,
          );
        }
        expect(arb.containsKey('supportAppStore'), isFalse);
      });

      test('the privacy policy in ${lang.nativeName} tells about messages', () {
        final l10n = l10nFor(lang);
        final section = privacySections(
          l10n,
        ).firstWhere((s) => s.heading == l10n.privacySupportHeading);
        expect(section.paragraphs, [l10n.privacySupport]);
        expect(l10n.privacySupport, contains('90'));
      });
    }

    test('the policy is dated 29 October 2026', () {
      expect(policyUpdated, DateTime(2026, 10, 29));
    });
  });
}
