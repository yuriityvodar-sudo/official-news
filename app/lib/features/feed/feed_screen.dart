import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/analytics.dart';
import '../../core/article.dart';
import '../../core/feed_language.dart';
import '../../core/news_widgets.dart';
import '../../core/pictures.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import 'feed_controller.dart';

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

  /// A language picked in the menu: another language is another feed, from the top.
  Future<void> _chooseLanguage(FeedLanguage chosen) async {
    if (chosen == _feed.language) return;
    unawaited(analytics.languageChosen(chosen, from: _feed.language));
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _feed.setLanguage(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
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
                        Text('Official News', style: text.masthead),
                        // The language at the right of the date, or under it when
                        // large text needs the whole line, so no word of the date is split.
                        SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                longDay(DateTime.now()),
                                style: text.dateLine,
                              ),
                              // Hidden, keeping its place, until the saved language is read.
                              Visibility(
                                visible: _feed.languageKnown,
                                maintainSize: true,
                                maintainAnimation: true,
                                maintainState: true,
                                child: _LanguageMenu(
                                  language: _feed.language,
                                  onSelected: _chooseLanguage,
                                ),
                              ),
                            ],
                          ),
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
                ? Text(
                    "Couldn't load the news. Pull down to retry.",
                    style: text.meta,
                  )
                : _feed.language == FeedLanguage.en
                ? Text('No decisions yet today.', style: text.meta)
                // The server lists only finished translations; they come in over the day.
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No translated decisions yet.',
                        style: text.meta.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Translations appear here as they are ready.',
                        style: text.meta,
                      ),
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
      slivers.add(
        _padded(
          Text("Couldn't refresh. Pull down to retry.", style: text.meta),
        ),
      );
    }

    if (_feed.top.isNotEmpty) {
      slivers.add(
        _padded(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 4),
            child: Text('Top stories', style: text.section),
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
            child: Text('Latest', style: text.section),
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
                      "Couldn't load more. Tap to try again.",
                      style: text.meta.copyWith(color: AppColors.accent),
                    ),
                  )
                : _feed.loadingMore || _feed.hasMore
                ? const CupertinoActivityIndicator()
                : Text("You're all caught up", style: text.meta),
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
                    Text(feedTime(article), style: dim(text.meta, read)),
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
            Text(feedTime(article), style: dim(text.meta, read)),
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

/// The feed's language next to the date: a globe and "EN", "УКР" or "РУС", in the
/// accent colour like the feed's other tappable text, with a 44-pt target.
class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.language, required this.onPressed});

  final FeedLanguage language;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final style = NewsText.from(
      context,
    ).dateLine.copyWith(fontSize: 15, color: AppColors.accent);
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: onPressed,
      child: Semantics(
        label: 'Language: ${language.nativeName}',
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grows with the text, like an SF Symbol.
              const Icon(
                CupertinoIcons.globe,
                size: 17,
                color: AppColors.accent,
                applyTextScaling: true,
              ),
              const SizedBox(width: 4),
              Text(language.shortLabel, style: style),
            ],
          ),
        ),
      ),
    );
  }
}

/// The iOS pull-down menu at the language button (as in Apple's apps): the
/// languages in their own names, a checkmark on the current one. It opens from the
/// button and stays on screen on any device size, iPad included.
class _LanguageMenu extends StatefulWidget {
  const _LanguageMenu({required this.language, required this.onSelected});

  final FeedLanguage language;
  final ValueChanged<FeedLanguage> onSelected;

  @override
  State<_LanguageMenu> createState() => _LanguageMenuState();
}

class _LanguageMenuState extends State<_LanguageMenu> {
  // Follows the animation, not MenuController.isOpen: while the menu is closing,
  // isOpen is still true, and a tap then would "close" it again instead of opening.
  AnimationStatus _status = AnimationStatus.dismissed;

  @override
  Widget build(BuildContext context) {
    return CupertinoMenuAnchor(
      onAnimationStatusChanged: (status) => _status = status,
      menuChildren: [
        for (final lang in FeedLanguage.values)
          CupertinoMenuItem(
            onPressed: () => widget.onSelected(lang),
            trailing: lang == widget.language
                ? const Icon(
                    CupertinoIcons.checkmark_alt,
                    color: AppColors.accent,
                  )
                : null,
            child: Semantics(
              selected: lang == widget.language,
              child: Text(lang.nativeName),
            ),
          ),
      ],
      builder: (context, controller, _) => _LanguageButton(
        language: widget.language,
        onPressed: () => _status.isForwardOrCompleted
            ? controller.close()
            : controller.open(),
      ),
    );
  }
}

/// "3 new decisions": shown instead of moving the list while it is being read.
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
          '$count new ${count == 1 ? 'decision' : 'decisions'}',
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
