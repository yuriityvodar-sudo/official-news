import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/feed_language.dart';
import '../../core/news_widgets.dart';
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

  void _open(Article article) {
    unawaited(_feed.markRead(article));
    // The article as the feed has it, so a translated one opens translated.
    Navigator.of(context).pushNamed(Routes.detail, arguments: article);
  }

  /// The iOS action sheet with the feed's languages, the current one checked.
  Future<void> _chooseLanguage() async {
    final current = _feed.language;
    final chosen = await showCupertinoModalPopup<FeedLanguage>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Language'),
        actions: [
          for (final lang in FeedLanguage.values)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.of(context).pop(lang),
              child: _LanguageChoice(lang, selected: lang == current),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (!mounted || chosen == null || chosen == _feed.language) return;
    // Another language is another feed: start it from the top.
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
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                longDay(DateTime.now()),
                                style: text.dateLine,
                              ),
                            ),
                            // Hidden, keeping its place, until the saved language is read.
                            Visibility(
                              visible: _feed.languageKnown,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: _LanguageButton(
                                language: _feed.language,
                                onPressed: _chooseLanguage,
                              ),
                            ),
                          ],
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
              onTap: () => _open(first),
            ),
          ),
        );
      }
      slivers.add(_rows(rest.toList()));
    }

    // Latest, then one group per earlier day: "Yesterday", "Monday 12 October"…
    final groups = <DateTime, List<Article>>{};
    for (final a in latest) {
      // The feed is in the order articles appeared, so days follow when they appeared.
      groups.putIfAbsent(localDay(a.addedAt ?? a.publishedAt), () => []).add(a);
    }
    var firstGroup = true;
    for (final entry in groups.entries) {
      final label = dayLabel(entry.key);
      final title = firstGroup && (label == 'Today' || _feed.top.isEmpty)
          ? 'Latest'
          : label;
      final style = title == 'Latest'
          ? text.section
          : text.section.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 20,
            );
      slivers.add(
        _padded(
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 4),
            child: Text(title, style: style),
          ),
        ),
      );
      if (title == 'Latest' && label != 'Today') {
        slivers.add(_padded(Text(label, style: text.meta)));
      }
      slivers.add(_rows(entry.value, groupDay: entry.key));
      firstGroup = false;
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

  /// Inside a day group, a date-only article shows no day when the group header says
  /// it. Groups follow when articles appeared, so one dated earlier still shows its day.
  Widget _rows(List<Article> articles, {DateTime? groupDay}) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverList.separated(
      itemCount: articles.length,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final a = articles[index];
        return _ArticleRow(
          article: a,
          read: _feed.readIds.contains(a.id),
          showDay: groupDay == null || localDay(a.publishedAt) != groupDay,
          onTap: () => _open(a),
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
                  if (showDay || !article.dateOnly) ...[
                    const SizedBox(height: 6),
                    Text(articleTime(article), style: dim(text.meta, read)),
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
            Text(articleTime(article), style: dim(text.meta, read)),
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
            return Image.network(
              url,
              fit: BoxFit.cover,
              width: width,
              height: height,
              cacheWidth: shown.isFinite ? (shown * ratio).round() : null,
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
              const Icon(
                CupertinoIcons.globe,
                size: 17,
                color: AppColors.accent,
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

/// One language in the menu, its own name centred, a checkmark on the current one.
class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice(this.language, {required this.selected});

  final FeedLanguage language;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      child: Row(
        children: [
          const SizedBox(width: 24),
          Expanded(
            child: Text(language.nativeName, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: 24,
            child: selected
                ? const Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 20,
                    color: AppColors.accent,
                  )
                : null,
          ),
        ],
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
