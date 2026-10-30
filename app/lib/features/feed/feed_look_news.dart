import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/article.dart';
import '../../core/card_zoom.dart';
import '../../core/countries.dart';
import '../../core/motion.dart';
import '../../core/news_widgets.dart';
import '../../core/read_mark.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'feed_look.dart';
import 'feed_look_now.dart';
import 'feed_pills.dart';
import 'feed_topic_tags.dart';
import 'feed_touches.dart';

/// The two looks after Apple News that Roman picked (26 Oct), in our own
/// colours ([NewsPalette]): a light grey page whose top takes a tint of the
/// colour, a large title with the logo and the date in grey, what the feed
/// shows as pills of Liquid Glass that stay at the top while the rows pass
/// under them (For you, the whole world, the topics: [FeedPills]), and every
/// decision on a white card with a soft shadow of the colour, its picture on
/// the right. Pulled down to refresh, the title
/// and the date grow from the left edge as iOS's large title does, and plain
/// grey words in the gap say what is happening, then how it went
/// ([_PullHint], Roman's pick 1 of `handoff/refresh-patterns.html`, 27 Oct).
/// Liquid Glass for the "N new" pill too. A card grows into its article when
/// opened (#141). Every card alike, as in every look (Yurii, 16 Oct): no
/// bigger first story yet.
class NewsLook extends FeedLook {
  NewsLook(this.palette);

  final NewsPalette palette;

  @override
  Color background(BuildContext context) =>
      _NewsStyle.of(context, palette).page;

  /// The colour's tint at the top of the screen, under the status bar and
  /// the masthead as one piece, fading into the page; fixed while the cards
  /// scroll over it.
  @override
  Gradient? backdrop(BuildContext context) {
    final style = _NewsStyle.of(context, palette);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [style.top, style.page],
      stops: const [0, _tinted],
    );
  }

  /// How far down the screen the tint fades into the page.
  static const _tinted = 0.32;

  /// The pinned glass row is the top edge: rows pass under it, not under a
  /// fade or a folded title.
  @override
  bool get fadesTopEdge => false;

  @override
  Widget refreshIndicator(BuildContext context, FeedPull pull) =>
      _PullHint(style: _NewsStyle.of(context, palette), pull: pull);

  @override
  bool get saysHowRefreshWent => true;

  @override
  Color cardColor(BuildContext context) => _NewsStyle.of(context, palette).card;

  @override
  double get cardRadius => _NewsStyle.radius;

  /// The Top stories title in the look's colour, as the chosen pill (#164).
  @override
  Widget topStoriesHeading(BuildContext context, TopStories block) {
    final style = _NewsStyle.of(context, palette);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: style.gradient.createShader,
              child: Text(
                block.title,
                style: style.title.copyWith(fontSize: 26),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            block.caption,
            style: TextStyle(fontSize: 14, color: style.muted),
          ),
        ],
      ),
    );
  }

  @override
  Widget masthead(BuildContext context, FeedMasthead masthead) {
    final style = _NewsStyle.of(context, palette);
    final scaler = MediaQuery.textScalerOf(context);
    // The title and the date as tall as their letters: they scroll away, the
    // pills stay.
    final titleHeight =
        10 + scaler.scale(32) * 1.08 + scaler.scale(26) * 1.08 + 12;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _NewsHeader(
        titleHeight: titleHeight,
        pillsHeight: FeedPills.heightFor(scaler),
        title: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Stretch(
                      pull: masthead.pull,
                      child: Row(
                        children: [
                          const _Logo(),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              masthead.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: style.title,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Stretch(
                      pull: masthead.pull,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          masthead.date,
                          maxLines: 1,
                          style: style.title.copyWith(
                            fontSize: 26,
                            color: style.muted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              masthead.buttons,
            ],
          ),
        ),
        // What the feed shows stays at the top, glass over the rows.
        pills: FeedPills(
          where: masthead.where,
          topic: masthead.topic,
          topics: masthead.topics,
          onChoose: masthead.onChoose,
          ink: style.ink,
          fill: style.card,
          edge: style.glassEdge,
          shadow: style.softShadow,
          chosen: style.chosen,
          glow: style.glow,
          tint: style.chosenColors.first,
        ),
      ),
    );
  }

  @override
  Widget articles(BuildContext context, FeedList list) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    sliver: SliverList.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final a = list.articles[i];
        list.shown(i);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: list.tile(
            i,
            _Card(
              palette: palette,
              article: a,
              mark: list.markOf(a),
              topics: list.topicsOf(a),
              onTap: () => list.open(i),
            ),
          ),
        );
      },
    ),
  );

  @override
  Widget feedEnd(BuildContext context, FeedEnd end) {
    final style = _NewsStyle.of(context, palette);
    final l10n = AppLocalizations.of(context);
    final meta = TextStyle(fontSize: 15, color: style.muted);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: switch (end.state) {
            FeedEndState.failed => CupertinoButton(
              onPressed: end.retry,
              child: Text(
                l10n.feedLoadMoreFailed,
                textAlign: TextAlign.center,
                style: meta.copyWith(color: style.accent),
              ),
            ),
            FeedEndState.loading => const CupertinoActivityIndicator(),
            FeedEndState.end => Text(l10n.feedEnd, style: meta),
          },
        ),
      ),
    );
  }

  @override
  Widget newPill(
    BuildContext context, {
    required int count,
    required VoidCallback onTap,
  }) {
    final style = _NewsStyle.of(context, palette);
    // Liquid Glass: the feed shows through, blurred, under a tint of the card.
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0x24000000),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: style.card.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: style.glassEdge),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.arrow_up, size: 15, color: style.accent),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context).newDecisions(count),
                    style: TextStyle(
                      color: style.accent,
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
    );
  }
}

/// [NewsLook]'s masthead, pinned: the title and the date scroll away and
/// fade, as an iOS large title does, and the pills stay at the top with
/// nothing behind them, so the rows pass under the glass. The tint behind it
/// all is the look's backdrop, one piece with the status bar's.
class _NewsHeader extends SliverPersistentHeaderDelegate {
  _NewsHeader({
    required this.titleHeight,
    required this.pillsHeight,
    required this.title,
    required this.pills,
  });

  /// As tall as their words at the reader's text size.
  final double titleHeight;
  final double pillsHeight;
  final Widget title;
  final Widget pills;

  @override
  double get minExtent => pillsHeight;

  @override
  double get maxExtent => titleHeight + pillsHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final gone = (shrinkOffset / titleHeight).clamp(0.0, 1.0);
    // The title stays, unseen once gone, so the pills keep their place in
    // the tree: the row keeps how far it was swiped, and the gear's glass
    // is not made again as the title comes back.
    // The chosen pill's glow reaches over the rows under the header, not cut
    // where it ends (Yurii, #210); the title is clipped to its own band.
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: -shrinkOffset,
          height: titleHeight,
          // The buttons' glass casts no shadow (GlassCircle.shadow): cut at
          // the band's foot, it showed as a band under them (Roman, 30 Oct).
          child: ClipRect(
            child: Opacity(opacity: 1 - gone, child: title),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: pillsHeight,
          child: pills,
        ),
      ],
    );
  }

  @override
  bool shouldRebuild(_NewsHeader old) =>
      old.titleHeight != titleHeight ||
      old.pillsHeight != pillsHeight ||
      old.title != title ||
      old.pills != pills;
}

/// What shows in the gap the pull opens above the masthead: plain grey
/// words in its middle, no spinner or ring. "Pull to refresh", "Release to
/// refresh" once the pull has gone far enough, "Refreshing the news…"
/// pulsing softly while the feed loads (steady with Reduce Motion), then how
/// it went with a green tick ("3 new decisions", "No new decisions"),
/// fading as the gap closes.
class _PullHint extends StatefulWidget {
  const _PullHint({required this.style, required this.pull});

  final _NewsStyle style;
  final FeedPull pull;

  @override
  State<_PullHint> createState() => _PullHintState();
}

enum _PullStep { pull, release, loading, done }

class _PullHintState extends State<_PullHint>
    with SingleTickerProviderStateMixin {
  /// The words' pulse while the feed loads: down to a third and back.
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  _PullStep get _step {
    final pull = widget.pull;
    return switch (pull.mode) {
      RefreshIndicatorMode.inactive ||
      RefreshIndicatorMode.drag => _PullStep.pull,
      RefreshIndicatorMode.armed when pull.pulled >= pull.trigger =>
        _PullStep.release,
      _ when pull.result != null => _PullStep.done,
      _ => _PullStep.loading,
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void didUpdateWidget(_PullHint old) {
    super.didUpdateWidget(old);
    _follow();
  }

  /// Pulses while the feed loads; not while the gap closes after a failure.
  void _follow() {
    final loading =
        _step == _PullStep.loading &&
        widget.pull.mode != RefreshIndicatorMode.done;
    if (loading && !Motion.reduced(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating || _pulse.value != 0) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pull = widget.pull;
    final result = pull.result;
    final step = _step;
    final words = switch (step) {
      _PullStep.pull => l10n.feedPullToRefresh,
      _PullStep.release => l10n.feedReleaseToRefresh,
      _PullStep.loading => l10n.feedRefreshing,
      _PullStep.done when result!.wasEmpty => l10n.feedUpdated,
      _PullStep.done when result!.newCount > 0 => l10n.newDecisions(
        result.newCount,
      ),
      _PullStep.done => l10n.feedNoNewDecisions,
    };
    // In as the pull opens the gap, out as the gap closes.
    final shown = switch (pull.mode) {
      RefreshIndicatorMode.inactive ||
      RefreshIndicatorMode.drag => clampDouble((pull.pulled - 18) / 40, 0, 1),
      RefreshIndicatorMode.done => clampDouble(pull.pulled / pull.extent, 0, 1),
      _ => 1.0,
    };
    final hint = Semantics(
      // VoiceOver says how it went.
      liveRegion: step == _PullStep.done,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (step == _PullStep.done) ...[
            Icon(
              CupertinoIcons.checkmark_circle_fill,
              size: 17,
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.systemGreen,
                context,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              words,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
                color: widget.style.muted,
              ),
            ),
          ),
        ],
      ),
    );
    // In the middle of the gap, as tall as its words even while the gap is
    // shorter.
    return OverflowBox(
      maxHeight: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: AnimatedBuilder(
          animation: _pulse,
          child: hint,
          builder: (context, hint) => Opacity(
            opacity:
                shown * (1 - 0.68 * Curves.easeInOut.transform(_pulse.value)),
            child: hint,
          ),
        ),
      ),
    );
  }
}

/// [child] grows from the middle of its left edge while the feed is pulled
/// down past its top, as iOS's large title does, and springs back with the
/// feed (Roman, 27 Oct): 9% bigger where the pull refreshes, at most 1.4
/// times that. Let go there, it shrinks back as the feed settles into the
/// gap held open while it refreshes, and stays its own size meanwhile. It
/// reads how far below its place the masthead is drawn as it paints, after
/// the frame's layout, so it follows the finger in the same frame with
/// nothing rebuilt; [pull] tells it which part of the pull that is.
class _Stretch extends SingleChildRenderObjectWidget {
  const _Stretch({required this.pull, required super.child});

  final ValueListenable<FeedPull?> pull;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderStretch(pull);

  @override
  void updateRenderObject(BuildContext context, _RenderStretch renderObject) =>
      renderObject.pull = pull;
}

class _RenderStretch extends RenderProxyBox {
  _RenderStretch(this._pull);

  ValueListenable<FeedPull?> _pull;
  set pull(ValueListenable<FeedPull?> value) {
    if (identical(value, _pull)) return;
    if (attached) _pull.removeListener(markNeedsPaint);
    _pull = value;
    if (attached) _pull.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _pull.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _pull.removeListener(markNeedsPaint);
    super.detach();
  }

  /// How much bigger for each point of pull, and at most.
  static const _perPoint = 0.09 / 100;
  static const _most = 0.09 * 1.4;

  /// How far below its place the masthead's sliver is drawn: its outermost
  /// one, whose place at rest is the top of the feed.
  double get _below {
    RenderObject? sliver = parent;
    while (sliver != null && sliver is! RenderSliver) {
      sliver = sliver.parent;
    }
    while (sliver?.parent is RenderSliver) {
      sliver = sliver!.parent;
    }
    if (sliver == null) return 0;
    final viewport = RenderAbstractViewport.maybeOf(sliver);
    if (viewport == null) return 0;
    return MatrixUtils.transformPoint(
      sliver.getTransformTo(viewport),
      Offset.zero,
    ).dy;
  }

  /// How much of that is the pull that stretches it: all of it until the
  /// feed refreshes; then none of the gap held open, all of what goes past
  /// the refresh point, and less and less in between, so it never jumps.
  double get _stretch {
    final below = _below;
    final pull = _pull.value;
    if (below <= 0 || pull == null) return math.max(below, 0);
    final gap = pull.extent;
    final held = switch (pull.mode) {
      RefreshIndicatorMode.inactive || RefreshIndicatorMode.drag => 0.0,
      _ => gap * (1 - clampDouble((below - gap) / (pull.trigger - gap), 0, 1)),
    };
    return math.max(0, below - held);
  }

  Matrix4 get _transform {
    final scale = 1 + clampDouble(_stretch * _perPoint, 0, _most);
    return Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(0, size.height / 2 * (1 - scale), 0);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final transform = _transform;
    if (transform.isIdentity()) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: layer as TransformLayer?,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_transform);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintTransform(
        transform: _transform,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );
}

/// The two colours of [NewsLook]: garnet, a red of our own, deeper than
/// Apple's; and seal, the green of an official seal.
enum NewsPalette { garnet, seal }

/// The app's logo before its name (Yurii, 29 Oct: our logo in place of the
/// seal): the black N on the light page, the red N on the black one, where
/// the black would vanish. Decorative: the name next to it is what VoiceOver
/// reads.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Image(
      key: const ValueKey('masthead-logo'),
      image: AssetImage(
        Theme.of(context).brightness == Brightness.dark
            ? 'assets/logo_n_dark.png'
            : 'assets/logo_n.png',
      ),
      width: 30,
      height: 30,
    ),
  );
}

/// One decision on a white card: where it comes from with the official
/// seal, the headline, when and its topics; its picture on the right.
/// Drawn as its article's top ([ZoomSource.isArticleTop]), it has no shadow:
/// the card has become the page.
class _Card extends StatelessWidget {
  const _Card({
    required this.palette,
    required this.article,
    required this.mark,
    required this.topics,
    required this.onTap,
  });

  final NewsPalette palette;
  final Article article;

  /// Opened or not, and how that shows ([ReadStyle]): fainter in Dim, or the
  /// unread dot between the country and the institution in the dot styles.
  final ReadMark mark;

  /// The topic tags, in order ([FeedList.topicsOf]).
  final List<String> topics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _NewsStyle.of(context, palette);
    final l10n = AppLocalizations.of(context);
    final read = mark.dimmed;
    final time = feedTime(article, l10n);
    final url = article.imageUrl;
    final grey = Theme.of(context).colorScheme.onSurfaceVariant;
    final source = dim(style.source, read);
    final meta = TextStyle(fontSize: 14, color: style.muted);
    final timeText = !read && isFresh(article)
        ? FreshTime(
            time,
            articleId: article.id,
            style: meta.copyWith(fontWeight: FontWeight.w600),
            color: style.accent,
          )
        : Text(time, style: meta);
    return Semantics(
      container: true,
      button: true,
      label: _spoken(context, article, topics),
      value: mark.unread ? l10n.feedUnread : null,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: style.card,
            borderRadius: BorderRadius.circular(_NewsStyle.radius),
            boxShadow: ZoomSource.isArticleTop(context)
                ? null
                : style.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // The dot takes the official seal's place; an
                              // event (#230) is not official, so it has none.
                              if (!mark.dots && !article.isEvent) ...[
                                Icon(
                                  CupertinoIcons.checkmark_seal_fill,
                                  size: 15,
                                  color: style.accent,
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: placeName(article, l10n),
                                        style: source,
                                      ),
                                      // In the dot styles the unread dot stands
                                      // between the two, a small grey dot once
                                      // read, so the institution never moves.
                                      if (mark.dots)
                                        unreadDotSpan(
                                          context,
                                          mark,
                                          fontSize: style.source.fontSize!,
                                          scaler: MediaQuery.textScalerOf(
                                            context,
                                          ),
                                          separator: grey,
                                        )
                                      else
                                        TextSpan(text: ' · ', style: source),
                                      TextSpan(
                                        text: article.source.name,
                                        style: source,
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text(
                            article.headline,
                            style: dim(style.headline(context), read),
                          ),
                          const SizedBox(height: 8),
                          timeText,
                        ],
                      ),
                    ),
                    if (url != null) ...[
                      const SizedBox(width: 12),
                      FeedPicture(
                        url: url,
                        width: 92,
                        height: 92,
                        radius: 14,
                        dimmed: read,
                      ),
                    ],
                  ],
                ),
                // The topics last, across the whole card, under the picture
                // too: three long names take two lines at most. Grey, faded
                // once read in Dim.
                if (topics.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  TopicTags(
                    topics,
                    color: dim(TextStyle(color: grey), read).color!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What VoiceOver reads for a card, once: the headline first, then where it
/// comes from, its topics and when ("Unread" is the card's value).
String _spoken(BuildContext context, Article a, List<String> topics) {
  final l10n = AppLocalizations.of(context);
  // One sentence each; a text that already ends in a full stop keeps one.
  String sentence(String s) => RegExp(r'[.!?…]$').hasMatch(s) ? s : '$s.';
  return [
    a.headline,
    '${placeName(a, l10n)}, ${a.source.name}',
    ?spokenTopics(topics, l10n),
    feedTime(a, l10n),
  ].map(sentence).join(' ');
}

/// [NewsLook]'s colours and type, light or dark.
class _NewsStyle {
  _NewsStyle._(this.dark, this.accent, this.accent2, this.chosenColors)
    : page = dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      card = dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF),
      ink = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      muted = dark ? const Color(0xFF98989F) : const Color(0xFF8A8A8E);

  factory _NewsStyle.of(BuildContext context, NewsPalette palette) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (palette) {
      NewsPalette.garnet => _NewsStyle._(
        dark,
        dark ? const Color(0xFFFF5A72) : const Color(0xFFC41230),
        dark ? const Color(0xFFFF8A9C) : const Color(0xFFE4566E),
        const [Color(0xFFC41230), Color(0xFF9E0E27)],
      ),
      NewsPalette.seal => _NewsStyle._(
        dark,
        dark ? const Color(0xFF3DD4A3) : const Color(0xFF0E7A5E),
        dark ? const Color(0xFF7BE6C2) : const Color(0xFF2DB88D),
        const [Color(0xFF0E7A5E), Color(0xFF0A5C47)],
      ),
    };
  }

  static const radius = 24.0;

  final bool dark;

  /// The look's colour, and the lighter end of its gradient.
  final Color accent;
  final Color accent2;

  /// The chosen pill's colour, deepening, the same in both themes, so its
  /// white words read: at least 5.3:1 (Yurii, #210; Roman's pick A of
  /// `handoff/chosen-pill-contrast.html`).
  final List<Color> chosenColors;

  LinearGradient get chosen => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: chosenColors,
  );

  final Color page;
  final Color card;
  final Color ink;
  final Color muted;

  /// The page's top: a tint of the colour over it.
  Color get top =>
      Color.alphaBlend(accent.withValues(alpha: dark ? 0.2 : 0.1), page);

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  /// The glow under what is filled with the colour.
  Color get glow => accent.withValues(alpha: dark ? 0.35 : 0.3);

  /// The edge of Liquid Glass.
  Color get glassEdge =>
      dark ? const Color(0x24FFFFFF) : const Color(0x8CFFFFFF);

  /// A card's shadow: close and grey, then wide in a tint of the colour.
  List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: dark ? const Color(0x00000000) : const Color(0x0D000000),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: accent.withValues(alpha: dark ? 0.16 : 0.18),
      blurRadius: 34,
      spreadRadius: -10,
      offset: const Offset(0, 16),
    ),
  ];

  /// The pills' shadow, lighter.
  List<BoxShadow> get softShadow => [
    BoxShadow(
      color: dark ? const Color(0x00000000) : const Color(0x0D000000),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: accent.withValues(alpha: dark ? 0.1 : 0.12),
      blurRadius: 18,
      spreadRadius: -6,
      offset: const Offset(0, 8),
    ),
  ];

  TextStyle get title => TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -1,
    height: 1.08,
    color: ink,
  );

  TextStyle get source =>
      TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink);

  /// The headline, in the system's sans, in the weight chosen in Settings.
  TextStyle headline(BuildContext context) => TextStyle(
    fontSize: 18,
    height: 1.22,
    letterSpacing: -0.3,
    fontWeight: NewsText.from(context).headline.fontWeight,
    color: ink,
  );
}
