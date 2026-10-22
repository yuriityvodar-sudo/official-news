import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/feed_design.dart';
import '../../core/read_mark.dart';
import 'feed_look_a.dart';
import 'feed_look_b.dart';
import 'feed_look_c.dart';
import 'feed_look_now.dart';
import 'feed_topic_tags.dart';

export '../../core/feed_design.dart';

/// The look shown now ([FeedDesign], #66). Settings switches it (the
/// "Design" row); a build can start with another one:
/// `--dart-define=FEED_DESIGN=a`.
///
/// Everything the feed draws goes through a [FeedLook]; everything it does
/// (loading, errors, empty states, pull to refresh, loading more, the "N new"
/// pill, opening an article, analytics) stays in the feed screen. To change a
/// look, change only its own file: `feed_look_a.dart` for [ALook], and so on,
/// plus any `feed_look_a_*.dart` files of its own. Nothing else needs editing.
final feedDesign = ValueNotifier<FeedDesign>(
  designNamed(const String.fromEnvironment('FEED_DESIGN')),
);

/// How read articles look, in every design. Yurii's pick (20 Oct): no
/// marking at all. A build can start with another: `--dart-define=READ_STYLE=blue`.
final readStyle = ValueNotifier<ReadStyle>(
  readStyleNamed(const String.fromEnvironment('READ_STYLE')),
);

/// `none`, `dim`, `blue` or `red`, in any case; anything else is [ReadStyle.none].
ReadStyle readStyleNamed(String name) =>
    ReadStyle.values.asNameMap()[name.trim().toLowerCase()] ?? ReadStyle.none;

/// How many of its topics a card shows at most, in every design: 3 (Yurii's
/// pick, 20 Oct). A build can start with another: `--dart-define=TOPIC_TAGS=1`.
final topicTagCount = ValueNotifier<int>(
  topicTagCountNamed(const String.fromEnvironment('TOPIC_TAGS')),
);

/// `1`, `2` or `3`; anything else is [maxCardTopics].
int topicTagCountNamed(String name) => switch (int.tryParse(name.trim())) {
  final n? when n >= 1 && n <= maxCardTopics => n,
  _ => maxCardTopics,
};

/// The look for [design]. Looks are created for each build of the feed, so
/// they keep no state: a look that needs some keeps it in a StatefulWidget
/// of its own.
FeedLook lookFor(FeedDesign design) => switch (design) {
  FeedDesign.now => NowLook(),
  FeedDesign.a => ALook(),
  FeedDesign.b => BLook(),
  FeedDesign.c => CLook(),
};

/// How the feed looks. The slot that holds the list returns a SLIVER, so a
/// long feed builds only the rows on screen: use SliverList (or
/// SliverMainAxisGroup to put something before it), never a Column of every
/// article.
///
/// The screen lays the page out as, top to bottom: the pull-to-refresh
/// control, [masthead], a notice when the refresh failed, [articles] (when
/// there are any) and [feedEnd]. While new articles wait, the screen floats
/// [newPill] just under the masthead as it is on screen: under the filters
/// at the top of the feed, under a pinned bar once folded, near the top once
/// the masthead has gone.
abstract class FeedLook {
  /// The colour behind the whole feed.
  Color background(BuildContext context);

  /// The theme the feed is drawn with: [base] is the app's. Returning another
  /// one changes the shared pieces at once (NewsText styles used by
  /// PublisherLine and the loading, error and empty texts; the divider colour).
  /// Returning [base] itself changes nothing.
  ThemeData theme(BuildContext context, ThemeData base) => base;

  /// The top of the feed: the app's name, today's date, the settings button
  /// and the filters, arranged as the look likes. One sliver (a pinned
  /// SliverPersistentHeader is fine).
  Widget masthead(BuildContext context, FeedMasthead masthead);

  /// The feed's one list (Yurii, 16 Oct): every article, each once, in the
  /// order it arrived in the feed, newest first. No section titles ("Top
  /// stories", "Latest") and no block of its own for the first articles (a
  /// lead card, a carousel, numbers): every row in the same style. No day
  /// headings either: an article dated yesterday can arrive today, and each
  /// row shows its own time. One sliver, built lazily; only called when
  /// there is at least one article.
  Widget articles(BuildContext context, FeedList list);

  /// The bottom of the feed: a spinner while more is loading, a retry when
  /// that failed, or the end of the feed. One sliver.
  Widget feedEnd(BuildContext context, FeedEnd end);

  /// "3 new decisions": a plain widget, as small as it looks (taps beside it
  /// reach the feed). The screen places it under the masthead, never on the
  /// name or the filters, and calls [onTap] to show them.
  Widget newPill(
    BuildContext context, {
    required int count,
    required VoidCallback onTap,
  });
}

/// The pieces of the feed's top for [FeedLook.masthead].
class FeedMasthead {
  const FeedMasthead({
    required this.title,
    required this.date,
    required this.openSettings,
    required this.filterBar,
  });

  /// "Official News": the app's name, the same in every language.
  final String title;

  /// Today in the reader's language: "Friday, 16 October", "Пʼятниця, 16 жовтня".
  final String date;

  /// Opens Settings. [settingsButton] is today's button for it.
  final VoidCallback openSettings;

  /// The filter bar: the Where and Topics pull-downs (#67, #68), built by
  /// the screen from the feed's state ([FeedFilterBar]). A look places it.
  final Widget filterBar;

  /// Today's settings button: a round gear with a 44-pt target and its
  /// VoiceOver label. A look may draw its own and call [openSettings].
  Widget get settingsButton => NowSettingsButton(onPressed: openSettings);
}

/// The feed's list for a look to draw: its articles and what a row does.
/// The screen does the rest.
class FeedList {
  const FeedList({
    required this.articles,
    required this.readIds,
    required this.open,
    this.shown = _nothing,
    this.readStyle = ReadStyle.none,
    this.topic,
    this.maxTopics = maxCardTopics,
  });

  final List<Article> articles;

  /// The topic the feed is filtered by (an id, as [Article.topics] has it),
  /// or null for every topic. Every article here has it, and its card shows
  /// it first among its topic tags, so the card agrees with the Topics chip
  /// ([cardTopics]).
  final String? topic;

  /// How many topic tags a card shows at most (3; a build may set 1 or 2,
  /// [topicTagCount]). Give each card `cardTopics(article, first: topic,
  /// max: maxTopics)`, or [topicsOf].
  final int maxTopics;

  /// Articles already opened: they stay in the feed, dimmed or without the
  /// unread dot ([readStyle]).
  final Set<String> readIds;

  /// How read articles look ([ReadStyle]): give each row [markOf] its article.
  final ReadStyle readStyle;

  /// Opens `articles[index]`: `onTap: () => list.open(i)`. Analytics
  /// records the index as the article's position in the feed.
  final ValueChanged<int> open;

  /// Call when the row for `articles[index]` is built, in the item builder:
  /// how deep the reader scrolled, for analytics. Cheap, and safe to call
  /// again.
  final ValueChanged<int> shown;

  static void _nothing(int _) {}

  int get length => articles.length;
  bool isRead(Article article) => readIds.contains(article.id);

  /// What the row of [article] shows of it being read: faded (Dim), or the
  /// unread dot in place of the official-source tick (Blue, Red).
  ReadMark markOf(Article article) =>
      ReadMark(readStyle, read: isRead(article));

  /// The topics the card of [article] shows as tags, in order: the filtered
  /// topic first, then the article's own order, at most [maxTopics]; none for
  /// an article without topics (its card then has no tag row at all).
  List<String> topicsOf(Article article) =>
      cardTopics(article, first: topic, max: maxTopics);
}

/// What the bottom of the feed shows for [FeedLook.feedEnd].
class FeedEnd {
  const FeedEnd({required this.state, required this.retry});

  final FeedEndState state;

  /// Loads the next page again after it failed ([FeedEndState.failed]).
  final VoidCallback retry;
}

enum FeedEndState {
  /// More is loading, or will load when the reader gets near the end.
  loading,

  /// The next page failed to load (offline): offer [FeedEnd.retry].
  failed,

  /// Everything in the feed is shown.
  end,
}
