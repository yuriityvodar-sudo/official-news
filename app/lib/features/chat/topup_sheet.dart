import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:in_app_purchase/in_app_purchase.dart' show ProductDetails;

import '../../core/analytics.dart';
import '../../core/motion.dart';
import '../../core/subscription.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'chat_style.dart';

/// More questions to the AI agent (#146, variant A of Roman's mockup, like
/// Claude): opened from the chat's card once the day's questions are used up.
/// The two packs, a one-time App Store purchase each, spent after the 20 a
/// day and never expiring. Closes with `true` once the server has credited
/// the pack.
class TopUpSheet extends StatefulWidget {
  const TopUpSheet({super.key, this.subscription, this.scroll});

  /// [chatSubscription] unless a test brings its own.
  final ChatSubscription? subscription;
  final ScrollController? scroll;

  static Future<bool> show(
    BuildContext context, {
    ChatSubscription? subscription,
  }) async =>
      await showCupertinoSheet<bool>(
        context: context,
        showDragHandle: true,
        scrollableBuilder: (_, scroll) =>
            TopUpSheet(subscription: subscription, scroll: scroll),
      ) ??
      false;

  @override
  State<TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<TopUpSheet> {
  ChatSubscription get _subscription => widget.subscription ?? chatSubscription;

  /// The packs credited when the sheet opened: a new one closes it.
  late final int _credited;
  bool _loaded = false;
  int _chosen = 0;
  PurchaseState? _was;

  @override
  void initState() {
    super.initState();
    _credited = _subscription.credited;
    unawaited(analytics.topUpView());
    _subscription.addListener(_changed);
    _subscription.state.addListener(_stateChanged);
    unawaited(
      _subscription.loadPacks().whenComplete(() {
        if (mounted) setState(() => _loaded = true);
      }),
    );
  }

  @override
  void dispose() {
    _subscription.removeListener(_changed);
    _subscription.state.removeListener(_stateChanged);
    super.dispose();
  }

  int get _questions =>
      ChatSubscription.packs[_pack?.id] ?? ChatSubscription.packs.values.first;

  ProductDetails? get _pack {
    final packs = _subscription.packProducts;
    return packs.isEmpty ? null : packs[_chosen.clamp(0, packs.length - 1)];
  }

  /// Credited on the server: the questions are there, the sheet's work is done.
  void _changed() {
    if (_done || _subscription.credited == _credited || !mounted) return;
    _done = true;
    unawaited(analytics.topUpResult('credited', questions: _questions));
    Navigator.of(context).pop(true);
  }

  /// Credited: the sheet is closing, what the purchase does next is not its own.
  bool _done = false;

  void _stateChanged() {
    if (_done) return;
    final state = _subscription.state.value;
    final result = switch (state) {
      PurchaseState.failed => 'failed',
      PurchaseState.pending => 'pending',
      PurchaseState.idle when _was == PurchaseState.buying => 'cancelled',
      _ => null,
    };
    if (result != null) {
      unawaited(analytics.topUpResult(result, questions: _questions));
    }
    _was = state;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ChatStyle.of(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final muted = CupertinoColors.secondaryLabel.resolveFrom(context);
    final card = CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
      context,
    );
    final packs = _subscription.packProducts;
    final pack = _pack;
    final state = _subscription.state.value;
    final busy = state == PurchaseState.buying;
    final message = switch (state) {
      _ when _loaded && packs.isEmpty => l10n.paywallUnavailable,
      PurchaseState.pending => l10n.paywallPending,
      PurchaseState.failed => l10n.paywallFailed,
      _ => null,
    };

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      // Material for the default text style (no yellow underline on plain Text).
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: ListView(
            controller: widget.scroll,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.topUpTitle,
                      // The sheet's title in the serif, as the paywall's (#188).
                      style: NewsText.from(
                        context,
                      ).headline.copyWith(color: label),
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Icon(
                      CupertinoIcons.xmark_circle_fill,
                      size: 30,
                      color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                      semanticLabel: l10n.paywallClose,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                l10n.topUpSubtitle,
                style: TextStyle(fontSize: 14, height: 1.4, color: muted),
              ),
              const SizedBox(height: 14),
              if (!_loaded) const CupertinoActivityIndicator(),
              for (final (i, p) in packs.indexed) ...[
                Semantics(
                  button: true,
                  selected: i == _chosen,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Haptics.selection();
                      setState(() => _chosen = i);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: i == _chosen
                              ? style.ink
                              : const Color(0x00000000),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            i == _chosen
                                ? CupertinoIcons.checkmark_circle_fill
                                : CupertinoIcons.circle,
                            size: 22,
                            color: i == _chosen ? style.ink : muted,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 6,
                              children: [
                                Text(
                                  l10n.topUpPack(
                                    ChatSubscription.packs[p.id] ?? 0,
                                  ),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: label,
                                  ),
                                ),
                                if (i == packs.length - 1 && packs.length > 1)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: style.fill,
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: Text(
                                      l10n.topUpBest,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFFFFFFF),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            p.price,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: label,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 4),
              SizedBox(
                height: 50,
                child: CupertinoButton(
                  padding: EdgeInsets.zero,
                  color: style.fill,
                  disabledColor: style.fill.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(25),
                  onPressed: pack == null || busy
                      ? null
                      : () {
                          Haptics.light();
                          unawaited(_subscription.buyPack(pack));
                        },
                  child: busy
                      ? const CupertinoActivityIndicator(
                          color: Color(0xFFFFFFFF),
                        )
                      : Text(
                          pack == null
                              ? l10n.chatTopUp
                              : l10n.topUpBuy(pack.price),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                l10n.topUpFine,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, height: 1.4, color: muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
