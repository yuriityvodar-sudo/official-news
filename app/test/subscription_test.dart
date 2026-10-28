import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:official_news/core/api_client.dart';
import 'package:official_news/core/subscription.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The AI chat by subscription in the app (#146), its first part: the
/// subscription kept from StoreKit, and the chat's call to the server.
/// StoreKit itself is checked on a phone; the paywall and the chat come with
/// their screens.

/// A signed transaction as the phone sees it: only the expiry is read here.
String _jws(DateTime expires) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({'expiresDate': expires.millisecondsSinceEpoch}))).replaceAll('=', '')}.s';

final _now = DateTime(2026, 10, 27, 12);

class FakeStore implements Store {
  final controller = StreamController<List<PurchaseDetails>>.broadcast();
  final bought = <String>[];
  final finished = <PurchaseDetails>[];
  int restores = 0;
  bool open = true;

  @override
  Stream<List<PurchaseDetails>> get purchases => controller.stream;

  @override
  Future<bool> available() async => open;

  @override
  Future<ProductDetails?> product(String id) async => ProductDetails(
    id: id,
    title: 'AI agent',
    description: 'Monthly',
    price: r'$4.99',
    rawPrice: 4.99,
    currencyCode: 'USD',
  );

  @override
  Future<void> buy(
    ProductDetails product, {
    required String accountToken,
  }) async => bought.add(accountToken);

  @override
  Future<void> restore() async => restores++;

  @override
  Future<void> finish(PurchaseDetails purchase) async => finished.add(purchase);

  /// StoreKit reporting a purchase of the chat's product.
  void report(PurchaseStatus status, {String jws = ''}) => controller.add([
    PurchaseDetails(
      purchaseID: 'p1',
      productID: ChatSubscription.productId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: jws,
        source: 'app_store',
      ),
      transactionDate: '1793000000000',
      status: status,
    )..pendingCompletePurchase = true,
  ]);
}

void main() {
  late FakeStore store;
  late ChatSubscription subscription;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FakeStore();
    subscription = ChatSubscription(store: store, clock: () => _now);
    await subscription.start();
  });

  group('the subscription', () {
    test(
      'keeps what StoreKit sold, finishes it, and is open until it expires',
      () async {
        expect(subscription.active, isFalse);
        store.report(
          PurchaseStatus.purchased,
          jws: _jws(_now.add(const Duration(days: 30))),
        );
        await pumpEventQueue();
        expect(subscription.active, isTrue);
        expect(store.finished, hasLength(1));

        // Kept on the phone for the next start.
        final again = ChatSubscription(store: FakeStore(), clock: () => _now);
        await again.start();
        expect(again.transaction, subscription.transaction);
        expect(
          ChatSubscription(
            store: FakeStore(),
            clock: () => _now.add(const Duration(days: 31)),
          ).active,
          isFalse,
        );

        // The server said it is not paid.
        subscription.lapsed();
        expect(subscription.active, isFalse);
        final third = ChatSubscription(store: FakeStore(), clock: () => _now);
        await third.start();
        expect(third.transaction, isNull);
      },
    );

    test('buys with the phone\'s own UUID, the same every time', () async {
      await subscription.buy();
      await subscription.buy();
      expect(store.bought, hasLength(2));
      expect(
        store.bought.first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(store.bought.toSet(), hasLength(1));
      expect(subscription.state.value, PurchaseState.buying);
      store.report(PurchaseStatus.pending);
      await pumpEventQueue();
      expect(subscription.state.value, PurchaseState.pending);
      store.report(PurchaseStatus.error);
      await pumpEventQueue();
      expect(subscription.state.value, PurchaseState.failed);
    });

    testWidgets('a restore that finds nothing says so', (tester) async {
      await subscription.restore();
      expect(store.restores, 1);
      expect(subscription.state.value, PurchaseState.restoring);
      await tester.pump(ChatSubscription.restoreWait);
      expect(subscription.state.value, PurchaseState.nothingToRestore);
    });
  });

  group('POST /v1/chat', () {
    ApiClient api(http.Response Function(http.Request request) answer) =>
        ApiClient(
          client: MockClient((request) async => answer(request)),
          baseUrl: 'https://api.test',
        );
    Future<ChatAnswer> ask(ApiClient client) => client.askChat(
      articleId: 'c1',
      lang: 'uk',
      messages: [(true, 'Чи стосується це мене?')],
      transaction: 'jws',
    );

    test(
      'sends the question with the transaction, and gives the answer as it comes',
      () async {
        late http.Request sent;
        final answer = await ask(
          api((request) {
            sent = request;
            return http.Response.bytes(
              utf8.encode('Так, з листопада 2027 року.'),
              200,
              headers: {'x-chat-remaining': '19'},
            );
          }),
        );
        expect(await answer.text.join(), 'Так, з листопада 2027 року.');
        expect(answer.remaining, 19);
        expect(sent.url.toString(), 'https://api.test/v1/chat');
        expect(jsonDecode(sent.body), {
          'articleId': 'c1',
          'lang': 'uk',
          'messages': [
            {'role': 'user', 'text': 'Чи стосується це мене?'},
          ],
          'transaction': 'jws',
        });
      },
    );

    test(
      'says when today\'s questions come back (429), and the server\'s status otherwise',
      () async {
        await expectLater(
          ask(
            api(
              (_) => http.Response(
                '{"error":"No questions left today","resetsAt":"2026-10-28T00:00:00Z","units":1}',
                429,
              ),
            ),
          ),
          throwsA(
            isA<ChatLimit>().having(
              (e) => e.resetsAt,
              'resetsAt',
              DateTime.utc(2026, 10, 28),
            ),
          ),
        );
        await expectLater(
          ask(
            api((_) => http.Response('{"error":"Subscription required"}', 402)),
          ),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 402),
          ),
        );
      },
    );
  });
}
