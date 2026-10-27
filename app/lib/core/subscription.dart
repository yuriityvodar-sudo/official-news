import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// The App Store as the subscription sees it; tests bring their own.
abstract class Store {
  /// Purchases and restores as StoreKit reports them, also ones made while
  /// the app was closed (renewals, Ask to Buy approved later).
  Stream<List<PurchaseDetails>> get purchases;
  Future<bool> available();
  Future<ProductDetails?> product(String id);

  /// Starts a purchase; its result comes through [purchases].
  Future<void> buy(ProductDetails product, {required String accountToken});

  /// Starts the purchase of a pack of questions, a consumable.
  Future<void> buyPack(ProductDetails pack, {required String accountToken});
  Future<void> restore();
  Future<void> finish(PurchaseDetails purchase);
}

/// StoreKit 2 through Flutter's `in_app_purchase` (#146).
class AppStore implements Store {
  final _store = InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchases => _store.purchaseStream;

  @override
  Future<bool> available() => _store.isAvailable();

  @override
  Future<ProductDetails?> product(String id) async {
    final answer = await _store.queryProductDetails({id});
    return answer.productDetails.where((p) => p.id == id).firstOrNull;
  }

  /// The account token goes to StoreKit 2 as `appAccountToken`.
  @override
  Future<void> buy(ProductDetails product, {required String accountToken}) =>
      _store.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
          applicationUserName: accountToken,
        ),
      );

  /// Finished by hand once the server has credited it ([ChatSubscription]).
  @override
  Future<void> buyPack(ProductDetails pack, {required String accountToken}) =>
      _store.buyConsumable(
        purchaseParam: PurchaseParam(
          productDetails: pack,
          applicationUserName: accountToken,
        ),
        autoConsume: false,
      );

  @override
  Future<void> restore() => _store.restorePurchases();

  @override
  Future<void> finish(PurchaseDetails purchase) =>
      _store.completePurchase(purchase);
}

/// Where a purchase or a restore stands, for the paywall and the top-up sheet.
enum PurchaseState {
  idle,
  buying,
  pending,
  failed,
  restoring,
  nothingToRestore,
}

/// The AI chat's subscription (#146, docs/contract.md): one monthly
/// auto-renewable product, `com.officialnews.app.agent.monthly`, bought with
/// StoreKit 2 on the reader's Apple ID, with no account. The phone keeps the
/// latest signed transaction, which every question sends; the server decides
/// whether it is still paid (a refund closes it there at once), and its 402
/// closes it here too ([lapsed]).
///
/// Packs of questions on top (Roman, 27 Oct): consumables, which StoreKit
/// does not restore and we have no account to keep, so the server keeps them
/// for the subscription. A bought pack is credited there first ([_credit])
/// and only then finished, so one the phone could not hand over comes back
/// from StoreKit at the next start and is credited then, once.
class ChatSubscription extends ChangeNotifier {
  ChatSubscription({this._store, this._credit, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const productId = 'com.officialnews.app.agent.monthly';

  /// The packs, by how many questions each adds: $0.99 and $2.99.
  static const packs = {
    'com.officialnews.app.agent.questions50': 50,
    'com.officialnews.app.agent.questions200': 200,
  };
  static const _transactionKey = 'chat.transaction';
  static const _tokenKey = 'chat.accountToken';

  /// How long a restore may take before "nothing to restore".
  static const restoreWait = Duration(seconds: 10);

  Store? _store;
  final Future<int> Function(String pack, String transaction)? _credit;
  final DateTime Function() _clock;
  SharedPreferences? _prefs;
  StreamSubscription<List<PurchaseDetails>>? _listening;
  Timer? _restoreEnd;

  /// The latest signed transaction (JWS), for the server.
  String? get transaction => _transaction;
  String? _transaction;
  DateTime? _expires;

  final state = ValueNotifier(PurchaseState.idle);

  /// The product as the App Store prices it for this reader ("4,99 $").
  ProductDetails? get product => _product;
  ProductDetails? _product;

  /// The packs as the App Store prices them, smallest first.
  List<ProductDetails> get packProducts => _packs;
  List<ProductDetails> _packs = const [];

  /// Packs credited since the app started: the top-up sheet closes on a new one.
  int get credited => _creditedCount;
  int _creditedCount = 0;

  /// The bought questions the server holds, as it last said after a pack.
  int? get boughtQuestions => _bought;
  int? _bought;

  /// Paid until later than now, as far as the phone knows.
  bool get active =>
      _transaction != null && (_expires == null || _expires!.isAfter(_clock()));

  /// Reads what the phone kept and listens to the App Store. Call once.
  Future<void> start() async {
    _prefs = await SharedPreferences.getInstance();
    _keep(_prefs!.getString(_transactionKey), notify: false);
    final store = _store ??= chatDemo ? DemoStore() : AppStore();
    _listening = store.purchases.listen(_purchased, onError: (_) {});
    notifyListeners();
  }

  /// The product's price, asked once the paywall shows.
  Future<ProductDetails?> loadProduct() async {
    final store = _store;
    if (store == null || _product != null) return _product;
    try {
      if (!await store.available()) return null;
      _product = await store.product(productId);
      notifyListeners();
    } catch (_) {
      // No App Store (offline, a simulator without StoreKit): the paywall says so.
    }
    return _product;
  }

  /// The packs' prices, asked once the top-up sheet shows.
  Future<List<ProductDetails>> loadPacks() async {
    final store = _store;
    if (store == null || _packs.isNotEmpty) return _packs;
    try {
      if (!await store.available()) return _packs;
      final found = [for (final id in packs.keys) ?await store.product(id)];
      _packs = found;
      notifyListeners();
    } catch (_) {
      // No App Store: the sheet says so.
    }
    return _packs;
  }

  Future<void> buyPack(ProductDetails pack) async {
    final store = _store;
    if (store == null || _transaction == null) {
      state.value = PurchaseState.failed;
      return;
    }
    state.value = PurchaseState.buying;
    try {
      await store.buyPack(pack, accountToken: await accountToken());
    } catch (_) {
      state.value = PurchaseState.failed;
    }
  }

  Future<void> buy() async {
    final store = _store;
    final product = _product ?? await loadProduct();
    if (store == null || product == null) {
      state.value = PurchaseState.failed;
      return;
    }
    state.value = PurchaseState.buying;
    try {
      await store.buy(product, accountToken: await accountToken());
    } catch (_) {
      state.value = PurchaseState.failed;
    }
  }

  Future<void> restore() async {
    final store = _store;
    if (store == null) return;
    state.value = PurchaseState.restoring;
    _restoreEnd?.cancel();
    _restoreEnd = Timer(restoreWait, () {
      if (state.value == PurchaseState.restoring) {
        state.value = PurchaseState.nothingToRestore;
      }
    });
    try {
      await store.restore();
    } catch (_) {
      _restoreEnd?.cancel();
      state.value = PurchaseState.failed;
    }
  }

  /// The server said the subscription is not paid (402): refunded, revoked
  /// or expired. The paywall shows again; a renewal brings a new transaction.
  void lapsed() {
    _transaction = null;
    _expires = null;
    unawaited(_prefs?.remove(_transactionKey));
    notifyListeners();
  }

  /// This phone's UUID, sent with each purchase as `appAccountToken`; made once.
  Future<String> accountToken() async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final kept = prefs.getString(_tokenKey);
    if (kept != null) return kept;
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final token =
        '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
    await prefs.setString(_tokenKey, token);
    return token;
  }

  Future<void> _purchased(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (packs.containsKey(purchase.productID)) {
        await _packPurchased(purchase);
        continue;
      }
      if (purchase.productID != productId) continue;
      switch (purchase.status) {
        case PurchaseStatus.purchased || PurchaseStatus.restored:
          final jws = purchase.verificationData.serverVerificationData;
          if (jws.isNotEmpty) {
            _keep(jws);
            await _prefs?.setString(_transactionKey, jws);
          }
          _restoreEnd?.cancel();
          state.value = PurchaseState.idle;
        case PurchaseStatus.pending:
          state.value = PurchaseState.pending;
        case PurchaseStatus.error:
          state.value = PurchaseState.failed;
        case PurchaseStatus.canceled:
          state.value = PurchaseState.idle;
      }
      if (purchase.pendingCompletePurchase) await _store?.finish(purchase);
    }
  }

  Future<void> _packPurchased(PurchaseDetails purchase) async {
    switch (purchase.status) {
      case PurchaseStatus.purchased || PurchaseStatus.restored:
        final pack = purchase.verificationData.serverVerificationData;
        final transaction = _transaction;
        if (pack.isEmpty || transaction == null) {
          state.value = PurchaseState.failed;
          return;
        }
        try {
          _bought = await (_credit ?? _serverCredit)(pack, transaction);
        } catch (_) {
          // Not credited: left unfinished, StoreKit gives it again at the next start.
          state.value = PurchaseState.failed;
          return;
        }
        // Credited first, so the top-up sheet closes before the purchase ends.
        _creditedCount++;
        notifyListeners();
        state.value = PurchaseState.idle;
        await _store?.finish(purchase);
        return;
      case PurchaseStatus.pending:
        state.value = PurchaseState.pending;
        return;
      case PurchaseStatus.error:
        state.value = PurchaseState.failed;
      case PurchaseStatus.canceled:
        state.value = PurchaseState.idle;
    }
    if (purchase.pendingCompletePurchase) await _store?.finish(purchase);
  }

  static Future<int> _serverCredit(String pack, String transaction) => chatDemo
      ? Future.value(packs.values.first)
      : ApiClient().creditPack(pack: pack, transaction: transaction);

  /// Keeps a transaction and reads its expiry from the payload (the server
  /// checks the signature; the phone only needs the date).
  void _keep(String? jws, {bool notify = true}) {
    _transaction = jws;
    _expires = jws == null ? null : expiryOf(jws);
    if (notify) notifyListeners();
  }

  @visibleForTesting
  static DateTime? expiryOf(String jws) {
    try {
      final payload = base64Url.normalize(jws.split('.')[1]);
      final json = jsonDecode(utf8.decode(base64Url.decode(payload)));
      final ms = (json as Map<String, dynamic>)['expiresDate'];
      return ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _listening?.cancel();
    _restoreEnd?.cancel();
    state.dispose();
    super.dispose();
  }
}

/// For looking at the paywall and the chat in the simulator, which has no
/// App Store products: a debug build with `--dart-define=CHAT_DEMO=1` sells a
/// pretend subscription at once ([DemoStore]) and the chat answers with the
/// article's summary. Release builds (TestFlight) never do.
const chatDemo = kDebugMode && bool.fromEnvironment('CHAT_DEMO');

/// [chatDemo]'s App Store: the price, and a purchase that goes through at once.
class DemoStore implements Store {
  final _purchases = StreamController<List<PurchaseDetails>>.broadcast();

  @override
  Stream<List<PurchaseDetails>> get purchases => _purchases.stream;

  @override
  Future<bool> available() async => true;

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
  }) async {
    final expires = DateTime.now().add(const Duration(days: 30));
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({'expiresDate': expires.millisecondsSinceEpoch}),
          ),
        )
        .replaceAll('=', '');
    _purchases.add([
      PurchaseDetails(
        purchaseID: 'demo',
        productID: product.id,
        verificationData: PurchaseVerificationData(
          localVerificationData: '',
          serverVerificationData: 'demo.$payload.demo',
          source: 'demo',
        ),
        transactionDate: '${DateTime.now().millisecondsSinceEpoch}',
        status: PurchaseStatus.purchased,
      ),
    ]);
  }

  @override
  Future<void> buyPack(
    ProductDetails pack, {
    required String accountToken,
  }) async => _purchases.add([
    PurchaseDetails(
      purchaseID: 'demo-pack',
      productID: pack.id,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: 'demo.pack.demo',
        source: 'demo',
      ),
      transactionDate: '${DateTime.now().millisecondsSinceEpoch}',
      status: PurchaseStatus.purchased,
    ),
  ]);

  @override
  Future<void> restore() async {}

  @override
  Future<void> finish(PurchaseDetails purchase) async {}
}

/// The app's subscription, started with the app on iOS (`main.dart`).
final chatSubscription = ChatSubscription();
