import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/glass.dart';
import '../../core/news_widgets.dart';
import '../../core/pictures.dart';
import '../../core/read_mark.dart';
import '../../core/theme.dart';
import '../../core/motion.dart';
import '../../l10n/app_localizations.dart';
import 'feed_look.dart';
import 'feed_topic_tags.dart';
import 'feed_touches.dart';

/// The feed as it looks today (docs/design/mvp.png): the Apple News look, a
/// big serif masthead, then one list of rows with a thumbnail on the right
/// (no section titles and no lead card since Yurii's review, 16 Oct).
///
/// The other looks start as copies of this one ([FeedLook] explains the
/// slots); its widgets below are public so a look can reuse any of them.
class NowLook extends FeedLook {
  @override
  Color background(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  @override
  Widget masthead(BuildContext context, FeedMasthead masthead) {
    final text = NewsText.from(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Settings at the top right (#64); the language is chosen there.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: Text(masthead.title, style: text.masthead)),
                masthead.settingsButton,
              ],
            ),
            Text(masthead.date, style: text.dateLine),
            masthead.filterBar,
          ],
        ),
      ),
    );
  }

  // One list in the order articles appeared, with no titles and no day
  // headings: an article dated yesterday can appear today, so headings by day
  // would contradict the cards' own dates. Each card shows its date instead.
  @override
  Widget articles(BuildContext context, FeedList list) => SliverPadding(
    // As far under the filters as the first row was under "Top stories".
    padding: const EdgeInsets.only(top: 8),
    sliver: rows(list),
  );

  @override
  Widget feedEnd(BuildContext context, FeedEnd end) {
    final text = NewsText.from(context);
    final l10n = AppLocalizations.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      sliver: SliverToBoxAdapter(
        child: Center(
          child: switch (end.state) {
            FeedEndState.failed => CupertinoButton(
              // A 44-pt target and a button role for VoiceOver.
              onPressed: end.retry,
              child: Text(
                l10n.feedLoadMoreFailed,
                textAlign: TextAlign.center,
                style: text.meta.copyWith(color: AppColors.accent),
              ),
            ),
            FeedEndState.loading => const CupertinoActivityIndicator(),
            FeedEndState.end => Text(l10n.feedEnd, style: text.meta),
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
  }) => NowNewPill(count: count, onTap: onTap);

  /// The masthead scrolls away whole, so the name folds into a small title
  /// at the top (#141).
  @override
  Widget? foldedTitle(BuildContext context, String title) =>
      FeedLook.smallTitle(context, title);

  /// [child] with the feed's 20-pt margins, as a sliver.
  Widget padded(Widget child) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverToBoxAdapter(child: child),
  );

  /// The articles of [list] as rows with a hairline between them. Every card
  /// shows its own date ("2h ago", or the day for date-only articles).
  Widget rows(FeedList list) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverList.separated(
      itemCount: list.length,
      separatorBuilder: (_, i) => list.line(i, const Divider()),
      itemBuilder: (context, i) {
        final a = list.articles[i];
        list.shown(i);
        return list.tile(
          i,
          NowArticleRow(
            article: a,
            mark: list.markOf(a),
            topics: list.topicsOf(a),
            showDay: true,
            onTap: () => list.open(i),
          ),
        );
      },
    ),
  );
}

/// One decision: its topics, publisher, serif headline, time, thumbnail on
/// the right. The topic tags stand where the red decision type stood until
/// Yurii's review (16 Oct); the type is on the article screen.
class NowArticleRow extends StatelessWidget {
  const NowArticleRow({
    super.key,
    required this.article,
    required this.mark,
    required this.onTap,
    this.topics = const [],
    this.showDay = true,
  });

  final Article article;

  /// The topic tags to show, in order ([FeedList.topicsOf]); none, no row.
  final List<String> topics;

  /// Read or not, and how that shows ([ReadStyle]): nothing, dimmed, or the
  /// unread dot.
  final ReadMark mark;
  final VoidCallback onTap;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final read = mark.dimmed;
    // In the dot styles VoiceOver says "Unread" after the row, as
    // in the other designs, not in the middle where the dot is.
    return Semantics(
      value: mark.unread ? AppLocalizations.of(context).feedUnread : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Opened articles stay in the feed, dimmed (or without the unread dot).
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The topics across the whole row, over the picture too: three
              // long names ("Безпека та оборона") take two lines at most.
              if (topics.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TopicTags(
                    topics,
                    // VoiceOver hears them after the time (_body): first
                    // in the row, they would be heard before the headline.
                    speak: false,
                    color: dim(text.meta, read).color!,
                    fill: dim(
                      TextStyle(
                        color: CupertinoColors.quaternarySystemFill.resolveFrom(
                          context,
                        ),
                      ),
                      read,
                    ).color,
                  ),
                ),
              _body(context, text, read),
            ],
          ),
        ),
      ),
    );
  }

  /// The publisher, headline and time, the picture on their right; for
  /// VoiceOver, the topics after them ("Topics: Economy, Trade").
  Widget _body(BuildContext context, NewsText text, bool read) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PublisherLine(article, dimmed: read, mark: mark),
            const SizedBox(height: 4),
            Text(
              article.headline,
              style: dim(text.headline, read),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            if (showDay || !article.dateOnly || article.addedAt != null) ...[
              const SizedBox(height: 6),
              // A decision of the last hour stands out (#141).
              if (!read && isFresh(article))
                FreshTime(
                  feedTime(article, AppLocalizations.of(context)),
                  articleId: article.id,
                  style: text.meta,
                )
              else
                Text(
                  feedTime(article, AppLocalizations.of(context)),
                  style: dim(text.meta, read),
                ),
            ],
            if (topics.isNotEmpty)
              Semantics(
                label: spokenTopics(topics, AppLocalizations.of(context)),
                child: const SizedBox.shrink(),
              ),
          ],
        ),
      ),
      if (article.imageUrl != null) ...[
        const SizedBox(width: 14),
        FeedPicture(
          url: article.imageUrl!,
          width: 84,
          height: 84,
          dimmed: read,
        ),
      ],
    ],
  );
}

/// A picture from the official page; it simply disappears if it cannot be
/// loaded. Any look can use it: it decodes the picture near the size shown,
/// which keeps a long feed's memory low.
class FeedPicture extends StatelessWidget {
  const FeedPicture({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.dimmed = false,
    this.radius = 10,
  });

  final String url;
  final double? width;
  final double? height;
  final bool dimmed;

  /// The corner radius.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
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
              frameBuilder: fadeInPicture,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }
}

/// The settings button at the top right of the feed: a round symbol like
/// the account button in Apple's apps, with a 44-pt target, on Liquid Glass
/// where the phone has it ([GlassCircle]; Yurii, 20 Oct).
class NowSettingsButton extends StatelessWidget {
  const NowSettingsButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => CupertinoButton(
    padding: EdgeInsets.zero,
    minimumSize: const Size(44, 44),
    onPressed: onPressed,
    // A little larger than before (36), so the glass reads as glass (Yurii, #160).
    child: GlassCircle(
      size: 40,
      shadow: false,
      child: Icon(
        CupertinoIcons.gear_alt,
        size: 21,
        color: CupertinoColors.label.resolveFrom(context),
        semanticLabel: AppLocalizations.of(context).settings,
      ),
    ),
  );
}

/// "3 new decisions": shown instead of moving the list while it is being read.
/// Plural forms per language: "1 нове рішення", "3 нові рішення", "5 нових рішень".
class NowNewPill extends StatelessWidget {
  const NowNewPill({super.key, required this.count, required this.onTap});

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
