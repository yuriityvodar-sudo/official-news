import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/countries.dart';
import '../../core/news_widgets.dart';
import '../../core/pictures.dart';
import '../../core/read_mark.dart';
import '../../core/motion.dart';
import '../../l10n/app_localizations.dart';
import 'feed_look.dart';
import 'feed_look_now.dart';
import 'feed_topic_tags.dart';
import 'feed_touches.dart';

/// Design option A (#66, from the prototype, kept in Settings → Design): "Refined editorial".
///
/// Today's Apple News structure, done carefully: one list of rows with a small
/// picture on the right (no section titles and no lead story since Yurii's
/// review, 16 Oct). Every row reads
/// in the same order, top to bottom: where it comes from (country,
/// institution), the headline in a reading serif and when ("8m ago"), then
/// its topics as small grey tags across the whole row (the decision type,
/// which stood before the time until 16 Oct, is on the article screen). Red
/// is kept for the brand's few accents only.
class ALook extends NowLook {
  @override
  Widget masthead(BuildContext context, FeedMasthead masthead) {
    final type = _AType.of(context);
    // The masthead is the app's nameplate and controls: its text grows with
    // Dynamic Type only so far, like iOS navigation bars, so it never takes
    // over the screen. Articles grow without a limit.
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: _mastheadMaxScale);
    final titleHeight = scaler.scale(type.nameplate.fontSize!) * 1.18;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _MastheadDelegate(
        masthead: masthead,
        background: background(context),
        scaler: scaler,
        titleHeight: titleHeight,
      ),
    );
  }

  // One list in the order articles appeared, with no titles and no day
  // headings: an article dated yesterday can appear today. Each row shows
  // its time.
  @override
  Widget articles(BuildContext context, FeedList list) => SliverPadding(
    // As far under the filters as the first row was under a section title.
    padding: const EdgeInsets.only(top: 6),
    sliver: _rows(list),
  );

  // As today's, but a failed page offers its retry in the text colour: the
  // brand red on white is too faint for small text (about 3.8:1).
  @override
  Widget feedEnd(BuildContext context, FeedEnd end) {
    if (end.state != FeedEndState.failed) return super.feedEnd(context, end);
    final type = _AType.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(_margin, 24, _margin, 48),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: CupertinoButton(
            onPressed: end.retry,
            child: Text(
              AppLocalizations.of(context).feedLoadMoreFailed,
              textAlign: TextAlign.center,
              style: type.footer.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: type.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget newPill(
    BuildContext context, {
    required int count,
    required VoidCallback onTap,
  }) => _NewPill(count: count, onTap: onTap);

  /// The articles of [list], a hairline between them.
  Widget _rows(FeedList list) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: _margin),
    sliver: SliverList.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final a = list.articles[i];
        list.shown(i);
        final row = list.tile(
          i,
          _Row(
            article: a,
            mark: list.markOf(a),
            topics: list.topicsOf(a),
            onTap: () => list.open(i),
          ),
        );
        if (i == 0) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [const Divider(height: 1), row],
        );
      },
    ),
  );
}

/// The feed's side margins.
const _margin = 20.0;

/// How far the masthead's text grows with Dynamic Type.
const _mastheadMaxScale = 1.3;

/// The reading serif: Charter, on every iPhone. Compared on the simulator
/// with Iowan Old Style and Palatino, it is the plainest and steadiest at
/// small sizes, and its regular and bold have Cyrillic (its Black has none,
/// so nothing here asks for a weight above bold).
const _serif = 'Charter';

/// Georgia has every glyph the app's languages need; Android has `serif`.
const _serifFallback = ['Georgia', 'serif'];

/// Option A's text styles, from the page's colours.
class _AType {
  _AType._(ColorScheme scheme)
    : ink = scheme.onSurface,
      muted = scheme.onSurfaceVariant,
      nameplate = TextStyle(
        fontFamily: _serif,
        fontFamilyFallback: _serifFallback,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: -0.4,
        color: scheme.onSurface,
      ),
      compactTitle = TextStyle(
        fontFamily: _serif,
        fontFamilyFallback: _serifFallback,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      dateline = TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: scheme.onSurfaceVariant,
      ),
      country = TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
        color: scheme.onSurfaceVariant,
      ),
      kicker = TextStyle(
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w400,
        color: scheme.onSurfaceVariant,
      ),
      headline = TextStyle(
        fontFamily: _serif,
        fontFamilyFallback: _serifFallback,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        height: 1.24,
        color: scheme.onSurface,
      ),
      footer = TextStyle(
        fontSize: 13,
        height: 1.3,
        color: scheme.onSurfaceVariant,
      );

  factory _AType.of(BuildContext context) =>
      _AType._(Theme.of(context).colorScheme);

  final Color ink;

  /// The grey of everything but the headline, the topic tags too: 5.2:1 on
  /// white and 7.3:1 on black.
  final Color muted;
  final TextStyle nameplate;
  final TextStyle compactTitle;
  final TextStyle dateline;

  /// "BRAZIL  Chamber of Deputies": the country in grey capitals, like a
  /// wire dateline, the institution in grey. The country is the field that
  /// repeats (one source gives several decisions in a row), so it is not in
  /// ink: the headline is.
  final TextStyle country;
  final TextStyle kicker;
  final TextStyle headline;

  /// "8m ago", under the headline.
  final TextStyle footer;

  /// A read article's ink text turns grey; text that is grey already stays
  /// as it is, so a read card stays readable (5.2:1 on white).
  TextStyle read(TextStyle style, bool read) =>
      read ? style.copyWith(color: muted) : style;
}

/// A site's default sharing picture (the GOV.UK crown tile,
/// Kantei's logo) says nothing about the decision and reads like an ad, so
/// the feed leaves it out. The real fix belongs in the fetcher: not saving
/// such a picture as the article's.
///
/// "logo" counts only as a name of its own in the path ("/logo.png",
/// "site-logo.svg", "/logos/"), not inside a word ("/catalogo/").
bool _sitePicture(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return path.contains('opengraph') ||
      path.contains('/ogp.') ||
      path.contains('og-image') ||
      path.contains('og_image') ||
      _logo.hasMatch(path);
}

final _logo = RegExp(r'(^|[/_.-])logos?([/_.-]|$)');

/// The article's own picture, or null.
String? _pictureOf(Article a) {
  final url = a.imageUrl;
  if (url == null || url.isEmpty || _sitePicture(url)) return null;
  return url;
}

/// Where a decision comes from: "BRAZIL  Chamber of Deputies". The
/// country comes first so it is never cut; a long institution name is.
/// It is grey already, so it looks the same once the article is read.
/// In the dot styles the unread dot stands between the two,
/// "BRAZIL ● Chamber of Deputies"; once read its room shows a small grey
/// " · ", as B does, so the institution does not move.
class _Kicker extends StatelessWidget {
  const _Kicker(this.article, {required this.mark, required this.maxLines});

  final Article article;
  final ReadMark mark;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final type = _AType.of(context);
    final l10n = AppLocalizations.of(context);
    return Text.rich(
      TextSpan(
        style: type.kicker,
        children: [
          TextSpan(
            text: countryName(article.country, l10n).toUpperCase(),
            style: type.country,
          ),
          if (mark.dots) ...[
            unreadDotSpan(
              context,
              mark,
              fontSize: type.country.fontSize!,
              scaler: MediaQuery.textScalerOf(context),
              separator: type.kicker.color,
            ),
            TextSpan(text: article.source.name),
          ] else
            TextSpan(text: '  ${article.source.name}'),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// When: "8m ago", where "Bill · 8m ago" was until the decision type moved
/// to the article screen (16 Oct).
class _Footer extends StatelessWidget {
  const _Footer(this.article);

  final Article article;

  @override
  Widget build(BuildContext context) {
    final time = feedTime(article, AppLocalizations.of(context));
    final style = _AType.of(context).footer;
    // A decision of the last hour stands out (#141).
    return isFresh(article)
        ? FreshTime(time, articleId: article.id, style: style)
        : Text(time, style: style);
  }
}

/// What VoiceOver reads for a card, once: the headline first, then where it
/// comes from, its topics and when.
String _spoken(BuildContext context, Article a, List<String> topics) {
  final l10n = AppLocalizations.of(context);
  // One sentence each; a text that already ends in a full stop keeps one.
  String sentence(String s) => RegExp(r'[.!?…]$').hasMatch(s) ? s : '$s.';
  return [
    a.headline,
    '${countryName(a.country, l10n)}, ${a.source.name}',
    ?spokenTopics(topics, l10n),
    feedTime(a, l10n),
  ].map(sentence).join(' ');
}

/// "Read", for VoiceOver on an opened article. It belongs in the
/// app's translations (`feedRead` in the .arb files) once a design is chosen;
/// a design option may change only its own file.
String _readWord(BuildContext context) =>
    switch (Localizations.localeOf(context).languageCode) {
      'uk' || 'ru' => 'Прочитано',
      'es' => 'Leído',
      'de' => 'Gelesen',
      _ => 'Read',
    };

/// A card that is one button for VoiceOver, with one label, and says "Read"
/// once it was opened (in the dot styles, "Unread" until it is). It tints
/// under the finger, across the whole width, as iOS lists do.
class _Card extends StatefulWidget {
  const _Card({
    required this.label,
    required this.mark,
    required this.onTap,
    required this.child,
  });

  final String label;
  final ReadMark mark;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> {
  bool _pressed = false;

  void _press(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      value: widget.mark.unread
          ? AppLocalizations.of(context).feedUnread
          : widget.mark.dimmed
          ? _readWord(context)
          : null,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Flutter reports the touch after 100 ms, or at once on a quick tap,
        // and cancels it when the finger starts a scroll: no flicker.
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        child: Stack(
          // The card keeps the full width it is given, also for a short lead.
          fit: StackFit.passthrough,
          clipBehavior: Clip.none,
          children: [
            if (_pressed)
              Positioned(
                top: 0,
                bottom: 0,
                left: -_margin,
                right: -_margin,
                child: ColoredBox(
                  color: scheme.onSurface.withValues(alpha: 0.06),
                ),
              ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

/// Dynamic Type for text of [size] points: small text grows as the reader
/// asks, large text less, as iOS's own text styles do (a 28-pt title grows
/// about 60% as much as body text). Flutter scales every size alike.
TextScaler _damped(BuildContext context, double? size) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  if (scale <= 1 || size == null || size <= 17) {
    return MediaQuery.textScalerOf(context);
  }
  return TextScaler.linear(1 + (scale - 1) * (17 / size));
}

/// Whether the reader chose one of the larger accessibility text sizes.
bool _hugeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) > 15;

/// One decision: where from, the headline and when with a small picture on
/// their right, then its topics.
class _Row extends StatelessWidget {
  const _Row({
    required this.article,
    required this.mark,
    required this.topics,
    required this.onTap,
  });

  final Article article;
  final ReadMark mark;

  /// The topic tags, in order ([FeedList.topicsOf]).
  final List<String> topics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = _AType.of(context);
    final read = mark.dimmed;
    final huge = _hugeText(context);
    // At the accessibility sizes the headline needs the whole width.
    final url = huge ? null : _pictureOf(article);
    return _Card(
      label: _spoken(context, article, topics),
      mark: mark,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Kicker(article, mark: mark, maxLines: huge ? 3 : 1),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _WholeWords(
                        article.headline,
                        style: type.read(type.headline, read),
                        maxLines: huge ? 9 : 6,
                      ),
                      const SizedBox(height: 6),
                      _Footer(article),
                    ],
                  ),
                ),
                if (url != null)
                  _Thumb(url: url, size: 76, gap: 16, dimmed: read),
              ],
            ),
            // The topics last, across the whole row, under the picture too:
            // three long names ("Sicherheit und Verteidigung") take two
            // lines at most. Grey, read or not (grey text stays as it is on a
            // read row).
            if (topics.isNotEmpty) ...[
              const SizedBox(height: 10),
              TopicTags(topics, color: type.muted),
            ],
          ],
        ),
      ),
    );
  }
}

/// Text cut after a whole word: "…in the National…", never "…in the Nati…".
/// Only a text that does not fit is measured again, a few times at most.
class _WholeWords extends StatelessWidget {
  const _WholeWords(this.text, {required this.style, required this.maxLines});

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final drawn = _drawnStyle(context);
      final shown = constraints.maxWidth.isFinite
          ? _fit(context, drawn, constraints.maxWidth)
          : text;
      return Text(
        shown,
        style: drawn,
        textScaler: _damped(context, style.fontSize),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    },
  );

  /// The style the text is drawn in, as Text builds it: with iOS Bold Text
  /// on, everything is bold, so it is measured bold too.
  TextStyle _drawnStyle(BuildContext context) {
    final s = DefaultTextStyle.of(context).style.merge(style);
    return MediaQuery.boldTextOf(context)
        ? s.merge(const TextStyle(fontWeight: FontWeight.bold))
        : s;
  }

  String _fit(BuildContext context, TextStyle drawn, double width) {
    final painter = TextPainter(
      maxLines: maxLines,
      textDirection: Directionality.of(context),
      textScaler: _damped(context, style.fontSize),
      textHeightBehavior: DefaultTextStyle.of(context).textHeightBehavior,
      locale: Localizations.maybeLocaleOf(context),
    );
    bool fits(String s) {
      painter.text = TextSpan(text: s, style: drawn);
      painter.layout(maxWidth: width);
      return !painter.didExceedMaxLines;
    }

    try {
      if (fits(text)) return text;
      final words = text.split(' ');
      if (words.length < 3) return text;
      String cut(int n) =>
          '${words.take(n).join(' ').replaceAll(RegExp(r'[\s,;:–—-]+$'), '')}…';
      // The most words that fit with the ellipsis.
      var lo = 1, hi = words.length - 1;
      while (lo < hi) {
        final mid = (lo + hi + 1) ~/ 2;
        if (fits(cut(mid))) {
          lo = mid;
        } else {
          hi = mid - 1;
        }
      }
      return cut(lo);
    } finally {
      painter.dispose();
    }
  }
}

/// The colour behind a picture that is still loading.
Color _pictureFill(BuildContext context, bool dimmed) {
  final fill = Theme.of(context).colorScheme.surfaceContainerHighest;
  return dimmed ? fill.withValues(alpha: fill.a * readOpacity) : fill;
}

/// How much of a picture shows: a read one fades with its text, and in dark
/// mode a bright picture is toned down so it does not glare.
double? _pictureOpacity(BuildContext context, bool dimmed) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final o = (dimmed ? readOpacity : 1.0) * (dark ? 0.88 : 1.0);
  return o == 1.0 ? null : o;
}

/// A small square picture on the right of a headline, [gap] from it. If it
/// cannot be loaded it takes no room at all, so the headline gets the width.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.url,
    required this.size,
    required this.gap,
    required this.dimmed,
  });

  final String url;
  final double size;
  final double gap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final opacity = _pictureOpacity(context, dimmed);
    // Decoded twice as wide as the box: a landscape picture is cropped to
    // its height and stays sharp.
    return Image(
      image: picture(url, width: (size * 2 * ratio).round()),
      width: size,
      height: size,
      fit: BoxFit.cover,
      opacity: opacity == null ? null : AlwaysStoppedAnimation(opacity),
      excludeFromSemantics: true,
      frameBuilder: (context, child, frame, sync) => Padding(
        // Lined up with the headline's first line, not the top of its box.
        padding: EdgeInsets.only(left: gap, top: 3),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ColoredBox(
            color: frame == null
                ? _pictureFill(context, dimmed)
                : Colors.transparent,
            child: fadeInPicture(context, child, frame, sync),
          ),
        ),
      ),
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}

/// The top of the feed, pinned: a slim bar with the date and the settings
/// button, then the nameplate and the filters. Scrolling folds the nameplate
/// and the filters away under the bar, which then shows the app's name small,
/// like an iOS large title, and a hairline over the articles.
class _MastheadDelegate extends SliverPersistentHeaderDelegate {
  _MastheadDelegate({
    required this.masthead,
    required this.background,
    required this.scaler,
    required this.titleHeight,
  });

  final FeedMasthead masthead;
  final Color background;
  final TextScaler scaler;
  final double titleHeight;

  static const _bar = 44.0;

  /// Today's pull-downs: their own 10-pt top margin, a chip up to 38 pt tall
  /// at the masthead's largest text, and a little air.
  static const _chips = 52.0;
  static const _bottom = 4.0;

  @override
  double get minExtent => _bar;

  @override
  double get maxExtent => _bar + titleHeight + _chips + _bottom;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final type = _AType.of(context);
    final mq = MediaQuery.of(context);
    final shrink = shrinkOffset.clamp(0.0, maxExtent - minExtent);
    // The date fades as the nameplate starts to go; the small name appears
    // once the nameplate is under the bar; the hairline once all is folded.
    final dateAlpha = 1 - (shrink / (titleHeight * 0.5)).clamp(0.0, 1.0);
    final nameAlpha = ((shrink - titleHeight * 0.7) / (titleHeight * 0.5))
        .clamp(0.0, 1.0);
    final ruleAlpha = ((shrink - (maxExtent - minExtent) + 12) / 12).clamp(
      0.0,
      1.0,
    );
    return _Snap(
      shrinkOffset: shrinkOffset,
      range: maxExtent - minExtent,
      child: MediaQuery(
        data: mq.copyWith(textScaler: scaler),
        child: ColoredBox(
          color: background,
          child: ClipRect(
            child: Stack(
              children: [
                // The nameplate and the filters, sliding up under the bar.
                Positioned(
                  top: _bar - shrink,
                  left: 0,
                  right: 0,
                  height: titleHeight + _chips,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _margin,
                        ),
                        child: SizedBox(
                          height: titleHeight,
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.bottomLeft,
                            child: Semantics(
                              header: true,
                              child: Text(
                                masthead.title,
                                maxLines: 1,
                                style: type.nameplate,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // One line of pull-downs that scrolls sideways if a long
                      // country or topic name does not fit, so the masthead
                      // keeps its height.
                      SizedBox(
                        height: _chips,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: _margin,
                          ),
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1000),
                              child: masthead.filterBar,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // The bar: date (or the small name) and the settings button.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: _bar,
                  child: ColoredBox(
                    color: background,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (dateAlpha > 0)
                          Positioned(
                            left: _margin,
                            right: 64,
                            child: Text(
                              masthead.date.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: type.dateline.copyWith(
                                color: type.dateline.color!.withValues(
                                  alpha: dateAlpha,
                                ),
                              ),
                            ),
                          ),
                        // Built only once it shows, so the page has one title.
                        if (nameAlpha > 0)
                          ExcludeSemantics(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 64,
                              ),
                              child: Text(
                                masthead.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: type.compactTitle.copyWith(
                                  color: type.ink.withValues(alpha: nameAlpha),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: _margin - 4,
                          child: _SettingsButton(
                            onPressed: masthead.openSettings,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (ruleAlpha > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 0.5,
                    child: ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: ruleAlpha),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_MastheadDelegate old) => true;
}

/// Settles the masthead open or folded when a scroll stops halfway, like an
/// iOS large title, so the nameplate is never left cut by the bar's edge.
class _Snap extends StatefulWidget {
  const _Snap({
    required this.shrinkOffset,
    required this.range,
    required this.child,
  });

  /// How far the masthead is folded now, and how far it folds at most.
  final double shrinkOffset;
  final double range;
  final Widget child;

  @override
  State<_Snap> createState() => _SnapState();
}

class _SnapState extends State<_Snap> {
  ScrollPosition? _position;

  /// Where in the feed's scroll the masthead starts folding: 0, unless the
  /// pull-to-refresh spinner is holding space above it.
  double _start = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position == _position) return;
    _position?.isScrollingNotifier.removeListener(_stopped);
    _position = position?..isScrollingNotifier.addListener(_stopped);
  }

  @override
  void dispose() {
    _position?.isScrollingNotifier.removeListener(_stopped);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    // Only while partly folded does the offset say where the masthead starts.
    if (position != null &&
        position.hasPixels &&
        widget.shrinkOffset > 0 &&
        widget.shrinkOffset < widget.range) {
      _start = position.pixels - widget.shrinkOffset;
    }
    return widget.child;
  }

  void _stopped() {
    final position = _position;
    if (position == null || position.isScrollingNotifier.value) return;
    // Measured from the scroll itself: the last frame of a fling may not
    // have reached this widget yet.
    final folded = position.pixels - _start;
    if (folded <= 0.5 || folded >= widget.range - 0.5) return;
    final fold = _start + widget.range;
    final target = folded < widget.range / 2 || fold > position.maxScrollExtent
        ? _start
        : fold;
    // Not from inside the scroll's own change of state.
    Future.microtask(() {
      if (!mounted || position.isScrollingNotifier.value) return;
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }
}

/// The settings gear in the same grey as the filter pull-downs beside it,
/// with a 44-pt target and its VoiceOver label.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: const Size(44, 44),
    onPressed: onPressed,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        shape: BoxShape.circle,
      ),
      child: Icon(
        CupertinoIcons.gear_alt,
        size: 21,
        color: CupertinoColors.label.resolveFrom(context),
        semanticLabel: AppLocalizations.of(context).settings,
      ),
    ),
  );
}

/// "3 new decisions": a calm capsule in a deeper shade of the brand's red
/// with an arrow, on a 44-pt target, just under the masthead. White on the
/// brand red itself is 3.8:1, too faint for 15-pt text; this red is 5.2:1.
const _pillRed = Color(0xFFD41A35);

class _NewPill extends StatelessWidget {
  const _NewPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).newDecisions(count);
    // The screen floats it just under the masthead, open or folded.
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            // Grows with the text up to twice the size: past that, three
            // words would cover the feed.
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 2,
              child: Builder(
                builder: (context) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: _pillRed,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.arrow_up,
                          size: MediaQuery.textScalerOf(context).scale(15),
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
