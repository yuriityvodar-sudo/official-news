import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/countries.dart';
import '../../core/decision_types.dart';
import '../../core/news_widgets.dart';
import '../../core/pictures.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'feed_look_b_words.dart';

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

/// Official pages' share pictures are mostly 1200 x 630 (1.91:1): the first
/// top story shows its picture whole.
const _pictureRatio = 1.91;

/// The iOS Accessibility text sizes, from AX1 (1.65x, body 28 pt). Up to the
/// largest standard size, XXXL (1.35x), a card keeps its normal layout. From
/// AX1 the filters take two rows, so they no longer stay pinned, and the
/// cards' padding narrows to give the text room.
bool bLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 16.0;

/// The largest a card's text grows, so that at the largest sizes each text
/// keeps its rank: the headline stops at 40 pt (from about AX2), what it
/// means at 36 pt and the labels (who decided, the topic and time) at 30 pt.
/// A headline then keeps two or three words a line.
enum _Largest {
  headline(40),
  summary(36),
  label(30);

  const _Largest(this.points);

  final double points;
}

/// [scaler] for text of [size] on a card, stopped at [largest].
TextScaler _capped(TextScaler scaler, double size, _Largest largest) =>
    scaler.clamp(maxScaleFactor: math.max(1.0, largest.points / size));

/// Where a line may break: at a space, and after a hyphen
/// ("імідж-консультанта"). A non-breaking hyphen (U+2011) keeps its word.
final _breaks = RegExp(r'\s+|(?<=-)');

/// Flutter breaks a word that is wider than the line between two letters
/// ("municipalitie / s"). This makes [scaler] smaller, for this text only, so
/// its widest word fits in [width]: at large text sizes a long word
/// ("головнокомандувача", "Bundesregierung") is drawn a little smaller
/// rather than broken. Text whose words all fit keeps [scaler]. The words
/// are measured in the font that draws them, so it holds for any font.
TextScaler bFitWords(
  BuildContext context,
  TextScaler scaler,
  double width,
  List<(String, TextStyle)> parts,
) {
  if (!width.isFinite || width <= 0 || parts.isEmpty) return scaler;
  final base = DefaultTextStyle.of(context).style;
  final painter = TextPainter(
    text: TextSpan(
      children: [
        for (final (text, style) in parts)
          TextSpan(
            text: '${text.trim().split(_breaks).join('\n')}\n',
            style: base.merge(style),
          ),
      ],
    ),
    textDirection: Directionality.of(context),
  );
  final size = parts.first.$2.fontSize ?? 14;
  var fitted = scaler;
  // Letter spacing does not grow with the text, so a word's width is not in
  // proportion to the scale: measured again until it fits (twice at most,
  // in practice).
  for (var tries = 0; tries < 4; tries++) {
    painter
      ..textScaler = fitted
      ..layout();
    final widest = painter.maxIntrinsicWidth;
    // A point under the line, for rounding.
    if (widest <= width - 0.5) break;
    final factor = fitted.scale(size) / size;
    fitted = scaler.clamp(maxScaleFactor: factor * (width - 1) / widest);
  }
  painter.dispose();
  return fitted;
}

/// The words of [text] that fit in [maxLines] lines of [width], cut after a
/// whole word with "…": Flutter's own ellipsis cuts inside a word
/// ("identificati…"). When the cut would leave only a few words of a new
/// sentence ("It requires…"), it ends with the sentence before instead.
/// Null when the whole text fits.
String? bCutAtWord(
  String text, {
  required TextStyle style,
  required TextScaler scaler,
  required int maxLines,
  required double width,
  required TextDirection direction,
}) {
  if (!width.isFinite || width <= 0) return null;
  final painter = TextPainter(
    textDirection: direction,
    textScaler: scaler,
    maxLines: maxLines,
  );
  bool fits(String s) {
    painter
      ..text = TextSpan(text: s, style: style)
      ..layout(maxWidth: width);
    return !painter.didExceedMaxLines;
  }

  try {
    if (fits(text)) return null;
    final words = text.split(' ');
    String cut(int n) =>
        '${words.take(n).join(' ').replaceFirst(RegExp(r'[\s,;:–—-]+$'), '')}…';
    var best = 0;
    var lo = 1, hi = words.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (fits(cut(mid))) {
        best = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    // Not even one word fits: Flutter's ellipsis does what it can.
    if (best == 0) return null;
    for (var n = best; n > 0 && best - n <= 3; n--) {
      if (RegExp(r'[.!?]["»”’)]?$').hasMatch(words[n - 1])) {
        return words.take(n).join(' ');
      }
    }
    return cut(best);
  } finally {
    painter.dispose();
  }
}

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

/// How much of its colour grey text keeps on a read card. Faded as much as
/// the headline (readOpacity), #6C6C70 fell to 2.2:1 on white; at 0.8 it is
/// about 3.5:1 (4.3:1 in dark), and the card still reads as opened.
const _readGrey = 0.8;

/// [style], grey text, faded for a card already read.
TextStyle _fadeGrey(TextStyle style, bool read) => read && style.color != null
    ? style.copyWith(
        color: style.color!.withValues(alpha: style.color!.a * _readGrey),
      )
    : style;

/// [parts] as sentences for VoiceOver, each ending in one full stop: a summary
/// that ends in its own is not read with a second.
String _sentences(List<String> parts) => [
  for (final part in parts.map((p) => p.trim()).where((p) => p.isNotEmpty))
    RegExp(r'[.!?…]$').hasMatch(part) ? part : '$part.',
].join(' ');

/// The sizes of a card.
enum BCardKind {
  /// A top story: more room, a bigger headline, four lines of summary.
  top(
    padding: 20,
    headline: 24,
    headlineHeight: 1.18,
    summary: 16,
    summaryLines: 4,
    // The band of Latest; only the first top story shows its picture whole.
    pictureRatio: 2.4,
  ),

  /// A card in Latest.
  latest(
    padding: 16,
    headline: 20,
    headlineHeight: 1.22,
    summary: 15,
    summaryLines: 3,
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

  /// Lines for the country and ministry: two, four at the Accessibility sizes.
  static int placeLines(bool large) => large ? 4 : 2;

  /// Lines for the topic and time beside the type tag.
  static int footerLines(bool large) => large ? 3 : 1;
}

/// One decision in its own card: picture (when the page has one), country and
/// ministry, the serif headline, what it means, then the decision type, the
/// topic and when it arrived.
class BCard extends StatefulWidget {
  const BCard({
    super.key,
    required this.article,
    required this.read,
    required this.onTap,
    this.kind = BCardKind.latest,
    this.lead = false,
  });

  final Article article;

  /// Opened before: the card stays, its headline and picture faded.
  final bool read;
  final VoidCallback onTap;
  final BCardKind kind;

  /// The first top story: its picture is shown whole.
  final bool lead;

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
    final padding = large ? 16.0 : k.padding;
    final country = countryName(a.country, l10n);
    final kind = decisionTypeLabel(a.decisionType, l10n);
    final topic = bTopicName(a, l10n);
    final time = feedTime(a, l10n);
    final summary = a.shortSummary?.trim();
    final hasSummary = summary != null && summary.isNotEmpty;

    // Who decided: the country, the official-source seal and the ministry,
    // in up to two lines, so a long ministry's name is not cut.
    final place = LayoutBuilder(
      builder: (context, constraints) {
        final fitted = bFitWords(
          context,
          _capped(scaler, 13, _Largest.label),
          constraints.maxWidth,
          [(country, s.country), (a.source.name, s.source)],
        );
        // Flutter scales an inline widget with its text; the seal is a mark,
        // not text, so it grows only to 1.4x.
        final grow = fitted.scale(14) / 14;
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: country, style: dim(s.country, read)),
              // The official-source seal, outlined and grey as a quiet mark.
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    CupertinoIcons.checkmark_seal,
                    size: 14 * math.min(grow, 1.4) / grow,
                    color: _fadeGrey(s.source, read).color,
                  ),
                ),
              ),
              TextSpan(text: ' · ', style: _fadeGrey(s.source, read)),
              TextSpan(text: a.source.name, style: _fadeGrey(s.source, read)),
            ],
          ),
          textScaler: fitted,
          maxLines: BCardKind.placeLines(large),
          overflow: TextOverflow.ellipsis,
        );
      },
    );

    final headlineStyle = dim(s.headline(k.headline, k.headlineHeight), read);
    final headline = LayoutBuilder(
      builder: (context, constraints) => Text(
        a.headline,
        style: headlineStyle,
        textScaler: bFitWords(
          context,
          _capped(scaler, k.headline, _Largest.headline),
          constraints.maxWidth,
          [(a.headline, headlineStyle)],
        ),
        // The headline is the news: never cut in the list, at any size.
        // (An ellipsis without a line limit would cut it after one line.)
        maxLines: fill ? BCardKind.carouselHeadlineLines : null,
        overflow: fill ? TextOverflow.ellipsis : TextOverflow.clip,
      ),
    );

    // The decision type leads the footer, the topic and time beside it; they
    // move under it when a long type and topic do not fit on one line.
    final footerText = Text(
      [?topic, time].join('  ·  '),
      maxLines: BCardKind.footerLines(large),
      overflow: TextOverflow.ellipsis,
      style: _fadeGrey(s.footer, read),
      textScaler: _capped(scaler, 13, _Largest.label),
    );
    final footer = kind == null
        ? footerText
        : Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _KindTag(kind, read: read, large: large),
              footerText,
            ],
          );

    final text = Padding(
      padding: EdgeInsets.fromLTRB(
        padding,
        a.imageUrl == null || fill ? padding : padding - 2,
        padding,
        padding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          place,
          SizedBox(height: k == BCardKind.top ? 10 : 8),
          headline,
          if (hasSummary) ...[
            SizedBox(height: k == BCardKind.top ? 8 : 6),
            _Teaser(
              summary,
              style: _fadeGrey(s.summary(k.summary), read),
              maxLines: k.summaryLines,
              scaler: _capped(scaler, k.summary, _Largest.summary),
            ),
          ],
          if (fill) const Spacer(),
          SizedBox(height: k == BCardKind.top ? 14 : 12),
          footer,
        ],
      ),
    );

    // One VoiceOver stop per card. The headline first, as it is the news,
    // then the card's own order: who, what it means, what kind, the topic,
    // when; "Read" after a card already opened.
    final spoken = _sentences([
      a.headline,
      '$country, ${a.source.name}',
      if (hasSummary) summary,
      ?kind,
      ?topic,
      time,
    ]);

    return Semantics(
      container: true,
      button: true,
      label: spoken,
      value: read ? bReadWord(l10n) : null,
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
                  ratio: widget.lead ? _pictureRatio : k.pictureRatio,
                ),
              if (fill) Expanded(child: text) else text,
            ],
          ),
        ),
      ),
    );
  }
}

/// The decision type as a small grey tag: "BILL", "РІШЕННЯ УРЯДУ".
class _KindTag extends StatelessWidget {
  const _KindTag(this.kind, {required this.read, required this.large});

  final String kind;
  final bool read;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final s = BStyle.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: read ? s.fill.withValues(alpha: s.fill.a * _readGrey) : s.fill,
        // A pill on one line; at the Accessibility sizes a long type may take
        // two, and a pill's round ends would cut into them.
        shape: large
            ? RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(10))
            : const StadiumBorder(),
      ),
      child: Text(
        kind.toUpperCase(),
        maxLines: large ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: _fadeGrey(s.kind, read),
        // A label: it grows to twice its size (22 pt), not with the text.
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2.0),
      ),
    );
  }
}

/// What it means, in at most [maxLines] lines, cut after a whole word.
class _Teaser extends StatelessWidget {
  const _Teaser(
    this.text, {
    required this.style,
    required this.maxLines,
    required this.scaler,
  });

  final String text;
  final TextStyle style;
  final int maxLines;
  final TextScaler scaler;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final fitted = bFitWords(context, scaler, constraints.maxWidth, [
        (text, style),
      ]);
      final cut = bCutAtWord(
        text,
        style: DefaultTextStyle.of(context).style.merge(style),
        scaler: fitted,
        maxLines: maxLines,
        width: constraints.maxWidth,
        direction: Directionality.of(context),
      );
      return Text(
        cut ?? text,
        style: style,
        textScaler: fitted,
        maxLines: maxLines,
        // Only if the cut above came out a hair long.
        overflow: TextOverflow.ellipsis,
      );
    },
  );
}

/// The page's picture across the top of a card. A grey box holds its place
/// while it loads and stays if it cannot be loaded, so the cards below never
/// move while they are read.
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
    Widget box([Widget? child]) => AspectRatio(
      aspectRatio: ratio,
      child: ColoredBox(color: s.fill, child: child),
    );
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
          frameBuilder: (context, child, frame, _) => box(child),
          // Flutter skips frameBuilder on an error, so the box is drawn here too.
          errorBuilder: (_, _, _) => box(),
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
