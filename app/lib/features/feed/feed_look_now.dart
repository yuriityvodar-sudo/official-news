import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/news_widgets.dart';
import '../../core/pictures.dart';
import '../../core/read_mark.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'feed_look.dart';

/// The feed as it looks today (docs/design/mvp.png): the Apple News look, a
/// big serif masthead, red section titles, a lead card when the first top
/// story has a picture, then rows with a thumbnail on the right.
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

  @override
  Widget topStories(BuildContext context, FeedSection top) {
    final first = top.articles.first;
    // A lead card only when the first top story has a picture.
    final lead = first.imageUrl != null;
    return SliverMainAxisGroup(
      slivers: [
        padded(
          NowSectionTitle(
            top.title,
            padding: const EdgeInsets.only(top: 16, bottom: 4),
          ),
        ),
        if (lead)
          padded(
            NowTopCard(
              article: first,
              mark: top.markOf(first),
              onTap: () => top.open(0),
            ),
          ),
        rows(top, from: lead ? 1 : 0),
      ],
    );
  }

  // One "Latest" list in the order articles appeared, with no day headings: an
  // article dated yesterday can appear today, so headings by day would contradict
  // the cards' own dates. Each card shows its date instead.
  @override
  Widget latest(BuildContext context, FeedSection latest) =>
      SliverMainAxisGroup(
        slivers: [
          padded(
            NowSectionTitle(
              latest.title,
              padding: const EdgeInsets.only(top: 20, bottom: 4),
            ),
          ),
          rows(latest),
        ],
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

  /// [child] with the feed's 20-pt margins, as a sliver.
  Widget padded(Widget child) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverToBoxAdapter(child: child),
  );

  /// The articles of [section] from index [from] on, as rows with a hairline
  /// between them. Every card shows its own date ("2h ago", or the day for
  /// date-only articles).
  Widget rows(FeedSection section, {int from = 0}) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    sliver: SliverList.separated(
      itemCount: section.length - from,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        final i = from + index;
        final a = section.articles[i];
        section.shown(i);
        return NowArticleRow(
          article: a,
          mark: section.markOf(a),
          showDay: true,
          onTap: () => section.open(i),
        );
      },
    ),
  );
}

/// A red section title: "Top stories", "Latest".
class NowSectionTitle extends StatelessWidget {
  const NowSectionTitle(this.title, {super.key, required this.padding});

  final String title;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(title, style: NewsText.from(context).section),
  );
}

/// One decision: label, publisher, serif headline, time, thumbnail on the right.
class NowArticleRow extends StatelessWidget {
  const NowArticleRow({
    super.key,
    required this.article,
    required this.mark,
    required this.onTap,
    this.showDay = true,
  });

  final Article article;

  /// Read or not, and how that shows (prototype): dimmed, or the unread dot.
  final ReadMark mark;
  final VoidCallback onTap;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final read = mark.dimmed;
    // PROTOTYPE: in the dot styles VoiceOver says "Unread" after the row, as
    // in the other designs, not in the middle where the dot is.
    return Semantics(
      value: mark.unread ? AppLocalizations.of(context).feedUnread : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Opened articles stay in the feed, dimmed (or without the unread dot).
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
                    PublisherLine(article, dimmed: read, mark: mark),
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
                FeedPicture(
                  url: article.imageUrl!,
                  width: 84,
                  height: 84,
                  dimmed: read,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The first top story: a big picture with the text below.
class NowTopCard extends StatelessWidget {
  const NowTopCard({
    super.key,
    required this.article,
    required this.mark,
    required this.onTap,
  });

  final Article article;

  /// Read or not, and how that shows (prototype): dimmed, or the unread dot.
  final ReadMark mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final read = mark.dimmed;
    return Semantics(
      value: mark.unread ? AppLocalizations.of(context).feedUnread : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: FeedPicture(url: article.imageUrl!, dimmed: read),
              ),
              const SizedBox(height: 12),
              KindLabel(article, dimmed: read),
              PublisherLine(article, dimmed: read, mark: mark),
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
      ),
    );
  }
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
class NowSettingsButton extends StatelessWidget {
  const NowSettingsButton({super.key, required this.onPressed});

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
