import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/countries.dart';
import '../../core/decision_types.dart';
import '../../core/news_widgets.dart';
import '../../core/pictures.dart';
import '../../core/theme.dart';
import '../../core/topics.dart';
import '../../l10n/app_localizations.dart';
import 'feed_filters.dart';

/// Design option B (#66), prototype: the cards and the styles they use.

/// The brand's serif, Georgia on iOS: it has Cyrillic, so Ukrainian and
/// Russian headlines are in the same face as English ones.
const _serif = 'Georgia';
const _serifFallback = ['serif'];

/// Margin between the screen edge and the cards. The masthead and section
/// titles sit 4 pt further in, as iOS insets titles over grouped cards.
const bMargin = 16.0;

/// The brand red made deeper, for small text on light grounds and white text
/// on red: 4.7:1 on the grey page, 5.3:1 with white.
const _deepRed = Color(0xFFD1203A);

/// Card corners: iOS's continuous corners (a superellipse, as on app icons).
const bRadius = 18.0;

/// Official pages' share pictures are mostly 1200 x 630 (1.91:1): a top
/// story shows them whole.
const _pictureRatio = 1.91;

/// The iOS Accessibility text sizes (from 1.65x): the top line stacks and the
/// filters no longer stay pinned.
bool bLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 13.5;

/// The colours and text styles of option B, for light and dark.
class BStyle {
  BStyle._(BuildContext context)
    : page = CupertinoColors.systemGroupedBackground.resolveFrom(context),
      card = CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
        context,
      ),
      pressed = CupertinoColors.systemGrey5.resolveFrom(context),
      fill = CupertinoColors.tertiarySystemFill.resolveFrom(context),
      separator = CupertinoColors.separator.resolveFrom(context),
      label = CupertinoColors.label.resolveFrom(context),
      // #6C6C70 on white is 5.2:1, #98989F on #1C1C1E 5.9:1: readable at 13 pt
      // (iOS's secondaryLabel is only 3.4:1 on white).
      secondary = Theme.of(context).colorScheme.onSurfaceVariant,
      dark = CupertinoTheme.brightnessOf(context) == Brightness.dark,
      // The brand red is 3.8:1 on white, too light for small text: the deeper
      // red in light mode, the brand red (5.5:1) on black.
      accentText = CupertinoTheme.brightnessOf(context) == Brightness.dark
          ? AppColors.accent
          : _deepRed;

  static BStyle of(BuildContext context) => BStyle._(context);

  final Color page, card, pressed, fill, separator, label, secondary;
  final Color accentText;
  final bool dark;

  TextStyle get dateline => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    color: accentText,
  );

  TextStyle get masthead => TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _serifFallback,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    height: 1.12,
    color: label,
  );

  TextStyle get section => TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.2,
    color: label,
  );

  TextStyle get country => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: label,
  );

  TextStyle get source => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: secondary,
  );

  TextStyle get kind => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    height: 1.25,
    color: secondary,
  );

  TextStyle headline(double size, double height) => TextStyle(
    fontFamily: _serif,
    fontFamilyFallback: _serifFallback,
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: height,
    color: label,
  );

  TextStyle summary(double size) =>
      TextStyle(fontSize: size, height: 1.33, color: secondary);

  TextStyle get footer => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: secondary,
  );
}

/// The article's main topic in the app's language: the names exist only in
/// English so far, so other languages show none rather than mix languages.
String? _topicName(Article article, AppLocalizations l10n) {
  if (article.topics.isEmpty || l10n.localeName != 'en') return null;
  final id = article.topics.first;
  return topicNames[id] ?? topicLabel(id);
}

/// [parts] as sentences for VoiceOver, each ending in one full stop: a summary
/// that ends in its own is not read with a second.
String _sentences(List<String> parts) => [
  for (final part in parts.map((p) => p.trim()).where((p) => p.isNotEmpty))
    RegExp(r'[.!?…]$').hasMatch(part) ? part : '$part.',
].join(' ');

/// The sizes of a card.
enum BCardKind {
  /// A top story: more room, a bigger headline, three lines of summary.
  top(
    padding: 20,
    headline: 24,
    headlineHeight: 1.18,
    summary: 16,
    summaryLines: 3,
    pictureRatio: _pictureRatio,
  ),

  /// A card in Latest.
  latest(
    padding: 16,
    headline: 20,
    headlineHeight: 1.22,
    summary: 15,
    summaryLines: 2,
    // A band rather than the whole picture, so the list keeps moving.
    pictureRatio: 2.4,
  ),

  /// A top story in the carousel (the alternative tried, FEED_B_TOP=carousel):
  /// every card as tall as the carousel, so it has no picture and its text a
  /// fixed number of lines.
  carousel(
    padding: 16,
    headline: 22,
    headlineHeight: 1.2,
    summary: 15,
    summaryLines: 3,
    pictureRatio: _pictureRatio,
  );

  const BCardKind({
    required this.padding,
    required this.headline,
    required this.headlineHeight,
    required this.summary,
    required this.summaryLines,
    required this.pictureRatio,
  });

  final double padding, headline, headlineHeight, summary, pictureRatio;
  final int summaryLines;

  static const carouselHeadlineLines = 4;
}

/// One decision in its own card: picture (when the page has one), country and
/// ministry with the decision type, the serif headline, what it means, and
/// when it arrived with its topic.
class BCard extends StatefulWidget {
  const BCard({
    super.key,
    required this.article,
    required this.read,
    required this.onTap,
    this.kind = BCardKind.latest,
  });

  final Article article;

  /// Opened before: the card stays, its text and picture faded.
  final bool read;
  final VoidCallback onTap;
  final BCardKind kind;

  @override
  State<BCard> createState() => _BCardState();
}

class _BCardState extends State<BCard> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final s = BStyle.of(context);
    final l10n = AppLocalizations.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final a = widget.article;
    final k = widget.kind;
    final read = widget.read;
    final fill = k == BCardKind.carousel;
    final large = bLargeText(context);
    final country = countryName(a.country, l10n);
    final kind = decisionTypeLabel(a.decisionType, l10n);
    final topic = _topicName(a, l10n);
    final time = feedTime(a, l10n);
    final summary = a.shortSummary?.trim();
    final hasSummary = summary != null && summary.isNotEmpty;

    final place = Text.rich(
      TextSpan(
        children: [
          // The official-source seal, always in the same place.
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(
                CupertinoIcons.checkmark_seal_fill,
                // A mark, not text: it grows with the text, but only so far.
                size: scaler.clamp(maxScaleFactor: 1.4).scale(15),
                color: read
                    ? AppColors.verified.withValues(alpha: readOpacity)
                    : AppColors.verified,
              ),
            ),
          ),
          TextSpan(text: country, style: dim(s.country, read)),
          TextSpan(text: ' · ', style: dim(s.source, read)),
          TextSpan(text: a.source.name, style: dim(s.source, read)),
        ],
      ),
      maxLines: large ? 3 : 1,
      overflow: TextOverflow.ellipsis,
    );

    final kindTag = kind == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: ShapeDecoration(
              color: read
                  ? s.fill.withValues(alpha: s.fill.a * readOpacity)
                  : s.fill,
              shape: const StadiumBorder(),
            ),
            child: Text(
              kind.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dim(s.kind, read),
            ),
          );

    final topLine = kindTag == null
        ? place
        : large
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [place, const SizedBox(height: 8), kindTag],
          )
        : Row(
            children: [
              Expanded(child: place),
              const SizedBox(width: 10),
              ConstrainedBox(
                // The country comes first and is never cut: a long type is.
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.42,
                ),
                child: kindTag,
              ),
            ],
          );

    final summaryStyle = dim(s.summary(k.summary), read);
    final footer = Text(
      [?topic, time].join('  ·  '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: dim(s.footer, read),
    );

    final text = Padding(
      padding: EdgeInsets.fromLTRB(
        k.padding,
        a.imageUrl == null || fill ? k.padding : k.padding - 2,
        k.padding,
        k.padding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          topLine,
          SizedBox(height: k == BCardKind.top ? 12 : 10),
          Text(
            a.headline,
            style: dim(s.headline(k.headline, k.headlineHeight), read),
            // The headline is the news: never cut in the list, at any size.
            // (An ellipsis without a line limit would cut it after one line.)
            maxLines: fill ? BCardKind.carouselHeadlineLines : null,
            overflow: fill ? TextOverflow.ellipsis : TextOverflow.clip,
          ),
          if (hasSummary) ...[
            SizedBox(height: k == BCardKind.top ? 8 : 6),
            Text(
              summary,
              style: summaryStyle,
              maxLines: k.summaryLines,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (fill) const Spacer(),
          SizedBox(height: k == BCardKind.top ? 14 : 12),
          footer,
        ],
      ),
    );

    // One VoiceOver stop per card, read in the order that matters: what, what
    // kind, who, what it means, when.
    final spoken = _sentences([
      a.headline,
      ?kind,
      '$country, ${a.source.name}',
      if (hasSummary) summary,
      ?topic,
      time,
    ]);

    return Semantics(
      container: true,
      button: true,
      label: spoken,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: _pressed ? s.pressed : s.card,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(bRadius),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (a.imageUrl != null && !fill)
                BCardPicture(
                  url: a.imageUrl!,
                  dimmed: read,
                  ratio: k.pictureRatio,
                ),
              if (fill) Expanded(child: text) else text,
            ],
          ),
        ),
      ),
    );
  }
}

/// The page's picture across the top of a card. If it cannot be loaded it is
/// left out, so the card shows its text alone instead of an empty grey box.
class BCardPicture extends StatelessWidget {
  const BCardPicture({
    super.key,
    required this.url,
    this.dimmed = false,
    this.ratio = _pictureRatio,
  });

  final String url;
  final bool dimmed;

  /// Width to height.
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final s = BStyle.of(context);
    final pixels = MediaQuery.devicePixelRatioOf(context);
    // Bright pictures (often a site's logo) are toned down a little on dark cards.
    final keep = (dimmed ? readOpacity : 1.0) * (s.dark ? 0.88 : 1.0);
    return LayoutBuilder(
      builder: (context, constraints) => ClipRSuperellipse(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(bRadius),
        ),
        child: Image(
          // Decoded near the size shown, so a long feed keeps little in memory.
          image: picture(
            url,
            width: constraints.maxWidth.isFinite
                ? (constraints.maxWidth * pixels).round()
                : null,
          ),
          fit: BoxFit.cover,
          opacity: keep < 1 ? AlwaysStoppedAnimation(keep) : null,
          frameBuilder: (context, child, frame, _) => AspectRatio(
            aspectRatio: ratio,
            child: ColoredBox(color: s.fill, child: child),
          ),
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// "3 new decisions" with an arrow up: shown instead of moving the list.
class BNewPill extends StatelessWidget {
  const BNewPill({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final words = AppLocalizations.of(context).newDecisions(count);
    // A control that floats over the list: it grows with the text, but only
    // so far, so at the largest sizes it does not cover the screen.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6);
    return Semantics(
      button: true,
      label: words,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minHeight: 44,
            maxWidth: MediaQuery.sizeOf(context).width - 2 * bMargin,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: const ShapeDecoration(
            // The deeper red: white on it is 5.3:1 (on the brand red, 3.8:1).
            color: _deepRed,
            shape: StadiumBorder(),
            shadows: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.arrow_up,
                size: scaler.scale(15),
                color: CupertinoColors.white,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  words,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textScaler: scaler,
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
