import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/analytics.dart';
import '../../core/article.dart';
import '../../core/feed_language.dart';
import '../../core/filters.dart';
import '../../core/news_widgets.dart';
import '../../core/pictures.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../settings/settings_screen.dart';
import 'feed_controller.dart';
import 'feed_filters.dart';

/// Item 3: the feed (docs/design/mvp.png). Top stories, then the latest
/// decisions grouped by day; opens instantly from the feed saved on the phone.
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
    if (widget.controller == null) _feed.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    final failed = _feed.error != null;
    if (failed && !_failed) unawaited(analytics.feedFailed());
    _failed = failed;
    setState(() {});
    // A page dropped because a refresh replaced the feed leaves the list at its end:
    // look again once the new feed is drawn.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _nearEnd();
    });
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
    // The countries for the Country row, if the feed has none yet (offline).
    unawaited(_feed.loadCountries());
    Navigator.of(context).push(
      CupertinoPageRoute(
        settings: const RouteSettings(name: '/settings'),
        builder: (_) => SettingsScreen(
          language: _feed.languageChanges,
          onLanguage: _chooseLanguage,
          country: _feed.countryChanges,
          onCountry: _chooseCountry,
          loadCountries: () => unawaited(_feed.loadCountries()),
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

  /// Global or Local from the chip (#68): another feed, from the top.
  Future<void> _chooseScope(FeedScope scope) async {
    if (scope != _feed.scope) _toTop();
    await _feed.setScope(scope);
  }

  /// One topic, or all, from the chip (#67): another feed, from the top.
  Future<void> _chooseTopic(String? topic) async {
    if (topic != _feed.topic) _toTop();
    await _feed.setTopic(topic);
  }

  /// Local's country from Settings: the feed changes only while it is Local.
  Future<void> _chooseCountry(String code) async {
    if (_feed.scope == FeedScope.local && code != _feed.localCountry) _toTop();
    await _feed.setCountry(code);
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    final local = _feed.localCountry;
    final topic = _feed.topic;
    return Scaffold(
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
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Settings at the top right (#64); the language is chosen there.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              // The app's name, the same in every language.
                              child: Text(
                                'Official News',
                                style: text.masthead,
                              ),
                            ),
                            _SettingsButton(onPressed: _openSettings),
                          ],
                        ),
                        Text(
                          longDay(DateTime.now(), l10n),
                          style: text.dateLine,
                        ),
                        FeedFilterBar(
                          scope: _feed.scope,
                          localName: local == null
                              ? null
                              : _feed.countryChanges.value.nameOf(local, l10n),
                          topic: topic,
                          topics: _feed.topics,
                          onScope: _chooseScope,
                          onTopic: _chooseTopic,
                        ),
                      ],
                    ),
                  ),
                ),
                ..._content(context),
              ],
            ),
            if (_feed.newCount > 0)
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: _NewPill(count: _feed.newCount, onTap: _showNew),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
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
                : _feed.filtered
                ? _FilteredEmpty(
                    local: _feed.feedCountry != null,
                    topic: _feed.topic != null,
                    onGlobal: () => _chooseScope(FeedScope.global),
                    onAllTopics: () => _chooseTopic(null),
                  )
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
    final latest = _feed.items.where((a) => !topIds.contains(a.id)).toList();
    final slivers = <Widget>[];

    if (_feed.error != null) {
      slivers.add(_padded(Text(l10n.feedRefreshFailed, style: text.meta)));
    }

    if (_feed.top.isNotEmpty) {
      slivers.add(
        _padded(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text(l10n.topStories, style: text.section),
          ),
        ),
      );
      final first = _feed.top.first;
      final rest = first.imageUrl != null ? _feed.top.skip(1) : _feed.top;
      if (first.imageUrl != null) {
        slivers.add(
          _padded(
            _TopCard(
              article: first,
              read: _feed.readIds.contains(first.id),
              onTap: () => _open(first, section: 'top', position: 0),
            ),
          ),
        );
      }
      slivers.add(
        _rows(
          rest.toList(),
          section: 'top',
          first: first.imageUrl != null ? 1 : 0,
        ),
      );
    }

    // One "Latest" list in the order articles appeared, with no day headings: an
    // article dated yesterday can appear today, so headings by day would contradict
    // the cards' own dates. Each card shows its date instead.
    if (latest.isNotEmpty) {
      slivers.add(
        _padded(
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 4),
            child: Text(l10n.latest, style: text.section),
          ),
        ),
      );
      slivers.add(_rows(latest, section: 'latest'));
    }

    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: _feed.loadMoreFailed
                ? CupertinoButton(
                    // A 44-pt target and a button role for VoiceOver.
                    onPressed: () => unawaited(_feed.loadMore(retry: true)),
                    child: Text(
                      l10n.feedLoadMoreFailed,
                      textAlign: TextAlign.center,
                      style: text.meta.copyWith(color: AppColors.accent),
                    ),
                  )
                : _feed.loadingMore || _feed.hasMore
                ? const CupertinoActivityIndicator()
                : Text(l10n.feedEnd, style: text.meta),
          ),
        ),
      ),
    );
    return slivers;
  }

  Widget _padded(Widget child) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverToBoxAdapter(child: child),
  );

  /// Every card shows its own date ("2h ago", or the day for date-only articles).
  /// [section] and [first] (the position of the first row) are for analytics.
  Widget _rows(
    List<Article> articles, {
    required String section,
    int first = 0,
  }) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverList.separated(
      itemCount: articles.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final a = articles[index];
        if (section == 'latest') _shownRow(index + 1);
        return _ArticleRow(
          article: a,
          read: _feed.readIds.contains(a.id),
          showDay: true,
          onTap: () => _open(a, section: section, position: first + index),
        );
      },
    ),
  );
}

/// A filtered feed with nothing in it (#67, #68): says so, with a way back to
/// all countries and to all topics, whichever narrows it.
class _FilteredEmpty extends StatelessWidget {
  const _FilteredEmpty({
    required this.local,
    required this.topic,
    required this.onGlobal,
    required this.onAllTopics,
  });

  final bool local;
  final bool topic;
  final VoidCallback onGlobal;
  final VoidCallback onAllTopics;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    Widget button(String label, VoidCallback onPressed) => CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: Text(
        label,
        style: text.meta.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.filterEmpty, style: text.meta),
        const SizedBox(height: 4),
        if (local) button(l10n.filterShowGlobal, onGlobal),
        if (topic) button(l10n.filterShowAllTopics, onAllTopics),
      ],
    );
  }
}

/// One decision: label, publisher, serif headline, time, thumbnail on the right.
class _ArticleRow extends StatelessWidget {
  const _ArticleRow({
    required this.article,
    required this.read,
    required this.onTap,
    this.showDay = true,
  });

  final Article article;
  final bool read;
  final VoidCallback onTap;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Opened articles stay in the feed, dimmed.
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KindLabel(article, dimmed: read),
                  PublisherLine(article, dimmed: read),
                  const SizedBox(height: 4),
                  Text(
                    article.headline,
                    style: dim(text.headline, read),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showDay ||
                      !article.dateOnly ||
                      article.addedAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      feedTime(article, AppLocalizations.of(context)),
                      style: dim(text.meta, read),
                    ),
                  ],
                ],
              ),
            ),
            if (article.imageUrl != null) ...[
              const SizedBox(width: 14),
              _Picture(
                url: article.imageUrl!,
                width: 84,
                height: 84,
                dimmed: read,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The first top story: a big picture with the text below.
class _TopCard extends StatelessWidget {
  const _TopCard({
    required this.article,
    required this.read,
    required this.onTap,
  });

  final Article article;
  final bool read;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _Picture(url: article.imageUrl!, dimmed: read),
            ),
            const SizedBox(height: 12),
            KindLabel(article, dimmed: read),
            PublisherLine(article, dimmed: read),
            const SizedBox(height: 4),
            Text(
              article.headline,
              style: dim(text.headline.copyWith(fontSize: 25), read),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              feedTime(article, AppLocalizations.of(context)),
              style: dim(text.meta, read),
            ),
          ],
        ),
      ),
    );
  }
}

/// A picture from the official page; it simply disappears if it cannot be loaded.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.url,
    this.width,
    this.height,
    this.dimmed = false,
  });

  final String url;
  final double? width;
  final double? height;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: width,
        height: height,
        // A read picture fades together with its placeholder, so it looks faded, not grey.
        color: dim(
          TextStyle(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          dimmed,
        ).color,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Official pages often serve 2,000+ px images; decode near the size shown,
            // so a long feed does not hold hundreds of MB of pictures. A square
            // thumbnail with BoxFit.cover crops a landscape picture to its height,
            // so it is decoded twice as wide as the box to stay sharp.
            final square = width != null && height != null && width == height;
            final shown = (width ?? constraints.maxWidth) * (square ? 2 : 1);
            return Image(
              image: picture(
                url,
                width: shown.isFinite ? (shown * ratio).round() : null,
              ),
              fit: BoxFit.cover,
              width: width,
              height: height,
              opacity: dimmed
                  ? const AlwaysStoppedAnimation(readOpacity)
                  : null,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }
}

/// The settings button at the top right of the feed: a round, tinted symbol
/// like the account button in Apple's apps, with a 44-pt target.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
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
}

/// "3 new decisions": shown instead of moving the list while it is being read.
/// Plural forms per language: "1 нове рішення", "3 нові рішення", "5 нових рішень".
class _NewPill extends StatelessWidget {
  const _NewPill({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          AppLocalizations.of(context).newDecisions(count),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
