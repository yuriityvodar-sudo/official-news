import 'dart:async';
import 'dart:math' show max, min;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../core/analytics.dart';
import '../../core/article.dart';
import '../../core/feed_language.dart';
import '../../core/news_widgets.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../settings/settings_screen.dart';
import 'feed_controller.dart';
import 'feed_filters.dart';
import 'feed_look.dart';

/// Item 3: the feed (docs/design/mvp.png). Top stories, then the latest
/// decisions in the order they arrived; opens instantly from the feed saved on
/// the phone. What it does lives here; how it looks is a [FeedLook] (#66,
/// prototype): `feed_look_now.dart` is today's.
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
  // PROTOTYPE filters (#67, #68). A build with
  // `--dart-define=FILTER_DEMO=GB:economy` starts with them chosen, for
  // screenshots ([demoFilters]).
  static final _demo = demoFilters(const String.fromEnvironment('FILTER_DEMO'));
  FeedPlace _place = _demo.place;
  String? _topic = _demo.topic;

  bool _shown(Article a) =>
      _place.includes(a) && (_topic == null || a.topics.contains(_topic));

  /// Where the masthead ends on screen now, in points from the top of the
  /// safe area: all of it at the top of the feed, a pinned bar once folded,
  /// 0 once a masthead that scrolls has gone. The "N new" pill floats just
  /// under it, so it never covers the name or the filters, in any look.
  final _mastheadBottom = ValueNotifier<double>(0);

  late final FeedController _feed = widget.controller ?? FeedController();
  final _scroll = ScrollController();
  Timer? _newCheck;

  /// Analytics (#60): the deepest Latest row shown this visit, and whether the
  /// feed's first page failed last time it changed.
  int _deepest = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _feed.addListener(_changed);
    feedDesign.addListener(_designChanged);
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
    _feed.removeListener(_changed);
    feedDesign.removeListener(_designChanged);
    if (widget.controller == null) _feed.dispose();
    _scroll.dispose();
    _mastheadBottom.dispose();
    super.dispose();
  }

  /// Another look chosen in Settings (#66, prototype): the feed redraws in it.
  void _designChanged() => setState(() {});

  void _changed() {
    final failed = _feed.error != null;
    if (failed && !_failed) unawaited(analytics.feedFailed());
    _failed = failed;
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

  /// PROTOTYPE (#66): a script cannot scroll the simulator, so a build with
  /// `--dart-define=FEED_SCROLL=1400` opens the feed that many points down once
  /// it has articles, for screenshots of the Latest list. 0 (the default) does nothing.
  static const _startScroll = int.fromEnvironment('FEED_SCROLL');
  bool _scrolledAtStart = false;
  void _scrollAtStart() {
    if (_startScroll <= 0 || _scrolledAtStart || _feed.items.isEmpty) return;
    _scrolledAtStart = true;
    _scroll.jumpTo(
      min(_startScroll.toDouble(), _scroll.position.maxScrollExtent),
    );
  }

  void _nearEnd() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
      unawaited(_feed.loadMore());
    }
  }

  Future<void> _showNew() async {
    await _feed.refresh();
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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
    // The article as the feed has it, so a translated one opens translated.
    Navigator.of(context).pushNamed(Routes.detail, arguments: article);
  }

  void _openSettings() {
    Navigator.of(context).push(
      CupertinoPageRoute(
        settings: const RouteSettings(name: '/settings'),
        builder: (_) => SettingsScreen(
          language: _feed.languageChanges,
          onLanguage: _chooseLanguage,
        ),
      ),
    );
  }

  /// The first time this visit a Latest row at a depth of [feedDepths] is drawn.
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
                CupertinoSliverRefreshControl(onRefresh: _feed.refresh),
                _MastheadEdge(
                  onBottom: (bottom) => _mastheadBottom.value = bottom,
                  sliver: look.masthead(
                    context,
                    FeedMasthead(
                      // The app's name, the same in every language.
                      title: 'Official News',
                      date: longDay(DateTime.now(), l10n),
                      openSettings: _openSettings,
                      filters: FeedFilters(
                        place: _place,
                        countries: _countries(),
                        topic: _topic,
                        topicCounts: _topicCounts(),
                        onPlace: (p) => setState(() => _place = p),
                        onTopic: (t) => setState(() => _topic = t),
                      ),
                    ),
                  ),
                ),
                ..._content(context, look),
              ],
            ),
            if (_feed.newCount > 0)
              ValueListenableBuilder<double>(
                valueListenable: _mastheadBottom,
                builder: (context, bottom, pill) => Positioned(
                  top: max(_pillTop, bottom + _pillGap),
                  left: 0,
                  right: 0,
                  child: pill!,
                ),
                child: Center(
                  child: look.newPill(
                    context,
                    count: _feed.newCount,
                    onTap: _showNew,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The "N new" pill's place: [_pillGap] under the masthead, and never
  /// higher than [_pillTop] from the top of the safe area (where it floated
  /// before, once the masthead has scrolled away).
  static const _pillTop = 12.0;
  static const _pillGap = 8.0;

  /// The countries with articles in the loaded feed.
  Set<String> _countries() => {
    for (final a in [..._feed.top, ..._feed.items]) a.country,
  };

  /// Topics in the feed under the current Where choice, busiest first.
  List<MapEntry<String, int>> _topicCounts() {
    final counts = <String, int>{};
    final seen = <String>{};
    for (final a in [..._feed.top, ..._feed.items]) {
      if (!seen.add(a.id)) continue;
      if (!_place.includes(a)) continue;
      for (final t in a.topics) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return counts.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
  }

  List<Widget> _content(BuildContext context, FeedLook look) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    if (_feed.items.isEmpty && _feed.top.isEmpty) {
      if (_feed.loading) {
        return const [
          SliverFillRemaining(
            child: Center(child: CupertinoActivityIndicator()),
          ),
        ];
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _feed.error != null
                ? Text(l10n.feedLoadFailed, style: text.meta)
                : _feed.language == FeedLanguage.en
                ? Text(l10n.feedEmpty, style: text.meta)
                // The server lists only finished translations; they come in over the day.
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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

    final topIds = _feed.top.map((a) => a.id).toSet();
    final latest = _feed.items
        .where((a) => !topIds.contains(a.id) && _shown(a))
        .toList();
    final top = _feed.top.where(_shown).toList();
    final slivers = <Widget>[];

    if (_feed.error != null) {
      slivers.add(_padded(Text(l10n.feedRefreshFailed, style: text.meta)));
    }

    if (top.isEmpty && latest.isEmpty) {
      Widget undo(String label, VoidCallback onPressed) => CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        child: Text(
          label,
          style: text.meta.copyWith(
            color: AppColors.accent,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      slivers.add(
        _padded(
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.filterEmpty, style: text.meta),
                if (!_place.isAll)
                  undo(
                    l10n.filterShowGlobal,
                    () => setState(() => _place = FeedPlace.all),
                  ),
                if (_topic != null)
                  undo(
                    l10n.filterShowAllTopics,
                    () => setState(() => _topic = null),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    // Analytics (#60) record each opened article's section and its index in
    // that section, and how deep the Latest list was drawn.
    if (top.isNotEmpty) {
      slivers.add(
        look.topStories(
          context,
          FeedSection(
            title: l10n.topStories,
            articles: top,
            readIds: _feed.readIds,
            open: (i) => _open(top[i], section: 'top', position: i),
          ),
        ),
      );
    }
    if (latest.isNotEmpty) {
      slivers.add(
        look.latest(
          context,
          FeedSection(
            title: l10n.latest,
            articles: latest,
            readIds: _feed.readIds,
            open: (i) => _open(latest[i], section: 'latest', position: i),
            shown: (i) => _shownRow(i + 1),
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
}

/// The masthead's sliver, telling where it ends on screen after each frame
/// that lays it out or paints it: scrolling, folding, pull to refresh. Any
/// look's masthead, so the screen can keep the "N new" pill under it.
class _MastheadEdge extends SingleChildRenderObjectWidget {
  const _MastheadEdge({required this.onBottom, required Widget sliver})
    : super(child: sliver);

  final ValueChanged<double> onBottom;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMastheadEdge(onBottom);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMastheadEdge renderObject,
  ) => renderObject.onBottom = onBottom;
}

class _RenderMastheadEdge extends RenderProxySliver {
  _RenderMastheadEdge(this.onBottom);

  ValueChanged<double> onBottom;
  bool _asked = false;

  @override
  void performLayout() {
    super.performLayout();
    _tell();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    _tell();
  }

  /// After the frame: the list's own place for the masthead is only known
  /// once it is laid out, and nothing may change during layout or paint.
  void _tell() {
    if (_asked) return;
    _asked = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _asked = false;
      final list = parent;
      if (!attached || list is! RenderBox) return;
      final shown = geometry?.paintExtent ?? 0;
      onBottom(
        shown <= 0
            ? 0
            : MatrixUtils.transformPoint(
                getTransformTo(list),
                Offset(0, shown),
              ).dy,
      );
    });
  }
}
