import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../../core/analytics.dart';
import '../../core/article.dart';
import '../../core/glass.dart';
import '../../core/motion.dart';
import '../../core/subscription.dart';
import '../../l10n/app_localizations.dart';
import '../settings/info_pages.dart';
import 'chat_style.dart';

/// The AI chat's paywall (#146), variant B of Roman's mockup, like a news
/// paywall that cuts an article (WSJ): a sample question about this decision
/// and the start of an answer, the first lines of its summary, fading under
/// the offer. A hard paywall: no free trial and no free question. What App
/// Store guideline 3.1.2 asks is here: the price and the period as the
/// largest words, auto-renewal and where to cancel, Restore Purchases, the
/// Terms and the Privacy Policy, and a close button. Closes with `true` once
/// the subscription is paid.
class PaywallSheet extends StatefulWidget {
  const PaywallSheet({
    super.key,
    required this.article,
    this.subscription,
    this.scroll,
  });

  final Article article;

  /// [chatSubscription] unless a test brings its own.
  final ChatSubscription? subscription;
  final ScrollController? scroll;

  static Future<bool> show(BuildContext context, Article article) async =>
      await showCupertinoSheet<bool>(
        context: context,
        showDragHandle: true,
        scrollableBuilder: (_, scroll) =>
            PaywallSheet(article: article, scroll: scroll),
      ) ??
      false;

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  ChatSubscription get _subscription => widget.subscription ?? chatSubscription;

  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(analytics.paywallView(widget.article));
    _subscription.addListener(_changed);
    _subscription.state.addListener(_stateChanged);
    unawaited(
      _subscription.loadProduct().whenComplete(() {
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

  PurchaseState? _was;

  void _stateChanged() {
    final state = _subscription.state.value;
    final result = switch (state) {
      PurchaseState.failed when _was == PurchaseState.restoring => null,
      PurchaseState.failed => 'failed',
      PurchaseState.pending => 'pending',
      PurchaseState.idle when _was == PurchaseState.buying => 'cancelled',
      _ => null,
    };
    if (result != null && !_subscription.active) {
      unawaited(analytics.subscribeResult(result));
    }
    if (_was == PurchaseState.restoring) {
      if (state == PurchaseState.nothingToRestore) {
        unawaited(analytics.restoreResult('nothing'));
      } else if (state == PurchaseState.failed) {
        unawaited(analytics.restoreResult('failed'));
      }
    }
    _was = state;
    if (mounted) setState(() {});
  }

  /// Paid: by a purchase or a restore, the sheet's work is done.
  void _changed() {
    if (!_subscription.active || !mounted) return;
    unawaited(
      _was == PurchaseState.restoring
          ? analytics.restoreResult('restored')
          : analytics.subscribeResult('purchased'),
    );
    Navigator.of(context).pop(true);
  }

  void _openPage(String title, List<InfoSection> sections) => unawaited(
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (context) => InfoPage(
          title: title,
          sections: sections,
          updated: policyUpdatedLine(AppLocalizations.of(context)),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ChatStyle.of(context);
    final label = CupertinoColors.label.resolveFrom(context);
    final muted = CupertinoColors.secondaryLabel.resolveFrom(context);
    final card = CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
      context,
    );
    final article = widget.article;
    final state = _subscription.state.value;
    final product = _subscription.product;
    final busy =
        state == PurchaseState.buying || state == PurchaseState.restoring;
    final message = switch (state) {
      _ when _loaded && product == null => l10n.paywallUnavailable,
      PurchaseState.pending => l10n.paywallPending,
      PurchaseState.failed => l10n.paywallFailed,
      PurchaseState.nothingToRestore => l10n.paywallNothingToRestore,
      _ => null,
    };
    final sample = article.summary ?? article.shortSummary ?? '';

    final header = Row(
      children: [
        Icon(CupertinoIcons.sparkles, size: 20, color: style.ink),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.aiAgent,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: label,
            ),
          ),
        ),
        Semantics(
          button: true,
          label: l10n.paywallClose,
          child: CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            onPressed: () => Navigator.of(context).pop(false),
            child: GlassCircle(
              size: 34,
              child: Icon(
                CupertinoIcons.xmark,
                size: 16,
                color: label,
                semanticLabel: l10n.paywallClose,
              ),
            ),
          ),
        ),
      ],
    );
    // The decision the sample is about, as a pill with the official seal.
    final about = Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.checkmark_seal_fill,
              size: 15,
              color: style.ink,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${article.source.name} · ${article.headline}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: label,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final question = Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: style.fill,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: Text(
          l10n.chatSuggestConcernsMe,
          style: const TextStyle(fontSize: 15, color: Color(0xFFFFFFFF)),
        ),
      ),
    );
    final agent = Row(
      children: [
        Icon(CupertinoIcons.sparkles, size: 15, color: style.ink),
        const SizedBox(width: 6),
        Text(
          l10n.aiAgent,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: label,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: muted.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            l10n.paywallSample,
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ),
      ],
    );
    // The answer fades out into the offer, as a cut article does.
    final answer = ExcludeSemantics(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF000000), Color(0x00000000)],
          stops: [0.3, 1],
        ).createShader(bounds),
        child: Text(
          sample,
          maxLines: 5,
          overflow: TextOverflow.clip,
          style: TextStyle(fontSize: 15, height: 1.45, color: label),
        ),
      ),
    );
    final offer = Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: style.fill.withValues(alpha: 0.22),
            blurRadius: 30,
            spreadRadius: -14,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: style.ink.withValues(alpha: 0.14),
            ),
            child: Icon(CupertinoIcons.lock_fill, size: 18, color: style.ink),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.paywallTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: label,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.paywallPoints,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: muted),
          ),
          const SizedBox(height: 10),
          if (product != null)
            Text(
              l10n.paywallPrice(product.price),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: label,
              ),
            )
          else if (!_loaded)
            const CupertinoActivityIndicator(),
          const SizedBox(height: 4),
          Text(
            l10n.paywallRenewal,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.35, color: muted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              color: style.fill,
              // Readable while there is nothing to buy yet.
              disabledColor: style.fill.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(26),
              onPressed: product == null || busy
                  ? null
                  : () {
                      Haptics.light();
                      unawaited(analytics.subscribeTap());
                      unawaited(_subscription.buy());
                    },
              child: state == PurchaseState.buying
                  ? const CupertinoActivityIndicator(color: Color(0xFFFFFFFF))
                  : Text(
                      l10n.paywallSubscribe,
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
          const SizedBox(height: 2),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Link(
                l10n.paywallRestore,
                color: style.ink,
                onTap: busy ? null : () => unawaited(_subscription.restore()),
              ),
              _Link(
                l10n.termsOfUse,
                color: style.ink,
                onTap: () => _openPage(l10n.termsOfUse, termsSections(l10n)),
              ),
              _Link(
                l10n.privacyPolicy,
                color: style.ink,
                onTap: () =>
                    _openPage(l10n.privacyPolicy, privacySections(l10n)),
              ),
            ],
          ),
        ],
      ),
    );

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      // Material for the default text style (no yellow underline on plain Text).
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          // The sample sits at the bottom, over the offer, as the end of a chat
          // does; on a short screen it all scrolls.
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              controller: widget.scroll,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(box.maxHeight - 20, 0),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 12),
                        about,
                        const SizedBox(height: 14),
                        question,
                        const SizedBox(height: 14),
                        agent,
                        const SizedBox(height: 6),
                        answer,
                        offer,
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.text, {required this.color, required this.onTap});

  final String text;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    minimumSize: const Size(44, 44),
    onPressed: onTap,
    child: Text(
      text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color),
    ),
  );
}
