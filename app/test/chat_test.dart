import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/subscription.dart';
import 'package:official_news/features/chat/chat_consent.dart';
import 'package:official_news/features/chat/chat_screen.dart';
import 'package:official_news/features/chat/paywall_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_store.dart';
import 'test_app.dart';

/// The AI chat by subscription in the app (#146): the paywall, the consent and
/// the chat. StoreKit itself and the glass are checked on a phone.

final _article = Article.fromJson({
  'id': 'c1',
  'country': 'GB',
  'source': {'id': 'gb-gov', 'name': 'GOV.UK', 'url': 'https://www.gov.uk'},
  'publishedAt': '2026-10-26T08:00:00Z',
  'dateOnly': false,
  'headline': 'New cars must meet Euro 7 from 2027',
  'shortSummary': 'Euro 7 for new cars.',
  'summary': 'From November 2027 new cars and vans must meet Euro 7.',
  'decisionType': 'regulation',
  'originalTitle': 'Euro 7',
  'originalLanguage': 'en',
  'topics': ['economy'],
  'tags': <String>[],
  'importance': 3,
  'imageUrl': null,
  'originalUrl': 'https://www.gov.uk/euro-7',
});

/// A signed transaction as the phone sees it: only the expiry is read here.
String _jws(DateTime expires) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({'expiresDate': expires.millisecondsSinceEpoch}))).replaceAll('=', '')}.s';

final _now = DateTime(2026, 10, 27, 12);

void main() {
  late List<(String, Map<String, Object>)> events;
  late FakeStore store;
  late ChatSubscription subscription;

  /// What the server was asked to credit, and whether it can.
  late List<(String, String)> credits;
  late bool serverUp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    credits = [];
    serverUp = true;
    events = [];
    analytics = Analytics(
      (name, parameters) async => events.add((name, parameters)),
      (_, _) async {},
    );
    store = FakeStore();
    subscription = ChatSubscription(
      store: store,
      credit: (pack, transaction) async {
        if (!serverUp) throw Exception('offline');
        credits.add((pack, transaction));
        return 50;
      },
      clock: () => _now,
    );
    await subscription.start();
  });
  tearDown(() => analytics = Analytics());

  List<String> sent() => [for (final e in events) e.$1];

  group('the paywall', () {
    Future<Future<bool>> showPaywall(WidgetTester tester) async {
      // An iPhone's screen, as the sheet shows on one.
      tester.view.physicalSize = const Size(393, 852) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      late Future<bool> closed;
      await tester.pumpWidget(
        testApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () => closed = showCupertinoSheet<bool>(
                context: context,
                scrollableBuilder: (_, scroll) => PaywallSheet(
                  article: _article,
                  subscription: subscription,
                  scroll: scroll,
                ),
              ).then((v) => v ?? false),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return closed;
    }

    testWidgets(
      'shows the sample about this decision, the price and what Apple asks for, and closes once bought',
      (tester) async {
        final closed = await showPaywall(tester);
        expect(find.text('Does this concern me?'), findsOneWidget);
        expect(
          find.text('From November 2027 new cars and vans must meet Euro 7.'),
          findsOneWidget,
        );
        expect(find.text(r'$4.99 a month'), findsOneWidget);
        expect(
          find.text(
            'Renews automatically. Cancel any time in your Apple ID settings.',
          ),
          findsOneWidget,
        );
        for (final link in [
          'Restore Purchases',
          'Terms of Use',
          'Privacy Policy',
        ]) {
          expect(find.text(link), findsOneWidget);
        }
        expect(find.bySemanticsLabel('Close'), findsWidgets);
        expect(sent(), contains('paywall_view'));

        await tester.tap(find.text('Subscribe'));
        await tester.pump();
        expect(store.bought, hasLength(1));
        store.report(
          PurchaseStatus.purchased,
          jws: _jws(_now.add(const Duration(days: 30))),
        );
        await tester.pumpAndSettle();
        expect(await closed, isTrue);
        expect(sent(), containsAll(['subscribe_tap', 'subscribe_result']));
        expect(events.lastWhere((e) => e.$1 == 'subscribe_result').$2, {
          'result': 'purchased',
        });
      },
    );

    testWidgets('says when the App Store is not there, and opens the terms', (
      tester,
    ) async {
      store.open = false;
      await showPaywall(tester);
      expect(
        find.text("Purchases aren't available right now."),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Terms of Use'));
      await tester.tap(find.text('Terms of Use'));
      await tester.pumpAndSettle();
      // The terms page, over the sheet: its subscription section, further down.
      await tester.scrollUntilVisible(
        find.text('AI agent subscription'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('AI agent subscription'), findsOneWidget);
    });
  });

  group('the consent', () {
    testWidgets('asks once, before the first question', (tester) async {
      final answers = <bool>[];
      await tester.pumpWidget(
        testApp(
          home: Builder(
            builder: (context) => CupertinoButton(
              onPressed: () async =>
                  answers.add(await ChatConsent.ask(context)),
              child: const Text('ask'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(find.textContaining('sent to OpenAI'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      expect(find.textContaining('sent to OpenAI'), findsNothing);
      expect(answers, [true, true]);
    });
  });

  group('the chat', () {
    late List<Map<String, dynamic>> asked;

    test(
      'stays closed in builds without the demo or Roman\'s key, such as TestFlight\'s',
      () => expect(ChatScreen.opened, isFalse),
    );

    /// The server: answers in pieces, or with [status]; [left] questions
    /// left before asking, at [units] a question.
    ApiClient server({
      int status = 200,
      int remaining = 9,
      String body = '{}',
      List<int> left = const [20],
      int units = 1,
    }) {
      var statuses = 0;
      return ApiClient(
        baseUrl: 'https://api.test',
        client: MockClient.streaming((request, bodyStream) async {
          final sent = await bodyStream.bytesToString();
          if (request.url.path == '/v1/chat/status') {
            final now = left[math.min(statuses++, left.length - 1)];
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'questionsLeft': now,
                    'boughtQuestions': 0,
                    'units': units,
                    'resetsAt': '2026-10-28T00:00:00Z',
                  }),
                ),
              ),
              200,
            );
          }
          asked.add(jsonDecode(sent) as Map<String, dynamic>);
          if (status != 200) {
            return http.StreamedResponse(
              Stream.value(utf8.encode(body)),
              status,
            );
          }
          return http.StreamedResponse(
            Stream.fromIterable(
              ['Yes,', ' from November', ' 2027.'].map(utf8.encode),
            ),
            200,
            headers: {
              'x-chat-remaining': '$remaining',
              'x-chat-units': '$units',
            },
          );
        }),
      );
    }

    Future<void> openChat(
      WidgetTester tester,
      ApiClient api, {
      List<Uri>? opened,
    }) async {
      asked = [];
      // Bought before the chat opens, and done with (outside the test's fake time).
      await tester.runAsync(() async {
        store.report(
          PurchaseStatus.purchased,
          jws: _jws(_now.add(const Duration(days: 30))),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpWidget(
        testApp(
          home: ChatScreen(
            key: UniqueKey(),
            article: _article,
            api: api,
            subscription: subscription,
            openLink: (uri) async => opened?.add(uri),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'asks about this decision and shows the answer as it comes, with the official link',
      (tester) async {
        final opened = <Uri>[];
        asked = [];
        await openChat(tester, server(remaining: 2), opened: opened);
        await tester.tap(find.text('What changes and when?'));
        await tester.pumpAndSettle();
        expect(find.text('Yes, from November 2027.'), findsOneWidget);
        expect(asked.single['articleId'], 'c1');
        expect(asked.single['lang'], 'en');
        expect(asked.single['messages'], [
          {'role': 'user', 'text': 'What changes and when?'},
        ]);
        expect(asked.single['transaction'], subscription.transaction);
        expect(find.text('2 questions left today'), findsOneWidget);
        await tester.tap(find.text('Read the official decision on gov.uk'));
        expect(opened, [Uri.parse('https://www.gov.uk/euro-7')]);
        expect(sent(), contains('chat_question'));
        expect(
          events.lastWhere((e) => e.$1 == 'chat_question').$2['number'],
          1,
        );

        // The next question carries the conversation.
        await tester.enterText(
          find.byType(CupertinoTextField),
          'What should I do?',
        );
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();
        expect(asked.last['messages'], [
          {'role': 'user', 'text': 'What changes and when?'},
          {'role': 'assistant', 'text': 'Yes, from November 2027.'},
          {'role': 'user', 'text': 'What should I do?'},
        ]);
      },
    );

    testWidgets(
      'says when today\'s questions are used up, or the agent is not there',
      (tester) async {
        await openChat(
          tester,
          server(
            status: 429,
            body:
                '{"error":"No questions left today","resetsAt":"2026-10-28T00:00:00Z","units":1}',
          ),
        );
        await tester.tap(find.text('Does this concern me?'));
        await tester.pumpAndSettle();
        // The card in the field's place, and the question kept for later.
        expect(find.text('No questions left for today'), findsOneWidget);
        expect(find.text('Buy more questions'), findsOneWidget);
        expect(find.byType(CupertinoTextField), findsNothing);
        expect(find.text('Does this concern me?'), findsOneWidget);

        await openChat(tester, server(status: 503));
        await tester.tap(find.text('Does this concern me?'));
        await tester.pumpAndSettle();
        expect(
          find.text("The AI agent isn't available right now."),
          findsOneWidget,
        );
        expect(find.text('Try again'), findsOneWidget);
      },
    );

    testWidgets(
      'nothing left on opening: the card, the packs, and a pack bought '
      'brings the field back',
      (tester) async {
        await openChat(tester, server(left: [0, 50]));
        expect(find.text('No questions left for today'), findsOneWidget);
        expect(find.textContaining('Or buy more'), findsOneWidget);
        await tester.tap(find.text('Buy more questions'));
        await tester.pumpAndSettle();
        expect(find.text('More questions'), findsOneWidget);
        expect(find.text('+50 questions'), findsOneWidget);
        expect(find.text('+200 questions'), findsOneWidget);
        expect(find.text('better value'), findsOneWidget);
        expect(find.text(r'Buy for $0.99'), findsOneWidget);
        expect(sent(), contains('topup_view'));

        await tester.tap(find.text('+200 questions'));
        await tester.pump();
        expect(find.text(r'Buy for $2.99'), findsOneWidget);
        await tester.tap(find.text('+50 questions'));
        await tester.pump();
        await tester.tap(find.text(r'Buy for $0.99'));
        await tester.pump();
        expect(store.boughtPacks, ['com.officialnews.app.agent.questions50']);

        // The subscription listens to StoreKit outside the test's fake time.
        await tester.runAsync(() async {
          store.reportPack(PurchaseStatus.purchased);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pumpAndSettle();
        expect(credits, hasLength(1));
        expect(find.text('More questions'), findsNothing);
        expect(find.byType(CupertinoTextField), findsOneWidget);
        expect(find.text('No questions left for today'), findsNothing);
        expect(
          events
              .where((e) => e.$1 == 'topup_result')
              .map((e) => e.$2['result']),
          ['credited'],
        );
        expect(events.lastWhere((e) => e.$1 == 'topup_result').$2, {
          'result': 'credited',
          'questions': 50,
        });
      },
    );

    testWidgets(
      'a long document says how much of the limit a question takes, and when few are left',
      (tester) async {
        await openChat(tester, server(left: [3], units: 3));
        expect(
          find.text('Long document: a question about it counts as 3'),
          findsOneWidget,
        );
        expect(find.text('3 questions left today'), findsOneWidget);
      },
    );

    testWidgets('not paid any more: the paywall again', (tester) async {
      await openChat(tester, server(status: 402));
      await tester.tap(find.text('Does this concern me?'));
      await tester.pumpAndSettle();
      expect(subscription.active, isFalse);
      expect(
        find.text('Continue the conversation with the AI agent'),
        findsOneWidget,
      );
    });
  });
}
