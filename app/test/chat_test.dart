import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:official_news/core/analytics.dart';
import 'package:official_news/core/article.dart';
import 'package:official_news/core/subscription.dart';
import 'package:official_news/features/chat/paywall_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_store.dart';
import 'test_app.dart';

/// The AI chat by subscription in the app (#146): its paywall. StoreKit itself
/// and the glass are checked on a phone; the consent and the chat come with
/// the chat screen.

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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    events = [];
    analytics = Analytics(
      (name, parameters) async => events.add((name, parameters)),
      (_, _) async {},
    );
    store = FakeStore();
    subscription = ChatSubscription(store: store, clock: () => _now);
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
}
