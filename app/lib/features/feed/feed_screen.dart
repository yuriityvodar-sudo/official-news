import 'dart:async';
import 'dart:math' show max, min;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/analytics.dart';
import '../../core/card_zoom.dart';
import '../../core/countries.dart';
import '../../core/glass.dart';
import '../../core/article.dart';
import '../../core/feed_language.dart';
import '../../core/filters.dart';
import '../../core/motion.dart';
import '../../core/news_widgets.dart';
import '../../core/pictures.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../detail/detail_screen.dart';
import '../settings/settings_screen.dart';
import 'feed_controller.dart';
import 'feed_filters.dart';
import 'feed_look.dart';
import 'feed_skeleton.dart';
import 'feed_touches.dart';

/// Item 3: the feed (docs/design/mvp.png). One list of decisions in the order
/// they arrived, with no sections (Yurii, 16 Oct: the server's top stories are
/// in it with the rest); opens instantly from the feed saved on the phone.
/// What it does lives here; how it looks is a [FeedLook] (#66):
/// `feed_look_now.dart` is today's, and Settings → Design switches to the
/// options Yurii compared.
class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    this.controller,
    this.newCheckEvery = const Duration(minutes: 5),
  });

  /// Injected in tests; the app creates its own.
  final FeedController? controller;
  final Duration newCheckEvery;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  /// The masthead's sliver, wherever it is on screen: all of it at the top
  /// of the feed, a pinned bar once folded, nothing once a masthead that
  /// scrolls has gone. The "N new" pill floats just under it, so it never
  /// covers the name or the filters, in any look.
  final _masthead = _MastheadLink();

  late final FeedController _feed = widget.controller ?? FeedController();
  final _scroll = ScrollController();
  Timer? _newCheck;

  /// Analytics (#60): the deepest row shown this visit, and whether the
  /// feed's first page failed last time it changed.
  int _deepest = 0;
  bool _failed = false;

  /// The feed has just gone from nothing to articles: its first rows arrive
  /// one after another for a moment (#141). Rows built after that (scrolled
  /// away and back) come in still.
  bool _arriving = false;
  bool _wasEmpty = true;
  Timer? _arrivalEnd;
  static const _arrival = Duration(milliseconds: 700);

  /// Decisions that have just come in at the top (a refresh, the "N new"
  /// pill): they spring in and push the others down (#141), for a moment.
  Set<String> _entering = const {};
  Set<String> _shownIds = const {};
  Timer? _enteringEnd;

  /// At most this many spring in: about a screen.
  static const _enteringRows = 6;

  @override
  void initState() {
    super.initState();
    _feed.addListener(_changed);
    feedDesign.addListener(_designChanged);
    readStyle.addListener(_designChanged);
    topicTagCount.addListener(_designChanged);
    _scroll.addListener(_nearEnd);
    unawaited(_feed.start());
    _newCheck = Timer.periodic(widget.newCheckEvery, (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_feed.checkForNew());
      }
    });
  }

  @override
  void dispose() {
    _newCheck?.cancel();
    _arrivalEnd?.cancel();
    _enteringEnd?.cancel();
    _feed.removeListener(_changed);
    feedDesign.removeListener(_designChanged);
    readStyle.removeListener(_designChanged);
    topicTagCount.removeListener(_designChanged);
    if (widget.controller == null) _feed.dispose();
    _scroll.dispose();
    _masthead.dispose();
    super.dispose();
  }

  /// Another look, chosen in Settings → Design (#66), or another way to show
  /// read articles or number of topic tags (a build's `--dart-define`): the
  /// feed redraws in it.
  void _designChanged() => setState(() {});

  void _changed() {
    final failed = _feed.error != null;
    if (failed && !_failed) unawaited(analytics.feedFailed());
    _failed = failed;
    final empty = _feed.feed.isEmpty;
    if (_wasEmpty && !empty) {
      _arriving = true;
      _arrivalEnd?.cancel();
      _arrivalEnd = Timer(_arrival, () {
        if (mounted) setState(() => _arriving = false);
      });
    }
    _wasEmpty = empty;
    _springIn();
    _readAtStart();
    setState(() {});
    // A page dropped because a refresh replaced the feed leaves the list at its end:
    // look again once the new feed is drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _nearEnd();
        _scrollAtStart();
      }
    });
  }

  /// The decisions above the first one shown before: new at the top. A feed
  /// that is all new (another filter, another language) arrives as a feed
  /// that has just loaded instead.
  void _springIn() {
    final ids = [for (final article in _feed.feed) article.id];
    final fresh = ids.takeWhile((id) => !_shownIds.contains(id)).toList();
    if (_shownIds.isNotEmpty && fresh.isNotEmpty && fresh.length < ids.length) {
      _entering = fresh.take(_enteringRows).toSet();
      _enteringEnd?.cancel();
      _enteringEnd = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _entering = const {});
      });
    }
    _shownIds = ids.toSet();
  }

  /// For screenshots (#66): a script cannot scroll the simulator, so a build with
  /// `--dart-define=FEED_SCROLL=1400` opens the feed that many points down once
  /// it has articles, for screenshots further down the list. 0 (the default)
  /// does nothing.
  static const _startScroll = int.fromEnvironment('FEED_SCROLL');
  bool _scrolledAtStart = false;
  void _scrollAtStart() {
    if (_startScroll <= 0 || _scrolledAtStart || _feed.feed.isEmpty) return;
    _scrolledAtStart = true;
    _scroll.jumpTo(
      min(_startScroll.toDouble(), _scroll.position.maxScrollExtent),
    );
  }

  /// For screenshots only: a script cannot tap the simulator, so a
  /// debug build with `--dart-define=READ_DEMO=2` shows the first 2 articles
  /// of the feed as read, once the feed has articles.
  /// Kept in memory only, never saved; ignored by release builds.
  static const _readDemo = int.fromEnvironment('READ_DEMO');
  bool _readDemoDone = false;
  void _readAtStart() {
    if (!kDebugMode || _readDemo <= 0 || _readDemoDone) return;
    if (_feed.feed.isEmpty) return;
    _readDemoDone = true;
    _feed.readIds.addAll(_feed.feed.take(_readDemo).map((a) => a.id));
  }

  void _nearEnd() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
      unawaited(_feed.loadMore());
    }
  }

  /// The "N new" pill: to the top first, then the new decisions spring in
  /// there, in view (#141).
  Future<void> _showNew() async {
    Haptics.light();
    await _toTopSmoothly();
    await _feed.refresh();
  }

  Future<void> _toTopSmoothly() async {
    if (!_scroll.hasClients || _scroll.offset <= 0) return;
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _open(
    Article article, {
    required String section,
    required int position,
  }) {
    unawaited(
      analytics.articleOpened(article, section: section, position: position),
    );
    unawaited(_feed.markRead(article));
    Haptics.light();
    // The article's picture, decoded for its screen while the card grows
    // into the article (#141), so it is sharp when it is there.
    final url = article.imageUrl;
    if (url != null) {
      unawaited(
        precacheImage(screenPicture(context, url), context, onError: (_, _) {}),
      );
    }
    // The article grows out of its card (#141); with Reduce Motion on, or a
    // card not on screen, it opens as before. The article as the feed has
    // it, so a translated one opens translated.
    final card = Motion.reduced(context) ? null : ZoomSource.rectOf(article.id);
    final top = card == null ? null : ZoomSource.cardOf(article.id);
    if (card == null || top == null) {
      Navigator.of(context).pushNamed(Routes.detail, arguments: article);
      return;
    }
    final look = lookFor(feedDesign.value);
    final color = look.cardColor(context);
    Navigator.of(context).push(
      CardZoomRoute<void>(
        from: card,
        background: color,
        radius: look.cardRadius,
        sourceId: article.id,
        settings: RouteSettings(name: Routes.detail, arguments: article),
        // The card itself is the article's top, where it is in the feed.
        builder: (_) => DetailScreen(
          article: article,
          top: top,
          topFrom: card,
          background: color,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      CupertinoPageRoute(
        settings: const RouteSettings(name: '/settings'),
        builder: (_) => SettingsScreen(
          language: _feed.languageChanges,
          onLanguage: _chooseLanguage,
          saveDesign: _feed.saveDesign,
          saveHeadlineWeight: _feed.saveHeadlineWeight,
        ),
      ),
    );
  }

  /// The first time this visit a row at a depth of [feedDepths] is drawn.
  void _shownRow(int row) {
    if (row <= _deepest) return;
    for (final depth in feedDepths) {
      if (_deepest < depth && row >= depth) {
        unawaited(analytics.feedDepth(depth));
      }
    }
    _deepest = row;
  }

  /// A language picked in Settings: another language is another feed, from the
  /// top, and the app's words change with it (#52). The one already shown is
  /// saved too, so the app stops following the phone, but is no new choice to
  /// count or reload.
  Future<void> _chooseLanguage(FeedLanguage chosen) async {
    if (chosen != _feed.language) {
      unawaited(analytics.languageChosen(chosen, from: _feed.language));
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    await _feed.setLanguage(chosen);
  }

  /// For you, the whole world or one topic from the menu (#170): another
  /// feed, from the top.
  Future<void> _chooseFeed(FeedWhere where, String? topic) async {
    if (where != _feed.where || topic != _feed.topic) {
      Haptics.selection();
      _toTop();
    }
    await _feed.setFeed(where, topic: topic);
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final look = lookFor(feedDesign.value);
    final base = Theme.of(context);
    final themed = look.theme(context, base);
    if (identical(themed, base)) return _page(context, look);
    return Theme(
      data: themed,
      child: Builder(builder: (context) => _page(context, look)),
    );
  }

  Widget _page(BuildContext context, FeedLook look) {
    final l10n = AppLocalizations.of(context);
    final foldedTitle = look.foldedTitle(context, 'Outer News');
    return Scaffold(
      backgroundColor: look.background(context),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // Pull to refresh works in every state, including error and empty.
                // It taps back itself as the pull passes the refresh point.
                CupertinoSliverRefreshControl(onRefresh: _feed.refresh),
                _MastheadEdge(
                  link: _masthead,
                  sliver: look.masthead(
                    context,
                    FeedMasthead(
                      // The app's name, the same in every language.
                      title: 'Outer News',
                      date: longDay(DateTime.now(), l10n),
                      openSettings: _openSettings,
                      filterBar: FeedFilterBar(
                        where: _feed.where,
                        topic: _feed.topic,
                        topics: _feed.topics,
                        onChoose: _chooseFeed,
                      ),
                    ),
                  ),
                ),
                ..._content(context, look),
              ],
            ),
            // Rows fade softly at the top edge once the feed is scrolled, and
            // the app's name folds into a small title there (#141).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopFade(
                scroll: _scroll,
                color: look.background(context),
                title: foldedTitle,
                onTitleTap: () => unawaited(_toTopSmoothly()),
              ),
            ),
            if (_feed.newCount > 0)
              Positioned.fill(
                child: _UnderMasthead(
                  masthead: _masthead,
                  scroll: _scroll,
                  // Under the folded title, where there is one.
                  top: foldedTitle == null ? _pillTop : _TopFade.bar + 8,
                  gap: _pillGap,
                  child: _SlideIn(
                    child: look.newPill(
                      context,
                      count: _feed.newCount,
                      onTap: _showNew,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The "N new" pill's place: [_pillGap] under the masthead, and never
  /// higher than [_pillTop] from the top of the safe area (where it floats
  /// once the masthead has scrolled away).
  static const _pillTop = 12.0;
  static const _pillGap = 8.0;

  List<Widget> _content(BuildContext context, FeedLook look) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    if (_feed.feed.isEmpty) {
      // Grey rows in the shape of the feed's while it loads (#141).
      if (_feed.loading) return const [FeedSkeleton()];
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _feed.error != null
                // Offline or the server failed: say so, with a way to try again (#141).
                ? FeedMessage(
                    icon: CupertinoIcons.wifi_slash,
                    action: l10n.tryAgain,
                    onAction: () => unawaited(_feed.refresh()),
                    children: [Text(l10n.feedLoadFailed, style: text.meta)],
                  )
                : _feed.filtered
                ? _filteredEmpty(context)
                : _feed.language == FeedLanguage.en
                ? FeedMessage(
                    icon: CupertinoIcons.news,
                    children: [Text(l10n.feedEmpty, style: text.meta)],
                  )
                // The server lists only finished translations; they come in over the day.
                : FeedMessage(
                    icon: CupertinoIcons.globe,
                    children: [
                      Text(
                        l10n.feedNoTranslations,
                        style: text.meta.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(l10n.feedTranslationsComing, style: text.meta),
                    ],
                  ),
          ),
        ),
      ];
    }

    // The Top stories block, then one list without its decisions (#164); the
    // server has applied the filters (#67, #68). In For you they are the
    // reader's country's top stories (#170).
    final block = _feed.topStories;
    final forYou = _feed.where.isForYou && _feed.topic == null
        ? _feed.homeCountry
        : null;
    final shown = _feed.feed;
    final slivers = <Widget>[];

    if (_feed.error != null) {
      slivers.add(_padded(Text(l10n.feedRefreshFailed, style: text.meta)));
    }
    // Analytics (#60) record each opened article's section ("top" for the
    // block, "feed" for the list) and place in it, and how deep the list was
    // drawn.
    if (block.isNotEmpty) {
      slivers.add(
        look.topStories(
          context,
          TopStories(
            title: forYou != null
                ? l10n.topStoriesForYouTitle
                : l10n.topStoriesTitle,
            caption: forYou != null
                ? _forYouCaption(l10n, forYou)
                : l10n.topStoriesCaption,
            list: FeedList(
              articles: block,
              readIds: _feed.readIds,
              readStyle: readStyle.value,
              open: (i) => _open(block[i], section: 'top', position: i),
              actions: (i) => showArticleActions(context, block[i]),
              shown: (i) => _shownRow(i + 1),
              topic: _feed.topic,
              maxTopics: topicTagCount.value,
              arriving: _arriving,
              entering: _entering,
            ),
          ),
        ),
      );
    }
    if (shown.isNotEmpty) {
      slivers.add(
        look.articles(
          context,
          FeedList(
            articles: shown,
            readIds: _feed.readIds,
            readStyle: readStyle.value,
            open: (i) => _open(shown[i], section: 'feed', position: i),
            actions: (i) => showArticleActions(context, shown[i]),
            // The depth counts the block's rows too.
            shown: (i) => _shownRow(block.length + i + 1),
            topic: _feed.topic,
            maxTopics: topicTagCount.value,
            arriving: _arriving,
            entering: _entering,
          ),
        ),
      );
    }

    slivers.add(
      look.feedEnd(
        context,
        FeedEnd(
          state: _feed.loadMoreFailed
              ? FeedEndState.failed
              : _feed.loadingMore || _feed.hasMore
              ? FeedEndState.loading
              : FeedEndState.end,
          retry: () => unawaited(_feed.loadMore(retry: true)),
        ),
      ),
    );
    return slivers;
  }

  Widget _padded(Widget child) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverToBoxAdapter(child: child),
  );

  /// What picked For you's top stories (#170): "Czechia · European Union ·
  /// the world's top stories", the European Union for its members only; a
  /// country the app has no name for is "Your country".
  String _forYouCaption(AppLocalizations l10n, String home) {
    final name = countryName(home, l10n);
    return [
      name == home ? l10n.yourCountry : name,
      if (euMembers.contains(home)) l10n.countryEU,
      l10n.topStoriesForYouWorld,
    ].join(' · ');
  }

  /// A filtered feed with nothing in it (#67, #68): says so, with a way back
  /// to all countries and to all topics, whichever narrows it. A group is a
  /// fixed choice, so it can be empty too.
  Widget _filteredEmpty(BuildContext context) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    Widget undo(String label, VoidCallback onPressed) => CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: Text(
        label,
        // The filters' red: these buttons undo a filter.
        style: text.meta.copyWith(
          color: filterRed.resolveFrom(context),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return FeedMessage(
      icon: CupertinoIcons.line_horizontal_3_decrease_circle,
      children: [
        Text(l10n.filterEmpty, style: text.meta),
        const SizedBox(height: 4),
        if (!_feed.where.isAll && !_feed.where.isForYou)
          undo(
            l10n.filterShowAllCountries,
            () => _chooseFeed(FeedWhere.all, _feed.topic),
          ),
        if (_feed.topic != null)
          undo(l10n.filterShowAllTopics, () => _chooseFeed(_feed.where, null)),
      ],
    );
  }
}

/// The top edge of the feed (#141): the feed's colour fading out downwards,
/// shown as soon as the list is scrolled, so rows soften under the status
/// bar instead of being cut, as iOS 26's scroll edges do. Once the masthead's
/// big title has scrolled away, [title] fades in there, small, as iOS folds
/// a large title into its bar; a tap on it goes back to the top.
class _TopFade extends StatelessWidget {
  const _TopFade({
    required this.scroll,
    required this.color,
    required this.title,
    required this.onTitleTap,
  });

  final ScrollController scroll;
  final Color color;
  final Widget? title;
  final VoidCallback onTitleTap;

  /// The folded title's bar.
  static const bar = 44.0;

  /// Scrolled this far, the big title is going: the small one starts to
  /// show, and is all there [_foldOver] further down.
  static const _foldFrom = 40.0;
  static const _foldOver = 36.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: scroll,
    builder: (context, _) {
      final offset = scroll.hasClients ? scroll.offset : 0.0;
      final folded = title == null
          ? 0.0
          : ((offset - _foldFrom) / _foldOver).clamp(0.0, 1.0);
      final rise = Motion.reduced(context) ? 0.0 : (1 - folded) * 6;
      return Stack(
        children: [
          Opacity(
            opacity: (offset / 24).clamp(0.0, 1.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Behind the small title, rows do not show through.
                IgnorePointer(
                  child: ColoredBox(
                    color: color,
                    child: SizedBox(
                      height: bar * folded,
                      width: double.infinity,
                    ),
                  ),
                ),
                ScrollEdgeFade(height: 20, color: color),
              ],
            ),
          ),
          // Not there at all while the big title is.
          if (folded > 0)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: bar,
              child: IgnorePointer(
                ignoring: folded < 1,
                // The masthead says it already: VoiceOver reads the list.
                child: ExcludeSemantics(
                  child: GestureDetector(
                    onTap: onTitleTap,
                    child: Opacity(
                      opacity: folded,
                      child: Transform.translate(
                        offset: Offset(0, rise),
                        child: Center(child: title),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// The "N new" pill arriving (#141): it slides down a little and settles
/// with a spring; with Reduce Motion on, it only fades in.
class _SlideIn extends StatelessWidget {
  const _SlideIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.slow,
      curve: reduced ? Motion.ease : Motion.spring,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, reduced ? 0 : (1 - t) * -16),
          child: child,
        ),
      ),
    );
  }
}

/// Where the masthead's sliver is, for the "N new" pill: [_MastheadEdge]
/// registers its render object here and tells each time it is laid out
/// (scrolling, folding, pull to refresh, a new size), so the pill moves in
/// the same frame as the masthead, never a frame behind it.
class _MastheadLink extends ChangeNotifier {
  _RenderMastheadEdge? _edge;

  /// Where the masthead ends on screen, in [box]'s coordinates: 0 once it
  /// has scrolled away, or before it is laid out. Read while painting, when
  /// this frame's layout is done.
  double bottomIn(RenderBox box) {
    final edge = _edge;
    if (edge == null || !edge.attached || !box.attached) return 0;
    final shown = edge.geometry?.paintExtent ?? 0;
    if (shown <= 0) return 0;
    return MatrixUtils.transformPoint(
      edge.getTransformTo(box),
      Offset(0, shown),
    ).dy;
  }

  void _laidOut() => notifyListeners();
}

/// The masthead's sliver, any look's, registered with a [_MastheadLink].
class _MastheadEdge extends SingleChildRenderObjectWidget {
  const _MastheadEdge({required this.link, required Widget sliver})
    : super(child: sliver);

  final _MastheadLink link;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMastheadEdge(link);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMastheadEdge renderObject,
  ) => renderObject.link = link;
}

class _RenderMastheadEdge extends RenderProxySliver {
  _RenderMastheadEdge(this._link);

  _MastheadLink _link;
  set link(_MastheadLink value) {
    if (identical(value, _link)) return;
    if (identical(_link._edge, this)) _link._edge = null;
    _link = value;
    if (attached) _link._edge = this;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _link._edge = this;
  }

  @override
  void detach() {
    if (identical(_link._edge, this)) _link._edge = null;
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    // Only marks the pill to be painted again: allowed during layout.
    _link._laidOut();
  }
}

/// Places [child] (the "N new" pill) across the middle, [gap] under where
/// the masthead ends on screen and never higher than [top]. The place is
/// worked out while painting, after this frame's layout, so the pill moves
/// with the masthead in the same frame; taps beside the pill reach the feed.
class _UnderMasthead extends SingleChildRenderObjectWidget {
  const _UnderMasthead({
    required this.masthead,
    required this.scroll,
    required this.top,
    required this.gap,
    required Widget super.child,
  });

  final _MastheadLink masthead;
  final Listenable scroll;
  final double top;
  final double gap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderUnderMasthead(masthead, scroll, top, gap);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderUnderMasthead renderObject,
  ) => renderObject
    ..masthead = masthead
    ..scroll = scroll
    ..top = top
    ..gap = gap;
}

class _RenderUnderMasthead extends RenderShiftedBox {
  _RenderUnderMasthead(this._masthead, this._scroll, this._top, this._gap)
    : super(null);

  _MastheadLink _masthead;
  set masthead(_MastheadLink value) {
    if (identical(value, _masthead)) return;
    if (attached) _masthead.removeListener(markNeedsPaint);
    _masthead = value;
    if (attached) _masthead.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  /// The list's scrolling: the pill is painted again as it scrolls, as well
  /// as each time the masthead is laid out.
  Listenable _scroll;
  set scroll(Listenable value) {
    if (identical(value, _scroll)) return;
    if (attached) _scroll.removeListener(markNeedsPaint);
    _scroll = value;
    if (attached) _scroll.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _top;
  set top(double value) {
    if (value == _top) return;
    _top = value;
    markNeedsPaint();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _masthead.addListener(markNeedsPaint);
    _scroll.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _masthead.removeListener(markNeedsPaint);
    _scroll.removeListener(markNeedsPaint);
    super.detach();
  }

  // Its own layer: moving the pill repaints only the pill.
  @override
  bool get isRepaintBoundary => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    // As small as the pill looks, as high as it likes (as under a Positioned
    // with only a top): taps beside it reach the feed.
    child?.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    (child.parentData! as BoxParentData).offset = Offset(
      (size.width - child.size.width) / 2,
      max(_top, _masthead.bottomIn(this) + _gap),
    );
    super.paint(context, offset);
  }

  @override
  bool hitTestSelf(Offset position) => false;
}
