import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:official_news/core/subscription.dart';

/// The App Store in tests (#146): the chat's product at $4.99 and the packs at
/// $0.99 and $2.99, what was bought and finished, and StoreKit's reports when
/// a test sends them.
class FakeStore implements Store {
  final controller = StreamController<List<PurchaseDetails>>.broadcast();
  final bought = <String>[];
  final boughtPacks = <String>[];
  final finished = <PurchaseDetails>[];
  int restores = 0;
  bool open = true;

  @override
  Stream<List<PurchaseDetails>> get purchases => controller.stream;

  @override
  Future<bool> available() async => open;

  @override
  Future<ProductDetails?> product(String id) async {
    final price = switch (ChatSubscription.packs[id]) {
      50 => 0.99,
      200 => 2.99,
      _ => 4.99,
    };
    return ProductDetails(
      id: id,
      title: 'AI agent',
      description: 'Monthly',
      price: '\$$price',
      rawPrice: price,
      currencyCode: 'USD',
    );
  }

  @override
  Future<void> buy(
    ProductDetails product, {
    required String accountToken,
  }) async => bought.add(accountToken);

  @override
  Future<void> buyPack(
    ProductDetails pack, {
    required String accountToken,
  }) async => boughtPacks.add(pack.id);

  /// StoreKit reporting a pack of 50 questions bought.
  void reportPack(PurchaseStatus status) => controller.add([
    PurchaseDetails(
      purchaseID: 'pack1',
      productID: 'com.officialnews.app.agent.questions50',
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: 'pack.jws',
        source: 'app_store',
      ),
      transactionDate: '1793000000000',
      status: status,
    )..pendingCompletePurchase = true,
  ]);

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
