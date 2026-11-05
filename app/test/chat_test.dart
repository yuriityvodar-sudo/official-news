import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:intl/intl.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/chat_history.dart';
import 'package:official_news/core/glass.dart';
import 'package:official_news/core/story.dart';
import 'package:official_news/core/subscription.dart';
import 'package:official_news/core/theme.dart';
import 'package:official_news/core/tick.dart';
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

/// The weekday the week's usage comes back on, Monday 00:00 UTC, as the chat
/// shows it in the phone's time.
final _resetsDay = DateFormat.EEEE(
  'en_GB',
).format(DateTime.utc(2026, 11, 2).toLocal());

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
      },
      clock: () => _now,
    );
    await subscription.start();
  });
  tearDown(() => analytics = Analytics());

  List<String> sent() => [for (final e in events) e.$1];

  group('the paywall', () {
    Future<Future<bool>> showPaywall(
      WidgetTester tester, {
      Article? article,
    }) async {
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
                  article: article ?? _article,
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
      'about a tick: the world\'s mark, not an official seal, and a tick\'s first question (#230)',
      (tester) async {
        await showPaywall(
          tester,
          article: Tick.fromJson(fakeTick()).asArticle(l10nFor()),
        );
        expect(find.text('What is known?'), findsOneWidget);
        expect(find.text('Does this concern me?'), findsNothing);
        // The sample answer in the reader's language, never the outlets' own.
        expect(find.text("US strikes Iran's Qeshm Island"), findsWidgets);
        expect(find.textContaining('headline 0'), findsNothing);
        expect(find.byIcon(CupertinoIcons.globe), findsOneWidget);
        expect(find.byIcon(CupertinoIcons.checkmark_seal_fill), findsNothing);
      },
    );

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
        expect(find.text('Weekly usage included'), findsOneWidget);
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

    testWidgets("iOS's glass on its close button is drawn after everything "
        'else in it: whatever Flutter drew after a native view inside a sheet '
        "showed only over iOS's other views (the AI chat, TestFlight 55, "
        'Roman, 30 Oct)', (tester) async {
      GlassCircle.debugNative = true;
      addTearDown(() => GlassCircle.debugNative = null);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      final closed = await showPaywall(tester);
      expect(
        paintOrder(tester, find.byType(UiKitView)),
        greaterThan(paintOrder(tester, find.text('Privacy Policy'))),
      );

      await tester.tap(find.bySemanticsLabel('Close').first);
      await tester.pumpAndSettle();
      expect(await closed, isFalse);
    });

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

    /// What `/v1/chat/status` was asked about.
    late List<Map<String, dynamic>> statusAsked;

    /// The server: answers in pieces, or with [status], with [used] of the
    /// week's usage after the answer and [extra] usage left; [usage] is the
    /// week's usage before asking, status by status: how much is used and
    /// whether extra usage is left; [units] a question.
    ApiClient server({
      int status = 200,
      int used = 10,
      bool extra = false,
      String body = '{}',
      List<(int, bool)> usage = const [(0, false)],
      int units = 1,
      List<String> pieces = const ['Yes,', ' from November', ' 2027.'],
      Future<void>? hold,
    }) {
      var statuses = 0;
      return ApiClient(
        baseUrl: 'https://api.test',
        client: MockClient.streaming((request, bodyStream) async {
          final sent = await bodyStream.bytesToString();
          if (request.url.path == '/v1/chat/status') {
            statusAsked.add(jsonDecode(sent) as Map<String, dynamic>);
            final (now, extraNow) =
                usage[math.min(statuses++, usage.length - 1)];
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  jsonEncode({
                    'usedPercent': now,
                    'extraUsage': extraNow,
                    'limitReached': now >= 100 && !extraNow,
                    'units': units,
                    'resetsAt': '2026-11-02T00:00:00Z',
                  }),
                ),
              ),
              200,
            );
          }
          asked.add(jsonDecode(sent) as Map<String, dynamic>);
          if (hold != null) await hold;
          if (status != 200) {
            return http.StreamedResponse(
              Stream.value(utf8.encode(body)),
              status,
            );
          }
          return http.StreamedResponse(
            Stream.fromIterable(pieces.map(utf8.encode)),
            200,
            headers: {
              'x-chat-used': '$used',
              'x-chat-extra': '$extra',
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
      ChatHistory? history,
      bool settle = true,
      Article? article,
    }) async {
      asked = [];
      statusAsked = [];
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
            article: article ?? _article,
            api: api,
            subscription: subscription,
            // Each chat its own, so no test goes on with another's conversation.
            history: history ?? ChatHistory(),
            openLink: (uri) async => opened?.add(uri),
          ),
        ),
      );
      if (settle) await tester.pumpAndSettle();
    }

    testWidgets("iOS's glass on the close button is drawn after everything "
        'else in the chat: drawn first, it left the chat under it empty '
        '(TestFlight 55, Roman, 30 Oct)', (tester) async {
      GlassCircle.debugNative = true;
      addTearDown(() => GlassCircle.debugNative = null);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        ),
      );
      await openChat(tester, server(used: 80));
      expect(
        paintOrder(tester, find.byType(UiKitView).last),
        greaterThan(paintOrder(tester, find.text('Ask about this decision'))),
      );
    });

    testWidgets(
      'asks about this decision and shows the answer as it comes, with the official link',
      (tester) async {
        final opened = <Uri>[];
        asked = [];
        await openChat(tester, server(used: 80), opened: opened);
        await tester.tap(find.text('What changes and when?'));
        await tester.pumpAndSettle();
        expect(find.text('Yes, from November 2027.'), findsOneWidget);
        expect(asked.single['articleId'], 'c1');
        expect(asked.single['lang'], 'en');
        expect(asked.single['messages'], [
          {'role': 'user', 'text': 'What changes and when?'},
        ]);
        expect(asked.single['transaction'], subscription.transaction);
        expect(
          find.text("80% of this week's usage used · resets $_resetsDay"),
          findsOneWidget,
        );
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
      'asks about a tick as `tickId`, with its own questions, its outlets in '
      'the header and no official link (#230)',
      (tester) async {
        final opened = <Uri>[];
        final tick = Tick.fromJson(fakeTick()).asArticle(l10nFor());
        await openChat(tester, server(used: 80), opened: opened, article: tick);
        // The big headline and the bar's title.
        expect(find.text("US strikes Iran's Qeshm Island"), findsNWidgets(2));
        expect(find.text('ABC News, BBC World and 1 more'), findsOneWidget);
        expect(find.text('Does this concern me?'), findsNothing);
        await tester.tap(find.text('What is known?'));
        await tester.pumpAndSettle();
        expect(find.text('Yes, from November 2027.'), findsOneWidget);
        expect(asked.single['tickId'], 'w1');
        expect(asked.single.containsKey('articleId'), isFalse);
        expect(find.textContaining('Read the official decision'), findsNothing);
        expect(find.textContaining('Read on'), findsNothing);
        expect(
          events.lastWhere((e) => e.$1 == 'chat_question').$2['decision_type'],
          'tick',
        );
      },
    );

    testWidgets(
      'asks about a story of a country\'s outlets as `storyId` with its '
      'country, as about a tick (#230)',
      (tester) async {
        final story = Story.fromJson(fakeStory()).asArticle(l10nFor(), 'CZ');
        await openChat(tester, server(used: 80), article: story);
        expect(find.text('Babiš names his government'), findsNWidgets(2));
        expect(find.text('ČT24, Seznam Zprávy and 2 more'), findsOneWidget);
        expect(find.text('Does this concern me?'), findsNothing);
        expect(statusAsked.last, containsPair('storyId', 's1'));
        expect(statusAsked.last, containsPair('country', 'CZ'));
        await tester.tap(find.text('What is known?'));
        await tester.pumpAndSettle();
        expect(find.text('Yes, from November 2027.'), findsOneWidget);
        expect(asked.single['storyId'], 's1');
        expect(asked.single['country'], 'CZ');
        expect(asked.single.containsKey('articleId'), isFalse);
        expect(asked.single.containsKey('tickId'), isFalse);
        expect(find.textContaining('Read the official decision'), findsNothing);
        expect(find.textContaining('Read on'), findsNothing);
        expect(
          events.lastWhere((e) => e.$1 == 'chat_question').$2['decision_type'],
          'media-story',
        );
      },
    );

    testWidgets(
      'says when the week\'s usage is used up, or the agent is not there',
      (tester) async {
        await openChat(
          tester,
          server(
            status: 429,
            body:
                '{"error":"No usage left this week","resetsAt":"2026-11-02T00:00:00Z","units":1}',
          ),
        );
        await tester.tap(find.text('Does this concern me?'));
        await tester.pumpAndSettle();
        // The card in the field's place, no questions to suggest over it.
        expect(
          find.text("You've reached this week's usage limit."),
          findsOneWidget,
        );
        expect(find.text('Get more usage'), findsOneWidget);
        expect(find.byType(CupertinoTextField), findsNothing);
        expect(find.text('Does this concern me?'), findsNothing);

        // The question kept for after a top-up: back in the field.
        await tester.tap(find.text('Get more usage'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(r'Buy for $0.99'));
        await tester.pump();
        await tester.runAsync(() async {
          store.reportPack(PurchaseStatus.purchased);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CupertinoTextField>(find.byType(CupertinoTextField))
              .controller!
              .text,
          'Does this concern me?',
        );

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
        await openChat(tester, server(usage: [(100, false), (100, true)]));
        expect(
          find.text("You've reached this week's usage limit."),
          findsOneWidget,
        );
        expect(
          find.textContaining('It resets on $_resetsDay at '),
          findsOneWidget,
        );
        await tester.tap(find.text('Get more usage'));
        await tester.pumpAndSettle();
        expect(find.text('+1 week of usage'), findsOneWidget);
        expect(find.text('+3 weeks of usage'), findsOneWidget);
        expect(find.text('better value'), findsOneWidget);
        expect(find.text(r'Buy for $0.99'), findsOneWidget);
        expect(sent(), contains('topup_view'));

        await tester.tap(find.text('+3 weeks of usage'));
        await tester.pump();
        expect(find.text(r'Buy for $2.99'), findsOneWidget);
        await tester.tap(find.text('+1 week of usage'));
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
        expect(find.text('+1 week of usage'), findsNothing);
        expect(find.byType(CupertinoTextField), findsOneWidget);
        expect(
          find.text("You've reached this week's usage limit."),
          findsNothing,
        );
        // The week's usage still used up and the extra usage being spent: no
        // line over the field, which looked like a button (Roman, 5 Nov).
        expect(find.textContaining("this week's usage used"), findsNothing);
        expect(find.text('Using extra usage'), findsNothing);
        expect(
          events
              .where((e) => e.$1 == 'topup_result')
              .map((e) => e.$2['result']),
          ['credited'],
        );
        expect(events.lastWhere((e) => e.$1 == 'topup_result').$2, {
          'result': 'credited',
          'weeks': 1,
        });
      },
    );

    testWidgets(
      'a long document says it uses more of the usage, and the week\'s usage shows from 75%',
      (tester) async {
        await openChat(tester, server(usage: [(80, false)], units: 3));
        expect(
          find.text('Questions about long documents use more of your usage.'),
          findsOneWidget,
        );
        expect(
          find.text("80% of this week's usage used · resets $_resetsDay"),
          findsOneWidget,
        );

        await openChat(tester, server(usage: [(74, false)]));
        expect(find.textContaining("this week's usage"), findsNothing);
        expect(find.textContaining('long documents'), findsNothing);
      },
    );

    testWidgets(
      'opens over the whole screen from the bottom, sets the status bar, and its button closes it (Roman, 4 Nov)',
      (tester) async {
        await tester.runAsync(() async {
          store.report(
            PurchaseStatus.purchased,
            jws: _jws(_now.add(const Duration(days: 30))),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pumpWidget(
          testApp(
            home: Builder(
              builder: (context) => CupertinoButton(
                onPressed: () => ChatScreen.show(context, _article),
                child: const Text('Discuss'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Discuss'));
        await tester.pumpAndSettle();
        final chat = find.byType(ChatScreen);
        expect(chat, findsOneWidget);
        final route = ModalRoute.of(tester.element(chat));
        expect(route, isA<CupertinoPageRoute<void>>());
        expect((route! as CupertinoPageRoute<void>).fullscreenDialog, isTrue);
        expect(
          tester.getRect(chat),
          Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio,
        );
        // White words on the cover, in both themes.
        final bar = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.descendant(
            of: chat,
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          ),
        );
        expect(bar.value, SystemUiOverlayStyle.light);
        await tester.tap(find.byIcon(CupertinoIcons.xmark));
        await tester.pumpAndSettle();
        expect(chat, findsNothing);
      },
    );

    testWidgets(
      "shows the answer's bold and lists as such, never their marks (Roman, 30 Oct)",
      (tester) async {
        await openChat(
          tester,
          server(
            pieces: [
              '**Yes.** It ',
              'starts in 2027.\n\nWhat changes:\n- new **cars**',
              '\n- old ones\n1. first\n### Unknown',
            ],
          ),
        );
        await tester.tap(find.text('What changes and when?'));
        await tester.pumpAndSettle();
        expect(find.textContaining('**'), findsNothing);
        expect(find.textContaining('###'), findsNothing);
        final yes = tester.widget<Text>(find.text('Yes. It starts in 2027.'));
        final spans = (yes.textSpan! as TextSpan).children!.cast<TextSpan>();
        expect(spans.first.text, 'Yes.');
        expect(spans.first.style?.fontWeight, FontWeight.w700);
        expect(find.text('What changes:'), findsOneWidget);
        expect(find.text('•'), findsNWidgets(2));
        expect(find.text('new cars'), findsOneWidget);
        expect(find.text('old ones'), findsOneWidget);
        expect(find.text('1.'), findsOneWidget);
        expect(find.text('first'), findsOneWidget);
        expect(find.text('Unknown'), findsOneWidget);
      },
    );

    testWidgets(
      'what the chat is about comes first: the headline as big as the '
      "article's, the agent's name small (Roman, 5 Nov)",
      (tester) async {
        await openChat(tester, server());
        final context = tester.element(find.byType(ChatScreen));
        final headline = find.text('New cars must meet Euro 7 from 2027').first;
        final size = tester.widget<Text>(headline).style!.fontSize!;
        expect(size, NewsText.from(context).articleHeadline.fontSize);
        expect(
          tester.widget<Text>(find.text('AI agent')).style!.fontSize,
          lessThan(size / 2),
        );
        // Over the headline, beside the close button.
        expect(
          tester.getBottomLeft(find.text('AI agent')).dy,
          lessThan(tester.getTopLeft(headline).dy),
        );
      },
    );

    testWidgets(
      'once asked only the notice and the suggestions go, the headline and '
      'its source stay, and a dot, not a spinner, while the agent thinks',
      (tester) async {
        final hold = Completer<void>();
        await openChat(tester, server(hold: hold.future));
        expect(find.text('GOV.UK'), findsOneWidget);
        expect(find.textContaining('not legal advice'), findsOneWidget);
        expect(find.text('What should I do?'), findsOneWidget);

        await tester.tap(find.text('Does this concern me?'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
        expect(find.text('GOV.UK'), findsOneWidget);
        expect(find.textContaining('not legal advice'), findsNothing);
        expect(find.text('What should I do?'), findsNothing);

        hold.complete();
        await tester.pumpAndSettle();
        expect(find.text('Yes, from November 2027.'), findsOneWidget);
      },
    );

    /// The band's title, drawn after the big headline.
    Finder bandTitle() => find.text('New cars must meet Euro 7 from 2027').last;

    /// Where the band ends: 14 points under its title.
    double bandEnd(WidgetTester tester) =>
        tester.getBottomLeft(bandTitle()).dy + 14;

    /// [text]'s bubble, around it.
    Rect bubbleOf(WidgetTester tester, String text) => tester.getRect(
      find
          .ancestor(of: find.text(text), matching: find.byType(Container))
          .first,
    );

    /// How much of the band's title shows.
    double titleShown(WidgetTester tester) => tester
        .widget<Opacity>(
          find.ancestor(of: bandTitle(), matching: find.byType(Opacity)).first,
        )
        .opacity;

    testWidgets(
      'the cover folds into a band with the headline as the page scrolls, '
      'and comes back',
      (tester) async {
        await openChat(
          tester,
          server(pieces: [for (var i = 1; i <= 60; i++) 'Line $i.\n\n']),
        );
        await tester.tap(find.text('Does this concern me?'));
        await tester.pumpAndSettle();
        expect(titleShown(tester), 0);

        final list = find.byType(SingleChildScrollView);
        await tester.drag(list, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(titleShown(tester), 1);
        // Only the band is left over the page: the agent's name has gone.
        expect(
          tester
              .widget<Opacity>(
                find
                    .ancestor(
                      of: find.text('AI agent'),
                      matching: find.byType(Opacity),
                    )
                    .first,
              )
              .opacity,
          0,
        );

        await tester.drag(list, const Offset(0, 1000));
        await tester.pumpAndSettle();
        expect(titleShown(tester), 0);
      },
    );

    testWidgets(
      "on a phone: the agent's name and the close button under the status "
      'bar, the field low over the foot, and the end of a long answer comes '
      'clear of what stands over the field',
      (tester) async {
        tester.view
          ..physicalSize = const Size(402, 874) * 3
          ..devicePixelRatio = 3
          ..padding = const FakeViewPadding(top: 186, bottom: 102)
          ..viewPadding = const FakeViewPadding(top: 186, bottom: 102);
        addTearDown(tester.view.reset);
        await openChat(
          tester,
          server(
            used: 80,
            pieces: [for (var i = 1; i <= 40; i++) 'Line $i.\n\n'],
          ),
        );
        final agent = tester.getCenter(find.text('AI agent'));
        expect(agent.dy, moreOrLessEquals(62 + 18));
        expect(agent.dx, lessThan(200));
        final close = tester.getCenter(find.byIcon(CupertinoIcons.xmark));
        expect(close.dy, moreOrLessEquals(62 + 18));
        expect(close.dx, moreOrLessEquals(402 - 14 - 18));
        final field = find.byType(CupertinoTextField);
        expect(tester.getBottomLeft(field).dy, moreOrLessEquals(874 - 26));
        expect(tester.getTopLeft(field).dx, moreOrLessEquals(12));

        await tester.tap(find.text('Does this concern me?'));
        await tester.pumpAndSettle();
        final usage = find.textContaining("of this week's usage used");
        expect(usage, findsOneWidget);
        expect(
          tester.getBottomLeft(usage).dy,
          lessThan(tester.getTopLeft(field).dy),
        );

        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -6000),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getBottomLeft(find.text('Line 40.')).dy,
          lessThan(tester.getTopLeft(usage).dy),
        );
      },
    );

    testWidgets('the send button is grey until there is something to send', (
      tester,
    ) async {
      await openChat(tester, server());
      final send = find.byIcon(CupertinoIcons.arrow_up_circle_fill);
      Color? colour() => tester.widget<Icon>(send).color;
      final grey = colour();
      expect(grey, isNot(const Color(0xFFC41230)));

      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(asked, isEmpty);

      await tester.enterText(find.byType(CupertinoTextField), 'And then?');
      await tester.pumpAndSettle();
      expect(colour(), const Color(0xFFC41230));

      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(asked, hasLength(1));
      expect(colour(), grey);
    });

    testWidgets(
      'the first question stays under the cover; a later one goes under the '
      'band and stays there as a long answer comes, never jumping to the '
      "answer's end",
      (tester) async {
        await openChat(
          tester,
          server(
            pieces: [
              for (var i = 1; i <= 40; i++) 'Line $i of the answer.\n\n',
            ],
          ),
        );
        final list = find.byType(SingleChildScrollView);
        // The cover's foot is 20 points under its source.
        final foot = tester.getBottomLeft(find.text('GOV.UK')).dy + 20;
        await tester.tap(find.text('Does this concern me?'));
        await tester.pumpAndSettle();
        expect(
          bubbleOf(tester, 'Does this concern me?').top,
          moreOrLessEquals(foot + 18),
        );
        expect(find.text('Line 1 of the answer.'), findsOneWidget);
        expect(titleShown(tester), 0);

        await tester.enterText(find.byType(CupertinoTextField), 'And then?');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();
        // Its bubble stands 16 points under the band, not flush with it, where
        // it slipped under the title on the phone (Roman, 30 Oct).
        expect(
          bubbleOf(tester, 'And then?').top,
          moreOrLessEquals(bandEnd(tester) + 16),
        );
        expect(titleShown(tester), 1);
        // The start of the answer shows under it; its end is further down.
        expect(
          tester.getTopLeft(find.text('Line 1 of the answer.').last).dy,
          lessThan(tester.getBottomLeft(list).dy),
        );
      },
    );

    /// How much of the conversation shows: none until it stands in place.
    double shown(WidgetTester tester) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.byType(SingleChildScrollView),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;

    /// A conversation the phone keeps about the decision: four questions.
    void keepFour() => SharedPreferences.setMockInitialValues({
      ChatHistory.key: jsonEncode([
        ChatConversation(
          article: _article,
          messages: [
            for (var i = 1; i <= 4; i++) ...[(true, 'Q$i'), (false, 'A$i')],
          ],
          updatedAt: _now,
        ).toJson(),
      ]),
    });

    testWidgets('a kept conversation opens where it left off: from its first '
        'frame, the cover folded and no notice, unseen until its last question '
        'is under the band, so nothing folds or jumps (Roman, 30 Oct)', (
      tester,
    ) async {
      keepFour();
      // The feed has read it already, for its Conversations button.
      final history = ChatHistory();
      await history.load();
      await openChat(tester, server(), history: history, settle: false);
      expect(find.textContaining('not legal advice'), findsNothing);
      expect(find.text('Q4'), findsOneWidget);
      expect(shown(tester), 0);
      expect(titleShown(tester), 1);

      await tester.pumpAndSettle();
      expect(shown(tester), 1);
      expect(
        bubbleOf(tester, 'Q4').top,
        moreOrLessEquals(bandEnd(tester) + 16),
      );
      expect(titleShown(tester), 1);
    });

    testWidgets('read only as the chat opens, a kept conversation still shows '
        'only once in place, its notice gone at once', (tester) async {
      keepFour();
      await openChat(tester, server(), history: ChatHistory(), settle: false);
      expect(shown(tester), 0);
      await tester.pumpAndSettle();
      expect(shown(tester), 1);
      expect(find.textContaining('not legal advice'), findsNothing);
      expect(
        bubbleOf(tester, 'Q4').top,
        moreOrLessEquals(bandEnd(tester) + 16),
      );
    });

    testWidgets('a new chat shows its header at once', (tester) async {
      final history = ChatHistory();
      await history.load();
      await openChat(tester, server(), history: history, settle: false);
      expect(shown(tester), 1);
      expect(find.text('GOV.UK'), findsOneWidget);
    });

    testWidgets(
      'keeps the conversation on the phone once the answer has come, and goes '
      'on with it when the chat opens again (Roman, 30 Oct)',
      (tester) async {
        final history = ChatHistory();
        await openChat(tester, server(), history: history);
        await tester.tap(find.text('What changes and when?'));
        await tester.pumpAndSettle();
        expect(history.of('c1')!.messages, [
          (true, 'What changes and when?'),
          (false, 'Yes, from November 2027.'),
        ]);

        // Opened again: there at once, its one question still under the
        // cover, the notice gone, and it goes on.
        await openChat(tester, server(), history: history);
        expect(find.text('What changes and when?'), findsOneWidget);
        expect(find.text('Yes, from November 2027.'), findsOneWidget);
        expect(find.textContaining('not legal advice'), findsNothing);
        expect(titleShown(tester), 0);
        await tester.enterText(find.byType(CupertinoTextField), 'And then?');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();
        expect(asked.last['messages'], [
          {'role': 'user', 'text': 'What changes and when?'},
          {'role': 'assistant', 'text': 'Yes, from November 2027.'},
          {'role': 'user', 'text': 'And then?'},
        ]);
        expect(history.of('c1')!.messages, hasLength(4));
      },
    );

    testWidgets(
      'sends the server the last 20 messages of a long conversation, from a question on',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          ChatHistory.key: jsonEncode([
            ChatConversation(
              article: _article,
              messages: [
                for (var i = 1; i <= 10; i++) ...[
                  (true, 'Q$i'),
                  (false, 'A$i'),
                ],
              ],
              updatedAt: _now,
            ).toJson(),
          ]),
        });
        final history = ChatHistory();
        await openChat(tester, server(), history: history);
        await tester.enterText(find.byType(CupertinoTextField), 'Q11');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();
        final sent = asked.last['messages'] as List;
        expect(sent, hasLength(19));
        expect(sent.first, {'role': 'user', 'text': 'Q2'});
        expect(sent.last, {'role': 'user', 'text': 'Q11'});
        // The phone keeps the last 20 too.
        expect(history.of('c1')!.messages, hasLength(20));
        expect(history.of('c1')!.messages.first, (true, 'Q2'));
      },
    );

    testWidgets('a question sent as the keyboard closes still goes to the '
        'top: the room under it counts the keyboard (the simulator, 30 Oct)', (
      tester,
    ) async {
      await openChat(tester, server(pieces: ['Short answer.']));
      await tester.tap(find.text('Does this concern me?'));
      await tester.pumpAndSettle();
      // The keyboard is up while the reader types, 300 points.
      tester.view.viewInsets = FakeViewPadding(
        bottom: 300 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), 'And then?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      // The return key closes it.
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(
        bubbleOf(tester, 'And then?').top,
        moreOrLessEquals(bandEnd(tester) + 16),
      );
    });

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

/// Where [finder]'s render object comes as the screen is painted: a parent
/// before its children, children in their order (true of the stacks,
/// columns and scroll views here).
int paintOrder(WidgetTester tester, Finder finder) {
  final target = tester.renderObject(finder);
  var index = 0;
  var found = -1;
  void visit(RenderObject object) {
    if (identical(object, target)) found = index;
    index++;
    object.visitChildren(visit);
  }

  visit(tester.renderObject(find.byType(CupertinoPageScaffold).first));
  return found;
}
